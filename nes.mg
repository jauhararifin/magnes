import mem "mem";
import bus "bus";
import cpu "cpu";

let the_cpu: *cpu::CPU = init_cpu();

fn init_cpu(): *cpu::CPU {
  let c = mem::alloc::<cpu::CPU>();
  c.* = cpu::new()
  return c;
}

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
  cpu::tick(the_cpu);
}

@wasm_export("getRom")
fn get_rom(): [*]u8 {
  return bus::ram[0x600] as [*]u8;
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
  bus::write(0xfffc, 0x00);
  bus::write(0xfffd, 0x06);
  bus::write(0x00fe, 0x2a);
  cpu::reset(the_cpu);
}

@wasm_export("debugCPU")
fn debug_cpu(): cpu::CPU {
  return the_cpu.*;
}

@wasm_export("return_10")
fn return_10(): i32 {
  return 10;
}
