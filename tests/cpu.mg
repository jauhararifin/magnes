import cpu "cpu";
import bus "bus";
import mem "mem";
import wasm "wasm";
import fmt "fmt";

@main()
fn main() {
  fmt::print_str("Running test1\n");
  test1();
  fmt::print_str("Passed\n");
}

fn test1() {
  // LDA #$c0 ; load a with 0xc0
  // TAX      ; transfer a to x
  // INX      ; increment x
  // BRK      ;
  load_ram("\xa9\xc0\xaa\xe8\x00", 5);

  let c = mem::alloc::<cpu::CPU>();
  c.* = cpu::new();
  cpu::reset(c);
  cpu::tick(c);
  if c.reg.a.* != 0xc0 {
    wasm::trap();
  }

  cpu::tick(c);
  if c.reg.x.* != 0xc0 {
    wasm::trap();
  }

  cpu::tick(c);
  if c.reg.a.* != 0xc0 {
    wasm::trap();
  }
  if c.reg.x.* != 0xc1 {
    wasm::trap();
  }
}

fn load_ram(data: [*]u8, size: usize) {
  let i: usize = 0;
  while i < size {
    bus::ram[i].* = data[i].*;
    i = i + 1;
  }
}
