import wasm "wasm";
import mem "mem";
import fmt "fmt";
import rom "rom";

// PPU memory map
// [0x0000 - 0x2000): pattern table (the characters rom)
// [0x2000 - 0x3f00): name table
// [0x3f00 - 0x4000): palette
// [0x4000 - 0xffff]: mirror all of the above (0x0000 - 0x3fff)
//
// CPU memory map
// 0x2000 - 0x2007: PPU registers
// 0x2008 - 0x3fff: mirror of PPU registers
//
// PPU registers:
// 0x2000: Controller  (write only)
// 0x2001: Mask        (write only)
// 0x2002: Status      (read only)
// 0x2003: OAM Address
// 0x2004: OAM Data
// 0x2005: Scroll      (write only)
// 0x2006: Address
// 0x2007: Data
//
// 0x4014: OAM DMA

let CONTROL_FLAG_NAMETABLE_1: u8             = 1;
let CONTROL_FLAG_NAMETABLE_2: u8             = 1<<1;
let CONTROL_FLAG_VRAM_ADD: u8                = 1<<2;
let CONTROL_FLAG_SPRITE_PATTERN_ADDR: u8     = 1<<3;
let CONTROL_FLAG_BACKGROUND_PATTERN_ADDR: u8 = 1<<4;
let CONTROL_FLAG_SPRITE_SIZE: u8             = 1<<5;
let CONTROL_FLAG_MASTER_SLAVE_SELECT: u8     = 1<<6;
let CONTROL_FLAG_NMI: u8                     = 1<<7;

struct PPU {
  characters:      [*]u8,
  characters_size: u16,
  palette:         [*]u8,
  vram:            [*]u8, // 2KB
  mirroring:       u8,

  reg: Register,

  addr_lo:       u8,
  addr_hi:       u8,
  data:          u8,
  is_reading_hi: bool,

  debug: Debug,
}

struct Register {
  control: u8,
}

struct Debug {
  tile_framebuffer: [*]u8,
}

fn new(): *PPU {
  let p = mem::alloc::<PPU>();

  // tile framebuffer stores 2 banks of 256 tile of 8x8 pixels of RGBa channel
  // so the size is 2*256*8*8*4 = 0x20000
  p.debug.tile_framebuffer.* = mem::alloc_array::<u8>(0x20000);
  p.vram.* = mem::alloc_array::<u8>(0x800);
  p.palette.* = mem::alloc_array::<u8>(0x20);

  reset(p);
  return p;
}

fn load_rom(ppu: *PPU, cart: *rom::ROM) {
  ppu.characters.* = cart.characters.*;
  ppu.characters_size.* = cart.characters_size.*;

  update_debug_chr_tile(ppu);
}

fn reset(ppu: *PPU) {
  ppu.reg.control.*   = 0;
  ppu.addr_lo.*       = 0;
  ppu.addr_hi.*       = 0;
  ppu.data.*          = 0;
  ppu.is_reading_hi.* = false;
}

fn set_register(ppu: *PPU, id: u8, data: u8) {
  if id == 0 {
  } else if id == 1 {
  } else if id == 2 {
    fmt::print_str("register 0 is read only\n"); wasm::trap();
  } else if id == 3 {
  } else if id == 4 {
  } else if id == 5 {
  } else if id == 6 {
  } else if id == 7 {
  } else {
    fmt::print_str("setting invalid register id ");
    fmt::print_u8(id);
    fmt::print_str("\n");
    wasm::trap();
  }
  wasm::trap();
}

fn get_register(ppu: *PPU, id: u8): u8 {
  if id == 0 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 1 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 2 {
  } else if id == 3 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 4 {
  } else if id == 5 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 6 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 7 {
  } else {
    fmt::print_str("setting invalid register id ");
    fmt::print_u8(id);
    fmt::print_str("\n");
    wasm::trap();
  }

  return 0;
}

fn put_addr(ppu: *PPU, addr: u8) {
  if ppu.is_reading_hi.* {
    ppu.addr_hi.* = addr;
  } else {
    ppu.addr_lo.* = addr;
  }
  ppu.is_reading_hi.* = !ppu.is_reading_hi.*;
}

// When reading while the VRAM address is in the range 0–$3EFF (i.e., before the palettes), the read will return the
// contents of an internal read buffer. This internal buffer is updated only when reading PPUDATA, and so is preserved
// across frames. After the CPU reads and gets the contents of the internal buffer, the PPU will immediately update the
// internal buffer with the byte at the current VRAM address. Thus, after setting the VRAM address, one should first
// read this register to prime the pipeline and discard the result.
// source: https://www.nesdev.org/wiki/PPU_registers#Address_($2006)_%3E%3E_write_x2
fn read_data(ppu: *PPU): u8 {
  let addr = get_addr(ppu);
  inc_addr(ppu);

  if addr < 0x2fff {
    let data = ppu.data.*;
    ppu.data.* = ppu.characters.*[addr].*;
    return data;
  } else if addr < 0x3000 {
    let data = ppu.data.*;
    ppu.data.* = 0; // get data from vram
    return data;
  } else if addr < 0x3f00 {
    fmt::print_str("addr 0x3000 - 0x3f00 shouldn't be used\n")
    wasm::trap();
  } else if addr < 0x4000 {
    // Addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C
    if addr == 0x3f10 || addr == 0x3f14 || addr == 0x3f18 || addr == 0x3f1c {
      addr = addr - 0x10;
    }
    return ppu.palette.*[addr-0x3fff].*;
  } else {
    fmt::print_str("reading addr above 3f00\n")
    wasm::trap();
  }

  return 0;
}

fn write_data(ppu: *PPU): u8 {
  let addr = get_addr(ppu);
  inc_addr(ppu);

  if addr < 0x2fff {
    // reading chr rom
  } else if addr < 0x3000 {
    // reading vram
  } else if addr < 0x3f00 {
    fmt::print_str("reading addr above 3f00\n")
    wasm::trap();
  } else if addr < 0x4000 {
    // reading palette
  } else {
    fmt::print_str("reading addr above 3f00\n")
    wasm::trap();
  }

  return 0;
}

fn inc_addr(ppu: *PPU) {
  let increment: u8 = 1;
  if (ppu.reg.control.* & CONTROL_FLAG_VRAM_ADD) != 0 {
    increment = 32;
  }

  let lo = ppu.addr_lo.*;
  ppu.addr_lo.* = lo + increment;
  if lo > ppu.addr_lo.* {
    ppu.addr_hi.* = ppu.addr_hi.* + 1;
  }
}

fn get_addr(ppu: *PPU): u16 {
  let addr = (ppu.addr_hi.* as u16 << 8) | (ppu.addr_lo.* as u16);
  if addr >= 0x4000 {
    addr = addr & 0x3fff;
  }
  return addr;
}

struct Color {
  r: u8,
  g: u8,
  b: u8,
}

let palette: [*]Color = init_palette();

fn init_palette(): [*]Color {
  let map = mem::alloc_array::<Color>(0x40);

  map[ 0].* = Color{r: 0x80, g: 0x80, b: 0x80};
  map[ 1].* = Color{r: 0x00, g: 0x3D, b: 0xA6};
  map[ 2].* = Color{r: 0x00, g: 0x12, b: 0xB0};
  map[ 3].* = Color{r: 0x44, g: 0x00, b: 0x96};
  map[ 4].* = Color{r: 0xA1, g: 0x00, b: 0x5E};
  map[ 5].* = Color{r: 0xC7, g: 0x00, b: 0x28};
  map[ 6].* = Color{r: 0xBA, g: 0x06, b: 0x00};
  map[ 7].* = Color{r: 0x8C, g: 0x17, b: 0x00};
  map[ 8].* = Color{r: 0x5C, g: 0x2F, b: 0x00};
  map[ 9].* = Color{r: 0x10, g: 0x45, b: 0x00};
  map[10].* = Color{r: 0x05, g: 0x4A, b: 0x00};
  map[11].* = Color{r: 0x00, g: 0x47, b: 0x2E};
  map[12].* = Color{r: 0x00, g: 0x41, b: 0x66};
  map[13].* = Color{r: 0x00, g: 0x00, b: 0x00};
  map[14].* = Color{r: 0x05, g: 0x05, b: 0x05};
  map[15].* = Color{r: 0x05, g: 0x05, b: 0x05};
  map[16].* = Color{r: 0xC7, g: 0xC7, b: 0xC7};
  map[17].* = Color{r: 0x00, g: 0x77, b: 0xFF};
  map[18].* = Color{r: 0x21, g: 0x55, b: 0xFF};
  map[19].* = Color{r: 0x82, g: 0x37, b: 0xFA};
  map[20].* = Color{r: 0xEB, g: 0x2F, b: 0xB5};
  map[21].* = Color{r: 0xFF, g: 0x29, b: 0x50};
  map[22].* = Color{r: 0xFF, g: 0x22, b: 0x00};
  map[23].* = Color{r: 0xD6, g: 0x32, b: 0x00};
  map[24].* = Color{r: 0xC4, g: 0x62, b: 0x00};
  map[25].* = Color{r: 0x35, g: 0x80, b: 0x00};
  map[26].* = Color{r: 0x05, g: 0x8F, b: 0x00};
  map[27].* = Color{r: 0x00, g: 0x8A, b: 0x55};
  map[28].* = Color{r: 0x00, g: 0x99, b: 0xCC};
  map[29].* = Color{r: 0x21, g: 0x21, b: 0x21};
  map[30].* = Color{r: 0x09, g: 0x09, b: 0x09};
  map[31].* = Color{r: 0x09, g: 0x09, b: 0x09};
  map[32].* = Color{r: 0xFF, g: 0xFF, b: 0xFF};
  map[33].* = Color{r: 0x0F, g: 0xD7, b: 0xFF};
  map[34].* = Color{r: 0x69, g: 0xA2, b: 0xFF};
  map[35].* = Color{r: 0xD4, g: 0x80, b: 0xFF};
  map[36].* = Color{r: 0xFF, g: 0x45, b: 0xF3};
  map[37].* = Color{r: 0xFF, g: 0x61, b: 0x8B};
  map[38].* = Color{r: 0xFF, g: 0x88, b: 0x33};
  map[39].* = Color{r: 0xFF, g: 0x9C, b: 0x12};
  map[40].* = Color{r: 0xFA, g: 0xBC, b: 0x20};
  map[41].* = Color{r: 0x9F, g: 0xE3, b: 0x0E};
  map[42].* = Color{r: 0x2B, g: 0xF0, b: 0x35};
  map[43].* = Color{r: 0x0C, g: 0xF0, b: 0xA4};
  map[44].* = Color{r: 0x05, g: 0xFB, b: 0xFF};
  map[45].* = Color{r: 0x5E, g: 0x5E, b: 0x5E};
  map[46].* = Color{r: 0x0D, g: 0x0D, b: 0x0D};
  map[47].* = Color{r: 0x0D, g: 0x0D, b: 0x0D};
  map[48].* = Color{r: 0xFF, g: 0xFF, b: 0xFF};
  map[49].* = Color{r: 0xA6, g: 0xFC, b: 0xFF};
  map[50].* = Color{r: 0xB3, g: 0xEC, b: 0xFF};
  map[51].* = Color{r: 0xDA, g: 0xAB, b: 0xEB};
  map[52].* = Color{r: 0xFF, g: 0xA8, b: 0xF9};
  map[53].* = Color{r: 0xFF, g: 0xAB, b: 0xB3};
  map[54].* = Color{r: 0xFF, g: 0xD2, b: 0xB0};
  map[55].* = Color{r: 0xFF, g: 0xEF, b: 0xA6};
  map[56].* = Color{r: 0xFF, g: 0xF7, b: 0x9C};
  map[57].* = Color{r: 0xD7, g: 0xE8, b: 0x95};
  map[58].* = Color{r: 0xA6, g: 0xED, b: 0xAF};
  map[59].* = Color{r: 0xA2, g: 0xF2, b: 0xDA};
  map[60].* = Color{r: 0x99, g: 0xFF, b: 0xFC};
  map[61].* = Color{r: 0xDD, g: 0xDD, b: 0xDD};
  map[62].* = Color{r: 0x11, g: 0x11, b: 0x11};
  map[63].* = Color{r: 0x11, g: 0x11, b: 0x11};

  return map;
}

fn update_debug_chr_tile(ppu: *PPU) {
  let yi = 0;
  while yi < 16 {
    let bank = 0;
    while bank < 2 {
      let xi = 0;
      while xi < 16 {
        let p = ppu.characters.*[yi*16*16 + xi*16 + bank * 0x1000] as [*]u8;

        let y = 0;
        while y < 8 {
          let hi = p[y].*;
          let lo = p[y + 8].*;

          let x7 = ((hi & 0b0000_0001) << 1) |  (lo & 0b0000_0001);
          let x6 =  (hi & 0b0000_0010)       | ((lo & 0b0000_0010) >> 1);
          let x5 = ((hi & 0b0000_0100) >> 1) | ((lo & 0b0000_0100) >> 2);
          let x4 = ((hi & 0b0000_1000) >> 2) | ((lo & 0b0000_1000) >> 3);
          let x3 = ((hi & 0b0001_0000) >> 3) | ((lo & 0b0001_0000) >> 4);
          let x2 = ((hi & 0b0010_0000) >> 4) | ((lo & 0b0010_0000) >> 5);
          let x1 = ((hi & 0b0100_0000) >> 5) | ((lo & 0b0100_0000) >> 6);
          let x0 = ((hi & 0b1000_0000) >> 6) | ((lo & 0b1000_0000) >> 7);

          let framebuffer_offset = 4 * ((yi * 32 * 8 * 8) + (y * 32 * 8) + (xi * 8) + (bank * 8*16));
          let framebuffer = ppu.debug.tile_framebuffer.*;
          set_debug_color(framebuffer[framebuffer_offset + 0 * 4] as [*]u8, x0);
          set_debug_color(framebuffer[framebuffer_offset + 1 * 4] as [*]u8, x1);
          set_debug_color(framebuffer[framebuffer_offset + 2 * 4] as [*]u8, x2);
          set_debug_color(framebuffer[framebuffer_offset + 3 * 4] as [*]u8, x3);
          set_debug_color(framebuffer[framebuffer_offset + 4 * 4] as [*]u8, x4);
          set_debug_color(framebuffer[framebuffer_offset + 5 * 4] as [*]u8, x5);
          set_debug_color(framebuffer[framebuffer_offset + 6 * 4] as [*]u8, x6);
          set_debug_color(framebuffer[framebuffer_offset + 7 * 4] as [*]u8, x7);

          y = y + 1;
        }

        xi = xi + 1;
      }
      bank = bank + 1;
    }
    yi = yi + 1;
  }
}

fn set_debug_color(pixel: [*]u8, color_id: u8) {
  let color: Color;
  if color_id == 0 {
    color = palette[0x01].*;
  } else if color_id == 1 {
    color = palette[0x23].*;
  } else if color_id == 2 {
    color = palette[0x27].*;
  } else if color_id == 3 {
    color = palette[0x30].*;
  }

  pixel[0].* = color.r;
  pixel[1].* = color.g;
  pixel[2].* = color.b;
  pixel[3].* = 255;
}
