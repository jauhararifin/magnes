import wasm "wasm";
import mem "mem";
import fmt "fmt";
import rom "rom";
import cpu "cpu";
import bus "bus";

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

// Palette
// 0x3f00:          contains the background color
// 0x3f01 - 0x3f04: palette 0. last byte is unused (or rather mirror to background color)
// 0x3f05 - 0x3f08: palette 1. last byte is unused (or rather mirror to background color)
// 0x3f09 - 0x3f0c: palette 2. last byte is unused (or rather mirror to background color)
// 0x3f0d - 0x3f10: palette 3. last byte is unused (or rather mirror to background color)
// 0x3f11 - 0x3f14: palette 4. last byte is unused (or rather mirror to background color)
// 0x3f15 - 0x3f18: palette 5. last byte is unused (or rather mirror to background color)
// 0x3f19 - 0x3f1c: palette 6. last byte is unused (or rather mirror to background color)
// 0x3f1d - 0x3f1f: palette 7. only 3 bytes
//
// to calcualte the address of palette P, color C just calculate: 0x3f00 + P * 4 + C
// Addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C

let CONTROL_FLAG_NAMETABLE_1: u8             = 1;
let CONTROL_FLAG_NAMETABLE_2: u8             = 1<<1;
let CONTROL_FLAG_VRAM_ADD: u8                = 1<<2;
let CONTROL_FLAG_SPRITE_PATTERN_ADDR: u8     = 1<<3;
let CONTROL_FLAG_BACKGROUND_PATTERN_ADDR: u8 = 1<<4;
let CONTROL_FLAG_SPRITE_SIZE: u8             = 1<<5;
let CONTROL_FLAG_MASTER_SLAVE_SELECT: u8     = 1<<6;
let CONTROL_FLAG_NMI: u8                     = 1<<7;

let STATUS_FLAG_SPRITE_OVERFLOW: u8 = 1<<5;
let STATUS_FLAG_ZERO_HIT: u8        = 1<<6;
let STATUS_FLAG_VBLANK_STARTED: u8  = 1<<7;

struct PPU {
  characters:      [*]u8,
  characters_size: u16,
  // maybe instead of storing the color id like this, 
  // we can store the actual color directly.
  palette:         [*]u8,
  vram:            [*]u8, // 2KB. also known as nametable
  mirroring:       u8,

  reg: Register,

  // for data transfer between cpu and ppu
  addr_lo:       u8,
  addr_hi:       u8,
  data:          u8,
  is_reading_lo: bool,

  debug: Debug,

  cycles:   i32,
  scanline: i32,
}

struct Register {
  control: u8,
  status:  u8,
}

struct Debug {
  tile_framebuffer:    [*]Color,
  palette_framebuffer: [*]Color,
}

fn new(): *PPU {
  let p = mem::alloc::<PPU>();

  // tile framebuffer stores 2 banks of 256 tile of 8x8 pixels of RGBa channel
  // so the size is 2*256*8*8 = 0x8000
  p.debug.tile_framebuffer.*    = mem::alloc_array::<Color>(0x8000);
  p.debug.palette_framebuffer.* = mem::alloc_array::<Color>(1 + 4*4 + 4*4);
  p.vram.*                      = mem::alloc_array::<u8>(0x800);
  p.palette.*                   = mem::alloc_array::<u8>(0x20);

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
  ppu.reg.status.*    = 0;
  ppu.addr_lo.*       = 0;
  ppu.addr_hi.*       = 0;
  ppu.data.*          = 0;
  ppu.is_reading_lo.* = false;
}

fn tick(ppu: *PPU, cycles: i64) {
  ppu.cycles.* = ppu.cycles.* + cycles as i32;

  while ppu.cycles.* >= 341 {
    ppu.cycles.* = ppu.cycles.* - 341;
    ppu.scanline.* = ppu.scanline.* + 1;

    if ppu.scanline.* == 241 {
      ppu.reg.status.* = ppu.reg.status.* | STATUS_FLAG_VBLANK_STARTED;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_ZERO_HIT;
      if (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0 {
        cpu::non_maskable_interrupt(bus::the_cpu);
      }
    }
    if ppu.scanline.* >= 262 {
      ppu.scanline.* = 0;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_ZERO_HIT;
      ppu.reg.status.* = ppu.reg.status.* & ~STATUS_FLAG_VBLANK_STARTED;
    }
  }
}

fn set_register(ppu: *PPU, id: u8, data: u8) {
  if id == 0 {
    let old_nmi_status = (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0;
    ppu.reg.control.* = data;
    let new_nmi_status = (ppu.reg.control.* & CONTROL_FLAG_NMI) != 0;
    let status_vblank = (ppu.reg.status.* & STATUS_FLAG_VBLANK_STARTED) != 0;
    if !old_nmi_status && new_nmi_status && status_vblank {
      cpu::non_maskable_interrupt(bus::the_cpu);
    }
  } else if id == 1 {
  } else if id == 2 {
    fmt::print_str("register 2 is read only\n");
    wasm::trap();
  } else if id == 3 {
  } else if id == 4 {
  } else if id == 5 {
  } else if id == 6 {
    put_addr(ppu, data);
  } else if id == 7 {
    write_data(ppu, data);
  } else {
    fmt::print_str("setting invalid register id ");
    fmt::print_u8(id);
    fmt::print_str("\n");
    wasm::trap();
  }
}

fn get_register(ppu: *PPU, id: u8): u8 {
  if id == 0 {
    fmt::print_str("register 0 is write only\n"); wasm::trap();
  } else if id == 1 {
    fmt::print_str("register 1 is write only\n"); wasm::trap();
  } else if id == 2 {
    let reg = ppu.reg.status.*;
    ppu.reg.status.* = reg & ~STATUS_FLAG_VBLANK_STARTED;
    return reg;
  } else if id == 3 {
    fmt::print_str("register 3 is write only\n"); wasm::trap();
  } else if id == 4 {
  } else if id == 5 {
    fmt::print_str("register 5 is write only\n"); wasm::trap();
  } else if id == 6 {
    fmt::print_str("register 6 is write only\n"); wasm::trap();
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
  if ppu.is_reading_lo.* {
    ppu.addr_lo.* = addr;
  } else {
    ppu.addr_hi.* = addr;
  }
  ppu.is_reading_lo.* = !ppu.is_reading_lo.*;
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
    // addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C
    // source: https://www.nesdev.org/wiki/PPU_palettes
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

fn write_data(ppu: *PPU, data: u8) {
  let addr = get_addr(ppu);
  fmt::print_str("write data to ppu ");
  fmt::print_u16(addr);
  fmt::print_str(", data=");
  fmt::print_u8(data);
  fmt::print_str("\n");
  inc_addr(ppu);

  if addr < 0x2fff {
    // writing chr rom
  } else if addr < 0x3000 {
    // writing vram
  } else if addr < 0x3f00 {
    fmt::print_str("reading addr 0x3000 - 0x3f00\n")
    wasm::trap();
  } else if addr < 0x4000 {
    // addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C
    // source: https://www.nesdev.org/wiki/PPU_palettes
    if addr == 0x3f10 || addr == 0x3f14 || addr == 0x3f18 || addr == 0x3f1c {
      addr = addr - 0x10;
    }
    ppu.palette.*[addr-0x3f00].* = data;
    let color = get_color(data);
    ppu.debug.palette_framebuffer.*[addr-0x3f00].* = color;
    fmt::print_str("setup palette framebuffer at ");
    fmt::print_usize(ppu.debug.palette_framebuffer.* as usize);
    fmt::print_str(",addr=");
    fmt::print_u16(addr);
    fmt::print_str(",r=");
    fmt::print_u8(color.r);
    fmt::print_str(",g=");
    fmt::print_u8(color.g);
    fmt::print_str(",b=");
    fmt::print_u8(color.b);
    fmt::print_str(",a=");
    fmt::print_u8(color.a);
    fmt::print_str("\n");
  } else {
    fmt::print_str("reading addr above 3f00\n")
    wasm::trap();
  }
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
  a: u8,
}

let palette: [*]Color = init_palette();

fn init_palette(): [*]Color {
  let map = mem::alloc_array::<Color>(0x40);

  map[ 0].* = Color{r: 0x80, g: 0x80, b: 0x80, a: 0xff};
  map[ 1].* = Color{r: 0x00, g: 0x3D, b: 0xA6, a: 0xff};
  map[ 2].* = Color{r: 0x00, g: 0x12, b: 0xB0, a: 0xff};
  map[ 3].* = Color{r: 0x44, g: 0x00, b: 0x96, a: 0xff};
  map[ 4].* = Color{r: 0xA1, g: 0x00, b: 0x5E, a: 0xff};
  map[ 5].* = Color{r: 0xC7, g: 0x00, b: 0x28, a: 0xff};
  map[ 6].* = Color{r: 0xBA, g: 0x06, b: 0x00, a: 0xff};
  map[ 7].* = Color{r: 0x8C, g: 0x17, b: 0x00, a: 0xff};
  map[ 8].* = Color{r: 0x5C, g: 0x2F, b: 0x00, a: 0xff};
  map[ 9].* = Color{r: 0x10, g: 0x45, b: 0x00, a: 0xff};
  map[10].* = Color{r: 0x05, g: 0x4A, b: 0x00, a: 0xff};
  map[11].* = Color{r: 0x00, g: 0x47, b: 0x2E, a: 0xff};
  map[12].* = Color{r: 0x00, g: 0x41, b: 0x66, a: 0xff};
  map[13].* = Color{r: 0x00, g: 0x00, b: 0x00, a: 0xff};
  map[14].* = Color{r: 0x05, g: 0x05, b: 0x05, a: 0xff};
  map[15].* = Color{r: 0x05, g: 0x05, b: 0x05, a: 0xff};
  map[16].* = Color{r: 0xC7, g: 0xC7, b: 0xC7, a: 0xff};
  map[17].* = Color{r: 0x00, g: 0x77, b: 0xFF, a: 0xff};
  map[18].* = Color{r: 0x21, g: 0x55, b: 0xFF, a: 0xff};
  map[19].* = Color{r: 0x82, g: 0x37, b: 0xFA, a: 0xff};
  map[20].* = Color{r: 0xEB, g: 0x2F, b: 0xB5, a: 0xff};
  map[21].* = Color{r: 0xFF, g: 0x29, b: 0x50, a: 0xff};
  map[22].* = Color{r: 0xFF, g: 0x22, b: 0x00, a: 0xff};
  map[23].* = Color{r: 0xD6, g: 0x32, b: 0x00, a: 0xff};
  map[24].* = Color{r: 0xC4, g: 0x62, b: 0x00, a: 0xff};
  map[25].* = Color{r: 0x35, g: 0x80, b: 0x00, a: 0xff};
  map[26].* = Color{r: 0x05, g: 0x8F, b: 0x00, a: 0xff};
  map[27].* = Color{r: 0x00, g: 0x8A, b: 0x55, a: 0xff};
  map[28].* = Color{r: 0x00, g: 0x99, b: 0xCC, a: 0xff};
  map[29].* = Color{r: 0x21, g: 0x21, b: 0x21, a: 0xff};
  map[30].* = Color{r: 0x09, g: 0x09, b: 0x09, a: 0xff};
  map[31].* = Color{r: 0x09, g: 0x09, b: 0x09, a: 0xff};
  map[32].* = Color{r: 0xFF, g: 0xFF, b: 0xFF, a: 0xff};
  map[33].* = Color{r: 0x0F, g: 0xD7, b: 0xFF, a: 0xff};
  map[34].* = Color{r: 0x69, g: 0xA2, b: 0xFF, a: 0xff};
  map[35].* = Color{r: 0xD4, g: 0x80, b: 0xFF, a: 0xff};
  map[36].* = Color{r: 0xFF, g: 0x45, b: 0xF3, a: 0xff};
  map[37].* = Color{r: 0xFF, g: 0x61, b: 0x8B, a: 0xff};
  map[38].* = Color{r: 0xFF, g: 0x88, b: 0x33, a: 0xff};
  map[39].* = Color{r: 0xFF, g: 0x9C, b: 0x12, a: 0xff};
  map[40].* = Color{r: 0xFA, g: 0xBC, b: 0x20, a: 0xff};
  map[41].* = Color{r: 0x9F, g: 0xE3, b: 0x0E, a: 0xff};
  map[42].* = Color{r: 0x2B, g: 0xF0, b: 0x35, a: 0xff};
  map[43].* = Color{r: 0x0C, g: 0xF0, b: 0xA4, a: 0xff};
  map[44].* = Color{r: 0x05, g: 0xFB, b: 0xFF, a: 0xff};
  map[45].* = Color{r: 0x5E, g: 0x5E, b: 0x5E, a: 0xff};
  map[46].* = Color{r: 0x0D, g: 0x0D, b: 0x0D, a: 0xff};
  map[47].* = Color{r: 0x0D, g: 0x0D, b: 0x0D, a: 0xff};
  map[48].* = Color{r: 0xFF, g: 0xFF, b: 0xFF, a: 0xff};
  map[49].* = Color{r: 0xA6, g: 0xFC, b: 0xFF, a: 0xff};
  map[50].* = Color{r: 0xB3, g: 0xEC, b: 0xFF, a: 0xff};
  map[51].* = Color{r: 0xDA, g: 0xAB, b: 0xEB, a: 0xff};
  map[52].* = Color{r: 0xFF, g: 0xA8, b: 0xF9, a: 0xff};
  map[53].* = Color{r: 0xFF, g: 0xAB, b: 0xB3, a: 0xff};
  map[54].* = Color{r: 0xFF, g: 0xD2, b: 0xB0, a: 0xff};
  map[55].* = Color{r: 0xFF, g: 0xEF, b: 0xA6, a: 0xff};
  map[56].* = Color{r: 0xFF, g: 0xF7, b: 0x9C, a: 0xff};
  map[57].* = Color{r: 0xD7, g: 0xE8, b: 0x95, a: 0xff};
  map[58].* = Color{r: 0xA6, g: 0xED, b: 0xAF, a: 0xff};
  map[59].* = Color{r: 0xA2, g: 0xF2, b: 0xDA, a: 0xff};
  map[60].* = Color{r: 0x99, g: 0xFF, b: 0xFC, a: 0xff};
  map[61].* = Color{r: 0xDD, g: 0xDD, b: 0xDD, a: 0xff};
  map[62].* = Color{r: 0x11, g: 0x11, b: 0x11, a: 0xff};
  map[63].* = Color{r: 0x11, g: 0x11, b: 0x11, a: 0xff};

  return map;
}

fn get_color(id: u8): Color {
  if id >= 64 {
    return Color{r: 0, g: 0, b: 0, a: 255};
  }
  return palette[id].*;
}

fn get_debug_tile_framebuffer(ppu: *PPU): Image {
  return Image {
    framebuffer: ppu.debug.tile_framebuffer.*,
    width:       32*8,
    height:      16*8,
  };
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

          let framebuffer_offset = (yi * 32 * 8 * 8) + (y * 32 * 8) + (xi * 8) + (bank * 8*16);
          let framebuffer = ppu.debug.tile_framebuffer.*;
          set_debug_color(framebuffer[framebuffer_offset + 0], x0);
          set_debug_color(framebuffer[framebuffer_offset + 1], x1);
          set_debug_color(framebuffer[framebuffer_offset + 2], x2);
          set_debug_color(framebuffer[framebuffer_offset + 3], x3);
          set_debug_color(framebuffer[framebuffer_offset + 4], x4);
          set_debug_color(framebuffer[framebuffer_offset + 5], x5);
          set_debug_color(framebuffer[framebuffer_offset + 6], x6);
          set_debug_color(framebuffer[framebuffer_offset + 7], x7);

          y = y + 1;
        }

        xi = xi + 1;
      }
      bank = bank + 1;
    }
    yi = yi + 1;
  }
}

fn set_debug_color(pixel: *Color, color_id: u8) {
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
  pixel.* = color;
}

struct Image {
  framebuffer: [*]Color,
  width:       usize,
  height:      usize,
}

struct DebugPalette {
  none: Image,

  background_palette0: Image,
  background_palette1: Image,
  background_palette2: Image,
  background_palette3: Image,

  sprite_palette0: Image,
  sprite_palette1: Image,
  sprite_palette2: Image,
  sprite_palette3: Image,
}

fn get_debug_palette_framebuffer(ppu: *PPU): DebugPalette {
  return DebugPalette {
    none: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[0] as [*]Color,
      width: 1,
      height: 1,
    },

    background_palette0: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[1] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette1: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[5] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette2: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[9] as [*]Color,
      width: 4,
      height: 1,
    }
    background_palette3: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[13] as [*]Color,
      width: 4,
      height: 1,
    }

    sprite_palette0: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[17] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette1: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[21] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette2: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[25] as [*]Color,
      width: 4,
      height: 1,
    }
    sprite_palette3: Image{
      framebuffer: ppu.debug.palette_framebuffer.*[29] as [*]Color,
      width: 4,
      height: 1,
    }
  };
}
