// ============================================================================
// File: defs.v
// Description: Global architectural definitions, constants, and opcodes
//              for the Scalar RV64IM Out-of-Order Processor.
// Standard Verilog-2001
// ============================================================================

`ifndef __DEFS_V__
`define __DEFS_V__

`timescale 1ns/100ps

// ----------------------------------------------------------------------------
// Architectural Constants
// ----------------------------------------------------------------------------
`define XLEN             64   // 64-bit Data and Address width
`define ILEN             32   // 32-bit Instruction width
`define NUM_ARCH_REGS    32   // x0 - x31
`define AR_WIDTH         5    // 5 bits to address 32 architectural registers

// Physical Register File (PRF) Constants
`define NUM_PHYS_REGS    64   // 32 architectural + 32 speculative in-flight
`define PR_WIDTH         6    // 6 bits to address 64 physical registers
`define ZERO_PR          6'd0 // p0 is hardwired to 64'd0

// Reorder Buffer (ROB) Constants
`define ROB_ENTRIES      32   // Maximum 32 instructions in flight
`define ROB_WIDTH        5    // 5 bits to address 32 ROB slots

// Reservation Station (RS) Constants
`define RS_ENTRIES       16   // 16 waiting slots
`define RS_WIDTH         4

// Store Queue (SQ) Constants
`define SQ_ENTRIES       16   // 16 in-flight stores tracked
`define SQ_WIDTH         4

// Branch Predictor Constants
`define BP_ENTRIES       64   // 64-entry 2-bit branch predictor
`define BP_INDEX_WIDTH   6

// ----------------------------------------------------------------------------
// Major RISC-V Opcodes (7 bits)
// ----------------------------------------------------------------------------
`define OPCODE_R_OP         7'b0110011 // 64-bit Reg-Reg (ADD, SUB, MUL, etc.)
`define OPCODE_R_OP_32      7'b0111011 // 32-bit Reg-Reg Word (ADDW, SUBW, MULW, etc.)
`define OPCODE_I_OP         7'b0010011 // 64-bit Reg-Imm (ADDI, ANDI, SLLI, etc.)
`define OPCODE_I_OP_32      7'b0011011 // 32-bit Reg-Imm Word (ADDIW, SLLIW, etc.)
`define OPCODE_LOAD         7'b0000011 // Loads (LB, LH, LW, LD, LBU, LHU, LWU)
`define OPCODE_STORE        7'b0100011 // Stores (SB, SH, SW, SD)
`define OPCODE_BRANCH       7'b1100011 // Branches (BEQ, BNE, BLT, BGE, BLTU, BGEU)
`define OPCODE_JAL          7'b1101111 // Jump and Link
`define OPCODE_JALR         7'b1100111 // Jump and Link Register
`define OPCODE_LUI          7'b0110111 // Load Upper Immediate
`define OPCODE_AUIPC        7'b0010111 // Add Upper Immediate to PC
`define OPCODE_SYSTEM       7'b1110011 // System instructions (WFI, ECALL, EBREAK)

// ----------------------------------------------------------------------------
// Funct3 Codes (3 bits)
// ----------------------------------------------------------------------------
// Branches
`define FUNCT3_BEQ          3'b000
`define FUNCT3_BNE          3'b001
`define FUNCT3_BLT          3'b100
`define FUNCT3_BGE          3'b101
`define FUNCT3_BLTU         3'b110
`define FUNCT3_BGEU         3'b111

// Loads
`define FUNCT3_LB           3'b000
`define FUNCT3_LH           3'b001
`define FUNCT3_LW           3'b010
`define FUNCT3_LD           3'b011
`define FUNCT3_LBU          3'b100
`define FUNCT3_LHU          3'b101
`define FUNCT3_LWU          3'b110

// Stores
`define FUNCT3_SB           3'b000
`define FUNCT3_SH           3'b001
`define FUNCT3_SW           3'b010
`define FUNCT3_SD           3'b011

// Multiplier funct3
`define FUNCT3_MUL          3'b000
`define FUNCT3_MULH         3'b001
`define FUNCT3_MULHSU       3'b010
`define FUNCT3_MULHU        3'b011

// ----------------------------------------------------------------------------
// Functional Unit Codes (3 bits)
// ----------------------------------------------------------------------------
`define FU_NONE             3'd0
`define FU_ALU              3'd1
`define FU_MULT             3'd2
`define FU_BRANCH           3'd3
`define FU_LOAD             3'd4
`define FU_STORE            3'd5

// ----------------------------------------------------------------------------
// ALU Operation Codes (5 bits)
// ----------------------------------------------------------------------------
`define ALU_ADD             5'd0
`define ALU_SUB             5'd1
`define ALU_SLL             5'd2
`define ALU_SLT             5'd3
`define ALU_SLTU            5'd4
`define ALU_XOR             5'd5
`define ALU_SRL             5'd6
`define ALU_SRA             5'd7
`define ALU_OR              5'd8
`define ALU_AND             5'd9
// 32-bit W-instruction ALU operations (truncated & sign-extended to 64 bits)
`define ALU_ADDW            5'd10
`define ALU_SUBW            5'd11
`define ALU_SLLW            5'd12
`define ALU_SRLW            5'd13
`define ALU_SRAW            5'd14
`define ALU_PASS_B          5'd15

// ----------------------------------------------------------------------------
// Multiplier Operation Codes (3 bits)
// ----------------------------------------------------------------------------
`define MULT_MUL            3'd0 // Signed x Signed lower 64-bit
`define MULT_MULH           3'd1 // Signed x Signed upper 64-bit
`define MULT_MULHSU         3'd2 // Signed x Unsigned upper 64-bit
`define MULT_MULHU          3'd3 // Unsigned x Unsigned upper 64-bit
`define MULT_MULW           3'd4 // 32-bit Word multiplication (sign-extended)

// ----------------------------------------------------------------------------
// Branch Condition Codes (3 bits)
// ----------------------------------------------------------------------------
`define BR_JAL              3'd0
`define BR_BEQ              3'd1
`define BR_BNE              3'd2
`define BR_BLT              3'd3
`define BR_BGE              3'd4
`define BR_BLTU             3'd5
`define BR_BGEU             3'd6
`define BR_JALR             3'd7

// ----------------------------------------------------------------------------
// NOP and WFI Instructions
// ----------------------------------------------------------------------------
`define NOP_INST            32'h00000013 // addi x0, x0, 0
`define WFI_INST            32'h10500073 // wfi

`endif // __DEFS_V__
