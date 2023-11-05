import mem "mem";

let ram: [*]u8 = mem::alloc_array::<u8>(0xffff);

fn read(addr: u16): u8 {
  return ram[addr].*;
}

fn write(addr: u16, data: u8) {
  ram[addr].* = data;
}
