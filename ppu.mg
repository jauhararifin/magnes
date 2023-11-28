import wasm "wasm";
import mem "mem";
import fmt "fmt";
import rom "rom";
import cpu "cpu";
import bus "bus";

// PPU memory map
// [0x0000 - 0x2000): pattern table (the characters rom)
// [0x2000 - 0x3f00): name table
// [0x3f00 - 0x4000): palette
// [0x4000 - 0xffff]: mirror all of the above (0x0000 - 0x3fff)
//
// CPU memory map
// 0x2000 - 0x2007: PPU registers
// 0x2008 - 0x3fff: mirror of PPU registers
//
// PPU registers:
// 0x2000: Controller  (write only)
// 0x2001: Mask        (write only)
// 0x2002: Status      (read only)
// 0x2003: OAM Address
// 0x2004: OAM Data
// 0x2005: Scroll      (write only)
// 0x2006: Address
// 0x2007: Data
//
// 0x4014: OAM DMA

// Palette
// 0x3f00:          contains the background color
// 0x3f01 - 0x3f04: palette 0. last byte is unused (or rather mirror to background color)
// 0x3f05 - 0x3f08: palette 1. last byte is unused (or rather mirror to background color)
// 0x3f09 - 0x3f0c: palette 2. last byte is unused (or rather mirror to background color)
// 0x3f0d - 0x3f10: palette 3. last byte is unused (or rather mirror to background color)
// 0x3f11 - 0x3f14: palette 4. last byte is unused (or rather mirror to background color)
// 0x3f15 - 0x3f18: palette 5. last byte is unused (or rather mirror to background color)
// 0x3f19 - 0x3f1c: palette 6. last byte is unused (or rather mirror to background color)
// 0x3f1d - 0x3f1f: palette 7. only 3 bytes
//
// to calcualte the address of palette P, color C just calculate: 0x3f00 + P * 4 + C
// Addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C

let CONTROL_FLAG_NAMETABLE_1: u8             = 1;
let CONTROL_FLAG_NAMETABLE_2: u8             = 1<<1;
let CONTROL_FLAG_VRAM_ADD: u8                = 1<<2;
let CONTROL_FLAG_SPRITE_PATTERN_ADDR: u8     = 1<<3;
let CONTROL_FLAG_BACKGROUND_PATTERN_ADDR: u8 = 1<<4;
let CONTROL_FLAG_SPRITE_SIZE: u8             = 1<<5;
let CONTROL_FLAG_MASTER_SLAVE_SELECT: u8     = 1<<6;
let CONTROL_FLAG_NMI: u8                     = 1<<7;

let STATUS_FLAG_SPRITE_OVERFLOW: u8 = 1<<5;
let STATUS_FLAG_ZERO_HIT: u8        = 1<<6;
let STATUS_FLAG_VBLANK_STARTED: u8  = 1<<7;

let MASK_FLAG_GREYSCALE: u8           = 1;
let MASK_FLAG_BACKGROUND_LEFTMOST: u8 = 1<<1;
let MASK_FLAG_SPRITE_LEFTMOST: u8     = 1<<2;
let MASK_FLAG_BACKGROUND: u8          = 1<<3;
let MASK_FLAG_SPRITE: u8              = 1<<4;
let MASK_FLAG_EMPHASIZE_RED: u8       = 1<<5;
let MASK_FLAG_EMPHASIZE_GREEN: u8     = 1<<6;
let MASK_FLAG_EMPHASIZE_BLUE: u8      = 1<<7;

struct PPU {
  fn_trigger_non_maskable_interrupt: fn(),

  // maybe instead of storing the color id like this, 
  // we can store the actual color directly.
  palette:         [*]u8,
  // VRAM also known as nametable, which is 2KB long.
  // NES screen is 256 x 240 and composed of 8x8 tiles
  // so there are 256/8=32 tile width, and 240/8=30 tile height.
  // The first 32*30=960 bytes represent the tile used to render
  // the screen.
  // The next 64 bytes specify which color pallete to use. it's
  // defined every 4x4 tile.
  // So there are 960 + 64 = 1024 bytes to define a single frame.
  vram:            [*]u8,
  // object array mapper, 64 * 4 bytes.
  oam:             [*]u8,
  mirroring:       u8,

  reg: Register,

  // for data transfer between cpu and ppu
  addr_lo:       u8,
  addr_hi:       u8,
  data:          u8,
  is_reading_lo: bool,
  oam_addr:      u8,

  scroll_x:     u8,
  scroll_y:     u8,
  scroll_latch: bool,

  screen_framebuffer: [*]Color,
  background_mask:    [*]u8,

  debug: Debug,

  cycles:   i32,
  scanline: i32,
}

struct Register {
  control: u8,
  status:  u8,
  mask:    u8,
}

struct Debug {
  tile_framebuffer:        [*]Color,
  palette_framebuffer:     [*]Color,
  debug_palette_id:        u8,
  nametable_1_framebuffer: [*]Color,
  nametable_2_framebuffer: [*]Color,
  nametable_3_framebuffer: [*]Color,
  nametable_4_framebuffer: [*]Color,
}

fn new(fn_trigger_nmi: fn()): *PPU {
  let p = mem::alloc::<PPU>();

  p.fn_trigger_non_maskable_interrupt.* = fn_trigger_nmi;

  // tile framebuffer stores 2 banks of 256 tile of 8x8 pixels of RGBa channel
  // so the size is 2*256*8*8 = 0x8000
  p.debug.tile_framebuffer.*        = mem::alloc_array::<Color>(0x8000);
  p.debug.palette_framebuffer.*     = mem::alloc_array::<Color>(1 + 4*4 + 4*4);
  p.debug.nametable_1_framebuffer.* = mem::alloc_array::<Color>(256 * 256);
  p.debug.nametable_2_framebuffer.* = mem::alloc_array::<Color>(256 * 256);
  p.debug.nametable_3_framebuffer.* = mem::alloc_array::<Color>(256 * 256);
  p.debug.nametable_4_framebuffer.* = mem::alloc_array::<Color>(256 * 256);
  p.vram.*                          = mem::alloc_array::<u8>(0x800);
  p.palette.*                       = mem::alloc_array::<u8>(0x20);
  p.oam.*                           = mem::alloc_array::<u8>(64 * 4);
  p.oam_addr.*                      = 0;
  p.screen_framebuffer.*            = mem::alloc_array::<Color>(256 * 256); // technically only 256 x 240 is used
  p.background_mask.*               = mem::alloc_array::<u8>(256 * 256); // technically only 256 x 240 is used

  reset(p);
  return p;
}

fn load_rom(ppu: *PPU, cart: *rom::ROM) {
  ppu.mirroring.* = cart.mirroring.*;

  update_debug_chr_tile(ppu);
}

fn reset(ppu: *PPU) {
  ppu.reg.control.*   = 0;
  ppu.reg.status.*    = 0;
  ppu.addr_lo.*       = 0;
  ppu.addr_hi.*       = 0;
  ppu.data.*          = 0;
  ppu.is_reading_lo.* = false;
  ppu.oam_addr.*      = 0;
  ppu.scroll_x.*      = 0;
  ppu.scroll_y.*      = 0;
  ppu.scroll_latch.*  = false;
  ppu.cycles.*        = 0;

  // vram,palette,oam,screenframebuffer
  let i = 0;
  while i < 0x800 {
    ppu.vram.*[i].* = 0;
    i = i + 1;
  }

  let i = 0;
  while i < 0x20 {
    ppu.palette.*[i].* = 0;
    i = i + 1;
  }

  let i = 0;
  while i < 64*4 {
    ppu.oam.*[i].* = 0;
    i = i + 1;
  }

  let i = 0;
  while i < 256 * 240 {
    ppu.screen_framebuffer.*[i].* = Color{r:0,g:0,b:0,a:0};
    ppu.background_mask.*[i].* = 0;
    i = i + 1;
  }
}

fn tick(ppu: *PPU, cycles: i64) {
  ppu.cycles.* = ppu.cycles.* + cycles as i32;

  while ppu.cycles.* >= 341 {
    // fmt::print_str("scanline=");
    // fmt::print_i32(ppu.scanline.*);
    // fmt::print_str("scroll_x=");
    // fmt::print_u8(ppu.scroll_x.*);
    // fmt::print_str(",scroll_y=");
    // fmt::print_u8(ppu.scroll_y.*);
    // fmt::print_str(",selected_nametable=");
    // let selected_nametable: u8 = (ppu.reg.control.* & CONTROL_FLAG_NAMETABLE_1) | (ppu.reg.control.* & CONTROL_FLAG_NAMETABLE_2);
    // fmt::print_u8(selected_nametable);
    // fmt::print_str("\n");

    let is_zero_hit = false;
    if ppu.scanline.* < 240 {
      let hit = render_background(ppu, ppu.scanline.*);
      if (ppu.reg.mask.* & MASK_FLAG_SPRITE) != 0 {
        is_zero_hit = hit;
      }
    }

    if is_zero_hit {
      // fmt::print_str("zero hit on scanline=");
      // fmt::print_i32(ppu.scanline.* as i32);
      // fmt::print_str(",scroll_x=");
      // fmt::print_u8(ppu.scroll_x.*);
      // fmt::print_str(",scroll_y=");
      // fmt::print_u8(ppu.scroll_y.*);
      // fmt::print_str(",sprite0_x=");
      // fmt::print_u8(ppu.oam.*[3].*);
      // fmt::print_str(",sprite0_y=");
      // fmt::print_u8(ppu.oam.*[0].*);
      // fmt::print_str("\n");
      ppu.reg.status.* = ppu.reg.status.* | STATUS_FLAG_ZERO_HIT;
    }

    ppu.cycles.* = ppu.cycles.* - 341;
    ppu.scanline.* = ppu.scanline.* + 1;

    if ppu.scanline.* == 241 {
      ppu.reg.status.* = ppu.reg.status.* | STATUS_FLAG_VBLANK_STARTED;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_ZERO_HIT;
      if (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0 {
        ppu.fn_trigger_non_maskable_interrupt.*();
      }
    }
    if ppu.scanline.* >= 262 {
      ppu.scanline.* = 0;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_ZERO_HIT;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_VBLANK_STARTED;
    }
  }
}

fn render(ppu: *PPU) {
  render_objects(ppu);
  update_debug_chr_tile(ppu);

  render_nametable(ppu, 0, ppu.debug.nametable_1_framebuffer.*);
  render_nametable(ppu, 1, ppu.debug.nametable_2_framebuffer.*);
  render_nametable(ppu, 2, ppu.debug.nametable_3_framebuffer.*);
  render_nametable(ppu, 3, ppu.debug.nametable_4_framebuffer.*);
}

fn set_register(ppu: *PPU, id: u8, data: u8) {
  // fmt::print_str("set_register id=");
  // fmt::print_u8(id);
  // fmt::print_str(",data=");
  // fmt::print_u8(data);
  // fmt::print_str("\n");

  if id == 0 {
    let old_nmi_status = (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0;
    ppu.reg.control.* = data;
    let new_nmi_status = (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0;
    let status_vblank = (ppu.reg.status.* & STATUS_FLAG_VBLANK_STARTED) != 0;
    if !old_nmi_status && new_nmi_status && status_vblank {
      ppu.fn_trigger_non_maskable_interrupt.*();
    }
  } else if id == 1 {
    ppu.reg.mask.* = data;
  } else if id == 2 {
    fmt::print_str("register 2 is read only\n");
    wasm::trap();
  } else if id == 3 {
    ppu.oam_addr.* = data;
  } else if id == 4 {
    write_oam(ppu, data);
  } else if id == 5 {
    if ppu.scroll_latch.* {
      ppu.scroll_y.* = data;
    } else {
      ppu.scroll_x.* = data;
    }
    ppu.scroll_latch.* = !ppu.scroll_latch.*;
  } else if id == 6 {
    put_addr(ppu, data);
  } else if id == 7 {
    write_data(ppu, data);
  } else {
    fmt::print_str("setting invalid register id ");
    fmt::print_u8(id);
    fmt::print_str("\n");
    wasm::trap();
  }
}

fn get_register(ppu: *PPU, id: u8): u8 {
  if id == 0 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 1 {
    fmt::print_str("register 1 is write only\n"); wasm::trap();
  } else if id == 2 {
    let reg = ppu.reg.status.*;
    ppu.reg.status.* = reg & ~STATUS_FLAG_VBLANK_STARTED;
    ppu.scroll_latch.* = false;
    ppu.is_reading_lo.* = false;
    return reg;
  } else if id == 3 {
    fmt::print_str("register 3 is write only\n"); wasm::trap();
  } else if id == 4 {
    return ppu.oam.*[ppu.oam_addr.*].*;
  } else if id == 5 {
    fmt::print_str("register 5 is write only\n"); wasm::trap();
  } else if id == 6 {
    fmt::print_str("register 6 is write only\n"); wasm::trap();
  } else if id == 7 {
    return read_data(ppu);
  } else {
    fmt::print_str("setting invalid register id ");
    fmt::print_u8(id);
    fmt::print_str("\n");
    wasm::trap();
  }

  return 0;
}

fn put_addr(ppu: *PPU, addr: u8) {
  if ppu.is_reading_lo.* {
    ppu.addr_lo.* = addr;
  } else {
    ppu.addr_hi.* = addr;
  }
  ppu.is_reading_lo.* = !ppu.is_reading_lo.*;
}

// When reading while the VRAM address is in the range 0–$3EFF (i.e., before the palettes), the read will return the
// contents of an internal read buffer. This internal buffer is updated only when reading PPUDATA, and so is preserved
// across frames. After the CPU reads and gets the contents of the internal buffer, the PPU will immediately update the
// internal buffer with the byte at the current VRAM address. Thus, after setting the VRAM address, one should first
// read this register to prime the pipeline and discard the result.
// source: https://www.nesdev.org/wiki/PPU_registers#Address_($2006)_%3E%3E_write_x2
fn read_data(ppu: *PPU): u8 {
  let addr = get_addr(ppu);
  inc_addr(ppu);

  if addr >= 0x3000 && addr < 0x3f00 {
    addr = addr - 0x2000;
  }

  if addr < 0x2000 {
    let data = ppu.data.*;
    ppu.data.* = rom::read_chr(bus::the_rom, addr);
    return data;
  } else if addr < 0x3000 {
    let data = ppu.data.*;
    let addr = mirror_vram(ppu.mirroring.*, addr - 0x2000);
    ppu.data.* = ppu.vram.*[addr].*;
    return data;
  } else if addr < 0x3f00 {
    fmt::print_str("should be impossible")
    wasm::trap();
  } else if addr < 0x4000 {
    // addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C
    // source: https://www.nesdev.org/wiki/PPU_palettes
    if addr >= 0x3f20 {
      addr = (addr - 0x3f00) % 0x20 + 0x3f00;
    }
    if addr == 0x3f10 || addr == 0x3f14 || addr == 0x3f18 || addr == 0x3f1c {
      addr = addr - 0x10;
    }
    return ppu.palette.*[addr-0x3f00].*;
  } else {
    fmt::print_str("reading addr above 3f00\n")
    wasm::trap();
  }

  return 0;
}

// Reference: https://www.nesdev.org/wiki/Mirroring
fn mirror_vram(mirroring: u8, index: u16): u16 {
  // nametable map:
  // 0 1
  // 2 3
  let name_table = index / 0x400;
  if mirroring == rom::MIRRORING_HORIZONTAL {
    // [A][a]
    // [B][b]
    if name_table == 1 || name_table == 2 {
      return index - 0x400;
    } else if name_table == 3 {
      return index - 0x800;
    } else {
      return index;
    }
  } else if mirroring == rom::MIRRORING_VERTICAL {
    // [A][B]
    // [a][b]
    if name_table == 2 || name_table == 3 {
      return index - 0x800;
    } else {
      return index;
    }
  } else if mirroring == rom::MIRRORING_FOUR_SCREEN {
    // [A][B]
    // [C][D]
    return index;
  }

  // [A][a]
  // [a][a]
  return index % 0x400;
}

fn write_data(ppu: *PPU, data: u8) {
  let addr = get_addr(ppu);
  // fmt::print_str("write data to ppu ");
  // fmt::print_u16(addr);
  // fmt::print_str(", data=");
  // fmt::print_u8(data);
  // fmt::print_str("\n");
  inc_addr(ppu);

  if addr >= 0x3000 && addr < 0x3f00 {
    addr = addr - 0x2000;
  }

  if addr < 0x2000 {
    rom::write_chr(bus::the_rom, addr, data);
  } else if addr < 0x3000 {
    let addr = mirror_vram(ppu.mirroring.*, addr - 0x2000);
    ppu.vram.*[addr].* = data;
  } else if addr < 0x3f00 {
    fmt::print_str("should be impossible\n");
    wasm::trap();
  } else if addr < 0x4000 {
    // fmt::print_str("write to palettte addr=");
    // fmt::print_u16(addr);
    // fmt::print_str(",data=");
    // fmt::print_u8(data);
    // fmt::print_str("\n");

    // addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C
    // source: https://www.nesdev.org/wiki/PPU_palettes
    if addr >= 0x3f20 {
      addr = (addr - 0x3f00) % 0x20 + 0x3f00;
    }
    if addr == 0x3f10 || addr == 0x3f14 || addr == 0x3f18 || addr == 0x3f1c {
      addr = addr - 0x10;
    }

    ppu.palette.*[addr-0x3f00].* = data;
    let color = get_color(data);
    ppu.debug.palette_framebuffer.*[addr-0x3f00].* = color;
  } else {
    fmt::print_str("writing addr above 0x4000\n")
    wasm::trap();
  }
}

fn inc_addr(ppu: *PPU) {
  let increment: u8 = 1;
  if (ppu.reg.control.* & CONTROL_FLAG_VRAM_ADD) != 0 {
    increment = 32;
  }

  let lo = ppu.addr_lo.*;
  ppu.addr_lo.* = lo + increment;
  if lo > ppu.addr_lo.* {
    ppu.addr_hi.* = ppu.addr_hi.* + 1;
  }
}

fn get_addr(ppu: *PPU): u16 {
  let addr = (ppu.addr_hi.* as u16 << 8) | (ppu.addr_lo.* as u16);
  if addr >= 0x4000 {
    addr = addr & 0x3fff;
  }
  return addr;
}

fn write_oam(ppu: *PPU, data: u8) {
  ppu.oam.*[ppu.oam_addr.*].* = data;
  ppu.oam_addr.* = ppu.oam_addr.* + 1;
}

struct Color {
  r: u8,
  g: u8,
  b: u8,
  a: u8,
}

let palette: [*]Color = init_palette();

fn init_palette(): [*]Color {
  let map = mem::alloc_array::<Color>(0x40);

  map[ 0].* = Color{r: 0x80, g: 0x80, b: 0x80, a: 0xff};
  map[ 1].* = Color{r: 0x00, g: 0x3D, b: 0xA6, a: 0xff};
  map[ 2].* = Color{r: 0x00, g: 0x12, b: 0xB0, a: 0xff};
  map[ 3].* = Color{r: 0x44, g: 0x00, b: 0x96, a: 0xff};
  map[ 4].* = Color{r: 0xA1, g: 0x00, b: 0x5E, a: 0xff};
  map[ 5].* = Color{r: 0xC7, g: 0x00, b: 0x28, a: 0xff};
  map[ 6].* = Color{r: 0xBA, g: 0x06, b: 0x00, a: 0xff};
  map[ 7].* = Color{r: 0x8C, g: 0x17, b: 0x00, a: 0xff};
  map[ 8].* = Color{r: 0x5C, g: 0x2F, b: 0x00, a: 0xff};
  map[ 9].* = Color{r: 0x10, g: 0x45, b: 0x00, a: 0xff};
  map[10].* = Color{r: 0x05, g: 0x4A, b: 0x00, a: 0xff};
  map[11].* = Color{r: 0x00, g: 0x47, b: 0x2E, a: 0xff};
  map[12].* = Color{r: 0x00, g: 0x41, b: 0x66, a: 0xff};
  map[13].* = Color{r: 0x00, g: 0x00, b: 0x00, a: 0xff};
  map[14].* = Color{r: 0x05, g: 0x05, b: 0x05, a: 0xff};
  map[15].* = Color{r: 0x05, g: 0x05, b: 0x05, a: 0xff};
  map[16].* = Color{r: 0xC7, g: 0xC7, b: 0xC7, a: 0xff};
  map[17].* = Color{r: 0x00, g: 0x77, b: 0xFF, a: 0xff};
  map[18].* = Color{r: 0x21, g: 0x55, b: 0xFF, a: 0xff};
  map[19].* = Color{r: 0x82, g: 0x37, b: 0xFA, a: 0xff};
  map[20].* = Color{r: 0xEB, g: 0x2F, b: 0xB5, a: 0xff};
  map[21].* = Color{r: 0xFF, g: 0x29, b: 0x50, a: 0xff};
  map[22].* = Color{r: 0xFF, g: 0x22, b: 0x00, a: 0xff};
  map[23].* = Color{r: 0xD6, g: 0x32, b: 0x00, a: 0xff};
  map[24].* = Color{r: 0xC4, g: 0x62, b: 0x00, a: 0xff};
  map[25].* = Color{r: 0x35, g: 0x80, b: 0x00, a: 0xff};
  map[26].* = Color{r: 0x05, g: 0x8F, b: 0x00, a: 0xff};
  map[27].* = Color{r: 0x00, g: 0x8A, b: 0x55, a: 0xff};
  map[28].* = Color{r: 0x00, g: 0x99, b: 0xCC, a: 0xff};
  map[29].* = Color{r: 0x21, g: 0x21, b: 0x21, a: 0xff};
  map[30].* = Color{r: 0x09, g: 0x09, b: 0x09, a: 0xff};
  map[31].* = Color{r: 0x09, g: 0x09, b: 0x09, a: 0xff};
  map[32].* = Color{r: 0xFF, g: 0xFF, b: 0xFF, a: 0xff};
  map[33].* = Color{r: 0x0F, g: 0xD7, b: 0xFF, a: 0xff};
  map[34].* = Color{r: 0x69, g: 0xA2, b: 0xFF, a: 0xff};
  map[35].* = Color{r: 0xD4, g: 0x80, b: 0xFF, a: 0xff};
  map[36].* = Color{r: 0xFF, g: 0x45, b: 0xF3, a: 0xff};
  map[37].* = Color{r: 0xFF, g: 0x61, b: 0x8B, a: 0xff};
  map[38].* = Color{r: 0xFF, g: 0x88, b: 0x33, a: 0xff};
  map[39].* = Color{r: 0xFF, g: 0x9C, b: 0x12, a: 0xff};
  map[40].* = Color{r: 0xFA, g: 0xBC, b: 0x20, a: 0xff};
  map[41].* = Color{r: 0x9F, g: 0xE3, b: 0x0E, a: 0xff};
  map[42].* = Color{r: 0x2B, g: 0xF0, b: 0x35, a: 0xff};
  map[43].* = Color{r: 0x0C, g: 0xF0, b: 0xA4, a: 0xff};
  map[44].* = Color{r: 0x05, g: 0xFB, b: 0xFF, a: 0xff};
  map[45].* = Color{r: 0x5E, g: 0x5E, b: 0x5E, a: 0xff};
  map[46].* = Color{r: 0x0D, g: 0x0D, b: 0x0D, a: 0xff};
  map[47].* = Color{r: 0x0D, g: 0x0D, b: 0x0D, a: 0xff};
  map[48].* = Color{r: 0xFF, g: 0xFF, b: 0xFF, a: 0xff};
  map[49].* = Color{r: 0xA6, g: 0xFC, b: 0xFF, a: 0xff};
  map[50].* = Color{r: 0xB3, g: 0xEC, b: 0xFF, a: 0xff};
  map[51].* = Color{r: 0xDA, g: 0xAB, b: 0xEB, a: 0xff};
  map[52].* = Color{r: 0xFF, g: 0xA8, b: 0xF9, a: 0xff};
  map[53].* = Color{r: 0xFF, g: 0xAB, b: 0xB3, a: 0xff};
  map[54].* = Color{r: 0xFF, g: 0xD2, b: 0xB0, a: 0xff};
  map[55].* = Color{r: 0xFF, g: 0xEF, b: 0xA6, a: 0xff};
  map[56].* = Color{r: 0xFF, g: 0xF7, b: 0x9C, a: 0xff};
  map[57].* = Color{r: 0xD7, g: 0xE8, b: 0x95, a: 0xff};
  map[58].* = Color{r: 0xA6, g: 0xED, b: 0xAF, a: 0xff};
  map[59].* = Color{r: 0xA2, g: 0xF2, b: 0xDA, a: 0xff};
  map[60].* = Color{r: 0x99, g: 0xFF, b: 0xFC, a: 0xff};
  map[61].* = Color{r: 0xDD, g: 0xDD, b: 0xDD, a: 0xff};
  map[62].* = Color{r: 0x11, g: 0x11, b: 0x11, a: 0xff};
  map[63].* = Color{r: 0x11, g: 0x11, b: 0x11, a: 0xff};

  return map;
}

fn get_color(id: u8): Color {
  if id >= 64 {
    return Color{r: 0, g: 0, b: 0, a: 255};
  }
  return palette[id].*;
}

fn get_debug_tile_framebuffer(ppu: *PPU): Image {
  return Image {
    framebuffer: ppu.debug.tile_framebuffer.*,
    width:       32*8,
    height:      16*8,
  };
}

fn update_debug_chr_tile(ppu: *PPU) {
  let yi: u16 = 0;
  while yi < 16 {
    let bank: u16 = 0;
    while bank < 2 {
      let xi: u16 = 0;
      while xi < 16 {
        let chr_offset: u16 = yi*16*16 + xi*16 + bank * 0x1000;

        let y: u16 = 0;
        while y < 8 {
          let hi = rom::read_chr(bus::the_rom, chr_offset + y);
          let lo = rom::read_chr(bus::the_rom, chr_offset + y + 8);

          let x7 = ((lo & 0b0000_0001) << 1) |  (hi & 0b0000_0001);
          let x6 =  (lo & 0b0000_0010)       | ((hi & 0b0000_0010) >> 1);
          let x5 = ((lo & 0b0000_0100) >> 1) | ((hi & 0b0000_0100) >> 2);
          let x4 = ((lo & 0b0000_1000) >> 2) | ((hi & 0b0000_1000) >> 3);
          let x3 = ((lo & 0b0001_0000) >> 3) | ((hi & 0b0001_0000) >> 4);
          let x2 = ((lo & 0b0010_0000) >> 4) | ((hi & 0b0010_0000) >> 5);
          let x1 = ((lo & 0b0100_0000) >> 5) | ((hi & 0b0100_0000) >> 6);
          let x0 = ((lo & 0b1000_0000) >> 6) | ((hi & 0b1000_0000) >> 7);

          let framebuffer_offset = (yi * 32 * 8 * 8) + (y * 32 * 8) + (xi * 8) + (bank * 8*16);
          let framebuffer = ppu.debug.tile_framebuffer.*;
          set_debug_color(ppu, framebuffer[framebuffer_offset + 0], x0);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 1], x1);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 2], x2);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 3], x3);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 4], x4);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 5], x5);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 6], x6);
          set_debug_color(ppu, framebuffer[framebuffer_offset + 7], x7);

          y = y + 1;
        }

        xi = xi + 1;
      }
      bank = bank + 1;
    }
    yi = yi + 1;
  }
}

fn set_debug_color(ppu: *PPU, pixel: *Color, color_id: u8) {
  let c: u8 = 0;
  if color_id == 0 {
    c = ppu.palette.*[0].*;
  } else {
    c = ppu.palette.*[ppu.debug.debug_palette_id.* * 4 + color_id].*;
  }
  pixel.* = palette[c].*;
}

struct Image {
  framebuffer: [*]Color,
  width:       usize,
  height:      usize,
}

struct DebugPalette {
  none: Image,

  background_palette0: Image,
  background_palette1: Image,
  background_palette2: Image,
  background_palette3: Image,

  sprite_palette0: Image,
  sprite_palette1: Image,
  sprite_palette2: Image,
  sprite_palette3: Image,
}

fn get_debug_palette_framebuffer(ppu: *PPU): DebugPalette {
  return DebugPalette {
    none: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[0] as [*]Color,
      width: 1,
      height: 1,
    },

    background_palette0: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[1] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette1: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[5] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette2: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[9] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette3: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[13] as [*]Color,
      width: 4,
      height: 1,
    }

    sprite_palette0: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[17] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette1: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[21] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette2: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[25] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette3: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[29] as [*]Color,
      width: 4,
      height: 1,
    }
  };
}

fn render_background(ppu: *PPU, y: i32): bool {
  let scroll_x = (ppu.scroll_x.* as u32) as i32;
  let scroll_y = (ppu.scroll_y.* as u32) as i32;

  let name_a: u16 = 0;
  let name_b: u16 = 1;
  let name_c: u16 = 2;
  let name_d: u16 = 3;

  let selected_nametable: u8 = (ppu.reg.control.* & CONTROL_FLAG_NAMETABLE_1) | (ppu.reg.control.* & CONTROL_FLAG_NAMETABLE_2);
  let selected_nametable: u16 = selected_nametable as u16;

  name_a = selected_nametable;
  if selected_nametable == 0 {
    name_b = 1; name_c = 2; name_d = 3;
  } else if selected_nametable == 1 {
    name_b = 0; name_c = 3; name_d = 2;
  } else if selected_nametable == 2 {
    name_b = 3; name_c = 0; name_d = 1;
  } else {
    name_b = 2; name_c = 1; name_d = 0;
  }

  let pattern_addr: u16 = 0;
  if (ppu.reg.control.* & CONTROL_FLAG_BACKGROUND_PATTERN_ADDR) != 0 {
    pattern_addr = 0x1000;
  }

  let sprite0_x = ppu.oam.*[3].* as i32;
  let sprite0_y = ppu.oam.*[0].* as i32 + 1;
  let sprite0_tile_id = ppu.oam.*[1].* as u16;
  let sprite0_y_offset = y - sprite0_y;
  let sprite0_x_color: [*]u8 = mem::alloc_array::<u8>(8);
  sprite0_x_color[0].* = 0;
  sprite0_x_color[1].* = 0;
  sprite0_x_color[2].* = 0;
  sprite0_x_color[3].* = 0;
  sprite0_x_color[4].* = 0;
  sprite0_x_color[5].* = 0;
  sprite0_x_color[6].* = 0;
  sprite0_x_color[7].* = 0;
  if sprite0_y < 0xef && sprite0_y_offset >= 0 && sprite0_y_offset < 8 {
    let sprite_pattern_addr: u16 = 0;
    if (ppu.reg.control.* & CONTROL_FLAG_SPRITE_PATTERN_ADDR) != 0 {
      sprite_pattern_addr = 0x1000;
    }
    let sprite_chr_offset = sprite_pattern_addr + sprite0_tile_id * 16;
    let sprite0_hi = rom::read_chr(bus::the_rom, sprite_chr_offset + sprite0_y_offset as u16);
    let sprite0_lo = rom::read_chr(bus::the_rom, sprite_chr_offset + sprite0_y_offset as u16 + 8);
    sprite0_x_color[7].* = ((sprite0_lo & 0b0000_0001) << 1) |  (sprite0_hi & 0b0000_0001);
    sprite0_x_color[6].* =  (sprite0_lo & 0b0000_0010)       | ((sprite0_hi & 0b0000_0010) >> 1);
    sprite0_x_color[5].* = ((sprite0_lo & 0b0000_0100) >> 1) | ((sprite0_hi & 0b0000_0100) >> 2);
    sprite0_x_color[4].* = ((sprite0_lo & 0b0000_1000) >> 2) | ((sprite0_hi & 0b0000_1000) >> 3);
    sprite0_x_color[3].* = ((sprite0_lo & 0b0001_0000) >> 3) | ((sprite0_hi & 0b0001_0000) >> 4);
    sprite0_x_color[2].* = ((sprite0_lo & 0b0010_0000) >> 4) | ((sprite0_hi & 0b0010_0000) >> 5);
    sprite0_x_color[1].* = ((sprite0_lo & 0b0100_0000) >> 5) | ((sprite0_hi & 0b0100_0000) >> 6);
    sprite0_x_color[0].* = ((sprite0_lo & 0b1000_0000) >> 6) | ((sprite0_hi & 0b1000_0000) >> 7);
  }
  let touch_sprite_0 = false;

  let x: i32 = 0;
  while x < 256 {
    // region represent which nametable does pixel (x, y) fall into.
    // 0 means: it falls into the main nametable.
    // 1 means: it falls into the nametable in the right side of the main nametable.
    // 2 means: it falls into the nametable in the bottom side of the main nametable.
    // 3 means: it falls into the nametable in the bottom-right side of the main nametable.
    // here is the illustration:
    // [0][1]
    // [2][3]
    let region: u8 = 0;
    if (scroll_x + x) >= 256 {
      region = region + 1;
    }
    if (scroll_y + y) >= 240 {
      region = region + 2;
    }

    let x_relative_to_nametable = (scroll_x + x) % 256;
    let y_relative_to_nametable = (scroll_y + y) % 240;
    let tile_id_x = x_relative_to_nametable / 8;
    let tile_id_y = y_relative_to_nametable / 8;
    let tile_id = tile_id_y * 32 + tile_id_x;
    let tile_y = (y_relative_to_nametable % 8) as u8;
    let tile_x = (x_relative_to_nametable % 8) as u8;

    let vram_offset: u16 = 0;
    if region == 0 {
      vram_offset = name_a as u16 * 0x400;
    } else if region == 1 {
      vram_offset = name_b as u16 * 0x400;
    } else if region == 2 {
      vram_offset = name_c as u16 * 0x400;
    } else {
      vram_offset = name_d as u16 * 0x400;
    }

    let nametable = ppu.vram.*[mirror_vram(ppu.mirroring.*, vram_offset)] as [*]u8;
    let attribute_byte_offset = (tile_id_y / 4) * 8 + (tile_id_x / 4);
    let attribute_byte = nametable[32 * 30 + attribute_byte_offset as isize].*;
    let attr_y = (tile_id_y % 4) / 2;
    let attr_x = (tile_id_x % 4) / 2;
    let palette_id: u8 = 0;
    if attr_y == 0 && attr_x == 0 {
      palette_id = (attribute_byte >> 0) & 0b11;
    } else if attr_y == 0 && attr_x == 1 {
      palette_id = (attribute_byte >> 2) & 0b11;
    } else if attr_y == 1 && attr_x == 0 {
      palette_id = (attribute_byte >> 4) & 0b11;
    } else if attr_y == 1 && attr_x == 1 {
      palette_id = (attribute_byte >> 6) & 0b11;
    }

    let tile_id = nametable[tile_id].*;
    let chr_offset = pattern_addr + tile_id as u16 * 16;
    let hi = rom::read_chr(bus::the_rom, chr_offset + tile_y as u16);
    let lo = rom::read_chr(bus::the_rom, chr_offset + tile_y as u16 + 8);
    let msb: u8 = 0;
    if (tile_x == 7 && (lo & 1) != 0) || (lo & (0b1000_0000 >> tile_x)) != 0 {
      msb = 1;
    }
    let lsb: u8 = 0;
    if (hi & (0b1000_0000 >> tile_x)) != 0 {
      lsb = 1;
    }
    let color_offset = (msb << 1) | lsb;

    if (x - sprite0_x) >= 0 && (x - sprite0_x) < 8  {
      let sprite_color = sprite0_x_color[x - sprite0_x].*;
      if sprite_color != 0 {
        touch_sprite_0 = true;
      }
    }

    set_background_color(ppu, palette_id, ppu.screen_framebuffer.*[y*256+x], color_offset);
    ppu.background_mask.*[y*256+x].* = color_offset;

    x = x + 1;
  }

  mem::dealloc_array::<u8>(sprite0_x_color);
  return touch_sprite_0;
}

fn set_background_color(ppu: *PPU, palette_id: u8, pixel: *Color, color_offset: u8) {
  let color_idx: u8 = 0;
  if color_offset == 0 {
    color_idx = ppu.palette.*[0].*;
  } else {
    color_idx = ppu.palette.*[palette_id * 4 + color_offset].*;
  }
  pixel.* = palette[color_idx].*;
}

fn get_screen_framebuffer(ppu: *PPU): Image {
  return Image{
    framebuffer: ppu.screen_framebuffer.*,
    width:       32*8,
    height:      30*8,
  };
}

fn render_nametable(ppu: *PPU, nametable: u8, framebuffer: [*]Color) {
  let nametable: u16 = nametable as u16;
  let nametable = nametable * 0x400;
  let nametable = mirror_vram(ppu.mirroring.*, nametable);

  let pattern_addr: u16 = 0;
  if (ppu.reg.control.* & CONTROL_FLAG_BACKGROUND_PATTERN_ADDR) != 0 {
    pattern_addr = 0x1000;
  }

  let yi: u16 = 0;
  while yi < 30 {
    let xi: u16 = 0;
    while xi < 32 {
      let vram_addr = nametable + (yi as u16) * 32 + (xi as u16);
      let tile_id = ppu.vram.*[vram_addr].* as u16;
      let chr_offset = pattern_addr + tile_id * 16;

      let attribute_byte_offset = (yi / 4) * 8 + (xi / 4);
      let attribute_byte = ppu.vram.*[nametable + 32 * 30 + attribute_byte_offset as u16].*;
      let attr_y = (yi % 4) / 2;
      let attr_x = (xi % 4) / 2;
      let palette_id: u8 = 0;
      if attr_y == 0 && attr_x == 0 {
        palette_id = (attribute_byte >> 0) & 0b11;
      } else if attr_y == 0 && attr_x == 1 {
        palette_id = (attribute_byte >> 2) & 0b11;
      } else if attr_y == 1 && attr_x == 0 {
        palette_id = (attribute_byte >> 4) & 0b11;
      } else if attr_y == 1 && attr_x == 1 {
        palette_id = (attribute_byte >> 6) & 0b11;
      }

      let y: u16 = 0;
      while y < 8 {
        let hi = rom::read_chr(bus::the_rom, chr_offset + y);
        let lo = rom::read_chr(bus::the_rom, chr_offset + y + 8);

        let x: u8 = 0;
        while x < 8 {
          let msb: u8 = 0;
          if (x == 7 && (lo & 1) != 0) || (lo & (0b1000_0000 >> x)) != 0 {
            msb = 1;
          }

          let lsb: u8 = 0;
          if (hi & (0b1000_0000 >> x)) != 0 {
            lsb = 1;
          }

          let color_offset = (msb << 1) | lsb;

          let screen_y = yi as isize * 8 + y as isize;
          let screen_x = xi as isize * 8 + x as isize;
          let framebuffer_offset = screen_y * 32 * 8 + screen_x;
          set_background_color(ppu, palette_id, framebuffer[framebuffer_offset], color_offset);

          x = x + 1;
        }

        y = y + 1;
      }

      xi = xi + 1;
    }
    yi = yi + 1;
  }
}

fn get_nametable_1_framebuffer(ppu: *PPU): Image {
  return Image{
    framebuffer: ppu.debug.nametable_1_framebuffer.*,
    width:       32*8,
    height:      30*8,
  };
}

fn get_nametable_2_framebuffer(ppu: *PPU): Image {
  return Image{
    framebuffer: ppu.debug.nametable_2_framebuffer.*,
    width:       32*8,
    height:      30*8,
  };
}

fn get_nametable_3_framebuffer(ppu: *PPU): Image {
  return Image{
    framebuffer: ppu.debug.nametable_3_framebuffer.*,
    width:       32*8,
    height:      30*8,
  };
}

fn get_nametable_4_framebuffer(ppu: *PPU): Image {
  return Image{
    framebuffer: ppu.debug.nametable_4_framebuffer.*,
    width:       32*8,
    height:      30*8,
  };
}

fn render_objects(ppu: *PPU) {
  if (ppu.reg.mask.* & MASK_FLAG_SPRITE) == 0 {
    return;
  }

  let render_left = (ppu.reg.mask.* & MASK_FLAG_SPRITE_LEFTMOST) != 0;

  let i = 63 * 4;
  while i >= 0 {
    let byte0 = ppu.oam.*[i+0].*;
    let byte1 = ppu.oam.*[i+1].*;
    let byte2 = ppu.oam.*[i+2].*;
    let byte3 = ppu.oam.*[i+3].*;

    let y = byte0;
    let x = byte3;
    let tile_id = byte1 as u16;

    if y >= 0xef {
      i = i - 4;
      continue;
    }

    y = y + 1;

    if !render_left && x < 8 {
      i = i - 4;
      continue;
    }

    // fmt::print_str("render object x=");
    // fmt::print_i32(x as i32);
    // fmt::print_str(" y=");
    // fmt::print_i32(y as i32);
    // fmt::print_str(" tile_id=");
    // fmt::print_u16(tile_id);
    // fmt::print_str("\n");

    let pattern_addr: u16 = 0;
    if (ppu.reg.control.* & CONTROL_FLAG_SPRITE_PATTERN_ADDR) != 0 {
      pattern_addr = 0x1000;
    }

    let palette_id = byte2 & 0b11;
    let behind_background = (byte2 & 0b0010_0000) != 0;
    let flip_vertical = (byte2 & 0b1000_0000) != 0;
    let flip_horizontal = (byte2 & 0b0100_0000) != 0;

    let chr_offset = pattern_addr + tile_id * 16;

    let y_offset: u16 = 0;
    while y_offset < 8 {
      let hi = rom::read_chr(bus::the_rom, chr_offset + y_offset);
      let lo = rom::read_chr(bus::the_rom, chr_offset + y_offset + 8);

      let x7 = ((lo & 0b0000_0001) << 1) |  (hi & 0b0000_0001);
      let x6 =  (lo & 0b0000_0010)       | ((hi & 0b0000_0010) >> 1);
      let x5 = ((lo & 0b0000_0100) >> 1) | ((hi & 0b0000_0100) >> 2);
      let x4 = ((lo & 0b0000_1000) >> 2) | ((hi & 0b0000_1000) >> 3);
      let x3 = ((lo & 0b0001_0000) >> 3) | ((hi & 0b0001_0000) >> 4);
      let x2 = ((lo & 0b0010_0000) >> 4) | ((hi & 0b0010_0000) >> 5);
      let x1 = ((lo & 0b0100_0000) >> 5) | ((hi & 0b0100_0000) >> 6);
      let x0 = ((lo & 0b1000_0000) >> 6) | ((hi & 0b1000_0000) >> 7);

      let y_final = y as u16 + y_offset;
      if flip_vertical {
        y_final = y as u16 + 7 - y_offset;
      }

      let framebuffer_offset = y_final * 32 * 8 + x as u16;

      if flip_horizontal {
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 0, x7);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 1, x6);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 2, x5);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 3, x4);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 4, x3);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 5, x2);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 6, x1);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 7, x0);
      } else {
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 0, x0);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 1, x1);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 2, x2);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 3, x3);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 4, x4);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 5, x5);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 6, x6);
        set_sprite_color(ppu, behind_background, palette_id, framebuffer_offset + 7, x7);
      }

      y_offset = y_offset + 1;
    }

    i = i - 4;
  }
}

fn set_sprite_color(ppu: *PPU, behind_background: bool, palette_id: u8, fb_offset: u16, color_offset: u8) {
  if color_offset == 0 {
    return;
  }

  if behind_background && (ppu.background_mask.*[fb_offset].* != 0) {
    return;
  }

  let color_idx = ppu.palette.*[(palette_id+4) * 4 + color_offset].*;
  ppu.screen_framebuffer.*[fb_offset].* = palette[color_idx].*;
}
