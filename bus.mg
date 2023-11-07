import mem "mem";
import fmt "fmt";
import wasm "wasm";
import cpu "cpu";
import rom "rom";

let the_cpu: *cpu::CPU = init_cpu();
let the_rom: *rom::ROM = mem::alloc::<rom::ROM>();
let ram: [*]u8 = mem::alloc_array::<u8>(0x2000);
let ppu_register: [*]u8 = mem::alloc_array::<u8>(8);
let debug: bool = false;

fn init_cpu(): *cpu::CPU {
  let c = mem::alloc::<cpu::CPU>();
  c.* = cpu::new()
  return c;
}

fn read(addr: u16): u8 {
  if debug {
    fmt::print_str("read ");
    fmt::print_u16(addr);
    fmt::print_str(" = ");
  }

  if addr == 0x00fe {
    let r = next_random_u8() & 0xff;
    if debug {
      fmt::print_u8(r);
      fmt::print_str("\n");
    }
    return r;
  }

  if (addr >= 0) && (addr < 0x2000) {
    if debug {
      fmt::print_u8(ram[addr & 0x07ff].*);
      fmt::print_str("\n");
    }
    return ram[addr & 0x07ff].*;
  } else if (addr >= 0x2000) && (addr < 0x4000) {
    if debug {
      fmt::print_u8(ppu_register[addr & 0x07].*);
      fmt::print_str("\n");
    }
    return ppu_register[addr & 0x07].*;
  } else if addr >= 0x8000 {
    let addr = addr - 0x8000;
    if (the_rom.program_size.* == 0x4000) && (addr >= 0x4000) {
      addr = addr & 0x3fff;
    }
    if debug {
      fmt::print_u8(the_rom.program.*[addr].*);
      fmt::print_str(" (from rom at ");
      fmt::print_u16(addr);
      fmt::print_str(")\n");
    }
    return the_rom.program.*[addr].*;
  }

  if debug {
    fmt::print_str("invalid mem read at ");
    fmt::print_u16(addr);
    fmt::print_str("\n");
  }
  return 0;
}

fn write(addr: u16, data: u8) {
  if debug {
    fmt::print_str("write addr=");
    fmt::print_u16(addr);
    fmt::print_str(",data=");
    fmt::print_u8(data);
    fmt::print_str("\n");
  }

  if (addr >= 0) && (addr < 0x2000) {
    ram[addr & 0x07ff].* = data;
  } else if (addr >= 0x2000) && (addr < 0x4000) {
    ppu_register[addr & 0x07].* = data;
  } else {
    if debug {
      fmt::print_str("invalid write ");
      fmt::print_u8(data);
      fmt::print_str(" at ");
      fmt::print_u16(addr);
      fmt::print_str("\n");
    }
  }
}

let a: u8 = 0x13;
let c: u8 = 0x0a;
let x: u8 = 0xfe;
fn next_random_u8(): u8 {
  x = a * x + c;
  return x;
}
