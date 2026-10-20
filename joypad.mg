import mem "mem";
import fmt "fmt";

pub let JOYPAD_BUTTON_A: u8      = 1;
pub let JOYPAD_BUTTON_B: u8      = 1<<1;
pub let JOYPAD_BUTTON_SELECT: u8 = 1<<2;
pub let JOYPAD_BUTTON_START: u8  = 1<<3;
pub let JOYPAD_BUTTON_UP: u8     = 1<<4;
pub let JOYPAD_BUTTON_DOWN: u8   = 1<<5;
pub let JOYPAD_BUTTON_LEFT: u8   = 1<<6;
pub let JOYPAD_BUTTON_RIGHT: u8  = 1<<7;

pub struct Joypad {
  strobe:   bool,
  button_i: u8,
  status:   u8,
}

pub fn new(): *Joypad {
  let p = mem.alloc[Joypad]();
  p.* = Joypad {
    strobe:   false,
    button_i: 0,
    status:   0,
  };
  return p;
}

pub fn reset(joypad: *Joypad) {
  joypad.* = Joypad {
    strobe:   false,
    button_i: 0,
    status:   0,
  };
}

pub fn write(joypad: *Joypad, data: u8) {
  joypad.strobe.* = (data & 1) != 0;
  if joypad.strobe.* {
    joypad.button_i.* = 0;
  }
}

pub fn read(joypad: *Joypad): u8 {
  if joypad.button_i.* > 7 {
    return 0x4; // I have no idea why returning 4 fix hanging menu on SMB.
  }

  let result = (joypad.status.* >> joypad.button_i.*) & 1;
  if !joypad.strobe.* && joypad.button_i.* <= 7 {
    joypad.button_i.* += 1;
  }
  if joypad.strobe.* {
    joypad.button_i.* = 0;
  }

  // fmt.print_str("joypad read, result=");
  // fmt.print_u8(result);
  // fmt.print_str("\n");
  return result;
}

pub fn press(joypad: *Joypad, mask: u8) {
  // fmt.print_str("joypad pressed, staus="); fmt.print_u8(joypad.status.*); fmt.print_str("\n");
  joypad.status.* |= mask;
}

pub fn unpress(joypad: *Joypad, mask: u8) {
  // fmt.print_str("joypad unpressed, staus="); fmt.print_u8(joypad.status.*); fmt.print_str("\n");
  joypad.status.* &= ~mask;
}
