import mem "mem";
import fmt "fmt";
import wasm "wasm";
import cpu "cpu";
import rom "rom";
import ppu "ppu";
import joypad "joypad";

let the_cpu: *cpu::CPU = cpu::new();
let the_ppu: *ppu::PPU = ppu::new();
let the_rom: *rom::ROM = mem::alloc::<rom::ROM>();
let ram: [*]u8 = mem::alloc_array::<u8>(0x2000);
let debug: bool = false;
let joypad_1: *joypad::Joypad = joypad::new();
let joypad_2: *joypad::Joypad = joypad::new();

fn init() {
  cpu::wire(the_cpu, read, write);
  ppu::wire(
    the_ppu,
    send_non_maskable_interrupt,
    read_chr_rom,
    write_chr_rom,
  )
}

fn send_non_maskable_interrupt() {
  cpu::trigger_non_maskable_interrupt(the_cpu);
}

fn read_chr_rom(addr: u16): u8 {
  return rom::read_chr(the_rom, addr);
}

fn write_chr_rom(addr: u16, data: u8) {
  return rom::write_chr(the_rom, addr, data);
}

fn reset() {
  let i = 0;
  while i < 0x2000 {
    ram[i].* = 0;
    i = i + 1;
  }
}

fn read(addr: u16): u8 {
  if debug {
    fmt::print_str("read ");
    fmt::print_u16(addr);
    fmt::print_str("\n");
  }

  if (addr >= 0) && (addr < 0x2000) {
    if debug {
      fmt::print_u8(ram[addr & 0x07ff].*);
      fmt::print_str("\n");
    }
    return ram[addr & 0x07ff].*;
  } else if (addr >= 0x2000) && (addr < 0x4000) {
    let data = ppu::get_register(the_ppu, (addr & 0x07) as u8);
    return data;
  } else if addr == 0x4016 {
    return joypad::read(joypad_1);
  } else if addr == 0x4017 {
    return joypad::read(joypad_2);
  } else if addr >= 0x8000 {
    let addr = addr - 0x8000;
    return rom::read_program(the_rom, addr);
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
    if debug {
      fmt::print_str("set ppu register i=");
      fmt::print_u16(addr);
      fmt::print_str(",data=");
      fmt::print_u8(data);
      fmt::print_str("\n");
    }

    ppu::set_register(the_ppu, (addr as u8) & 0x07, data);
  } else if addr == 0x4014 {
    let addr = (data as u16) << 8;
    let i: u16 = 0;
    while i < 256 {
      let b = read(addr + i);
      ppu::write_oam(the_ppu, b);
      i = i + 1;
    }
  } else if addr == 0x4016 {
    joypad::write(joypad_1, data);
  } else if addr == 0x4017 {
    joypad::write(joypad_2, data);
  } else if addr >= 0x8000 {
    let addr = addr - 0x8000;
    return rom::write_program(the_rom, addr, data);
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
