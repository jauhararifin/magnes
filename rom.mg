import fmt "fmt";

let MIRRORING_VERTICAL: u8 = 0;
let MIRRORING_HORIZONTAL: u8 = 1;
let MIRRORING_FOUR_SCREEN: u8 = 2;

let PRG_ROM_PAGE_SIZE: u16 = 0x4000;
let CHR_ROM_PAGE_SIZE: u16 = 0x2000;

let debug: bool = true;

struct ROM {
  valid:           bool,
  error:           [*]u8,
  program:         [*]u8,
  program_size:    u16,
  characters:      [*]u8,
  characters_size: u16,
  mapper:          u8,
  mirroring:       u8,
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

  let mapper = (raw_bytes[7].* & 0xf0) | (raw_bytes[6].* >> 4);

  let ines_ver = (raw_bytes[7].* >> 2) & 0b11;
  if ines_ver != 0 {
    return ROM{valid: false, error: "NES2.0 format is not supported"};
  }

  let four_screen = (raw_bytes[6].* & 0b1000) != 0;
  let vertical_mirroring = (raw_bytes[6].* & 0b1) != 0;
  let mirroring: u8;
  if four_screen {
    mirroring = MIRRORING_FOUR_SCREEN;
  } else if vertical_mirroring {
    mirroring = MIRRORING_VERTICAL;
  } else {
    mirroring = MIRRORING_HORIZONTAL;
  }

  let prg_rom_size = (raw_bytes[4].* as u16) * PRG_ROM_PAGE_SIZE;
  let chr_rom_size = (raw_bytes[5].* as u16) * CHR_ROM_PAGE_SIZE;

  if debug {
    fmt::print_str("program rom size = ");
    fmt::print_u16(prg_rom_size);
    fmt::print_str(", character rom size = ");
    fmt::print_u16(chr_rom_size);
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

  let prg_start: u16 = 16;
  if skip_trainer {
    prg_start = prg_start + 512;
  }
  let chr_start: u16 = prg_start + prg_rom_size;

  return ROM{
    valid:           true,
    error:           0 as [*]u8,
    program:         raw_bytes[prg_start] as [*]u8,
    program_size:    prg_rom_size,
    characters:      raw_bytes[chr_start] as [*]u8,
    characters_size: chr_rom_size,
    mapper:          mapper,
    mirroring:       mirroring,
  };
}
