import bus "bus";
import wasm "wasm";

struct CPU {
  reg: Register,
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
let FLAG_MASK_B: u8                 = 1 << 4;
let FLAG_MASK_1: u8                 = 1 << 5;
let FLAG_MASK_OVERFLOW: u8          = 1 << 6;
let FLAG_MASK_NEGATIVE: u8          = 1 << 7;

let ADDR_MOD_A: u8 = 0;
let ADDR_MOD_ABS: u8 = 1;
let ADDR_MOD_ABS_X: u8 = 2;
let ADDR_MOD_ABS_Y: u8 = 3;
let ADDR_MOD_IMM: u8 = 4;
let ADDR_MOD_IMP: u8 = 5;
let ADDR_MOD_INDIRECT: u8 = 6;
let ADDR_MOD_X_INDIRECT: u8 = 7;
let ADDR_MOD_INDIRECT_Y: u8 = 8;
let ADDR_MOD_REL: u8 = 9;
let ADDR_MOD_ZERO_PAGE: u8 = 10;
let ADDR_MOD_ZERO_PAGE_X: u8 = 11;
let ADDR_MOD_ZERO_PAGE_Y: u8 = 12;

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
  handler:   fn( *CPU, u8, u8),
}

let instruction_map: [*]Instruction = init_instruction_map();

fn init_instruction_map(): [*]Instruction {
  let map = wasm::memory_grow(1) as [*]Instruction;
  map[0].* = Instruction{code: 0, opcode: OPCODE_BRK, addr_mode: ADDR_MOD_IMP};

  map[0x00].* = Instruction{code: 0x00, opcode: OPCODE_BRK, handler: handle_ins_brk, addr_mode: ADDR_MOD_IMP};
  map[0x01].* = Instruction{code: 0x01, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0x05].* = Instruction{code: 0x05, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x06].* = Instruction{code: 0x06, opcode: OPCODE_ASL, handler: handle_ins_asl, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x08].* = Instruction{code: 0x08, opcode: OPCODE_PHP, handler: handle_ins_php, addr_mode: ADDR_MOD_IMP};
  map[0x09].* = Instruction{code: 0x09, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_IMM};
  map[0x0A].* = Instruction{code: 0x0A, opcode: OPCODE_ASL, handler: handle_ins_asl, addr_mode: ADDR_MOD_A};
  map[0x0D].* = Instruction{code: 0x0D, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_ABS};
  map[0x0E].* = Instruction{code: 0x0E, opcode: OPCODE_ASL, handler: handle_ins_asl, addr_mode: ADDR_MOD_ABS};
  map[0x10].* = Instruction{code: 0x10, opcode: OPCODE_BPL, handler: handle_ins_bpl, addr_mode: ADDR_MOD_REL};
  map[0x11].* = Instruction{code: 0x11, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0x15].* = Instruction{code: 0x15, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x16].* = Instruction{code: 0x16, opcode: OPCODE_ASL, handler: handle_ins_asl, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x18].* = Instruction{code: 0x18, opcode: OPCODE_CLC, handler: handle_ins_clc, addr_mode: ADDR_MOD_IMP};
  map[0x19].* = Instruction{code: 0x19, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_ABS_Y};
  map[0x1D].* = Instruction{code: 0x1D, opcode: OPCODE_ORA, handler: handle_ins_ora, addr_mode: ADDR_MOD_ABS_X};
  map[0x1E].* = Instruction{code: 0x1E, opcode: OPCODE_ASL, handler: handle_ins_asl, addr_mode: ADDR_MOD_ABS_X};
  map[0x20].* = Instruction{code: 0x20, opcode: OPCODE_JSR, handler: handle_ins_jsr, addr_mode: ADDR_MOD_ABS};
  map[0x21].* = Instruction{code: 0x21, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0x24].* = Instruction{code: 0x24, opcode: OPCODE_BIT, handler: handle_ins_bit, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x25].* = Instruction{code: 0x25, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x26].* = Instruction{code: 0x26, opcode: OPCODE_ROL, handler: handle_ins_rol, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x28].* = Instruction{code: 0x28, opcode: OPCODE_PLP, handler: handle_ins_plp, addr_mode: ADDR_MOD_IMP};
  map[0x29].* = Instruction{code: 0x29, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_IMM};
  map[0x2A].* = Instruction{code: 0x2A, opcode: OPCODE_ROL, handler: handle_ins_rol, addr_mode: ADDR_MOD_A};
  map[0x2C].* = Instruction{code: 0x2C, opcode: OPCODE_BIT, handler: handle_ins_bit, addr_mode: ADDR_MOD_ABS};
  map[0x2D].* = Instruction{code: 0x2D, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_ABS};
  map[0x2E].* = Instruction{code: 0x2E, opcode: OPCODE_ROL, handler: handle_ins_rol, addr_mode: ADDR_MOD_ABS};
  map[0x30].* = Instruction{code: 0x30, opcode: OPCODE_BMI, handler: handle_ins_bmi, addr_mode: ADDR_MOD_REL};
  map[0x31].* = Instruction{code: 0x31, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0x35].* = Instruction{code: 0x35, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x36].* = Instruction{code: 0x36, opcode: OPCODE_ROL, handler: handle_ins_rol, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x38].* = Instruction{code: 0x38, opcode: OPCODE_SEC, handler: handle_ins_sec, addr_mode: ADDR_MOD_IMP};
  map[0x39].* = Instruction{code: 0x39, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_ABS_Y};
  map[0x3D].* = Instruction{code: 0x3D, opcode: OPCODE_AND, handler: handle_ins_and, addr_mode: ADDR_MOD_ABS_X};
  map[0x3E].* = Instruction{code: 0x3E, opcode: OPCODE_ROL, handler: handle_ins_rol, addr_mode: ADDR_MOD_ABS_X};
  map[0x40].* = Instruction{code: 0x40, opcode: OPCODE_RTI, handler: handle_ins_rti, addr_mode: ADDR_MOD_IMP};
  map[0x41].* = Instruction{code: 0x41, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0x45].* = Instruction{code: 0x45, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x46].* = Instruction{code: 0x46, opcode: OPCODE_LSR, handler: handle_ins_lsr, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x48].* = Instruction{code: 0x48, opcode: OPCODE_PHA, handler: handle_ins_pha, addr_mode: ADDR_MOD_IMP};
  map[0x49].* = Instruction{code: 0x49, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_IMM};
  map[0x4A].* = Instruction{code: 0x4A, opcode: OPCODE_LSR, handler: handle_ins_lsr, addr_mode: ADDR_MOD_A};
  map[0x4C].* = Instruction{code: 0x4C, opcode: OPCODE_JMP, handler: handle_ins_jmp, addr_mode: ADDR_MOD_ABS};
  map[0x4D].* = Instruction{code: 0x4D, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_ABS};
  map[0x4E].* = Instruction{code: 0x4E, opcode: OPCODE_LSR, handler: handle_ins_lsr, addr_mode: ADDR_MOD_ABS};
  map[0x50].* = Instruction{code: 0x50, opcode: OPCODE_BVC, handler: handle_ins_bvc, addr_mode: ADDR_MOD_REL};
  map[0x51].* = Instruction{code: 0x51, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0x55].* = Instruction{code: 0x55, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x56].* = Instruction{code: 0x56, opcode: OPCODE_LSR, handler: handle_ins_lsr, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x58].* = Instruction{code: 0x58, opcode: OPCODE_CLI, handler: handle_ins_cli, addr_mode: ADDR_MOD_IMP};
  map[0x59].* = Instruction{code: 0x59, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_ABS_Y};
  map[0x5D].* = Instruction{code: 0x5D, opcode: OPCODE_EOR, handler: handle_ins_eor, addr_mode: ADDR_MOD_ABS_X};
  map[0x5E].* = Instruction{code: 0x5E, opcode: OPCODE_LSR, handler: handle_ins_lsr, addr_mode: ADDR_MOD_ABS_X};
  map[0x60].* = Instruction{code: 0x60, opcode: OPCODE_RTS, handler: handle_ins_rts, addr_mode: ADDR_MOD_IMP};
  map[0x61].* = Instruction{code: 0x61, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0x65].* = Instruction{code: 0x65, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x66].* = Instruction{code: 0x66, opcode: OPCODE_ROR, handler: handle_ins_ror, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x68].* = Instruction{code: 0x68, opcode: OPCODE_PLA, handler: handle_ins_pla, addr_mode: ADDR_MOD_IMP};
  map[0x69].* = Instruction{code: 0x69, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_IMM};
  map[0x6A].* = Instruction{code: 0x6A, opcode: OPCODE_ROR, handler: handle_ins_ror, addr_mode: ADDR_MOD_A};
  map[0x6C].* = Instruction{code: 0x6C, opcode: OPCODE_JMP, handler: handle_ins_jmp, addr_mode: ADDR_MOD_INDIRECT};
  map[0x6D].* = Instruction{code: 0x6D, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_ABS};
  map[0x6E].* = Instruction{code: 0x6E, opcode: OPCODE_ROR, handler: handle_ins_ror, addr_mode: ADDR_MOD_ABS};
  map[0x70].* = Instruction{code: 0x70, opcode: OPCODE_BVS, handler: handle_ins_bvs, addr_mode: ADDR_MOD_REL};
  map[0x71].* = Instruction{code: 0x71, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0x75].* = Instruction{code: 0x75, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x76].* = Instruction{code: 0x76, opcode: OPCODE_ROR, handler: handle_ins_ror, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x78].* = Instruction{code: 0x78, opcode: OPCODE_SEI, handler: handle_ins_sei, addr_mode: ADDR_MOD_IMP};
  map[0x79].* = Instruction{code: 0x79, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_ABS_Y};
  map[0x7D].* = Instruction{code: 0x7D, opcode: OPCODE_ADC, handler: handle_ins_adc, addr_mode: ADDR_MOD_ABS_X};
  map[0x7E].* = Instruction{code: 0x7E, opcode: OPCODE_ROR, handler: handle_ins_ror, addr_mode: ADDR_MOD_ABS_X};
  map[0x81].* = Instruction{code: 0x81, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0x84].* = Instruction{code: 0x84, opcode: OPCODE_STY, handler: handle_ins_sty, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x85].* = Instruction{code: 0x85, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x86].* = Instruction{code: 0x86, opcode: OPCODE_STX, handler: handle_ins_stx, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0x88].* = Instruction{code: 0x88, opcode: OPCODE_DEY, handler: handle_ins_dey, addr_mode: ADDR_MOD_IMP};
  map[0x8A].* = Instruction{code: 0x8A, opcode: OPCODE_TXA, handler: handle_ins_txa, addr_mode: ADDR_MOD_IMP};
  map[0x8C].* = Instruction{code: 0x8C, opcode: OPCODE_STY, handler: handle_ins_sty, addr_mode: ADDR_MOD_ABS};
  map[0x8D].* = Instruction{code: 0x8D, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_ABS};
  map[0x8E].* = Instruction{code: 0x8E, opcode: OPCODE_STX, handler: handle_ins_stx, addr_mode: ADDR_MOD_ABS};
  map[0x90].* = Instruction{code: 0x90, opcode: OPCODE_BCC, handler: handle_ins_bcc, addr_mode: ADDR_MOD_REL};
  map[0x91].* = Instruction{code: 0x91, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0x94].* = Instruction{code: 0x94, opcode: OPCODE_STY, handler: handle_ins_sty, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x95].* = Instruction{code: 0x95, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0x96].* = Instruction{code: 0x96, opcode: OPCODE_STX, handler: handle_ins_stx, addr_mode: ADDR_MOD_ZERO_PAGE_Y};
  map[0x98].* = Instruction{code: 0x98, opcode: OPCODE_TYA, handler: handle_ins_tya, addr_mode: ADDR_MOD_IMP};
  map[0x99].* = Instruction{code: 0x99, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_ABS_Y};
  map[0x9A].* = Instruction{code: 0x9A, opcode: OPCODE_TXS, handler: handle_ins_txs, addr_mode: ADDR_MOD_IMP};
  map[0x9D].* = Instruction{code: 0x9D, opcode: OPCODE_STA, handler: handle_ins_sta, addr_mode: ADDR_MOD_ABS_X};
  map[0xA0].* = Instruction{code: 0xA0, opcode: OPCODE_LDY, handler: handle_ins_ldy, addr_mode: ADDR_MOD_IMM};
  map[0xA1].* = Instruction{code: 0xA1, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0xA2].* = Instruction{code: 0xA2, opcode: OPCODE_LDX, handler: handle_ins_ldx, addr_mode: ADDR_MOD_IMM};
  map[0xA4].* = Instruction{code: 0xA4, opcode: OPCODE_LDY, handler: handle_ins_ldy, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xA5].* = Instruction{code: 0xA5, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xA6].* = Instruction{code: 0xA6, opcode: OPCODE_LDX, handler: handle_ins_ldx, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xA8].* = Instruction{code: 0xA8, opcode: OPCODE_TAY, handler: handle_ins_tay, addr_mode: ADDR_MOD_IMP};
  map[0xA9].* = Instruction{code: 0xA9, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_IMM};
  map[0xAA].* = Instruction{code: 0xAA, opcode: OPCODE_TAX, handler: handle_ins_tax, addr_mode: ADDR_MOD_IMP};
  map[0xAC].* = Instruction{code: 0xAC, opcode: OPCODE_LDY, handler: handle_ins_ldy, addr_mode: ADDR_MOD_ABS};
  map[0xAD].* = Instruction{code: 0xAD, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_ABS};
  map[0xAE].* = Instruction{code: 0xAE, opcode: OPCODE_LDX, handler: handle_ins_ldx, addr_mode: ADDR_MOD_ABS};
  map[0xB0].* = Instruction{code: 0xB0, opcode: OPCODE_BCS, handler: handle_ins_bcs, addr_mode: ADDR_MOD_REL};
  map[0xB1].* = Instruction{code: 0xB1, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0xB4].* = Instruction{code: 0xB4, opcode: OPCODE_LDY, handler: handle_ins_ldy, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xB5].* = Instruction{code: 0xB5, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xB6].* = Instruction{code: 0xB6, opcode: OPCODE_LDX, handler: handle_ins_ldx, addr_mode: ADDR_MOD_ZERO_PAGE_Y};
  map[0xB8].* = Instruction{code: 0xB8, opcode: OPCODE_CLV, handler: handle_ins_clv, addr_mode: ADDR_MOD_IMP};
  map[0xB9].* = Instruction{code: 0xB9, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_ABS_Y};
  map[0xBA].* = Instruction{code: 0xBA, opcode: OPCODE_TSX, handler: handle_ins_tsx, addr_mode: ADDR_MOD_IMP};
  map[0xBC].* = Instruction{code: 0xBC, opcode: OPCODE_LDY, handler: handle_ins_ldy, addr_mode: ADDR_MOD_ABS_X};
  map[0xBD].* = Instruction{code: 0xBD, opcode: OPCODE_LDA, handler: handle_ins_lda, addr_mode: ADDR_MOD_ABS_X};
  map[0xBE].* = Instruction{code: 0xBE, opcode: OPCODE_LDX, handler: handle_ins_ldx, addr_mode: ADDR_MOD_ABS_Y};
  map[0xC0].* = Instruction{code: 0xC0, opcode: OPCODE_CPY, handler: handle_ins_cpy, addr_mode: ADDR_MOD_IMM};
  map[0xC1].* = Instruction{code: 0xC1, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0xC4].* = Instruction{code: 0xC4, opcode: OPCODE_CPY, handler: handle_ins_cpy, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xC5].* = Instruction{code: 0xC5, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xC6].* = Instruction{code: 0xC6, opcode: OPCODE_DEC, handler: handle_ins_dec, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xC8].* = Instruction{code: 0xC8, opcode: OPCODE_INY, handler: handle_ins_iny, addr_mode: ADDR_MOD_IMP};
  map[0xC9].* = Instruction{code: 0xC9, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_IMM};
  map[0xCA].* = Instruction{code: 0xCA, opcode: OPCODE_DEX, handler: handle_ins_dex, addr_mode: ADDR_MOD_IMP};
  map[0xCC].* = Instruction{code: 0xCC, opcode: OPCODE_CPY, handler: handle_ins_cpy, addr_mode: ADDR_MOD_ABS};
  map[0xCD].* = Instruction{code: 0xCD, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_ABS};
  map[0xCE].* = Instruction{code: 0xCE, opcode: OPCODE_DEC, handler: handle_ins_dec, addr_mode: ADDR_MOD_ABS};
  map[0xD0].* = Instruction{code: 0xD0, opcode: OPCODE_BNE, handler: handle_ins_bne, addr_mode: ADDR_MOD_REL};
  map[0xD1].* = Instruction{code: 0xD1, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0xD5].* = Instruction{code: 0xD5, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xD6].* = Instruction{code: 0xD6, opcode: OPCODE_DEC, handler: handle_ins_dec, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xD8].* = Instruction{code: 0xD8, opcode: OPCODE_CLD, handler: handle_ins_cld, addr_mode: ADDR_MOD_IMP};
  map[0xD9].* = Instruction{code: 0xD9, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_ABS_Y};
  map[0xDD].* = Instruction{code: 0xDD, opcode: OPCODE_CMP, handler: handle_ins_cmp, addr_mode: ADDR_MOD_ABS_X};
  map[0xDE].* = Instruction{code: 0xDE, opcode: OPCODE_DEC, handler: handle_ins_dec, addr_mode: ADDR_MOD_ABS_X};
  map[0xE0].* = Instruction{code: 0xE0, opcode: OPCODE_CPX, handler: handle_ins_cpx, addr_mode: ADDR_MOD_IMM};
  map[0xE1].* = Instruction{code: 0xE1, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_X_INDIRECT};
  map[0xE4].* = Instruction{code: 0xE4, opcode: OPCODE_CPX, handler: handle_ins_cpx, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xE5].* = Instruction{code: 0xE5, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xE6].* = Instruction{code: 0xE6, opcode: OPCODE_INC, handler: handle_ins_inc, addr_mode: ADDR_MOD_ZERO_PAGE};
  map[0xE8].* = Instruction{code: 0xE8, opcode: OPCODE_INX, handler: handle_ins_inx, addr_mode: ADDR_MOD_IMP};
  map[0xE9].* = Instruction{code: 0xE9, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_IMM};
  map[0xEA].* = Instruction{code: 0xEA, opcode: OPCODE_NOP, handler: handle_ins_nop, addr_mode: ADDR_MOD_IMP};
  map[0xEC].* = Instruction{code: 0xEC, opcode: OPCODE_CPX, handler: handle_ins_cpx, addr_mode: ADDR_MOD_ABS};
  map[0xED].* = Instruction{code: 0xED, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_ABS};
  map[0xEE].* = Instruction{code: 0xEE, opcode: OPCODE_INC, handler: handle_ins_inc, addr_mode: ADDR_MOD_ABS};
  map[0xF0].* = Instruction{code: 0xF0, opcode: OPCODE_BEQ, handler: handle_ins_beq, addr_mode: ADDR_MOD_REL};
  map[0xF1].* = Instruction{code: 0xF1, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_INDIRECT_Y};
  map[0xF5].* = Instruction{code: 0xF5, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xF6].* = Instruction{code: 0xF6, opcode: OPCODE_INC, handler: handle_ins_inc, addr_mode: ADDR_MOD_ZERO_PAGE_X};
  map[0xF8].* = Instruction{code: 0xF8, opcode: OPCODE_SED, handler: handle_ins_sed, addr_mode: ADDR_MOD_IMP};
  map[0xF9].* = Instruction{code: 0xF9, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_ABS_Y};
  map[0xFD].* = Instruction{code: 0xFD, opcode: OPCODE_SBC, handler: handle_ins_sbc, addr_mode: ADDR_MOD_ABS_X};
  map[0xFE].* = Instruction{code: 0xFE, opcode: OPCODE_INC, handler: handle_ins_inc, addr_mode: ADDR_MOD_ABS_X};

  return map;
}

// https://www.nesdev.org/wiki/CPU_power_up_state
fn reset(cpu: *CPU) {
  cpu.reg.a.* = 0;
  cpu.reg.x.* = 0;
  cpu.reg.y.* = 0;
  cpu.reg.sp.* = 0xfd;
  cpu.reg.status.* = 0x00 | FLAG_MASK_ZERO | FLAG_MASK_INTERRUPT_DISABLE | FLAG_MASK_B | FLAG_MASK_1;

  let addr_0 = 0xfffc;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = hi << 8 | lo;
}

fn interrupt(cpu: *CPU) {
  if (cpu.reg.status.* & FLAG_MASK_INTERRUPT_DISABLE) == 0 {
    return;
  }

  bus::write(cpu.reg.sp.*, cpu.reg.pc.* >> 8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  bus::write(cpu.reg.sp.*, cpu.reg.pc.* & 0xff);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_B;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  bus::write(cpu.reg.sp.*, cpu.reg.status.*);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  let addr_0 = 0xfffe;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = hi << 8 | lo;
}

fn non_maskable_interrupt(cpu: *CPU) {
  bus::write(cpu.reg.sp.*, cpu.reg.pc.* >> 8);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  bus::write(cpu.reg.sp.*, cpu.reg.pc.* & 0xff);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  cpu.reg.status.* = cpu.reg.status.* & ~FLAG_MASK_B;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_1;
  cpu.reg.status.* = cpu.reg.status.* | FLAG_MASK_INTERRUPT_DISABLE;
  bus::write(cpu.reg.sp.*, cpu.reg.status.*);
  cpu.reg.sp.* = cpu.reg.sp.* - 1;

  let addr_0 = 0xfffa;
  let lo = bus::read(addr_0) as u16;
  let hi = bus::read(addr_0 + 1) as u16;
  cpu.reg.pc.* = hi << 8 | lo;
}

fn tick(cpu: *CPU) {

}

fn handle_ins_adc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_and(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_asl(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bcc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bcs(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_beq(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bit(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bmi(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bne(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bpl(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_brk(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bvc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_bvs(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_clc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_cld(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_cli(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_clv(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_cmp(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_cpx(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_cpy(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_dec(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_dex(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_dey(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_eor(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_inc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_inx(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_iny(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_jmp(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_jsr(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_lda(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_ldx(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_ldy(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_lsr(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_nop(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_ora(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_pha(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_php(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_pla(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_plp(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_rol(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_ror(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_rti(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_rts(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sbc(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sec(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sed(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sei(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sta(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_stx(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_sty(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_tax(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_tay(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_tsx(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_txa(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_txs(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
fn handle_ins_tya(cpu: *CPU, data1: u8, data2: u8) { wasm::trap(); }
