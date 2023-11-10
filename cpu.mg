import bus "bus";
import wasm "wasm";
import fmt "fmt";
import mem "mem";

struct CPU {
  reg: Register,
  remaining_cycle: i32,

  last_opcode: u8,
  last_ins: [*]u8, // TODO: remove this, this is for debugging only
  last_addr: u16,
  last_pc: u16,
}

fn new(): CPU {
  return CPU{};
}

struct Register {
  a:      u8,
  x:      u8,
  y:      u8,
  sp:     u8,
  pc:     u16,
  status: u8,
}

let FLAG_MASK_CARRY: u8             = 1 << 0;
let FLAG_MASK_ZERO: u8              = 1 << 1;
let FLAG_MASK_INTERRUPT_DISABLE: u8 = 1 << 2;
let FLAG_MASK_DECIMAL: u8           = 1 << 3;
let FLAG_MASK_BREAK: u8             = 1 << 4;
let FLAG_MASK_1: u8                 = 1 << 5;
let FLAG_MASK_OVERFLOW: u8          = 1 << 6;
let FLAG_MASK_NEGATIVE: u8          = 1 << 7;

let ADDR_MODE_A: u8 = 0;
let ADDR_MODE_ABS: u8 = 1;
let ADDR_MODE_ABS_X: u8 = 2;
let ADDR_MODE_ABS_Y: u8 = 3;
let ADDR_MODE_IMM: u8 = 4;
let ADDR_MODE_IMP: u8 = 5;
let ADDR_MODE_INDIRECT: u8 = 6;
let ADDR_MODE_X_INDIRECT: u8 = 7;
let ADDR_MODE_INDIRECT_Y: u8 = 8;
let ADDR_MODE_REL: u8 = 9;
let ADDR_MODE_ZERO_PAGE: u8 = 10;
let ADDR_MODE_ZERO_PAGE_X: u8 = 11;
let ADDR_MODE_ZERO_PAGE_Y: u8 = 12;

let OPCODE_ADC: u8 =  0; // add with carry
let OPCODE_AND: u8 =  1; // and (with accumulator)
let OPCODE_ASL: u8 =  2; // arithmetic shift left
let OPCODE_BCC: u8 =  3; // branch on carry clear
let OPCODE_BCS: u8 =  4; // branch on carry set
let OPCODE_BEQ: u8 =  5; // branch on equal (zero set)
let OPCODE_BIT: u8 =  6; // bit test
let OPCODE_BMI: u8 =  7; // branch on minus (negative set)
let OPCODE_BNE: u8 =  8; // branch on not equal (zero clear)
let OPCODE_BPL: u8 =  9; // branch on plus (negative clear)
let OPCODE_BRK: u8 = 10; // break / interrupt
let OPCODE_BVC: u8 = 11; // branch on overflow clear
let OPCODE_BVS: u8 = 12; // branch on overflow set
let OPCODE_CLC: u8 = 13; // clear carry
let OPCODE_CLD: u8 = 14; // clear decimal
let OPCODE_CLI: u8 = 15; // clear interrupt disable
let OPCODE_CLV: u8 = 16; // clear overflow
let OPCODE_CMP: u8 = 17; // compare (with accumulator)
let OPCODE_CPX: u8 = 18; // compare with X
let OPCODE_CPY: u8 = 19; // compare with Y
let OPCODE_DEC: u8 = 20; // decrement
let OPCODE_DEX: u8 = 21; // decrement X
let OPCODE_DEY: u8 = 22; // decrement Y
let OPCODE_EOR: u8 = 23; // exclusive or (with accumulator)
let OPCODE_INC: u8 = 24; // increment
let OPCODE_INX: u8 = 25; // increment X
let OPCODE_INY: u8 = 26; // increment Y
let OPCODE_JMP: u8 = 27; // jump
let OPCODE_JSR: u8 = 28; // jump subroutine
let OPCODE_LDA: u8 = 29; // load accumulator
let OPCODE_LDX: u8 = 30; // load X
let OPCODE_LDY: u8 = 31; // load Y
let OPCODE_LSR: u8 = 32; // logical shift right
let OPCODE_NOP: u8 = 33; // no operation
let OPCODE_ORA: u8 = 34; // or with accumulator
let OPCODE_PHA: u8 = 35; // push accumulator
let OPCODE_PHP: u8 = 36; // push processor status (SR)
let OPCODE_PLA: u8 = 37; // pull accumulator
let OPCODE_PLP: u8 = 38; // pull processor status (SR)
let OPCODE_ROL: u8 = 39; // rotate left
let OPCODE_ROR: u8 = 40; // rotate right
let OPCODE_RTI: u8 = 41; // return from interrupt
let OPCODE_RTS: u8 = 42; // return from subroutine
let OPCODE_SBC: u8 = 43; // subtract with carry
let OPCODE_SEC: u8 = 44; // set carry
let OPCODE_SED: u8 = 45; // set decimal
let OPCODE_SEI: u8 = 46; // set interrupt disable
let OPCODE_STA: u8 = 47; // store accumulator
let OPCODE_STX: u8 = 48; // store X
let OPCODE_STY: u8 = 49; // store Y
let OPCODE_TAX: u8 = 50; // transfer accumulator to X
let OPCODE_TAY: u8 = 51; // transfer accumulator to Y
let OPCODE_TSX: u8 = 52; // transfer stack pointer to X
let OPCODE_TXA: u8 = 53; // transfer X to accumulator
let OPCODE_TXS: u8 = 54; // transfer X to stack pointer
let OPCODE_TYA: u8 = 55; // transfer Y to accumulator
let OPCODE_LAX: u8 = 56; // LDA + LDX
let OPCODE_SAX: u8 = 57; // a and x -> m
let OPCODE_USBC: u8 = 58;
let OPCODE_DCP: u8 = 59;
let OPCODE_ISB: u8 = 60;
let OPCODE_SLO: u8 = 61;
let OPCODE_RLA: u8 = 62;
let OPCODE_SRE: u8 = 63;
let OPCODE_RRA: u8 = 64;
let OPCODE_JAM: u8 = 65;
let OPCODE_ANC: u8 = 66;
let OPCODE_ALR: u8 = 67;

struct Instruction {
  code:      u8,
  opcode:    u8,
  addr_mode: u8,
  handler:   fn( *CPU, u8, u16): i32,
  name:      [*]u8,
  desc:      [*]u8,
  illegal:   bool,
  cycle:     i32,
}

let instruction_map: [*]Instruction = init_instruction_map();

fn init_instruction_map(): [*]Instruction {
  let map = mem::alloc_array::<Instruction>(0x100);

  map[0x00].* = Instruction{code: 0x00, opcode: OPCODE_BRK, handler: handle_instr_brk, addr_mode: ADDR_MODE_IMP, desc: "BRK:IMP", name: "BRK", cycle: 7};
  map[0x01].* = Instruction{code: 0x01, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_X_INDIRECT, desc: "ORA:X_INDIRECT", name: "ORA", cycle: 6};
  map[0x02].* = Instruction{code: 0x02, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x03].* = Instruction{code: 0x03, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_X_INDIRECT, desc: "SLO:X_INDIRECT", name: "SLO", illegal: true, cycle: 8};
  map[0x04].* = Instruction{code: 0x04, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "NOP:ZERO_PAGE", name: "NOP", illegal: true, cycle: 3};
  map[0x05].* = Instruction{code: 0x05, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ORA:ZERO_PAGE", name: "ORA", cycle: 3};
  map[0x06].* = Instruction{code: 0x06, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ASL:ZERO_PAGE", name: "ASL", cycle: 5};
  map[0x07].* = Instruction{code: 0x07, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "SLO:ZERO_PAGE", name: "SLO", illegal: true, cycle: 5};
  map[0x08].* = Instruction{code: 0x08, opcode: OPCODE_PHP, handler: handle_instr_php, addr_mode: ADDR_MODE_IMP, desc: "PHP:IMP", name: "PHP", cycle: 3};
  map[0x09].* = Instruction{code: 0x09, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_IMM, desc: "ORA:IMM", name: "ORA", cycle: 2};
  map[0x0A].* = Instruction{code: 0x0A, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_A, desc: "ASL:A", name: "ASL", cycle: 2};
  map[0x0B].* = Instruction{code: 0x0B, opcode: OPCODE_ANC, handler: handle_instr_anc, addr_mode: ADDR_MODE_IMM, desc: "ANC:IMM", name: "ANC", cycle: 2};
  map[0x0C].* = Instruction{code: 0x0C, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS, desc: "NOP:ABS", name: "NOP", illegal: true, cycle: 4};
  map[0x0D].* = Instruction{code: 0x0D, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS, desc: "ORA:ABS", name: "ORA", cycle: 4};
  map[0x0E].* = Instruction{code: 0x0E, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ABS, desc: "ASL:ABS", name: "ASL", cycle: 6};
  map[0x0F].* = Instruction{code: 0x0F, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_ABS, desc: "SLO:ABS", name: "SLO", illegal: true, cycle: 6};
  map[0x10].* = Instruction{code: 0x10, opcode: OPCODE_BPL, handler: handle_instr_bpl, addr_mode: ADDR_MODE_REL, desc: "BPL:REL", name: "BPL", cycle: 2};
  map[0x11].* = Instruction{code: 0x11, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "ORA:INDIRECT_Y", name: "ORA", cycle: 5};
  map[0x12].* = Instruction{code: 0x12, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x13].* = Instruction{code: 0x13, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "SLO:INDIRECT_Y", name: "SLO", illegal: true, cycle: 8};
  map[0x14].* = Instruction{code: 0x14, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0x15].* = Instruction{code: 0x15, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ORA:ZERO_PAGE_X", name: "ORA", cycle: 4};
  map[0x16].* = Instruction{code: 0x16, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ASL:ZERO_PAGE_X", name: "ASL", cycle: 6};
  map[0x17].* = Instruction{code: 0x17, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "SLO:ZERO_PAGE_X", name: "SLO", illegal: true, cycle: 6};
  map[0x18].* = Instruction{code: 0x18, opcode: OPCODE_CLC, handler: handle_instr_clc, addr_mode: ADDR_MODE_IMP, desc: "CLC:IMP", name: "CLC", cycle: 2};
  map[0x19].* = Instruction{code: 0x19, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS_Y, desc: "ORA:ABS_Y", name: "ORA", cycle: 4};
  map[0x1A].* = Instruction{code: 0x1A, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0x1B].* = Instruction{code: 0x1B, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_ABS_Y, desc: "SLO:ABS_Y", name: "SLO", illegal: true, cycle: 7};
  map[0x1C].* = Instruction{code: 0x1C, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0x1D].* = Instruction{code: 0x1D, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS_X, desc: "ORA:ABS_X", name: "ORA", cycle: 4};
  map[0x1E].* = Instruction{code: 0x1E, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ABS_X, desc: "ASL:ABS_X", name: "ASL", cycle: 7};
  map[0x1F].* = Instruction{code: 0x1F, opcode: OPCODE_SLO, handler: handle_instr_slo, addr_mode: ADDR_MODE_ABS_X, desc: "SLO:ABS_X", name: "SLO", illegal: true, cycle: 7};
  map[0x20].* = Instruction{code: 0x20, opcode: OPCODE_JSR, handler: handle_instr_jsr, addr_mode: ADDR_MODE_ABS, desc: "JSR:ABS", name: "JSR", cycle: 6};
  map[0x21].* = Instruction{code: 0x21, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_X_INDIRECT, desc: "AND:X_INDIRECT", name: "AND", cycle: 6};
  map[0x22].* = Instruction{code: 0x22, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x23].* = Instruction{code: 0x23, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_X_INDIRECT, desc: "RLA:X_INDIRECT", name: "RLA", illegal: true, cycle: 8};
  map[0x24].* = Instruction{code: 0x24, opcode: OPCODE_BIT, handler: handle_instr_bit, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "BIT:ZERO_PAGE", name: "BIT", cycle: 3};
  map[0x25].* = Instruction{code: 0x25, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "AND:ZERO_PAGE", name: "AND", cycle: 3};
  map[0x26].* = Instruction{code: 0x26, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ROL:ZERO_PAGE", name: "ROL", cycle: 5};
  map[0x27].* = Instruction{code: 0x27, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "RLA:ZERO_PAGE", name: "RLA", illegal: true, cycle: 5};
  map[0x28].* = Instruction{code: 0x28, opcode: OPCODE_PLP, handler: handle_instr_plp, addr_mode: ADDR_MODE_IMP, desc: "PLP:IMP", name: "PLP", cycle: 4};
  map[0x29].* = Instruction{code: 0x29, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_IMM, desc: "AND:IMM", name: "AND", cycle: 2};
  map[0x2A].* = Instruction{code: 0x2A, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_A, desc: "ROL:A", name: "ROL", cycle: 2};
  map[0x2B].* = Instruction{code: 0x2B, opcode: OPCODE_ANC, handler: handle_instr_anc, addr_mode: ADDR_MODE_IMM, desc: "ANC:IMM", name: "ANC", cycle: 2};
  map[0x2C].* = Instruction{code: 0x2C, opcode: OPCODE_BIT, handler: handle_instr_bit, addr_mode: ADDR_MODE_ABS, desc: "BIT:ABS", name: "BIT", cycle: 4};
  map[0x2D].* = Instruction{code: 0x2D, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS, desc: "AND:ABS", name: "AND", cycle: 4};
  map[0x2E].* = Instruction{code: 0x2E, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ABS, desc: "ROL:ABS", name: "ROL", cycle: 6};
  map[0x2F].* = Instruction{code: 0x2F, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_ABS, desc: "RLA:ABS", name: "RLA", illegal: true, cycle: 6};
  map[0x30].* = Instruction{code: 0x30, opcode: OPCODE_BMI, handler: handle_instr_bmi, addr_mode: ADDR_MODE_REL, desc: "BMI:REL", name: "BMI", cycle: 2};
  map[0x31].* = Instruction{code: 0x31, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "AND:INDIRECT_Y", name: "AND", cycle: 5};
  map[0x32].* = Instruction{code: 0x32, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x33].* = Instruction{code: 0x33, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "RLA:INDIRECT_Y", name: "RLA", illegal: true, cycle: 8};
  map[0x34].* = Instruction{code: 0x34, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0x35].* = Instruction{code: 0x35, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "AND:ZERO_PAGE_X", name: "AND", cycle: 4};
  map[0x36].* = Instruction{code: 0x36, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ROL:ZERO_PAGE_X", name: "ROL", cycle: 6};
  map[0x37].* = Instruction{code: 0x37, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "RLA:ZERO_PAGE_X", name: "RLA", illegal: true, cycle: 6};
  map[0x38].* = Instruction{code: 0x38, opcode: OPCODE_SEC, handler: handle_instr_sec, addr_mode: ADDR_MODE_IMP, desc: "SEC:IMP", name: "SEC", cycle: 2};
  map[0x39].* = Instruction{code: 0x39, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS_Y, desc: "AND:ABS_Y", name: "AND", cycle: 4};
  map[0x3A].* = Instruction{code: 0x3A, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0x3B].* = Instruction{code: 0x3B, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_ABS_Y, desc: "RLA:ABS_Y", name: "RLA", illegal: true, cycle: 7};
  map[0x3C].* = Instruction{code: 0x3C, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0x3D].* = Instruction{code: 0x3D, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS_X, desc: "AND:ABS_X", name: "AND", cycle: 4};
  map[0x3E].* = Instruction{code: 0x3E, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ABS_X, desc: "ROL:ABS_X", name: "ROL", cycle: 7};
  map[0x3F].* = Instruction{code: 0x3F, opcode: OPCODE_RLA, handler: handle_instr_rla, addr_mode: ADDR_MODE_ABS_X, desc: "RLA:ABS_X", name: "RLA", illegal: true, cycle: 7};
  map[0x40].* = Instruction{code: 0x40, opcode: OPCODE_RTI, handler: handle_instr_rti, addr_mode: ADDR_MODE_IMP, desc: "RTI:IMP", name: "RTI", cycle: 6};
  map[0x41].* = Instruction{code: 0x41, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_X_INDIRECT, desc: "EOR:X_INDIRECT", name: "EOR", cycle: 6};
  map[0x42].* = Instruction{code: 0x42, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x43].* = Instruction{code: 0x43, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_X_INDIRECT, desc: "SRE:X_INDIRECT", name: "SRE", illegal: true, cycle: 8};
  map[0x44].* = Instruction{code: 0x44, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "NOP:ZERO_PAGE", name: "NOP", illegal: true, cycle: 3};
  map[0x45].* = Instruction{code: 0x45, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "EOR:ZERO_PAGE", name: "EOR", cycle: 3};
  map[0x46].* = Instruction{code: 0x46, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LSR:ZERO_PAGE", name: "LSR", cycle: 5};
  map[0x47].* = Instruction{code: 0x47, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "SRE:ZERO_PAGE", name: "SRE", illegal: true, cycle: 5};
  map[0x48].* = Instruction{code: 0x48, opcode: OPCODE_PHA, handler: handle_instr_pha, addr_mode: ADDR_MODE_IMP, desc: "PHA:IMP", name: "PHA", cycle: 3};
  map[0x49].* = Instruction{code: 0x49, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_IMM, desc: "EOR:IMM", name: "EOR", cycle: 2};
  map[0x4A].* = Instruction{code: 0x4A, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_A, desc: "LSR:A", name: "LSR", cycle: 2};
  map[0x4B].* = Instruction{code: 0x4B, opcode: OPCODE_ALR, handler: handle_instr_alr, addr_mode: ADDR_MODE_IMM, desc: "ALR:IMM", name: "ALR", cycle: 2};
  map[0x4C].* = Instruction{code: 0x4C, opcode: OPCODE_JMP, handler: handle_instr_jmp, addr_mode: ADDR_MODE_ABS, desc: "JMP:ABS", name: "JMP", cycle: 3};
  map[0x4D].* = Instruction{code: 0x4D, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS, desc: "EOR:ABS", name: "EOR", cycle: 4};
  map[0x4E].* = Instruction{code: 0x4E, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ABS, desc: "LSR:ABS", name: "LSR", cycle: 6};
  map[0x4F].* = Instruction{code: 0x4F, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_ABS, desc: "SRE:ABS", name: "SRE", illegal: true, cycle: 6};
  map[0x50].* = Instruction{code: 0x50, opcode: OPCODE_BVC, handler: handle_instr_bvc, addr_mode: ADDR_MODE_REL, desc: "BVC:REL", name: "BVC", cycle: 2};
  map[0x51].* = Instruction{code: 0x51, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "EOR:INDIRECT_Y", name: "EOR", cycle: 5};
  map[0x52].* = Instruction{code: 0x52, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x53].* = Instruction{code: 0x53, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "SRE:INDIRECT_Y", name: "SRE", illegal: true, cycle: 8};
  map[0x54].* = Instruction{code: 0x54, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0x55].* = Instruction{code: 0x55, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "EOR:ZERO_PAGE_X", name: "EOR", cycle: 4};
  map[0x56].* = Instruction{code: 0x56, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LSR:ZERO_PAGE_X", name: "LSR", cycle: 6};
  map[0x57].* = Instruction{code: 0x57, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "SRE:ZERO_PAGE_X", name: "SRE", illegal: true, cycle: 6};
  map[0x58].* = Instruction{code: 0x58, opcode: OPCODE_CLI, handler: handle_instr_cli, addr_mode: ADDR_MODE_IMP, desc: "CLI:IMP", name: "CLI", cycle: 2};
  map[0x59].* = Instruction{code: 0x59, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS_Y, desc: "EOR:ABS_Y", name: "EOR", cycle: 4};
  map[0x5A].* = Instruction{code: 0x5A, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0x5B].* = Instruction{code: 0x5B, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_ABS_Y, desc: "SRE:ABS_Y", name: "SRE", illegal: true, cycle: 7};
  map[0x5C].* = Instruction{code: 0x5C, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0x5D].* = Instruction{code: 0x5D, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS_X, desc: "EOR:ABS_X", name: "EOR", cycle: 4};
  map[0x5E].* = Instruction{code: 0x5E, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ABS_X, desc: "LSR:ABS_X", name: "LSR", cycle: 7};
  map[0x5F].* = Instruction{code: 0x5F, opcode: OPCODE_SRE, handler: handle_instr_sre, addr_mode: ADDR_MODE_ABS_X, desc: "SRE:ABS_X", name: "SRE", illegal: true, cycle: 7};
  map[0x60].* = Instruction{code: 0x60, opcode: OPCODE_RTS, handler: handle_instr_rts, addr_mode: ADDR_MODE_IMP, desc: "RTS:IMP", name: "RTS", cycle: 6};
  map[0x61].* = Instruction{code: 0x61, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_X_INDIRECT, desc: "ADC:X_INDIRECT", name: "ADC", cycle: 6};
  map[0x62].* = Instruction{code: 0x62, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x63].* = Instruction{code: 0x43, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_X_INDIRECT, desc: "RRA:X_INDIRECT", name: "RRA", illegal: true, cycle: 8};
  map[0x64].* = Instruction{code: 0x64, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "NOP:ZERO_PAGE", name: "NOP", illegal: true, cycle: 3};
  map[0x65].* = Instruction{code: 0x65, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ADC:ZERO_PAGE", name: "ADC", cycle: 3};
  map[0x66].* = Instruction{code: 0x66, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ROR:ZERO_PAGE", name: "ROR", cycle: 5};
  map[0x67].* = Instruction{code: 0x47, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "RRA:ZERO_PAGE", name: "RRA", illegal: true, cycle: 5};
  map[0x68].* = Instruction{code: 0x68, opcode: OPCODE_PLA, handler: handle_instr_pla, addr_mode: ADDR_MODE_IMP, desc: "PLA:IMP", name: "PLA", cycle: 4};
  map[0x69].* = Instruction{code: 0x69, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_IMM, desc: "ADC:IMM", name: "ADC", cycle: 2};
  map[0x6A].* = Instruction{code: 0x6A, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_A, desc: "ROR:A", name: "ROR", cycle: 2};
  map[0x6B].* = Instruction{code: 0};
  map[0x6C].* = Instruction{code: 0x6C, opcode: OPCODE_JMP, handler: handle_instr_jmp, addr_mode: ADDR_MODE_INDIRECT, desc: "JMP:INDIRECT", name: "JMP", cycle: 5};
  map[0x6D].* = Instruction{code: 0x6D, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS, desc: "ADC:ABS", name: "ADC", cycle: 4};
  map[0x6E].* = Instruction{code: 0x6E, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ABS, desc: "ROR:ABS", name: "ROR", cycle: 6};
  map[0x6F].* = Instruction{code: 0x4F, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_ABS, desc: "RRA:ABS", name: "RRA", illegal: true, cycle: 6};
  map[0x70].* = Instruction{code: 0x70, opcode: OPCODE_BVS, handler: handle_instr_bvs, addr_mode: ADDR_MODE_REL, desc: "BVS:REL", name: "BVS", cycle: 2};
  map[0x71].* = Instruction{code: 0x71, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "ADC:INDIRECT_Y", name: "ADC", cycle: 5};
  map[0x72].* = Instruction{code: 0x72, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x73].* = Instruction{code: 0x73, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "RRA:INDIRECT_Y", name: "RRA", illegal: true, cycle: 8};
  map[0x74].* = Instruction{code: 0x74, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0x75].* = Instruction{code: 0x75, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ADC:ZERO_PAGE_X", name: "ADC", cycle: 4};
  map[0x76].* = Instruction{code: 0x76, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ROR:ZERO_PAGE_X", name: "ROR", cycle: 6};
  map[0x77].* = Instruction{code: 0x77, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "RRA:ZERO_PAGE_X", name: "RRA", illegal: true, cycle: 6};
  map[0x78].* = Instruction{code: 0x78, opcode: OPCODE_SEI, handler: handle_instr_sei, addr_mode: ADDR_MODE_IMP, desc: "SEI:IMP", name: "SEI", cycle: 2};
  map[0x79].* = Instruction{code: 0x79, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS_Y, desc: "ADC:ABS_Y", name: "ADC", cycle: 4};
  map[0x7A].* = Instruction{code: 0x7A, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0x7B].* = Instruction{code: 0x7B, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_ABS_Y, desc: "RRA:ABS_Y", name: "RRA", illegal: true, cycle: 7};
  map[0x7C].* = Instruction{code: 0x7C, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0x7D].* = Instruction{code: 0x7D, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS_X, desc: "ADC:ABS_X", name: "ADC", cycle: 4};
  map[0x7E].* = Instruction{code: 0x7E, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ABS_X, desc: "ROR:ABS_X", name: "ROR", cycle: 7};
  map[0x7F].* = Instruction{code: 0x7F, opcode: OPCODE_RRA, handler: handle_instr_rra, addr_mode: ADDR_MODE_ABS_X, desc: "RRA:ABS_X", name: "RRA", illegal: true, cycle: 7};
  map[0x80].* = Instruction{code: 0x80, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMM, desc: "NOP:IMM", name: "NOP", illegal: true, cycle: 2};
  map[0x81].* = Instruction{code: 0x81, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_X_INDIRECT, desc: "STA:X_INDIRECT", name: "STA", cycle: 6};
  map[0x82].* = Instruction{code: 0x82, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMM, desc: "NOP:IMM", name: "NOP", illegal: true, cycle: 2};
  map[0x83].* = Instruction{code: 0x83, opcode: OPCODE_SAX, handler: handle_instr_sax, addr_mode: ADDR_MODE_X_INDIRECT, desc: "SAX:X_INDIRECT", name: "SAX", illegal: true, cycle: 6};
  map[0x84].* = Instruction{code: 0x84, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STY:ZERO_PAGE", name: "STY", cycle: 3};
  map[0x85].* = Instruction{code: 0x85, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STA:ZERO_PAGE", name: "STA", cycle: 3};
  map[0x86].* = Instruction{code: 0x86, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STX:ZERO_PAGE", name: "STX", cycle: 3};
  map[0x87].* = Instruction{code: 0x87, opcode: OPCODE_SAX, handler: handle_instr_sax, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "SAX:ZERO_PAGE", name: "SAX", illegal: true, cycle: 3};
  map[0x88].* = Instruction{code: 0x88, opcode: OPCODE_DEY, handler: handle_instr_dey, addr_mode: ADDR_MODE_IMP, desc: "DEY:IMP", name: "DEY", cycle: 2};
  map[0x89].* = Instruction{code: 0x89, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMM, desc: "NOP:IMM", name: "NOP", illegal: true, cycle: 2};
  map[0x8A].* = Instruction{code: 0x8A, opcode: OPCODE_TXA, handler: handle_instr_txa, addr_mode: ADDR_MODE_IMP, desc: "TXA:IMP", name: "TXA", cycle: 2};
  map[0x8B].* = Instruction{code: 0};
  map[0x8C].* = Instruction{code: 0x8C, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ABS, desc: "STY:ABS", name: "STY", cycle: 4};
  map[0x8D].* = Instruction{code: 0x8D, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS, desc: "STA:ABS", name: "STA", cycle: 4};
  map[0x8E].* = Instruction{code: 0x8E, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ABS, desc: "STX:ABS", name: "STX", cycle: 4};
  map[0x8F].* = Instruction{code: 0x8F, opcode: OPCODE_SAX, handler: handle_instr_sax, addr_mode: ADDR_MODE_ABS, desc: "SAX:ABS", name: "SAX", illegal: true, cycle: 4};
  map[0x90].* = Instruction{code: 0x90, opcode: OPCODE_BCC, handler: handle_instr_bcc, addr_mode: ADDR_MODE_REL, desc: "BCC:REL", name: "BCC", cycle: 2};
  map[0x91].* = Instruction{code: 0x91, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "STA:INDIRECT_Y", name: "STA", cycle: 6};
  map[0x92].* = Instruction{code: 0x91, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0x93].* = Instruction{code: 0};
  map[0x94].* = Instruction{code: 0x94, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "STY:ZERO_PAGE_X", name: "STY", cycle: 4};
  map[0x95].* = Instruction{code: 0x95, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "STA:ZERO_PAGE_X", name: "STA", cycle: 4};
  map[0x96].* = Instruction{code: 0x96, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "STX:ZERO_PAGE_Y", name: "STX", cycle: 4};
  map[0x97].* = Instruction{code: 0x97, opcode: OPCODE_SAX, handler: handle_instr_sax, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "SAX:ZERO_PAGE_Y", name: "SAX", illegal: true, cycle: 4};
  map[0x98].* = Instruction{code: 0x98, opcode: OPCODE_TYA, handler: handle_instr_tya, addr_mode: ADDR_MODE_IMP, desc: "TYA:IMP", name: "TYA", cycle: 2};
  map[0x99].* = Instruction{code: 0x99, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS_Y, desc: "STA:ABS_Y", name: "STA", cycle: 5};
  map[0x9A].* = Instruction{code: 0x9A, opcode: OPCODE_TXS, handler: handle_instr_txs, addr_mode: ADDR_MODE_IMP, desc: "TXS:IMP", name: "TXS", cycle: 2};
  map[0x9B].* = Instruction{code: 0};
  map[0x9C].* = Instruction{code: 0};
  map[0x9D].* = Instruction{code: 0x9D, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS_X, desc: "STA:ABS_X", name: "STA", cycle: 5};
  map[0x9E].* = Instruction{code: 0};
  map[0x9F].* = Instruction{code: 0};
  map[0xA0].* = Instruction{code: 0xA0, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_IMM, desc: "LDY:IMM", name: "LDY", cycle: 2};
  map[0xA1].* = Instruction{code: 0xA1, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_X_INDIRECT, desc: "LDA:X_INDIRECT", name: "LDA", cycle: 6};
  map[0xA2].* = Instruction{code: 0xA2, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_IMM, desc: "LDX:IMM", name: "LDX", cycle: 2};
  map[0xA3].* = Instruction{code: 0xA3, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_X_INDIRECT, desc: "LAX:X_INDIRECT", name: "LAX", illegal: true, cycle: 6};
  map[0xA4].* = Instruction{code: 0xA4, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDY:ZERO_PAGE", name: "LDY", cycle: 3};
  map[0xA5].* = Instruction{code: 0xA5, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDA:ZERO_PAGE", name: "LDA", cycle: 3};
  map[0xA6].* = Instruction{code: 0xA6, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDX:ZERO_PAGE", name: "LDX", cycle: 3};
  map[0xA7].* = Instruction{code: 0xA7, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LAX:ZERO_PAGE", name: "LAX", illegal: true, cycle: 3};
  map[0xA8].* = Instruction{code: 0xA8, opcode: OPCODE_TAY, handler: handle_instr_tay, addr_mode: ADDR_MODE_IMP, desc: "TAY:IMP", name: "TAY", cycle: 2};
  map[0xA9].* = Instruction{code: 0xA9, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_IMM, desc: "LDA:IMM", name: "LDA", cycle: 2};
  map[0xAA].* = Instruction{code: 0xAA, opcode: OPCODE_TAX, handler: handle_instr_tax, addr_mode: ADDR_MODE_IMP, desc: "TAX:IMP", name: "TAX", cycle: 2};
  map[0xAB].* = Instruction{code: 0};
  map[0xAC].* = Instruction{code: 0xAC, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ABS, desc: "LDY:ABS", name: "LDY", cycle: 4};
  map[0xAD].* = Instruction{code: 0xAD, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS, desc: "LDA:ABS", name: "LDA", cycle: 4};
  map[0xAE].* = Instruction{code: 0xAE, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ABS, desc: "LDX:ABS", name: "LDX", cycle: 4};
  map[0xAF].* = Instruction{code: 0xAF, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_ABS, desc: "LAX:ABS", name: "LAX", illegal: true, cycle: 4};
  map[0xB0].* = Instruction{code: 0xB0, opcode: OPCODE_BCS, handler: handle_instr_bcs, addr_mode: ADDR_MODE_REL, desc: "BCS:REL", name: "BCS", cycle: 2};
  map[0xB1].* = Instruction{code: 0xB1, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "LDA:INDIRECT_Y", name: "LDA", cycle: 5};
  map[0xB2].* = Instruction{code: 0xB2, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0xB3].* = Instruction{code: 0xB3, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "LAX:INDIRECT_Y", name: "LAX", illegal: true, cycle: 5};
  map[0xB4].* = Instruction{code: 0xB4, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LDY:ZERO_PAGE_X", name: "LDY", cycle: 4};
  map[0xB5].* = Instruction{code: 0xB5, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LDA:ZERO_PAGE_X", name: "LDA", cycle: 4};
  map[0xB6].* = Instruction{code: 0xB6, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "LDX:ZERO_PAGE_Y", name: "LDX", cycle: 4};
  map[0xB7].* = Instruction{code: 0xB7, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "LAX:ZERO_PAGE_Y", name: "LAX", illegal: true, cycle: 4};
  map[0xB8].* = Instruction{code: 0xB8, opcode: OPCODE_CLV, handler: handle_instr_clv, addr_mode: ADDR_MODE_IMP, desc: "CLV:IMP", name: "CLV", cycle: 2};
  map[0xB9].* = Instruction{code: 0xB9, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS_Y, desc: "LDA:ABS_Y", name: "LDA", cycle: 4};
  map[0xBA].* = Instruction{code: 0xBA, opcode: OPCODE_TSX, handler: handle_instr_tsx, addr_mode: ADDR_MODE_IMP, desc: "TSX:IMP", name: "TSX", cycle: 2};
  map[0xBB].* = Instruction{code: 0};
  map[0xBC].* = Instruction{code: 0xBC, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ABS_X, desc: "LDY:ABS_X", name: "LDY", cycle: 4};
  map[0xBD].* = Instruction{code: 0xBD, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS_X, desc: "LDA:ABS_X", name: "LDA", cycle: 4};
  map[0xBE].* = Instruction{code: 0xBE, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ABS_Y, desc: "LDX:ABS_Y", name: "LDX", cycle: 4};
  map[0xBF].* = Instruction{code: 0xBF, opcode: OPCODE_LAX, handler: handle_instr_lax, addr_mode: ADDR_MODE_ABS_Y, desc: "LAX:ABS_Y", name: "LAX", illegal: true, cycle: 4};
  map[0xC0].* = Instruction{code: 0xC0, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_IMM, desc: "CPY:IMM", name: "CPY", cycle: 2};
  map[0xC1].* = Instruction{code: 0xC1, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_X_INDIRECT, desc: "CMP:X_INDIRECT", name: "CMP", cycle: 6};
  map[0xC2].* = Instruction{code: 0xC2, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMM, desc: "NOP:IMM", name: "NOP", illegal: true, cycle: 2};
  map[0xC3].* = Instruction{code: 0xC3, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_X_INDIRECT, desc: "DCP:X_INDIRECT", name: "DCP", illegal: true, cycle: 8};
  map[0xC4].* = Instruction{code: 0xC4, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CPY:ZERO_PAGE", name: "CPY", cycle: 3};
  map[0xC5].* = Instruction{code: 0xC5, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CMP:ZERO_PAGE", name: "CMP", cycle: 3};
  map[0xC6].* = Instruction{code: 0xC6, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "DEC:ZERO_PAGE", name: "DEC", cycle: 5};
  map[0xC7].* = Instruction{code: 0xC7, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "DCP:ZERO_PAGE", name: "DCP", illegal: true, cycle: 5};
  map[0xC8].* = Instruction{code: 0xC8, opcode: OPCODE_INY, handler: handle_instr_iny, addr_mode: ADDR_MODE_IMP, desc: "INY:IMP", name: "INY", cycle: 2};
  map[0xC9].* = Instruction{code: 0xC9, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_IMM, desc: "CMP:IMM", name: "CMP", cycle: 2};
  map[0xCA].* = Instruction{code: 0xCA, opcode: OPCODE_DEX, handler: handle_instr_dex, addr_mode: ADDR_MODE_IMP, desc: "DEX:IMP", name: "DEX", cycle: 2};
  map[0xCB].* = Instruction{code: 0};
  map[0xCC].* = Instruction{code: 0xCC, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_ABS, desc: "CPY:ABS", name: "CPY", cycle: 4};
  map[0xCD].* = Instruction{code: 0xCD, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS, desc: "CMP:ABS", name: "CMP", cycle: 4};
  map[0xCE].* = Instruction{code: 0xCE, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ABS, desc: "DEC:ABS", name: "DEC", cycle: 6};
  map[0xCF].* = Instruction{code: 0xCF, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_ABS, desc: "DCP:ABS", name: "DCP", illegal: true, cycle: 6};
  map[0xD0].* = Instruction{code: 0xD0, opcode: OPCODE_BNE, handler: handle_instr_bne, addr_mode: ADDR_MODE_REL, desc: "BNE:REL", name: "BNE", cycle: 2};
  map[0xD1].* = Instruction{code: 0xD1, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "CMP:INDIRECT_Y", name: "CMP", cycle: 5};
  map[0xD2].* = Instruction{code: 0xD2, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0xD3].* = Instruction{code: 0xD3, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "DCP:INDIRECT_Y", name: "DCP", illegal: true, cycle: 8};
  map[0xD4].* = Instruction{code: 0xD4, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0xD5].* = Instruction{code: 0xD5, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "CMP:ZERO_PAGE_X", name: "CMP", cycle: 4};
  map[0xD6].* = Instruction{code: 0xD6, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "DEC:ZERO_PAGE_X", name: "DEC", cycle: 6};
  map[0xD7].* = Instruction{code: 0xD7, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "DCP:ZERO_PAGE_X", name: "DCP", illegal: true, cycle: 6};
  map[0xD8].* = Instruction{code: 0xD8, opcode: OPCODE_CLD, handler: handle_instr_cld, addr_mode: ADDR_MODE_IMP, desc: "CLD:IMP", name: "CLD", cycle: 2};
  map[0xD9].* = Instruction{code: 0xD9, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS_Y, desc: "CMP:ABS_Y", name: "CMP", cycle: 4};
  map[0xDA].* = Instruction{code: 0xDA, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0xDB].* = Instruction{code: 0xDB, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_ABS_Y, desc: "DCP:ABS_Y", name: "DCP", illegal: true, cycle: 7};
  map[0xDC].* = Instruction{code: 0xDC, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0xDD].* = Instruction{code: 0xDD, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS_X, desc: "CMP:ABS_X", name: "CMP", cycle: 4};
  map[0xDE].* = Instruction{code: 0xDE, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ABS_X, desc: "DEC:ABS_X", name: "DEC", cycle: 7};
  map[0xDF].* = Instruction{code: 0xDF, opcode: OPCODE_DCP, handler: handle_instr_dcp, addr_mode: ADDR_MODE_ABS_X, desc: "DCP:ABS_X", name: "DCP", illegal: true, cycle: 7};
  map[0xE0].* = Instruction{code: 0xE0, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_IMM, desc: "CPX:IMM", name: "CPX", cycle: 2};
  map[0xE1].* = Instruction{code: 0xE1, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_X_INDIRECT, desc: "SBC:X_INDIRECT", name: "SBC", cycle: 6};
  map[0xE2].* = Instruction{code: 0xE2, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMM, desc: "NOP:IMM", name: "NOP", illegal: true, cycle: 2};
  map[0xE3].* = Instruction{code: 0xE3, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_X_INDIRECT, desc: "ISB:X_INDIRECT", name: "ISB", illegal: true, cycle: 8};
  map[0xE4].* = Instruction{code: 0xE4, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CPX:ZERO_PAGE", name: "CPX", cycle: 3};
  map[0xE5].* = Instruction{code: 0xE5, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "SBC:ZERO_PAGE", name: "SBC", cycle: 3};
  map[0xE6].* = Instruction{code: 0xE6, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "INC:ZERO_PAGE", name: "INC", cycle: 5};
  map[0xE7].* = Instruction{code: 0xE7, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ISB:ZERO_PAGE", name: "ISB", illegal: true, cycle: 5};
  map[0xE8].* = Instruction{code: 0xE8, opcode: OPCODE_INX, handler: handle_instr_inx, addr_mode: ADDR_MODE_IMP, desc: "INX:IMP", name: "INX", cycle: 2};
  map[0xE9].* = Instruction{code: 0xE9, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_IMM, desc: "SBC:IMM", name: "SBC", cycle: 2};
  map[0xEA].* = Instruction{code: 0xEA, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", cycle: 2};
  map[0xEB].* = Instruction{code: 0xEB, opcode: OPCODE_USBC, handler: handle_instr_usbc, addr_mode: ADDR_MODE_IMM, desc: "INC:IMM", name: "SBC", illegal: true, cycle: 2};
  map[0xEC].* = Instruction{code: 0xEC, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_ABS, desc: "CPX:ABS", name: "CPX", cycle: 4};
  map[0xED].* = Instruction{code: 0xED, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS, desc: "SBC:ABS", name: "SBC", cycle: 4};
  map[0xEE].* = Instruction{code: 0xEE, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ABS, desc: "INC:ABS", name: "INC", cycle: 6};
  map[0xEF].* = Instruction{code: 0xEF, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_ABS, desc: "ISB:ABS", name: "ISB", illegal: true, cycle: 6};
  map[0xF0].* = Instruction{code: 0xF0, opcode: OPCODE_BEQ, handler: handle_instr_beq, addr_mode: ADDR_MODE_REL, desc: "BEQ:REL", name: "BEQ", cycle: 2};
  map[0xF1].* = Instruction{code: 0xF1, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "SBC:INDIRECT_Y", name: "SBC", cycle: 5};
  map[0xF2].* = Instruction{code: 0xF2, opcode: OPCODE_JAM, handler: handle_instr_jam, addr_mode: ADDR_MODE_IMP, desc: "JAM", name: "JAM", cycle: 1};
  map[0xF3].* = Instruction{code: 0xF3, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "ISB:INDIRECT_Y", name: "ISB", illegal: true, cycle: 8};
  map[0xF4].* = Instruction{code: 0xF4, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "NOP:ZERO_PAGE_X", name: "NOP", illegal: true, cycle: 4};
  map[0xF5].* = Instruction{code: 0xF5, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "SBC:ZERO_PAGE_X", name: "SBC", cycle: 4};
  map[0xF6].* = Instruction{code: 0xF6, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "INC:ZERO_PAGE_X", name: "INC", cycle: 6};
  map[0xF7].* = Instruction{code: 0xF7, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ISB:ZERO_PAGE_X", name: "ISB", illegal: true, cycle: 6};
  map[0xF8].* = Instruction{code: 0xF8, opcode: OPCODE_SED, handler: handle_instr_sed, addr_mode: ADDR_MODE_IMP, desc: "SED:IMP", name: "SED", cycle: 2};
  map[0xF9].* = Instruction{code: 0xF9, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS_Y, desc: "SBC:ABS_Y", name: "SBC", cycle: 4};
  map[0xFA].* = Instruction{code: 0xFA, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP", name: "NOP", illegal: true, cycle: 2};
  map[0xFB].* = Instruction{code: 0xFB, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_ABS_Y, desc: "ISB:ABS_Y", name: "ISB", illegal: true, cycle: 7};
  map[0xFC].* = Instruction{code: 0xFC, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_ABS_X, desc: "NOP:ABS_X", name: "NOP", illegal: true, cycle: 4};
  map[0xFD].* = Instruction{code: 0xFD, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS_X, desc: "SBC:ABS_X", name: "SBC", cycle: 4};
  map[0xFE].* = Instruction{code: 0xFE, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ABS_X, desc: "INC:ABS_X", name: "INC", cycle: 7};
  map[0xFF].* = Instruction{code: 0xFF, opcode: OPCODE_ISB, handler: handle_instr_isb, addr_mode: ADDR_MODE_ABS_X, desc: "ISB:ABS_X", name: "ISB", illegal: true, cycle: 7};

  return map;
}

fn reset(cpu: *CPU) {
  cpu.reg.a.* = 0;
  cpu.reg.x.* = 0;
  cpu.reg.y.* = 0;
  cpu.reg.sp.* = 0xfd;
  cpu.reg.status.* = 0x00 | FLAG_MASK_INTERRUPT_DISABLE | FLAG_MASK_1;
  cpu.reg.pc.* = mem_read_u16(0xfffc);
  cpu.remaining_cycle.* = 7;
}

fn mem_read_u16(addr: u16): u16 {
  let lo = bus::read(addr) as u16;
  let hi = bus::read(addr + 1) as u16;
  return (hi << 8) | lo;
}

fn interrupt(cpu: *CPU) {
  if (cpu.reg.status.* & FLAG_MASK_INTERRUPT_DISABLE) == 0 {
    return;
  }

  bus::write(cpu.reg.sp.* as u16, (cpu.reg.pc.* >> 8) as u8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  bus::write(cpu.reg.sp.* as u16, (cpu.reg.pc.* & 0xff) as u8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_BREAK;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  bus::write(cpu.reg.sp.* as u16, cpu.reg.status.*);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  let addr_0: u16 = 0xfffe;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = hi << 8 | lo;
}

fn non_maskable_interrupt(cpu: *CPU) {
  stack_push_u16(cpu, cpu.reg.pc.*);

  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_BREAK;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  stack_push(cpu, cpu.reg.status.*);

  let addr_0: u16 = 0xfffa;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = (hi << 8) | lo;
}

fn tick(cpu: *CPU, cycles: i64) {
  let cycles = cycles as i32;
  while cycles > 0 {
    if cpu.remaining_cycle.* <= cycles {
      cycles = cycles - cpu.remaining_cycle.*;
      cpu.remaining_cycle.* = execute_next_instruction(cpu);
    } else {
      cpu.remaining_cycle.* = cpu.remaining_cycle.* - cycles;
      cycles = 0;
    }
  }
}

let debug: bool = false;
fn execute_next_instruction(cpu: *CPU): i32 {
  let opcode = bus::read(cpu.reg.pc.*);

  if debug {
    debug_u16(cpu.reg.pc.*);
    fmt::print_str("  ");
    debug_u8(opcode);
  }

  cpu.last_opcode.* = opcode;
  cpu.last_pc.* = cpu.reg.pc.*;
  cpu.reg.pc.* = cpu.reg.pc.* + 1;

  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;

  let ins = instruction_map[opcode];
  let addr_mode = ins.addr_mode.*;
  cpu.last_ins.* = ins.desc.*;

  if ins.code.* == 0 {
    fmt::print_str("found undefined instruction ");
    fmt::print_u8(opcode);
    fmt::print_str("\n");
    wasm::trap();
  }

  let addr: u16;

  if addr_mode == ADDR_MODE_IMP {
    if debug { fmt::print_str("       "); }
  } else if addr_mode == ADDR_MODE_A {
    if debug { fmt::print_str("       "); }
  } else if addr_mode == ADDR_MODE_IMM {
    addr = cpu.reg.pc.*;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_ZERO_PAGE {
    addr = bus::read(cpu.reg.pc.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    if debug {
      fmt::print_str(" ");
      debug_u8((addr as u8) & 0xff);
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_ZERO_PAGE_X {
    addr = (bus::read(cpu.reg.pc.*) + cpu.reg.x.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_ZERO_PAGE_Y {
    addr = (bus::read(cpu.reg.pc.*) + cpu.reg.y.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_REL {
    addr = ((bus::read(cpu.reg.pc.*) as i8) as i16 + cpu.reg.pc.* as i16 + 1) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_ABS {
    addr = mem_read_u16(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 2));
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str(" ");
    }
  } else if addr_mode == ADDR_MODE_ABS_X {
    addr = mem_read_u16(cpu.reg.pc.*) + cpu.reg.x.* as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 2));
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str(" ");
    }
  } else if addr_mode == ADDR_MODE_ABS_Y {
    addr = mem_read_u16(cpu.reg.pc.*) + cpu.reg.y.* as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 2));
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str(" ");
    }
  } else if addr_mode == ADDR_MODE_INDIRECT {
    addr = mem_read_u16(cpu.reg.pc.*);

    let lo = bus::read(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    let hi = bus::read(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 1;

    let addr_lo = (hi as u16 << 8) | (lo as u16);
    let addr_hi = (hi as u16 << 8) | (((lo + 1) & 0xff) as u16);
    let lo = bus::read(addr_lo);
    let hi = bus::read(addr_hi);
    addr = (hi as u16 << 8) | (lo as u16);

    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 2));
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str(" ");
    }
  } else if addr_mode == ADDR_MODE_X_INDIRECT {
    let ptr = bus::read(cpu.reg.pc.*) + cpu.reg.x.*;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    let lo = bus::read(ptr as u16);
    let hi = bus::read(((ptr+1) & 0xff) as u16);
    addr = (hi as u16 << 8) | (lo as u16)
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  } else if addr_mode == ADDR_MODE_INDIRECT_Y {
    let ptr = bus::read(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    let lo = bus::read(ptr as u16);
    let hi = bus::read((ptr + 1) as u16);
    let base = (hi as u16 << 8) | (lo as u16);
    addr = base + cpu.reg.y.* as u16;
    if debug {
      fmt::print_str(" ");
      debug_u8(bus::read(cpu.reg.pc.* - 1));
      fmt::print_str("    ");
    }
  }

  cpu.last_addr.* = addr;

  if debug {
    if ins.illegal.* {
      fmt::print_str("*");
    } else {
      fmt::print_str(" ");
    }
    fmt::print_str(ins.name.*);
    // fmt::print_str(" addr=");
    // fmt::print_u16(addr);
    // fmt::print_str(" data=");
    // fmt::print_u8(data);

    fmt::print_str("  ");
    fmt::print_str("A:");
    debug_u8(cpu.reg.a.*);
    fmt::print_str(" X:");
    debug_u8(cpu.reg.x.*);
    fmt::print_str(" Y:");
    debug_u8(cpu.reg.y.*);
    fmt::print_str(" P:");
    debug_u8(cpu.reg.status.*);
    fmt::print_str(" SP:");
    debug_u8(cpu.reg.sp.*);
    // if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 { fmt::print_str("C"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_ZERO) != 0 { fmt::print_str("Z"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_INTERRUPT_DISABLE) != 0 { fmt::print_str("I"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_DECIMAL) != 0 { fmt::print_str("D"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_BREAK) != 0 { fmt::print_str("B"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_1) != 0 { fmt::print_str("1"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) != 0 { fmt::print_str("V"); } else { fmt::print_str("-"); }
    // if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) != 0 { fmt::print_str("N"); } else { fmt::print_str("-"); }
    fmt::print_str("\n");
  }

  let handler = ins.handler.*;
  let additional_cycle = handler(cpu, addr_mode, addr);
  return ins.cycle.* + additional_cycle;
}

fn handle_instr_adc(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  add_to_reg_a(cpu, data);
  return 0;
}

fn get_data(cpu: *CPU, mode: u8, addr: u16): u8 {
  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    return cpu.reg.a.*;
  }
  return bus::read(addr);
}

fn add_to_reg_a(cpu: *CPU, data: u8) {
  let data_san = data & 0xff;

  let tmp = (cpu.reg.a.* as u16) + (data_san as u16);
  if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 {
    tmp = tmp + 1;
  }

  if tmp > 0xff {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let result = (tmp as u8) & 0xff;
  if ((data_san ^ result) & (result ^ cpu.reg.a.*) & 0x80) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_OVERFLOW;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_OVERFLOW;
  }

  set_reg_a(cpu, result);
}

fn handle_instr_and(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, cpu.reg.a.* & data);
  return 0;
}

fn set_reg_a(cpu: *CPU, data: u8) {
  cpu.reg.a.* = data;
  update_zero_and_neg_flag(cpu, cpu.reg.a.*);
}

fn update_zero_and_neg_flag(cpu: *CPU, result: u8) {
  if result == 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_ZERO;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_ZERO;
  }

  if (result & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_NEGATIVE;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_NEGATIVE;
  }
}

fn update_neg_flag(cpu: *CPU, result: u8) {
  if (result & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_NEGATIVE;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_NEGATIVE;
  }
}

fn handle_instr_asl(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if (data & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let tmp = data << 1;

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    cpu.reg.a.* = tmp as u8;
  } else {
    bus::write(addr, tmp as u8);
  }

  update_zero_and_neg_flag(cpu, tmp);
  return 0;
}

fn handle_instr_bcc(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_CARRY) == 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_bcs(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_beq(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_ZERO) != 0 {
    cpu.reg.pc.* = addr;
    return 1;
  }
  return 0;
}

fn handle_instr_bit(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let result = cpu.reg.a.* & data;
  if result == 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_ZERO;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_ZERO;
  }

  if (data & FLAG_MASK_NEGATIVE) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_NEGATIVE;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_NEGATIVE;
  }

  if (data & FLAG_MASK_OVERFLOW) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_OVERFLOW;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_OVERFLOW;
  }
  return 0;
}

fn handle_instr_bmi(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) != 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_bne(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_ZERO) == 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_bpl(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) == 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_brk(cpu: *CPU, mode: u8, addr: u16): i32 {
  // TODO: maybe should turn off the emulation?
  wasm::trap();
  return 0;
}

fn handle_instr_bvc(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) == 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_bvs(cpu: *CPU, mode: u8, addr: u16): i32 {
  if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) != 0 {
    cpu.reg.pc.* = addr;
  }
  return 0;
}

fn handle_instr_clc(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  return 0;
}

fn handle_instr_cld(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_DECIMAL;
  return 0;
}

fn handle_instr_cli(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_INTERRUPT_DISABLE;
  return 0;
}

fn handle_instr_clv(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_OVERFLOW;
  return 0;
}

fn handle_instr_cmp(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let tmp = (cpu.reg.a.* - data) & 0xff;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.a.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  return 0;
}

fn handle_instr_cpx(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let tmp = cpu.reg.x.* - data;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.x.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  return 0;
}

fn handle_instr_cpy(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let tmp = cpu.reg.y.* - data;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.y.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  return 0;
}

fn handle_instr_dec(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if data == 0 {
    data = 0xff;
  } else {
    data = data - 1;
  }
  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
  return 0;
}

fn handle_instr_dex(cpu: *CPU, mode: u8, addr: u16): i32 {
  if cpu.reg.x.* == 0 {
    cpu.reg.x.* = 0xff;
  } else {
    cpu.reg.x.* = cpu.reg.x.* - 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
  return 0;
}

fn handle_instr_dey(cpu: *CPU, mode: u8, addr: u16): i32 {
  if cpu.reg.y.* == 0 {
    cpu.reg.y.* = 0xff;
  } else {
    cpu.reg.y.* = cpu.reg.y.* - 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
  return 0;
}

fn handle_instr_eor(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, cpu.reg.a.* ^ data);
  return 0;
}

fn handle_instr_inc(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if data == 0xff {
    data = 0;
  } else {
    data = data + 1;
  }
  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
  return 0;
}

fn handle_instr_inx(cpu: *CPU, mode: u8, addr: u16): i32 {
  if cpu.reg.x.* == 0xff {
    cpu.reg.x.* = 0;
  } else {
    cpu.reg.x.* = cpu.reg.x.* + 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
  return 0;
}

fn handle_instr_iny(cpu: *CPU, mode: u8, addr: u16): i32 {
  if cpu.reg.y.* == 0xff {
    cpu.reg.y.* = 0;
  } else {
    cpu.reg.y.* = cpu.reg.y.* + 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
  return 0;
}

fn handle_instr_jmp(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.pc.* = addr;
  return 0;
}

fn handle_instr_jsr(cpu: *CPU, mode: u8, addr: u16): i32 {
  stack_push_u16(cpu, cpu.reg.pc.* - 1);
  cpu.reg.pc.* = addr;
  return 0;
}

fn stack_push_u16(cpu: *CPU, data: u16) {
  let hi = (data >> 8) as u8;
  let lo = data as u8;
  stack_push(cpu, hi);
  stack_push(cpu, lo);
}

fn stack_push(cpu: *CPU, data: u8) {
  bus::write(cpu.reg.sp.* as u16 + 0x100, data);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;
}

fn handle_instr_lda(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, data);
  return 0;
}

fn handle_instr_ldx(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  cpu.reg.x.* = data;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
  return 0;
}

fn handle_instr_ldy(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  cpu.reg.y.* = data;
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
  return 0;
}

fn handle_instr_lsr(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let data = (data & 0xff) >> 1;
  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    cpu.reg.a.* = data;
  } else {
    bus::write(addr, data);
  }

  update_zero_and_neg_flag(cpu, data);
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_NEGATIVE;
  return 0;
}

fn handle_instr_nop(cpu: *CPU, mode: u8, addr: u16): i32 {
  return 0;
}

fn handle_instr_ora(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, cpu.reg.a.* | data);
  return 0;
}

fn handle_instr_pha(cpu: *CPU, mode: u8, addr: u16): i32 {
  stack_push(cpu, cpu.reg.a.*);
  return 0;
}

fn handle_instr_php(cpu: *CPU, mode: u8, addr: u16): i32 {
  stack_push(cpu, cpu.reg.status.* | FLAG_MASK_BREAK | FLAG_MASK_1);
  return 0;
}

fn handle_instr_pla(cpu: *CPU, mode: u8, addr: u16): i32 {
  set_reg_a(cpu, stack_pop(cpu));
  return 0;
}

fn stack_pop(cpu: *CPU): u8 {
  cpu.reg.sp.* = cpu.reg.sp.* + 1;
  return bus::read(cpu.reg.sp.* as u16 + 0x100);
}

fn stack_pop_u16(cpu: *CPU): u16 {
  let lo = stack_pop(cpu);
  let hi = stack_pop(cpu);
  return (hi as u16 << 8) | (lo as u16);
}

fn handle_instr_plp(cpu: *CPU, mode: u8, addr: u16): i32 {
  let flag = stack_pop(cpu);
  cpu.reg.status.* = (flag & ~FLAG_MASK_BREAK) | FLAG_MASK_1;
  return 0;
}

fn handle_instr_rol(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  data = data << 1;

  if old_carry {
    data = data | 1;
  }

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    set_reg_a(cpu, data);
  } else {
    bus::write(addr, data);
    update_zero_and_neg_flag(cpu, data);
  }
  return 0;
}

fn handle_instr_ror(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  data = data >> 1;
  if old_carry {
    data = data | 0b1000_0000;
  }

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    set_reg_a(cpu, data);
  } else {
    bus::write(addr, data);
    update_zero_and_neg_flag(cpu, data);
  }
  return 0;
}

fn handle_instr_rti(cpu: *CPU, mode: u8, addr: u16): i32 {
  let flag = stack_pop(cpu);
  cpu.reg.status.* = (flag & ~FLAG_MASK_BREAK) | FLAG_MASK_1;
  cpu.reg.pc.* = stack_pop_u16(cpu);
  return 0;
}

fn handle_instr_rts(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.pc.* = stack_pop_u16(cpu) + 1;
  return 0;
}

fn handle_instr_sbc(cpu: *CPU, mode: u8, addr: u16) : i32 {
  let data = get_data(cpu, mode, addr);
  add_to_reg_a(cpu, (-(data as i8)-1) as u8);
  return 0;
}

fn handle_instr_sec(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  return 0;
}

fn handle_instr_sed(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_DECIMAL;
  return 0;
}

fn handle_instr_sei(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  return 0;
}

fn handle_instr_sta(cpu: *CPU, mode: u8, addr: u16): i32 {
  bus::write(addr, cpu.reg.a.*);
  return 0;
}

fn handle_instr_stx(cpu: *CPU, mode: u8, addr: u16): i32 {
  bus::write(addr, cpu.reg.x.*);
  return 0;
}

fn handle_instr_sty(cpu: *CPU, mode: u8, addr: u16): i32 {
  bus::write(addr, cpu.reg.y.*);
  return 0;
}

fn handle_instr_tax(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.x.* = cpu.reg.a.*;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
  return 0;
}

fn handle_instr_tay(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.y.* = cpu.reg.a.*;
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
  return 0;
}

fn handle_instr_tsx(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.x.* = cpu.reg.sp.*;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
  return 0;
}

fn handle_instr_txa(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.a.* = cpu.reg.x.*;
  update_zero_and_neg_flag(cpu, cpu.reg.a.*);
  return 0;
}

fn handle_instr_txs(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.sp.* = cpu.reg.x.*;
  return 0;
}

fn handle_instr_tya(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.a.* = cpu.reg.y.*;
  update_zero_and_neg_flag(cpu, cpu.reg.a.*);
  return 0;
}

fn handle_instr_lax(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, data);
  cpu.reg.x.* = cpu.reg.a.*;
  return 0;
}

fn handle_instr_sax(cpu: *CPU, mode: u8, addr: u16): i32 {
  bus::write(addr, cpu.reg.a.* & cpu.reg.x.*);
  return 0;
}

fn handle_instr_usbc(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  add_to_reg_a(cpu, (-(data as i8)-1) as u8);
  return 0;
}

fn handle_instr_dcp(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let data = data - 1;
  bus::write(addr, data);
  if data <= cpu.reg.a.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.a.* - data);
  return 0;
}

fn handle_instr_isb(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if data == 0xff {
    data = 0;
  } else {
    data = data + 1;
  }
  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);

  add_to_reg_a(cpu, (-(data as i8)-1) as u8);
  return 0;
}

fn handle_instr_slo(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if (data & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let tmp = data << 1;

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    cpu.reg.a.* = tmp as u8;
  } else {
    bus::write(addr, tmp as u8);
  }

  update_zero_and_neg_flag(cpu, tmp);

  set_reg_a(cpu, tmp | cpu.reg.a.*);
  return 0;
}

fn handle_instr_rla(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 0b1000_0000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  data = data << 1;

  if old_carry {
    data = data | 1;
  }

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    set_reg_a(cpu, data);
  } else {
    bus::write(addr, data);
    update_zero_and_neg_flag(cpu, data);
  }

  set_reg_a(cpu, data & cpu.reg.a.*);
  return 0;
}

fn handle_instr_sre(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let data = (data & 0xff) >> 1;
  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    cpu.reg.a.* = data;
  } else {
    bus::write(addr, data);
  }

  update_zero_and_neg_flag(cpu, data);

  set_reg_a(cpu, data ^ cpu.reg.a.*);
  return 0;
}

fn handle_instr_rra(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  data = data >> 1;

  if old_carry {
    data = data | 0b1000_0000;
  }

  if mode == ADDR_MODE_IMP || mode == ADDR_MODE_A {
    set_reg_a(cpu, data);
  } else {
    bus::write(addr, data);
    update_zero_and_neg_flag(cpu, data);
  }

  add_to_reg_a(cpu, data);
  return 0;
}

fn handle_instr_jam(cpu: *CPU, mode: u8, addr: u16): i32 {
  cpu.reg.pc.* = cpu.reg.pc.* - 1;
  return 0;
}

fn handle_instr_anc(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, data & cpu.reg.a.*);
  if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  return 0;
}

fn handle_instr_alr(cpu: *CPU, mode: u8, addr: u16): i32 {
  let data = get_data(cpu, mode, addr);
  set_reg_a(cpu, data & cpu.reg.a.*);

  if (cpu.reg.a.* & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  set_reg_a(cpu, cpu.reg.a.* >> 1);

  return 0;
}

let s: [*]u8 = mem::alloc_array::<u8>(5);
fn debug_u16(val: u16) {
  let i = 0;
  while i < 4 {
    if (val & 0xf) > 9 {
      s[3-i].* = 65 + (val & 0xf) as u8 - 10;
    } else {
      s[3-i].* = 48 + (val & 0xf) as u8;
    }
    i = i + 1;
    val = val >> 4;
  }
  s[4].* = 0;
  fmt::print_str(s);
}

fn debug_u8(val: u8) {
  let i = 0;
  while i < 2 {
    if (val & 0xf) > 9 {
      s[1-i].* = 65 + (val & 0xf) as u8 - 10;
    } else {
      s[1-i].* = 48 + (val & 0xf) as u8;
    }
    i = i + 1;
    val = val >> 4;
  }
  s[2].* = 0;
  fmt::print_str(s);
}
