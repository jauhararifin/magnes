import bus "bus";
import wasm "wasm";
import fmt "fmt";
import mem "mem";

struct CPU {
  reg: Register,

  last_opcode: u8,
  last_ins: [*]u8, // TODO: remove this, this is for debugging only
  last_addr: u16,
  last_data: u8,
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

let OPCODE_ADC: u8 =  0; // OPCODE_ADC add with carry
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

struct Instruction {
  code:      u8,
  opcode:    u8,
  addr_mode: u8,
  handler:   fn( *CPU, u8, u16, u8),
  desc:      [*]u8,
}

let instruction_map: [*]Instruction = init_instruction_map();

fn init_instruction_map(): [*]Instruction {
  let map = mem::alloc_array::<Instruction>(0xFF);

  map[0x00].* = Instruction{code: 0x00, opcode: OPCODE_BRK, handler: handle_instr_brk, addr_mode: ADDR_MODE_IMP, desc: "BRK:IMP"};
  map[0x01].* = Instruction{code: 0x01, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_X_INDIRECT, desc: "ORA:X_INDIRECT"};
  map[0x05].* = Instruction{code: 0x05, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ORA:ZERO_PAGE"};
  map[0x06].* = Instruction{code: 0x06, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ASL:ZERO_PAGE"};
  map[0x08].* = Instruction{code: 0x08, opcode: OPCODE_PHP, handler: handle_instr_php, addr_mode: ADDR_MODE_IMP, desc: "PHP:IMP"};
  map[0x09].* = Instruction{code: 0x09, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_IMM, desc: "ORA:IMM"};
  map[0x0A].* = Instruction{code: 0x0A, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_A, desc: "ASL:A"};
  map[0x0D].* = Instruction{code: 0x0D, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS, desc: "ORA:ABS"};
  map[0x0E].* = Instruction{code: 0x0E, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ABS, desc: "ASL:ABS"};
  map[0x10].* = Instruction{code: 0x10, opcode: OPCODE_BPL, handler: handle_instr_bpl, addr_mode: ADDR_MODE_REL, desc: "BPL:REL"};
  map[0x11].* = Instruction{code: 0x11, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "ORA:INDIRECT_Y"};
  map[0x15].* = Instruction{code: 0x15, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ORA:ZERO_PAGE_X"};
  map[0x16].* = Instruction{code: 0x16, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ASL:ZERO_PAGE_X"};
  map[0x18].* = Instruction{code: 0x18, opcode: OPCODE_CLC, handler: handle_instr_clc, addr_mode: ADDR_MODE_IMP, desc: "CLC:IMP"};
  map[0x19].* = Instruction{code: 0x19, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS_Y, desc: "ORA:ABS_Y"};
  map[0x1D].* = Instruction{code: 0x1D, opcode: OPCODE_ORA, handler: handle_instr_ora, addr_mode: ADDR_MODE_ABS_X, desc: "ORA:ABS_X"};
  map[0x1E].* = Instruction{code: 0x1E, opcode: OPCODE_ASL, handler: handle_instr_asl, addr_mode: ADDR_MODE_ABS_X, desc: "ASL:ABS_X"};
  map[0x20].* = Instruction{code: 0x20, opcode: OPCODE_JSR, handler: handle_instr_jsr, addr_mode: ADDR_MODE_ABS, desc: "JSR:ABS"};
  map[0x21].* = Instruction{code: 0x21, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_X_INDIRECT, desc: "AND:X_INDIRECT"};
  map[0x24].* = Instruction{code: 0x24, opcode: OPCODE_BIT, handler: handle_instr_bit, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "BIT:ZERO_PAGE"};
  map[0x25].* = Instruction{code: 0x25, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "AND:ZERO_PAGE"};
  map[0x26].* = Instruction{code: 0x26, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ROL:ZERO_PAGE"};
  map[0x28].* = Instruction{code: 0x28, opcode: OPCODE_PLP, handler: handle_instr_plp, addr_mode: ADDR_MODE_IMP, desc: "PLP:IMP"};
  map[0x29].* = Instruction{code: 0x29, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_IMM, desc: "AND:IMM"};
  map[0x2A].* = Instruction{code: 0x2A, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_A, desc: "ROL:A"};
  map[0x2C].* = Instruction{code: 0x2C, opcode: OPCODE_BIT, handler: handle_instr_bit, addr_mode: ADDR_MODE_ABS, desc: "BIT:ABS"};
  map[0x2D].* = Instruction{code: 0x2D, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS, desc: "AND:ABS"};
  map[0x2E].* = Instruction{code: 0x2E, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ABS, desc: "ROL:ABS"};
  map[0x30].* = Instruction{code: 0x30, opcode: OPCODE_BMI, handler: handle_instr_bmi, addr_mode: ADDR_MODE_REL, desc: "BMI:REL"};
  map[0x31].* = Instruction{code: 0x31, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "AND:INDIRECT_Y"};
  map[0x35].* = Instruction{code: 0x35, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "AND:ZERO_PAGE_X"};
  map[0x36].* = Instruction{code: 0x36, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ROL:ZERO_PAGE_X"};
  map[0x38].* = Instruction{code: 0x38, opcode: OPCODE_SEC, handler: handle_instr_sec, addr_mode: ADDR_MODE_IMP, desc: "SEC:IMP"};
  map[0x39].* = Instruction{code: 0x39, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS_Y, desc: "AND:ABS_Y"};
  map[0x3D].* = Instruction{code: 0x3D, opcode: OPCODE_AND, handler: handle_instr_and, addr_mode: ADDR_MODE_ABS_X, desc: "AND:ABS_X"};
  map[0x3E].* = Instruction{code: 0x3E, opcode: OPCODE_ROL, handler: handle_instr_rol, addr_mode: ADDR_MODE_ABS_X, desc: "ROL:ABS_X"};
  map[0x40].* = Instruction{code: 0x40, opcode: OPCODE_RTI, handler: handle_instr_rti, addr_mode: ADDR_MODE_IMP, desc: "RTI:IMP"};
  map[0x41].* = Instruction{code: 0x41, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_X_INDIRECT, desc: "EOR:X_INDIRECT"};
  map[0x45].* = Instruction{code: 0x45, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "EOR:ZERO_PAGE"};
  map[0x46].* = Instruction{code: 0x46, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LSR:ZERO_PAGE"};
  map[0x48].* = Instruction{code: 0x48, opcode: OPCODE_PHA, handler: handle_instr_pha, addr_mode: ADDR_MODE_IMP, desc: "PHA:IMP"};
  map[0x49].* = Instruction{code: 0x49, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_IMM, desc: "EOR:IMM"};
  map[0x4A].* = Instruction{code: 0x4A, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_A, desc: "LSR:A"};
  map[0x4C].* = Instruction{code: 0x4C, opcode: OPCODE_JMP, handler: handle_instr_jmp, addr_mode: ADDR_MODE_ABS, desc: "JMP:ABS"};
  map[0x4D].* = Instruction{code: 0x4D, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS, desc: "EOR:ABS"};
  map[0x4E].* = Instruction{code: 0x4E, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ABS, desc: "LSR:ABS"};
  map[0x50].* = Instruction{code: 0x50, opcode: OPCODE_BVC, handler: handle_instr_bvc, addr_mode: ADDR_MODE_REL, desc: "BVC:REL"};
  map[0x51].* = Instruction{code: 0x51, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "EOR:INDIRECT_Y"};
  map[0x55].* = Instruction{code: 0x55, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "EOR:ZERO_PAGE_X"};
  map[0x56].* = Instruction{code: 0x56, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LSR:ZERO_PAGE_X"};
  map[0x58].* = Instruction{code: 0x58, opcode: OPCODE_CLI, handler: handle_instr_cli, addr_mode: ADDR_MODE_IMP, desc: "CLI:IMP"};
  map[0x59].* = Instruction{code: 0x59, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS_Y, desc: "EOR:ABS_Y"};
  map[0x5D].* = Instruction{code: 0x5D, opcode: OPCODE_EOR, handler: handle_instr_eor, addr_mode: ADDR_MODE_ABS_X, desc: "EOR:ABS_X"};
  map[0x5E].* = Instruction{code: 0x5E, opcode: OPCODE_LSR, handler: handle_instr_lsr, addr_mode: ADDR_MODE_ABS_X, desc: "LSR:ABS_X"};
  map[0x60].* = Instruction{code: 0x60, opcode: OPCODE_RTS, handler: handle_instr_rts, addr_mode: ADDR_MODE_IMP, desc: "RTS:IMP"};
  map[0x61].* = Instruction{code: 0x61, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_X_INDIRECT, desc: "ADC:X_INDIRECT"};
  map[0x65].* = Instruction{code: 0x65, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ADC:ZERO_PAGE"};
  map[0x66].* = Instruction{code: 0x66, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "ROR:ZERO_PAGE"};
  map[0x68].* = Instruction{code: 0x68, opcode: OPCODE_PLA, handler: handle_instr_pla, addr_mode: ADDR_MODE_IMP, desc: "PLA:IMP"};
  map[0x69].* = Instruction{code: 0x69, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_IMM, desc: "ADC:IMM"};
  map[0x6A].* = Instruction{code: 0x6A, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_A, desc: "ROR:A"};
  map[0x6C].* = Instruction{code: 0x6C, opcode: OPCODE_JMP, handler: handle_instr_jmp, addr_mode: ADDR_MODE_INDIRECT, desc: "JMP:INDIRECT"};
  map[0x6D].* = Instruction{code: 0x6D, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS, desc: "ADC:ABS"};
  map[0x6E].* = Instruction{code: 0x6E, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ABS, desc: "ROR:ABS"};
  map[0x70].* = Instruction{code: 0x70, opcode: OPCODE_BVS, handler: handle_instr_bvs, addr_mode: ADDR_MODE_REL, desc: "BVS:REL"};
  map[0x71].* = Instruction{code: 0x71, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "ADC:INDIRECT_Y"};
  map[0x75].* = Instruction{code: 0x75, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ADC:ZERO_PAGE_X"};
  map[0x76].* = Instruction{code: 0x76, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "ROR:ZERO_PAGE_X"};
  map[0x78].* = Instruction{code: 0x78, opcode: OPCODE_SEI, handler: handle_instr_sei, addr_mode: ADDR_MODE_IMP, desc: "SEI:IMP"};
  map[0x79].* = Instruction{code: 0x79, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS_Y, desc: "ADC:ABS_Y"};
  map[0x7D].* = Instruction{code: 0x7D, opcode: OPCODE_ADC, handler: handle_instr_adc, addr_mode: ADDR_MODE_ABS_X, desc: "ADC:ABS_X"};
  map[0x7E].* = Instruction{code: 0x7E, opcode: OPCODE_ROR, handler: handle_instr_ror, addr_mode: ADDR_MODE_ABS_X, desc: "ROR:ABS_X"};
  map[0x81].* = Instruction{code: 0x81, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_X_INDIRECT, desc: "STA:X_INDIRECT"};
  map[0x84].* = Instruction{code: 0x84, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STY:ZERO_PAGE"};
  map[0x85].* = Instruction{code: 0x85, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STA:ZERO_PAGE"};
  map[0x86].* = Instruction{code: 0x86, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "STX:ZERO_PAGE"};
  map[0x88].* = Instruction{code: 0x88, opcode: OPCODE_DEY, handler: handle_instr_dey, addr_mode: ADDR_MODE_IMP, desc: "DEY:IMP"};
  map[0x8A].* = Instruction{code: 0x8A, opcode: OPCODE_TXA, handler: handle_instr_txa, addr_mode: ADDR_MODE_IMP, desc: "TXA:IMP"};
  map[0x8C].* = Instruction{code: 0x8C, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ABS, desc: "STY:ABS"};
  map[0x8D].* = Instruction{code: 0x8D, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS, desc: "STA:ABS"};
  map[0x8E].* = Instruction{code: 0x8E, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ABS, desc: "STX:ABS"};
  map[0x90].* = Instruction{code: 0x90, opcode: OPCODE_BCC, handler: handle_instr_bcc, addr_mode: ADDR_MODE_REL, desc: "BCC:REL"};
  map[0x91].* = Instruction{code: 0x91, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "STA:INDIRECT_Y"};
  map[0x94].* = Instruction{code: 0x94, opcode: OPCODE_STY, handler: handle_instr_sty, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "STY:ZERO_PAGE_X"};
  map[0x95].* = Instruction{code: 0x95, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "STA:ZERO_PAGE_X"};
  map[0x96].* = Instruction{code: 0x96, opcode: OPCODE_STX, handler: handle_instr_stx, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "STX:ZERO_PAGE_Y"};
  map[0x98].* = Instruction{code: 0x98, opcode: OPCODE_TYA, handler: handle_instr_tya, addr_mode: ADDR_MODE_IMP, desc: "TYA:IMP"};
  map[0x99].* = Instruction{code: 0x99, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS_Y, desc: "STA:ABS_Y"};
  map[0x9A].* = Instruction{code: 0x9A, opcode: OPCODE_TXS, handler: handle_instr_txs, addr_mode: ADDR_MODE_IMP, desc: "TXS:IMP"};
  map[0x9D].* = Instruction{code: 0x9D, opcode: OPCODE_STA, handler: handle_instr_sta, addr_mode: ADDR_MODE_ABS_X, desc: "STA:ABS_X"};
  map[0xA0].* = Instruction{code: 0xA0, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_IMM, desc: "LDY:IMM"};
  map[0xA1].* = Instruction{code: 0xA1, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_X_INDIRECT, desc: "LDA:X_INDIRECT"};
  map[0xA2].* = Instruction{code: 0xA2, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_IMM, desc: "LDX:IMM"};
  map[0xA4].* = Instruction{code: 0xA4, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDY:ZERO_PAGE"};
  map[0xA5].* = Instruction{code: 0xA5, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDA:ZERO_PAGE"};
  map[0xA6].* = Instruction{code: 0xA6, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "LDX:ZERO_PAGE"};
  map[0xA8].* = Instruction{code: 0xA8, opcode: OPCODE_TAY, handler: handle_instr_tay, addr_mode: ADDR_MODE_IMP, desc: "TAY:IMP"};
  map[0xA9].* = Instruction{code: 0xA9, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_IMM, desc: "LDA:IMM"};
  map[0xAA].* = Instruction{code: 0xAA, opcode: OPCODE_TAX, handler: handle_instr_tax, addr_mode: ADDR_MODE_IMP, desc: "TAX:IMP"};
  map[0xAC].* = Instruction{code: 0xAC, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ABS, desc: "LDY:ABS"};
  map[0xAD].* = Instruction{code: 0xAD, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS, desc: "LDA:ABS"};
  map[0xAE].* = Instruction{code: 0xAE, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ABS, desc: "LDX:ABS"};
  map[0xB0].* = Instruction{code: 0xB0, opcode: OPCODE_BCS, handler: handle_instr_bcs, addr_mode: ADDR_MODE_REL, desc: "BCS:REL"};
  map[0xB1].* = Instruction{code: 0xB1, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "LDA:INDIRECT_Y"};
  map[0xB4].* = Instruction{code: 0xB4, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LDY:ZERO_PAGE_X"};
  map[0xB5].* = Instruction{code: 0xB5, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "LDA:ZERO_PAGE_X"};
  map[0xB6].* = Instruction{code: 0xB6, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ZERO_PAGE_Y, desc: "LDX:ZERO_PAGE_Y"};
  map[0xB8].* = Instruction{code: 0xB8, opcode: OPCODE_CLV, handler: handle_instr_clv, addr_mode: ADDR_MODE_IMP, desc: "CLV:IMP"};
  map[0xB9].* = Instruction{code: 0xB9, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS_Y, desc: "LDA:ABS_Y"};
  map[0xBA].* = Instruction{code: 0xBA, opcode: OPCODE_TSX, handler: handle_instr_tsx, addr_mode: ADDR_MODE_IMP, desc: "TSX:IMP"};
  map[0xBC].* = Instruction{code: 0xBC, opcode: OPCODE_LDY, handler: handle_instr_ldy, addr_mode: ADDR_MODE_ABS_X, desc: "LDY:ABS_X"};
  map[0xBD].* = Instruction{code: 0xBD, opcode: OPCODE_LDA, handler: handle_instr_lda, addr_mode: ADDR_MODE_ABS_X, desc: "LDA:ABS_X"};
  map[0xBE].* = Instruction{code: 0xBE, opcode: OPCODE_LDX, handler: handle_instr_ldx, addr_mode: ADDR_MODE_ABS_Y, desc: "LDX:ABS_Y"};
  map[0xC0].* = Instruction{code: 0xC0, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_IMM, desc: "CPY:IMM"};
  map[0xC1].* = Instruction{code: 0xC1, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_X_INDIRECT, desc: "CMP:X_INDIRECT"};
  map[0xC4].* = Instruction{code: 0xC4, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CPY:ZERO_PAGE"};
  map[0xC5].* = Instruction{code: 0xC5, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CMP:ZERO_PAGE"};
  map[0xC6].* = Instruction{code: 0xC6, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "DEC:ZERO_PAGE"};
  map[0xC8].* = Instruction{code: 0xC8, opcode: OPCODE_INY, handler: handle_instr_iny, addr_mode: ADDR_MODE_IMP, desc: "INY:IMP"};
  map[0xC9].* = Instruction{code: 0xC9, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_IMM, desc: "CMP:IMM"};
  map[0xCA].* = Instruction{code: 0xCA, opcode: OPCODE_DEX, handler: handle_instr_dex, addr_mode: ADDR_MODE_IMP, desc: "DEX:IMP"};
  map[0xCC].* = Instruction{code: 0xCC, opcode: OPCODE_CPY, handler: handle_instr_cpy, addr_mode: ADDR_MODE_ABS, desc: "CPY:ABS"};
  map[0xCD].* = Instruction{code: 0xCD, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS, desc: "CMP:ABS"};
  map[0xCE].* = Instruction{code: 0xCE, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ABS, desc: "DEC:ABS"};
  map[0xD0].* = Instruction{code: 0xD0, opcode: OPCODE_BNE, handler: handle_instr_bne, addr_mode: ADDR_MODE_REL, desc: "BNE:REL"};
  map[0xD1].* = Instruction{code: 0xD1, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "CMP:INDIRECT_Y"};
  map[0xD5].* = Instruction{code: 0xD5, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "CMP:ZERO_PAGE_X"};
  map[0xD6].* = Instruction{code: 0xD6, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "DEC:ZERO_PAGE_X"};
  map[0xD8].* = Instruction{code: 0xD8, opcode: OPCODE_CLD, handler: handle_instr_cld, addr_mode: ADDR_MODE_IMP, desc: "CLD:IMP"};
  map[0xD9].* = Instruction{code: 0xD9, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS_Y, desc: "CMP:ABS_Y"};
  map[0xDD].* = Instruction{code: 0xDD, opcode: OPCODE_CMP, handler: handle_instr_cmp, addr_mode: ADDR_MODE_ABS_X, desc: "CMP:ABS_X"};
  map[0xDE].* = Instruction{code: 0xDE, opcode: OPCODE_DEC, handler: handle_instr_dec, addr_mode: ADDR_MODE_ABS_X, desc: "DEC:ABS_X"};
  map[0xE0].* = Instruction{code: 0xE0, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_IMM, desc: "CPX:IMM"};
  map[0xE1].* = Instruction{code: 0xE1, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_X_INDIRECT, desc: "SBC:X_INDIRECT"};
  map[0xE4].* = Instruction{code: 0xE4, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "CPX:ZERO_PAGE"};
  map[0xE5].* = Instruction{code: 0xE5, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "SBC:ZERO_PAGE"};
  map[0xE6].* = Instruction{code: 0xE6, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ZERO_PAGE, desc: "INC:ZERO_PAGE"};
  map[0xE8].* = Instruction{code: 0xE8, opcode: OPCODE_INX, handler: handle_instr_inx, addr_mode: ADDR_MODE_IMP, desc: "INX:IMP"};
  map[0xE9].* = Instruction{code: 0xE9, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_IMM, desc: "SBC:IMM"};
  map[0xEA].* = Instruction{code: 0xEA, opcode: OPCODE_NOP, handler: handle_instr_nop, addr_mode: ADDR_MODE_IMP, desc: "NOP:IMP"};
  map[0xEC].* = Instruction{code: 0xEC, opcode: OPCODE_CPX, handler: handle_instr_cpx, addr_mode: ADDR_MODE_ABS, desc: "CPX:ABS"};
  map[0xED].* = Instruction{code: 0xED, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS, desc: "SBC:ABS"};
  map[0xEE].* = Instruction{code: 0xEE, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ABS, desc: "INC:ABS"};
  map[0xF0].* = Instruction{code: 0xF0, opcode: OPCODE_BEQ, handler: handle_instr_beq, addr_mode: ADDR_MODE_REL, desc: "BEQ:REL"};
  map[0xF1].* = Instruction{code: 0xF1, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_INDIRECT_Y, desc: "SBC:INDIRECT_Y"};
  map[0xF5].* = Instruction{code: 0xF5, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "SBC:ZERO_PAGE_X"};
  map[0xF6].* = Instruction{code: 0xF6, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ZERO_PAGE_X, desc: "INC:ZERO_PAGE_X"};
  map[0xF8].* = Instruction{code: 0xF8, opcode: OPCODE_SED, handler: handle_instr_sed, addr_mode: ADDR_MODE_IMP, desc: "SED:IMP"};
  map[0xF9].* = Instruction{code: 0xF9, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS_Y, desc: "SBC:ABS_Y"};
  map[0xFD].* = Instruction{code: 0xFD, opcode: OPCODE_SBC, handler: handle_instr_sbc, addr_mode: ADDR_MODE_ABS_X, desc: "SBC:ABS_X"};
  map[0xFE].* = Instruction{code: 0xFE, opcode: OPCODE_INC, handler: handle_instr_inc, addr_mode: ADDR_MODE_ABS_X, desc: "INC:ABS_X"};

  return map;
}

fn reset(cpu: *CPU) {
  cpu.reg.a.* = 0;
  cpu.reg.x.* = 0;
  cpu.reg.y.* = 0;
  cpu.reg.sp.* = 0xfd;
  cpu.reg.status.* = 0x00 | FLAG_MASK_INTERRUPT_DISABLE | FLAG_MASK_1;
  cpu.reg.pc.* = mem_read_u16(0xfffc);
}

fn mem_read_u16(addr: u16): u16 {
  let lo = bus::read(addr) as u16;
  let hi = bus::read(addr + 1) as u16;
  return hi << 8 | lo;
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
  bus::write(cpu.reg.sp.* as u16, (cpu.reg.pc.* >> 8) as u8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  bus::write(cpu.reg.sp.* as u16, (cpu.reg.pc.* & 0xff) as u8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_BREAK;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  bus::write(cpu.reg.sp.* as u16, cpu.reg.status.*);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  let addr_0: u16 = 0xfffa;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = hi << 8 | lo;
}

let debug: bool = false;
fn tick(cpu: *CPU) {
  let opcode = bus::read(cpu.reg.pc.*);

  if debug {
    fmt::print_str("TICK pc=");
    fmt::print_u16(cpu.reg.pc.*);
    fmt::print_str(" opcode=");
    fmt::print_u8(opcode);
    fmt::print_str(" ");
  }

  cpu.last_opcode.* = opcode;
  cpu.last_pc.* = cpu.reg.pc.*;
  cpu.reg.pc.* = cpu.reg.pc.* + 1;

  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;

  let ins = instruction_map[opcode];
  let addr_mode = ins.addr_mode.*;
  cpu.last_ins.* = ins.desc.*;

  let data: u8;
  let addr: u16;

  if addr_mode == ADDR_MODE_IMP {
    data = cpu.reg.a.*;
  } else if addr_mode == ADDR_MODE_A {
    data = cpu.reg.a.*;
  } else if addr_mode == ADDR_MODE_IMM {
    addr = cpu.reg.pc.*;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ZERO_PAGE {
    addr = bus::read(cpu.reg.pc.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ZERO_PAGE_X {
    addr = (bus::read(cpu.reg.pc.*) + cpu.reg.x.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ZERO_PAGE_Y {
    addr = (bus::read(cpu.reg.pc.*) + cpu.reg.y.*) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_REL {
    addr = ((bus::read(cpu.reg.pc.*) as i8) as i16 + cpu.reg.pc.* as i16 + 1) as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ABS {
    addr = mem_read_u16(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ABS_X {
    addr = mem_read_u16(cpu.reg.pc.*) + cpu.reg.x.* as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_ABS_Y {
    addr = mem_read_u16(cpu.reg.pc.*) + cpu.reg.y.* as u16;
    cpu.reg.pc.* = cpu.reg.pc.* + 2;
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_INDIRECT {
    wasm::trap();
  } else if addr_mode == ADDR_MODE_X_INDIRECT {
    let ptr = bus::read(cpu.reg.pc.*) + cpu.reg.x.*;
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    let lo = bus::read(ptr as u16);
    let hi = bus::read((ptr + 1) as u16);
    addr = (hi as u16 << 8) | (lo as u16);
    data = bus::read(addr);
  } else if addr_mode == ADDR_MODE_INDIRECT_Y {
    let ptr = bus::read(cpu.reg.pc.*);
    cpu.reg.pc.* = cpu.reg.pc.* + 1;
    let lo = bus::read(ptr as u16);
    let hi = bus::read((ptr + 1) as u16);
    let base = (hi as u16 << 8) | (lo as u16);
    addr = base + cpu.reg.y.* as u16;
    data = bus::read(addr);
  }

  cpu.last_data.* = data;
  cpu.last_addr.* = addr;

  if debug {
    fmt::print_str(ins.desc.*);
    fmt::print_str(" addr=");
    fmt::print_u16(addr);
    fmt::print_str(" data=");
    fmt::print_u8(data);
    fmt::print_str("\n");
  }

  let handler = ins.handler.*;
  handler(cpu, addr_mode, addr, data);

  if debug {
    fmt::print_str("A=");
    fmt::print_u8(cpu.reg.a.*);
    fmt::print_str(",X=");
    fmt::print_u8(cpu.reg.x.*);
    fmt::print_str(",Y=");
    fmt::print_u8(cpu.reg.y.*);
    fmt::print_str(",status=");
    fmt::print_u8(cpu.reg.status.*);
    fmt::print_str(" ");
    if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 { fmt::print_str("C"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_ZERO) != 0 { fmt::print_str("Z"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_INTERRUPT_DISABLE) != 0 { fmt::print_str("I"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_DECIMAL) != 0 { fmt::print_str("D"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_BREAK) != 0 { fmt::print_str("B"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_1) != 0 { fmt::print_str("1"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) != 0 { fmt::print_str("V"); } else { fmt::print_str("-"); }
    if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) != 0 { fmt::print_str("N"); } else { fmt::print_str("-"); }
    fmt::print_str("\n---------------------------------------------------------\n");
  }
}

fn handle_instr_adc(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  add_to_reg_a(cpu, data);
}

fn add_to_reg_a(cpu: *CPU, data: u8) {
  data = data & 0xff;

  let tmp = cpu.reg.a.* as u16 + data as u16;
  if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 {
    tmp = tmp + 1;
  }

  if tmp > 0xff {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let result = (tmp as u8) & 0xff;
  if ((data ^ result) & (result ^ cpu.reg.a.*) & 0x80) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_OVERFLOW;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_OVERFLOW;
  }

  set_reg_a(cpu, result);
}

fn handle_instr_and(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  set_reg_a(cpu, cpu.reg.a.* & data);
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

fn handle_instr_asl(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (data & 0b1000_000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let tmp = data << 1;

  if mode == ADDR_MODE_A {
    cpu.reg.a.* = tmp as u8;
  } else {
    bus::write(addr, tmp as u8);
  }

  update_zero_and_neg_flag(cpu, tmp);
}

fn handle_instr_bcc(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_CARRY) == 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_bcs(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_CARRY) != 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_beq(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_ZERO) != 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_bit(cpu: *CPU, mode: u8, addr: u16, data: u8) {
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
}

fn handle_instr_bmi(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) != 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_bne(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_ZERO) == 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_bpl(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_NEGATIVE) == 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_brk(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  // TODO: maybe should turn off the emulation?
  wasm::trap();
}

fn handle_instr_bvc(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) == 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_bvs(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (cpu.reg.status.* & FLAG_MASK_OVERFLOW) != 0 {
    cpu.reg.pc.* = addr;
  }
}

fn handle_instr_clc(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
}

fn handle_instr_cld(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_DECIMAL;
}

fn handle_instr_cli(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_INTERRUPT_DISABLE;
}

fn handle_instr_clv(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_OVERFLOW;
}

fn handle_instr_cmp(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let tmp = (cpu.reg.a.* - data) & 0xff;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.a.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
}

fn handle_instr_cpx(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let tmp = cpu.reg.x.* - data;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.x.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
}

fn handle_instr_cpy(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let tmp = cpu.reg.y.* - data;
  update_zero_and_neg_flag(cpu, tmp);
  if data <= cpu.reg.y.* {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
}

fn handle_instr_dec(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if data == 0 {
    data = 0xff;
  } else {
    data = data - 1;
  }
  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
}

fn handle_instr_dex(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if cpu.reg.x.* == 0 {
    cpu.reg.x.* = 0xff;
  } else {
    cpu.reg.x.* = cpu.reg.x.* - 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
}

fn handle_instr_dey(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if cpu.reg.y.* == 0 {
    cpu.reg.y.* = 0xff;
  } else {
    cpu.reg.y.* = cpu.reg.y.* - 1;
  }
  cpu.reg.y.* = cpu.reg.y.* - 1;
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
}

fn handle_instr_eor(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  set_reg_a(cpu, cpu.reg.a.* ^ data);
}

fn handle_instr_inc(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if data == 0xff {
    data = 0;
  } else {
    data = data + 1;
  }
  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
}

fn handle_instr_inx(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if cpu.reg.x.* == 0xff {
    cpu.reg.x.* = 0;
  } else {
    cpu.reg.x.* = cpu.reg.x.* + 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
}

fn handle_instr_iny(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if cpu.reg.y.* == 0xff {
    cpu.reg.y.* = 0;
  } else {
    cpu.reg.y.* = cpu.reg.y.* + 1;
  }
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
}

fn handle_instr_jmp(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.pc.* = addr;
}

fn handle_instr_jsr(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  stack_push_u16(cpu, cpu.reg.pc.* - 1);
  cpu.reg.pc.* = addr;
}

fn stack_push_u16(cpu: *CPU, data: u16) {
  let hi = (data >> 8) as u8;
  let lo = data as u8;
  stack_push(cpu, hi);
  stack_push(cpu, lo);
}

fn stack_push(cpu: *CPU, data: u8) {
  bus::write(cpu.reg.sp.* as u16, data);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;
}

fn handle_instr_lda(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  set_reg_a(cpu, data);
}

fn handle_instr_ldx(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.x.* = data;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
}

fn handle_instr_ldy(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.y.* = data;
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
}

fn handle_instr_lsr(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }

  let data = (data & 0xff) >> 1;
  if mode == ADDR_MODE_A {
    cpu.reg.a.* = data;
  } else {
    bus::write(addr, data);
  }

  update_zero_and_neg_flag(cpu, data);
}

fn handle_instr_nop(cpu: *CPU, mode: u8, addr: u16, data: u8) {
}

fn handle_instr_ora(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  set_reg_a(cpu, cpu.reg.a.* | data);
}

fn handle_instr_pha(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  stack_push(cpu, cpu.reg.a.*);
}

fn handle_instr_php(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  stack_push(cpu, cpu.reg.status.* | FLAG_MASK_BREAK | FLAG_MASK_1);
}

fn handle_instr_pla(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  set_reg_a(cpu, stack_pop(cpu));
}

fn stack_pop(cpu: *CPU): u8 {
  cpu.reg.sp.* = cpu.reg.sp.* + 1;
  return bus::read(cpu.reg.sp.* as u16);
}

fn stack_pop_u16(cpu: *CPU): u16 {
  let lo = stack_pop(cpu);
  let hi = stack_pop(cpu);
  return (hi as u16 << 8) | (lo as u16);
}

fn handle_instr_plp(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let flag = stack_pop(cpu);
  cpu.reg.status.* = (flag & ~FLAG_MASK_BREAK) | FLAG_MASK_1;
}

fn handle_instr_rol(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 0b1000_000) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  data = data << 1;

  if old_carry {
    data = data | 1;
  }

  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
}

fn handle_instr_ror(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let old_carry = (cpu.reg.status.* & FLAG_MASK_CARRY) != 0;

  if (data & 1) != 0 {
    cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
  } else {
    cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_CARRY;
  }
  data = data >> 1;

  if old_carry {
    data = data | 0b1000_000;
  }

  bus::write(addr, data);
  update_zero_and_neg_flag(cpu, data);
}

fn handle_instr_rti(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  let flag = stack_pop(cpu);
  cpu.reg.status.* = (flag & ~FLAG_MASK_BREAK) | FLAG_MASK_1;
  cpu.reg.pc.* = stack_pop_u16(cpu);
}

fn handle_instr_rts(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.pc.* = stack_pop_u16(cpu) + 1;
}

fn handle_instr_sbc(cpu: *CPU, mode: u8, addr: u16, data: u8) { 
  add_to_reg_a(cpu, (-(data as i8)-1) as u8);
}

fn handle_instr_sec(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_CARRY;
}

fn handle_instr_sed(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_DECIMAL;
}

fn handle_instr_sei(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
}

fn handle_instr_sta(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  bus::write(addr, cpu.reg.a.*);
}

fn handle_instr_stx(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  bus::write(addr, cpu.reg.x.*);
}

fn handle_instr_sty(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  bus::write(addr, cpu.reg.y.*);
}

fn handle_instr_tax(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.x.* = cpu.reg.a.*;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
}

fn handle_instr_tay(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.y.* = cpu.reg.a.*;
  update_zero_and_neg_flag(cpu, cpu.reg.y.*);
}

fn handle_instr_tsx(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.x.* = cpu.reg.sp.*;
  update_zero_and_neg_flag(cpu, cpu.reg.x.*);
}

fn handle_instr_txa(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.a.* = cpu.reg.x.*;
  update_zero_and_neg_flag(cpu, cpu.reg.a.*);
}

fn handle_instr_txs(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.sp.* = cpu.reg.x.*;
}

fn handle_instr_tya(cpu: *CPU, mode: u8, addr: u16, data: u8) {
  cpu.reg.a.* = cpu.reg.y.*;
  update_zero_and_neg_flag(cpu, cpu.reg.a.*);
}
