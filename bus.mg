import mem "mem";
import fmt "fmt";

let ram: [*]u8 = mem::alloc_array::<u8>(0xffff);

fn read(addr: u16): u8 {
  if addr == 0x00fe {
    return next_random_u8();
  }
  return ram[addr].*;
}

let debug: bool = false;
fn write(addr: u16, data: u8) {
  if debug {
    fmt::print_str("write addr=");
    fmt::print_u16(addr);
    fmt::print_str(",data=");
    fmt::print_u8(data);
    fmt::print_str("\n");
  }
  ram[addr].* = data;
}

let a: u8 = 0x13;
let c: u8 = 0x0a;
let x: u8 = 0xfe;
fn next_random_u8(): u8 {
  x = a * x + c;
  return x;
}
