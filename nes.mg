import mem "mem";
import rom "rom";
import bus "bus";
import cpu "cpu";
import ppu "ppu";
import fmt "fmt";

@wasm_export("onKeyupArrowUp")
fn on_keyup_arrow_up() {}

@wasm_export("onKeyupArrowLeft")
fn on_keyup_arrow_left() {}

@wasm_export("onKeyupArrowRight")
fn on_keyup_arrow_right() {}

@wasm_export("onKeyupArrowDown")
fn on_keyup_arrow_down() {}

@wasm_export("onKeydownArrowUp")
fn on_keydown_arrow_up() {
  bus::write(0x00ff, 0x77);
}

@wasm_export("onKeydownArrowLeft")
fn on_keydown_arrow_left() {
  bus::write(0x00ff, 0x61);
}

@wasm_export("onKeydownArrowRight")
fn on_keydown_arrow_right() {
  bus::write(0x00ff, 0x64);
}

@wasm_export("onKeydownArrowDown")
fn on_keydown_arrow_down() {
  bus::write(0x00ff, 0x73);
}

@wasm_export("tick")
fn tick() {
  cpu::tick(bus::the_cpu);
}

let rom_buffer: [*]u8 = mem::alloc_array::<u8>(0x10000);
@wasm_export("getRom")
fn get_rom(): [*]u8 {
  return rom_buffer;
}

struct LoadRomResult {
  valid: bool,
  error: [*]u8,
}

@wasm_export("loadRom")
fn load_rom(): LoadRomResult {
  let result = rom::load(rom_buffer);
  if !result.valid {
    return LoadRomResult{valid: false, error: result.error};
  }

  bus::the_rom.* = result;

  ppu::load_rom(bus::the_ppu, bus::the_rom);

  return LoadRomResult{valid: true, error: 0 as [*]u8};
}

@wasm_export("getRam")
fn get_ram(): [*]u8 {
  return bus::ram as [*]u8;
}

@wasm_export("getFrameBuffer")
fn get_frame_buffer(): [*]u8 {
  return bus::ram[0x200] as [*]u8;
}

@wasm_export("reset")
fn reset() {
  // bus::write(0xfffc, 0x00);
  // bus::write(0xfffd, 0x06);
  // bus::write(0x00fe, 0x2a);
  cpu::reset(bus::the_cpu);
  ppu::reset(bus::the_ppu);
}

@wasm_export("debugCPU")
fn debug_cpu(): cpu::CPU {
  return bus::the_cpu.*;
}

@wasm_export("getDebugTileFramebufer")
fn get_debug_tile_framebuffer(): [*]u8 {
  return bus::the_ppu.debug.tile_framebuffer.*;
}

