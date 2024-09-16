import fmt "fmt";
import wasm "wasm";
import mem "mem";

let MIRRORING_VERTICAL: u8 = 0;
let MIRRORING_HORIZONTAL: u8 = 1;
let MIRRORING_FOUR_SCREEN: u8 = 2;

let PRG_ROM_PAGE_SIZE: usize = 0x4000;
let CHR_ROM_PAGE_SIZE: usize = 0x2000;

let debug: bool = true;

struct ROM {
  valid:           bool,
  error:           [*]u8,
  program:         [*]u8,
  program_size:    usize,
  characters:      [*]u8,
  characters_size: usize,
  mirroring:       u8,
  mapper:          Mapper,
}

fn load(raw_bytes: [*]u8): ROM {
  if raw_bytes[0].* != 0x4e {
    return ROM{valid: false, error: "File is not a valid iNES file format"};
  }
  if raw_bytes[1].* != 0x45 {
    return ROM{valid: false, error: "File is not a valid iNES file format"};
  }
  if raw_bytes[2].* != 0x53 {
    return ROM{valid: false, error: "File is not a valid iNES file format"};
  }
  if raw_bytes[3].* != 0x1a {
    return ROM{valid: false, error: "File is not a valid iNES file format"};
  }

  let mapper_id = (raw_bytes[7].* & 0xf0) | (raw_bytes[6].* >> 4);
  if debug {
    fmt::print_str("program mapper = ");
    fmt::print_u8(mapper_id);
    fmt::print_str("\n");
  }

  let mapper: Mapper;
  if mapper_id == 0 {
    mapper = mapper0;
  } else if mapper_id == 2 {
    mapper = mapper2;
  } else {
    return ROM{valid: false, error: "The rom uses mapper type that is not supported"};
  }

  let ines_ver = (raw_bytes[7].* >> 2) & 0b11;
  if ines_ver != 0 {
    return ROM{valid: false, error: "NES2.0 format is not supported"};
  }

  let four_screen = (raw_bytes[6].* & 0b1000) != 0;
  let vertical_mirroring = (raw_bytes[6].* & 0b1) != 0;
  let mirroring: u8;
  if four_screen {
    mirroring = MIRRORING_FOUR_SCREEN;
    if debug {
      fmt::print_str("mirroring=four screen\n");
    }
  } else if vertical_mirroring {
    mirroring = MIRRORING_VERTICAL;
    if debug {
      fmt::print_str("mirroring=vertical\n");
    }
  } else {
    mirroring = MIRRORING_HORIZONTAL;
    if debug {
      fmt::print_str("mirroring=horizontal\n");
    }
  }

  let prg_rom_size = (raw_bytes[4].* as usize) * PRG_ROM_PAGE_SIZE;
  let chr_rom_size = (raw_bytes[5].* as usize) * CHR_ROM_PAGE_SIZE;

  if debug {
    fmt::print_str("program rom size = ");
    fmt::print_usize(prg_rom_size);
    fmt::print_str(", character rom size = ");
    fmt::print_usize(chr_rom_size);
    fmt::print_str("\n");
  }

  let skip_trainer = (raw_bytes[6].* & 0b100) != 0;

  if debug {
    if skip_trainer {
      fmt::print_str("skip_trainer = true\n");
    } else {
      fmt::print_str("skip_trainer = false\n");
    }
  }

  let prg_start: usize = 16;
  if skip_trainer {
    prg_start = prg_start + 512;
  }
  let chr_start: usize = prg_start + prg_rom_size;

  return ROM{
    valid:           true,
    error:           0 as [*]u8,
    program:         raw_bytes[prg_start] as [*]u8,
    program_size:    prg_rom_size,
    characters:      raw_bytes[chr_start] as [*]u8,
    characters_size: chr_rom_size,
    mirroring:       mirroring,
    mapper:          mapper,
  };
}

fn reset(rom: *ROM) {
  rom.mapper.reset.*(rom);
}

fn read_program(rom: *ROM, addr: u16): u8 {
  return rom.mapper.read_prg.*(rom, addr);
}

fn write_program(rom: *ROM, addr: u16, data: u8) {
  rom.mapper.write_prg.*(rom, addr, data);
}

fn read_chr(rom: *ROM, addr: u16): u8 {
  return rom.mapper.read_chr.*(rom, addr);
}

fn write_chr(rom: *ROM, addr: u16, data: u8) {
  rom.mapper.write_chr.*(rom, addr, data);
}

let mapper0: Mapper = Mapper {
  id:        0,
  reset:     mapper_0_reset,
  read_prg:  mapper_0_read_prg,
  write_prg: mapper_0_write_prg,
  read_chr:  mapper_0_read_chr,
  write_chr: mapper_0_write_chr,
};

let mapper2: Mapper = Mapper {
  id:        2,
  reset:     mapper_2_reset,
  read_prg:  mapper_2_read_prg,
  write_prg: mapper_2_write_prg,
  read_chr:  mapper_2_read_chr,
  write_chr: mapper_2_write_chr,
};

struct Mapper {
  id:        u8,
  reset:     fn(rom: *ROM),
  read_prg:  fn(rom: *ROM, addr: u16): u8,
  write_prg: fn(rom: *ROM, addr: u16, data: u8),
  read_chr:  fn(rom: *ROM, addr: u16): u8,
  write_chr: fn(rom: *ROM, addr: u16, data: u8),
}

fn mapper_0_reset(rom: *ROM) {
}

fn mapper_0_read_prg(rom: *ROM, addr: u16): u8 {
  if (rom.program_size.* == 0x4000) && (addr >= 0x4000) {
    addr = addr & 0x3fff;
  }
  return rom.program.*[addr].*;
}

fn mapper_0_write_prg(rom: *ROM, addr: u16, data: u8) {
  fmt::print_str("invalid write to ROM program at ");
  fmt::print_u16(addr);
  fmt::print_str("\n");
}

fn mapper_0_read_chr(rom: *ROM, addr: u16): u8 {
  return rom.characters.*[addr].*;
}

fn mapper_0_write_chr(rom: *ROM, addr: u16, data: u8) {
  rom.characters.*[addr].* = data;
}

// TODO: move this into local variable
let mapper_2_selected_bank: u8 = 0;
let fallback_chr_rom: [*]u8 = mem::alloc_array::<u8>(0x2000);

fn mapper_2_reset(rom: *ROM) {
  mapper_2_selected_bank = 0;
  let i = 0;
  while i < 0x2000 {
    fallback_chr_rom[i].* = 0;
    i = i + 1;
  }
}

fn mapper_2_read_prg(rom: *ROM, addr: u16): u8 {
  if addr >= 0x4000 {
    return rom.program.*[rom.program_size.* - PRG_ROM_PAGE_SIZE + addr as usize - 0x4000].*;
  }

  return rom.program.*[mapper_2_selected_bank as usize * 0x4000 + addr as usize].*;
}

fn mapper_2_write_prg(rom: *ROM, addr: u16, data: u8) {
  mapper_2_selected_bank = data & 0x0f;
}

fn mapper_2_read_chr(rom: *ROM, addr: u16): u8 {
  if rom.characters_size.* < addr as usize {
    return fallback_chr_rom[addr].*;
  }
  return rom.characters.*[addr].*;
}

fn mapper_2_write_chr(rom: *ROM, addr: u16, data: u8) {
  if rom.characters_size.* < addr as usize {
    fallback_chr_rom[addr].* = data;
    return;
  }
  rom.characters.*[addr].* = data;
}
