# Magnes bug report: Super Mario Bros. flicker / sprite glitches and Nomolos rendering

Date: 2026-08-26

## 1. Symptoms reported

| # | Game | Symptom |
|---|------|---------|
| S1 | Nomolos | "Scrolling is not implemented correctly": after the story text the screen turns black, then shows colourful garbage instead of the cut-scene picture; a bit later the emulator crashes (`The emulator is crashing` alert). |
| S2 | Super Mario Bros. (`mario.nes`) | Flickering while playing. |
| S3 | Super Mario Bros. | Enemies sometimes rendered at the edge ("end of the map") / not where the real game shows them; the game "does not feel the same" as in other emulators. |

## 2. How the bugs were found

* The wasm build was driven headlessly with Node (`tools/headless/`, see §7): scripted joypad
  input, frame-exact stepping (a new `runFrame` export), PNG snapshots.
* [jsnes](https://github.com/bfirsh/jsnes) was used as a reference emulator with **Magnes' own
  colour palette injected**, so frames can be compared pixel by pixel.
* An instrumented build printed every PPU register access with frame / scanline / dot, the mapper
  bank switches and the CPU program counter for suspicious reads.
* blargg's CPU instruction test ROMs in `roms/tests` were run (they need PRG RAM at `$6000`, which
  did not exist before this fix).

## 3. Root causes

### Bug 1 - Mapper 2 bank number masked to 4 bits (Nomolos garbage screen + crash) - **root cause of S1**

`rom.mg`:

```
fn mapper_2_write_prg(rom: *ROM, addr: u16, data: u8) {
  mapper_2_selected_bank = data & 0x0f;
}
```

`nomolos.nes` is a 512 KB UNROM cartridge: 32 PRG banks. Its intro selects bank `0x10` (the trace
shows 120 writes of `BANK 0x10` during the story sequence). With the 4 bit mask bank 16 aliases to
bank 0, so the cut-scene loader reads its data tables from the wrong bank:

* The VRAM copy routine at `$E8B2` (`LDA ($26),Y / STA $2007` with a 16 bit length in `$28/$29`)
  gets a garbage length and streams ~549 bytes per frame for hundreds of frames. The PPU address
  wraps around `$0000-$3FFF` again and again (trace: `f=445 first=0x222b last=0x244a`,
  `f=460 first=0x251 ...`), overwriting CHR RAM, name tables and palettes: the "garbage" picture.
* The source pointer walks through CPU memory and eventually reads `$2000-$3FFF`
  (`WO-READ addr=0x3ffe pc=0xe8c2`). Reading a write-only PPU register made the emulator execute
  `wasm::trap()` (`register 0 is write only`), which is the crash.

In gameplay only banks `0x0-0xf` were used in the first level, which is why the first level looked
"almost right" and only the intro / later levels broke.

### Bug 2 - Reads of write-only PPU registers trapped the emulator

`ppu.mg` `get_register` called `wasm::trap()` for `$2000/$2001/$2003/$2005/$2006`. Real hardware
returns the value left on the PPU data bus ("open bus"). Games do read those addresses (Nomolos
above; many games also do `BIT $2000`-style dummy reads).

### Bug 3 - PPUMASK (`$2001`) ignored by the background renderer

`render_background` rendered the name table regardless of the background enable bit. When a game
turns rendering off (Nomolos writes `$2001 = $06` before uploading the cut-scene) the screen must
show the backdrop colour; instead the half-uploaded CHR/name table data was displayed (this is why
the runaway upload of bug 1 was *visible* as animated garbage). The greyscale bit (used by Nomolos
for its pause screen) and the left-8-pixel clipping bits were ignored as well.

### Bug 4 - Frame presentation: tearing, ghost sprites and sprite drop-outs - **root cause of S2/S3**

Old pipeline (`ppu.mg` `tick` / `render`, `nes.mg` `tick`):

1. Background scanlines were rasterized straight into the framebuffer the browser displays, one
   scanline at a time, as the CPU ran.
2. Sprites were **not** rendered per scanline. `nes::tick` (one call per `requestAnimationFrame`)
   called `ppu::render` → `render_objects`, which stamped all 64 sprites from the *current* OAM over
   whatever the framebuffer contained at that moment.
3. `nes::tick` capped the emulated time at 16 ms per call, i.e. 0.963 NES frames per 60 Hz browser
   tick, so the point in the NES frame at which the browser sampled the framebuffer drifted by ~10
   scanlines every tick.

Consequences: the displayed image is always part old frame / part new frame with a moving tear line
(visible as jitter while scrolling); sprites were drawn on top of a background that belongs to two
different scroll positions (enemies appear displaced, sometimes at the screen edge); rows that were
not re-rendered in a tick kept the previous tick's sprites (ghosting); and when a tick ended while
SMB had sprites disabled in its NMI handler (`$2001 = $06` between scanline 241 and 244), no sprites
were drawn at all for that displayed frame (flicker).

Additional problems in the same code:

* `remaining_elapsed_nanosecond = cpu_cycle` assigned the leftover *cycle* count (≤ 0) to a
  *nanosecond* variable, discarding the remainder every tick; `cycle_period` was truncated to 558 ns
  (0.13 % too fast); the 16 ms cap means the emulator ran at 96 % speed on 60 Hz displays.
* OAM DMA (`$4014`) took 0 CPU cycles instead of 513.
* Sprites were drawn with a plain `y*256 + x` offset, so a sprite at x ≥ 249 wrapped into the next
  row; 8x16 sprites (`$2000` bit 5) were not supported; there was no 8-sprites-per-scanline limit;
  sprite priority between overlapping sprites was wrong (later sprites could overwrite earlier ones
  that had the "behind background" flag).

### Bug 5 - Sprite 0 hit timing and semantics (SMB status bar split)

SMB splits the screen after the status bar with a sprite 0 hit. In the old `tick`:

* The hit was detected while rasterizing the whole scanline at its *end* (dot 341), i.e. up to ~250
  dots late (the real hit for SMB is at scanline 30, dot ≈ 90, tile `$FF` rows 5-6).
* Only the sprite pixel was tested; hardware requires an opaque background pixel too.
* The flag was cleared at the start of vblank (scanline 241) instead of on the pre-render line.

Trace of the split scroll write in the old build (it should always land in the same place):

```
W f=434 sl=32 cyc=10  reg=0x5 data=0x91
W f=435 sl=31 cyc=340 reg=0x5 data=0x93   <- one scanline earlier than the frame before
W f=436 sl=32 cyc=0   reg=0x5 data=0x95
```

### Bug 6 - Scroll registers were an approximation

The PPU kept `scroll_x`, `scroll_y`, the name table bits of `$2000` and a separate address
register for `$2006`, with **two independent write latches** (`scroll_latch`, `is_reading_lo`).
On hardware `$2005` and `$2006` share one latch (`w`) and one temporary address (`t`):

* `$2006` writes did not change the scroll position at all (games use `$2006` to select the name
  table / vertical position; Nomolos writes `$2006` then `$2005` every frame).
* A `$2005` Y write in the middle of a frame took effect on the next scanline; on hardware vertical
  scroll only changes on the next frame (only the horizontal part is reloaded every line).
* `$2007` reads of palette RAM did not fill the read buffer; four-screen mirroring could index past
  the 2 KB VRAM array.

### Bug 7 - CHR RAM / cartridge memory

* Mapper 2 used a global "fallback" CHR buffer with an off-by-one test (`characters_size < addr`),
  so CHR address 0 read/wrote the byte after the PRG ROM.
* Mapper 0 wrote into CHR ROM.
* `$6000-$7FFF` (PRG RAM) was unmapped, so blargg's test ROMs (and games with work RAM) cannot run.

### Bug 8 - Web front end

* `fd_write` indexed the iovec array with `iovec + 2*i` (an iovec is 8 bytes).
* `memoryBuffer` was captured once; if the wasm memory grows the ArrayBuffer is detached and every
  `renderToCanvas` call throws.

### Compiler quirk found on the way

With the current magelang compiler `u8 as i32` / `u16 as i32` **sign-extend** (`0x83 as i32 == -125`)
and `i32 as u16` does not mask the upper bits. The existing code worked around it with
`(x as u32) as i32`; the new code does the same and documents it (`ppu.mg`).

## 4. Fix plan (executed in this order)

1. Mapper 2: mask the bank number with the real bank count (`program_size / 16 KB`).
2. PPU registers: open-bus latch instead of `wasm::trap()`; `$2002` returns the latch in its low 5
   bits; shared `w` latch.
3. Implement the real scroll/address registers `v`, `t`, `x`, `w` (`$2000`, `$2005`, `$2006`,
   `$2007` incl. the "increment during rendering" glitch, palette read buffer) and the per-dot
   register updates (`inc y` at dot 256, horizontal reload at dot 257, vertical reload at dot 280 of
   the pre-render line).
4. Rewrite the renderer as a scanline compositor: background from `v`/`x` (33 tile fetches with
   name-table wrap), sprite evaluation per scanline (8 sprite limit + overflow flag, 8x16 sprites,
   flips, priority, left-column clipping, no wrap-around at x ≥ 249), PPUMASK honoured (backdrop when
   rendering is off, greyscale), sprite 0 hit computed at the exact pixel and the flag set when the
   dot counter reaches it; status flags cleared on the pre-render line.
5. Double buffering: scanlines are rasterized into a back buffer that is swapped at scanline 240, so
   the platform layer always shows a complete frame. `ppu::render` now only refreshes the debug
   views.
6. `nes.mg`: exact cycle bookkeeping (`elapsed * 1789773 / 1e9`, remainder carried over), cap of ~2
   frames, OAM DMA stall (513 cycles) via `bus::take_dma_stall_cycles`, `runFrame` export for
   deterministic tests.
7. `bus.mg`: PRG RAM at `$6000-$7FFF`. `rom.mg`: CHR RAM allocated when the header has no CHR ROM,
   CHR ROM read-only.
8. `platform/web/main.js`: iovec stride, live `memory.buffer`.

## 5. Changed files

`ppu.mg` (rewritten core, debug helpers unchanged), `bus.mg`, `rom.mg`, `nes.mg`,
`platform/web/main.js`, and the rebuilt `build/` directory (`bash ./build.sh`).
Test tooling in `tools/headless/`.

## 6. Verification

Frames compared against jsnes (Magnes palette injected). jsnes blanks an 8 pixel border around the
screen, which is excluded from the counts.

| ROM | Frames | Result |
|-----|--------|--------|
| mario.nes | 200, 300, 400, 450 | 0 differing pixels |
| mario.nes | 500 | 1 px horizontal scroll offset: jsnes' power-on sequence is one frame ahead (its frame counter `$07` differs by 1), i.e. a phase difference, not a rendering difference |
| nomolos.nes intro (story text, fade, cut-scene) | 400-500 | 0 differing pixels (was black / garbage / crash) |
| nomolos.nes gameplay | 800-1000 | identical scroll position, only sprite poses differ by the same one-frame phase |
| croom, flappybird, jetpaco, bootee, snake2, nestest | 250, 450, 600 | 0 differing pixels (flappybird 450: 123 px, sprite phase) |
| blargg `01`-`16` instruction tests | | 15/16 pass; `07-abs_xy` fails only on the unofficial `SHX`/`SHY` opcodes |
| `cpu_dummy_writes_*` | | fail (read-modify-write double writes are not emulated; no game impact observed) |

Browser (`build/platform/web`): SMB and Nomolos run at full speed, one `requestAnimationFrame`
callback takes ~2 ms on a 120 Hz display; the Nomolos story now continues past the point where the
old build trapped.

Figures (left: old build, middle: new build, right: jsnes):

* `docs/report/nomolos_story_fade_before_after.png` - old build shows black instead of the fading-in picture.
* `docs/report/nomolos_cutscene_before_after.png` - old build shows the garbage of the runaway VRAM upload.
* `docs/report/smb_frame500_before_after.png` - frame-exact SMB comparison.
* `docs/report/nomolos_gameplay_after.png` - new build vs jsnes during gameplay.
* `docs/report/blargg_cpu_tests.png` - blargg test screens.

## 7. Reproducing / running the checks

```bash
bash ./build.sh                       # rebuild build/nes.wasm and build/platform/web
cd tools/headless && npm install      # jsnes + pngjs (dev only)
node run.mjs ../../build/nes.wasm ../../mario.nes out/smb scripts/smb.json      # magnes vs jsnes PNGs
node diff.mjs out/smb 200 300 400                                                # pixel diff
node run.mjs ../../build/nes.wasm ../../roms/nomolos.nes out/nomolos scripts/nomolos_intro.json
```

## 8. Known remaining inaccuracies (not needed for the reported bugs)

* CPU: unofficial `SHX`/`SHY`, dummy reads/writes of read-modify-write instructions, and the odd
  frame dot skip are not emulated. `cpu.mg` `interrupt()` (IRQ) has an inverted `I` flag check and
  pushes to `sp` instead of `$100+sp`; it is currently dead code (no APU/mapper IRQ sources) but must
  be fixed before IRQs are wired up.
* No APU; joypad returns `$04` after the 8th read (hardware returns `$01`).
* Colour emphasis bits of `$2001` are ignored. The built-in palette is noticeably more red than the
  common NTSC palettes (cosmetic).
* Sprite evaluation uses the OAM at the start of the scanline (hardware evaluates during the
  previous line) and mid-scanline writes to the scroll registers only take effect on the next line.
