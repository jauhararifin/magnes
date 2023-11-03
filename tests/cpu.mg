import cpu "cpu";
import bus "bus";
import mem "mem";
import wasm "wasm";

@wasm_export("cpu_test1")
fn test1() {
  // LDA #$c0
  // TAX
  // INX
  // BRK
  load_ram("\xa9\xc0\xaa\xe8\x00");

  let c = mem::alloc::<cpu::CPU>();
  c.* = cpu::new();
  cpu::reset(c);
  cpu::tick(c);
  if c.reg.x.* != 0xc1 {
    wasm::trap();
  }
}

fn load_ram(data: [*]u8) {
  let i: usize = 0;
  while i < 0x800 {
    bus::ram[i].* = data[i].*;
    i = i + 1;
  }
}
