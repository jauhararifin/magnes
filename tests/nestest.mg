import nes "nes";
import bus "bus";
import cpu "cpu";
import rom "rom";
import fmt "fmt";
import wasm "wasm";

@embed_file("./roms/nestest.nes")
let nestest_rom: [*]u8;

@main()
fn main() {
  cpu::debug = true;

  let rom = rom::load(nestest_rom);
  if !rom.valid {
    fmt::print_str(rom.error);
    fmt::print_str("\n");
    wasm::trap();
  }

  bus::the_rom.* = rom;

  nes::reset();
  bus::the_cpu.reg.pc.* = 0xc000;

  let i = 0;
  while i < 10000 {
    nes::tick();
    i = i + 1;
  }
}

