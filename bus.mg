import mem "mem";

let ram: [*]u8 = mem::alloc_array::<u8>(0x800);

fn read(addr: u16): u8 {
  if addr < 0x2000 {
    return ram[addr & 0x7ff].*;
  }
  return 0;
}

fn write(addr: u16, data: u8) {
  if addr < 0x2000 {
    ram[addr & 0x7ff].* = data;
  }
  return;
}
