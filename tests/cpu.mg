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

  fmt::print_str("Running test2\n");
  test2();
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
    fmt::print_str("1. register a is not 0xc0\n");
    wasm::trap();
  }

  cpu::tick(c);
  if c.reg.x.* != 0xc0 {
    fmt::print_str("2. register x is not 0xc0\n");
    wasm::trap();
  }

  cpu::tick(c);
  if c.reg.a.* != 0xc0 {
    fmt::print_str("3. register a is not 0xc0\n");
    wasm::trap();
  }
  if c.reg.x.* != 0xc1 {
    fmt::print_str("4. register x is not 0xc1\n");
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

fn test2() {
  let pc: u16 = 0x6cc;
  let operand: u8 = 0xf9;
  let result: u16 = ((operand as i8) as u16) + pc + 1;
  if result != 0x6c6 {
    fmt::print_u16(result);
    fmt::print_str("\n");
    wasm::trap();
  }
}
