import mem "mem";
import fmt "fmt";

let JOYPAD_BUTTON_A: u8      = 1;
let JOYPAD_BUTTON_B: u8      = 1<<1;
let JOYPAD_BUTTON_SELECT: u8 = 1<<2;
let JOYPAD_BUTTON_START: u8  = 1<<3;
let JOYPAD_BUTTON_UP: u8     = 1<<4;
let JOYPAD_BUTTON_DOWN: u8   = 1<<5;
let JOYPAD_BUTTON_LEFT: u8   = 1<<6;
let JOYPAD_BUTTON_RIGHT: u8  = 1<<7;

struct Joypad {
  strobe:   bool,
  button_i: u8,
  status:   u8,
}

fn new(): *Joypad {
  let p = mem::alloc::<Joypad>();
  p.* = Joypad {
    strobe:   false,
    button_i: 0,
    status:   0,
  }
  return p;
}

fn reset(joypad: *Joypad) {
  joypad.* = Joypad {
    strobe:   false,
    button_i: 0,
    status:   0,
  }
}

fn write(joypad: *Joypad, data: u8) {
  joypad.strobe.* = (data & 1) != 0;
  if joypad.strobe.* {
    joypad.button_i.* = 0;
  }
}

fn read(joypad: *Joypad): u8 {
  if joypad.button_i.* > 7 {
    return 1;
  }

  let result = (joypad.status.* >> joypad.button_i.*) & 1;
  if !joypad.strobe.* && joypad.button_i.* <= 7 {
    joypad.button_i.* = joypad.button_i.* + 1;
  }

  // fmt::print_str("joypad read, result=");
  // fmt::print_u8(result);
  // fmt::print_str("\n");
  return result;
}

fn press(joypad: *Joypad, mask: u8) {
  // fmt::print_str("joypad pressed, staus="); fmt::print_u8(joypad.status.*); fmt::print_str("\n");
  joypad.status.* = joypad.status.* | mask;
}

fn unpress(joypad: *Joypad, mask: u8) {
  // fmt::print_str("joypad unpressed, staus="); fmt::print_u8(joypad.status.*); fmt::print_str("\n");
  joypad.status.* = joypad.status.* & ~mask;
}
