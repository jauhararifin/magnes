import mem "mem";
import rom "rom";
import bus "bus";
import cpu "cpu";
import ppu "ppu";
import fmt "fmt";
import joypad "joypad";

let remaining_elapsed_nanosecond: i64 = 0;
let cycle_rate: i64 = 2_000_000; // cycles per second
let cycle_period: i64 = 1_000_000_000 / cycle_rate;
@wasm_export("tick")
fn tick(elapsed: i64) {
  remaining_elapsed_nanosecond = remaining_elapsed_nanosecond + elapsed;
  let cpu_cycle = remaining_elapsed_nanosecond / cycle_period;
  cpu::tick(bus::the_cpu, cpu_cycle);
  let ppu_cycle = cpu_cycle * 3;
  ppu::tick(bus::the_ppu, ppu_cycle);

  remaining_elapsed_nanosecond = remaining_elapsed_nanosecond % cycle_period;
}

let rom_buffer: [*]u8 = mem::alloc_array::<u8>(0x100000);
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

@wasm_export("reset")
fn reset() {
  bus::reset();
  rom::reset(bus::the_rom);
  cpu::reset(bus::the_cpu);
  ppu::reset(bus::the_ppu);
  joypad::reset(bus::joypad_1);
}

@wasm_export("debugCPU")
fn debug_cpu(): cpu::CPU {
  return bus::the_cpu.*;
}

@wasm_export("getDebugTileFramebufer")
fn get_debug_tile_framebuffer(): ppu::Image {
  return ppu::get_debug_tile_framebuffer(bus::the_ppu);
}

@wasm_export("getDebugPaletteImage")
fn get_debug_palette_framebuffer(): ppu::DebugPalette {
  return ppu::get_debug_palette_framebuffer(bus::the_ppu);
}

@wasm_export("setDebugPaletteId")
fn set_debug_palette_id(id: u8) {
  bus::the_ppu.debug.debug_palette_id.* = id;
}

@wasm_export("getScreenFramebuffer")
fn get_screen_framebuffer(): ppu::Image {
  return ppu::get_screen_framebuffer(bus::the_ppu);
}

@wasm_export("getNametable1Framebuffer")
fn get_nametable_1_framebuffer(): ppu::Image {
  return ppu::get_nametable_1_framebuffer(bus::the_ppu);
}

@wasm_export("getNametable2Framebuffer")
fn get_nametable_2_framebuffer(): ppu::Image {
  return ppu::get_nametable_2_framebuffer(bus::the_ppu);
}

@wasm_export("getNametable3Framebuffer")
fn get_nametable_3_framebuffer(): ppu::Image {
  return ppu::get_nametable_3_framebuffer(bus::the_ppu);
}

@wasm_export("getNametable4Framebuffer")
fn get_nametable_4_framebuffer(): ppu::Image {
  return ppu::get_nametable_4_framebuffer(bus::the_ppu);
}

@wasm_export("keydownJoypad1A")
fn keydown_joypad1_a() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_A); }

@wasm_export("keydownJoypad1B")
fn keydown_joypad1_b() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_B);}

@wasm_export("keydownJoypad1Select")
fn keydown_joypad1_select() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_SELECT);}

@wasm_export("keydownJoypad1Start")
fn keydown_joypad1_start() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_START);}

@wasm_export("keydownJoypad1Up")
fn keydown_joypad1_up() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_UP);}

@wasm_export("keydownJoypad1Down")
fn keydown_joypad1_down() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_DOWN); }

@wasm_export("keydownJoypad1Left")
fn keydown_joypad1_left() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_LEFT);}

@wasm_export("keydownJoypad1Right")
fn keydown_joypad1_right() { joypad::press(bus::joypad_1, joypad::JOYPAD_BUTTON_RIGHT);}

@wasm_export("keyupJoypad1A")
fn keyup_joypad1_a() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_A); }

@wasm_export("keyupJoypad1B")
fn keyup_joypad1_b() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_B);}

@wasm_export("keyupJoypad1Select")
fn keyup_joypad1_select() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_SELECT);}

@wasm_export("keyupJoypad1Start")
fn keyup_joypad1_start() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_START);}

@wasm_export("keyupJoypad1Up")
fn keyup_joypad1_up() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_UP);}

@wasm_export("keyupJoypad1Down")
fn keyup_joypad1_down() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_DOWN);}

@wasm_export("keyupJoypad1Left")
fn keyup_joypad1_left() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_LEFT);}

@wasm_export("keyupJoypad1Right")
fn keyup_joypad1_right() { joypad::unpress(bus::joypad_1, joypad::JOYPAD_BUTTON_RIGHT);}
