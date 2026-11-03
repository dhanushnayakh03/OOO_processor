// ============================================================================
// File: dispatch_stage.v
// Description: Instruction Decode & Dispatch Stage for Scalar RV64IM OoO Processor.
//              Decodes 32-bit instructions into functional unit operations.
//              Performs structural hazard detection (ROB, RS, FreeList, SQ).
//              Manages register renaming via Map Table (RAT) and Free List.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module dispatch_stage (
    // IF/ID Pipeline Register Inputs
    input  wire                   if_id_valid,
    input  wire [`XLEN-1:0]       if_id_pc,
    input  wire [`XLEN-1:0]       if_id_npc,
    input  wire [`ILEN-1:0]       if_id_inst,
    input  wire                   if_id_pred_taken,
    input  wire [`XLEN-1:0]       if_id_pred_target,

    // Structural Hazard Inputs from OoO Queues
    input  wire                   rob_full,
    input  wire                   rs_full,
    input  wire                   fl_empty,
    input  wire                   sq_full,

    // Pipeline Stall Output to Fetch Stage
    output wire                   stall,

    // Map Table (RAT) Renaming Interface
    output wire [`AR_WIDTH-1:0]   rat_src1_ar,
    input  wire [`PR_WIDTH-1:0]   rat_src1_pr,
    input  wire                   rat_src1_ready,

    output wire [`AR_WIDTH-1:0]   rat_src2_ar,
    input  wire [`PR_WIDTH-1:0]   rat_src2_pr,
    input  wire                   rat_src2_ready,

    output wire [`AR_WIDTH-1:0]   rat_dest_ar,
    input  wire [`PR_WIDTH-1:0]   rat_dest_old_pr,

    output wire                   rat_alloc_en,
    output wire [`AR_WIDTH-1:0]   rat_alloc_dest_ar,
    output wire [`PR_WIDTH-1:0]   rat_alloc_new_pr,

    // Free List Interface
    output wire                   fl_alloc_en,
    input  wire [`PR_WIDTH-1:0]   fl_alloc_pr,

    // ROB Allocation Interface
    output wire                   rob_alloc_en,
    output wire [`AR_WIDTH-1:0]   rob_alloc_arch_dest,
    output wire [`PR_WIDTH-1:0]   rob_alloc_tag_new,
    output wire [`PR_WIDTH-1:0]   rob_alloc_tag_old,
    output wire                   rob_alloc_is_store,
    output wire [`SQ_WIDTH-1:0]   rob_alloc_sq_idx,
    output wire [`XLEN-1:0]       rob_alloc_pc,
    output wire [`XLEN-1:0]       rob_alloc_npc,
    output wire                   rob_alloc_pred_taken,
    output wire [`XLEN-1:0]       rob_alloc_pred_target,
    output wire                   rob_alloc_halt,
    input  wire [`ROB_WIDTH-1:0]  rob_alloc_idx,

    // Store Queue Allocation Interface
    output wire                   sq_alloc_en,
    input  wire [`SQ_WIDTH-1:0]   sq_alloc_idx,

    // RS Allocation Interface
    output wire                   rs_alloc_en,
    output wire [2:0]             rs_alloc_fu,
    output wire [4:0]             rs_alloc_op,
    output wire [`ROB_WIDTH-1:0]  rs_alloc_rob_idx,
    output wire [`PR_WIDTH-1:0]   rs_alloc_dest_pr,
    output wire [`PR_WIDTH-1:0]   rs_alloc_src1_pr,
    output wire                   rs_alloc_src1_ready,
    output wire [`PR_WIDTH-1:0]   rs_alloc_src2_pr,
    output wire                   rs_alloc_src2_ready,
    output wire [`XLEN-1:0]       rs_alloc_imm,
    output wire                   rs_alloc_use_imm,
    output wire                   rs_alloc_use_pc,
    output wire [`XLEN-1:0]       rs_alloc_pc,
    output wire                   rs_alloc_pred_taken,
    output wire [`XLEN-1:0]       rs_alloc_pred_target,
    output wire [`SQ_WIDTH-1:0]   rs_alloc_sq_idx,
    output wire                   rs_alloc_is_branch,
    output wire                   rs_alloc_is_store
);

    // ------------------------------------------------------------------------
    // Instruction Fields
    // ------------------------------------------------------------------------
    wire [6:0] opcode = if_id_inst[6:0];
    wire [4:0] rd     = if_id_inst[11:7];
    wire [2:0] funct3 = if_id_inst[14:12];
    wire [4:0] rs1    = if_id_inst[19:15];
    wire [4:0] rs2    = if_id_inst[24:20];
    wire [6:0] funct7 = if_id_inst[31:25];

    // Immediates
    wire [`XLEN-1:0] imm_i = {{52{if_id_inst[31]}}, if_id_inst[31:20]};
    wire [`XLEN-1:0] imm_s = {{52{if_id_inst[31]}}, if_id_inst[31:25], if_id_inst[11:7]};
    wire [`XLEN-1:0] imm_b = {{51{if_id_inst[31]}}, if_id_inst[31], if_id_inst[7], if_id_inst[30:25], if_id_inst[11:8], 1'b0};
    wire [`XLEN-1:0] imm_u = {{32{if_id_inst[31]}}, if_id_inst[31:12], 12'd0};
    wire [`XLEN-1:0] imm_j = {{43{if_id_inst[31]}}, if_id_inst[31], if_id_inst[19:12], if_id_inst[20], if_id_inst[30:21], 1'b0};

    // ------------------------------------------------------------------------
    // Decode Control Signals
    // ------------------------------------------------------------------------
    reg [2:0]       fu_type;
    reg [4:0]       fu_op;
    reg [`XLEN-1:0] imm_val;
    reg             use_imm;
    reg             use_pc;
    reg             dest_valid;
    reg             src1_valid;
    reg             src2_valid;
    reg             is_branch;
    reg             is_store;
    reg             is_halt;

    always @(*) begin
        fu_type    = `FU_NONE;
        fu_op      = 5'd0;
        imm_val    = 64'd0;
        use_imm    = 1'b0;
        use_pc     = 1'b0;
        dest_valid = 1'b0;
        src1_valid = 1'b0;
        src2_valid = 1'b0;
        is_branch  = 1'b0;
        is_store   = 1'b0;
        is_halt    = 1'b0;

        case (opcode)
            `OPCODE_R_OP: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                src2_valid = 1'b1;
                if (funct7 == 7'h01) begin
                    // RV64M Multiplication
                    fu_type = `FU_MULT;
                    case (funct3)
                        `FUNCT3_MUL:    fu_op = `MULT_MUL;
                        `FUNCT3_MULH:   fu_op = `MULT_MULH;
                        `FUNCT3_MULHSU: fu_op = `MULT_MULHSU;
                        `FUNCT3_MULHU:  fu_op = `MULT_MULHU;
                        default:        fu_op = `MULT_MUL;
                    endcase
                end else begin
                    // Standard 64-bit ALU
                    fu_type = `FU_ALU;
                    case (funct3)
                        3'b000:  fu_op = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001:  fu_op = `ALU_SLL;
                        3'b010:  fu_op = `ALU_SLT;
                        3'b011:  fu_op = `ALU_SLTU;
                        3'b100:  fu_op = `ALU_XOR;
                        3'b101:  fu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                        3'b110:  fu_op = `ALU_OR;
                        3'b111:  fu_op = `ALU_AND;
                    endcase
                end
            end

            `OPCODE_R_OP_32: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                src2_valid = 1'b1;
                if (funct7 == 7'h01) begin
                    // RV64M 32-bit Word Multiplication (MULW)
                    fu_type = `FU_MULT;
                    fu_op   = `MULT_MULW;
                end else begin
                    // 32-bit Word ALU Operations
                    fu_type = `FU_ALU;
                    case (funct3)
                        3'b000:  fu_op = (funct7[5]) ? `ALU_SUBW : `ALU_ADDW;
                        3'b001:  fu_op = `ALU_SLLW;
                        3'b101:  fu_op = (funct7[5]) ? `ALU_SRAW : `ALU_SRLW;
                        default: fu_op = `ALU_ADDW;
                    endcase
                end
            end

            `OPCODE_I_OP: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                use_imm    = 1'b1;
                imm_val    = imm_i;
                fu_type    = `FU_ALU;
                case (funct3)
                    3'b000:  fu_op = `ALU_ADD;  // ADDI
                    3'b001:  begin fu_op = `ALU_SLL; imm_val = {58'd0, if_id_inst[25:20]}; end // SLLI (6-bit shamt)
                    3'b010:  fu_op = `ALU_SLT;  // SLTI
                    3'b011:  fu_op = `ALU_SLTU; // SLTIU
                    3'b100:  fu_op = `ALU_XOR;  // XORI
                    3'b101:  begin
                        fu_op   = (if_id_inst[30]) ? `ALU_SRA : `ALU_SRL; // SRAI / SRLI
                        imm_val = {58'd0, if_id_inst[25:20]};
                    end
                    3'b110:  fu_op = `ALU_OR;   // ORI
                    3'b111:  fu_op = `ALU_AND;  // ANDI
                endcase
            end

            `OPCODE_I_OP_32: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                use_imm    = 1'b1;
                imm_val    = imm_i;
                fu_type    = `FU_ALU;
                case (funct3)
                    3'b000:  fu_op = `ALU_ADDW; // ADDIW
                    3'b001:  begin fu_op = `ALU_SLLW; imm_val = {59'd0, if_id_inst[24:20]}; end // SLLIW (5-bit shamt)
                    3'b101:  begin
                        fu_op   = (if_id_inst[30]) ? `ALU_SRAW : `ALU_SRLW; // SRAIW / SRLIW
                        imm_val = {59'd0, if_id_inst[24:20]};
                    end
                    default: fu_op = `ALU_ADDW;
                endcase
            end

            `OPCODE_LUI: begin
                dest_valid = (rd != 5'd0);
                use_imm    = 1'b1;
                imm_val    = imm_u;
                fu_type    = `FU_ALU;
                fu_op      = `ALU_PASS_B;
            end

            `OPCODE_AUIPC: begin
                dest_valid = (rd != 5'd0);
                use_imm    = 1'b1;
                use_pc     = 1'b1;
                imm_val    = imm_u;
                fu_type    = `FU_ALU;
                fu_op      = `ALU_ADD;
            end

            `OPCODE_LOAD: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                use_imm    = 1'b1;
                imm_val    = imm_i;
                fu_type    = `FU_LOAD;
                fu_op      = {2'b00, funct3}; // Pass funct3 (LB, LH, LW, LD, LBU, LHU, LWU)
            end

            `OPCODE_STORE: begin
                src1_valid = 1'b1;
                src2_valid = 1'b1; // Store data from rs2
                use_imm    = 1'b1;
                imm_val    = imm_s;
                is_store   = 1'b1;
                fu_type    = `FU_ALU;         // ALU computes effective address & formats store data
                fu_op      = {2'b01, funct3}; // Stores (SB, SH, SW, SD)
            end

            `OPCODE_BRANCH: begin
                src1_valid = 1'b1;
                src2_valid = 1'b1;
                use_imm    = 1'b0; // Compares rs1 and rs2; target uses ex_imm
                imm_val    = imm_b;
                is_branch  = 1'b1;
                fu_type    = `FU_BRANCH;
                case (funct3)
                    `FUNCT3_BEQ:  fu_op = `BR_BEQ;
                    `FUNCT3_BNE:  fu_op = `BR_BNE;
                    `FUNCT3_BLT:  fu_op = `BR_BLT;
                    `FUNCT3_BGE:  fu_op = `BR_BGE;
                    `FUNCT3_BLTU: fu_op = `BR_BLTU;
                    `FUNCT3_BGEU: fu_op = `BR_BGEU;
                    default:      fu_op = `BR_BEQ;
                endcase
            end

            `OPCODE_JAL: begin
                dest_valid = (rd != 5'd0);
                use_imm    = 1'b1;
                imm_val    = imm_j;
                is_branch  = 1'b1;
                fu_type    = `FU_BRANCH;
                fu_op      = `BR_JAL;
            end

            `OPCODE_JALR: begin
                dest_valid = (rd != 5'd0);
                src1_valid = 1'b1;
                use_imm    = 1'b1;
                imm_val    = imm_i;
                is_branch  = 1'b1;
                fu_type    = `FU_BRANCH;
                fu_op      = `BR_JALR;
            end

            `OPCODE_SYSTEM: begin
                // WFI / Halt Detection
                if (if_id_inst == `WFI_INST || if_id_inst[31:20] == 12'h105) begin
                    is_halt    = 1'b1;
                    fu_type    = `FU_ALU;
                    fu_op      = `ALU_PASS_B;
                end
            end

            default: ;
        endcase
    end

    // ------------------------------------------------------------------------
    // Structural Hazard Check
    // ------------------------------------------------------------------------
    wire structural_hazard = rob_full ||
                             rs_full  ||
                             (dest_valid && fl_empty) ||
                             (is_store && sq_full);

    assign stall = if_id_valid && structural_hazard;

    wire dispatch_en = if_id_valid && !structural_hazard;

    // ------------------------------------------------------------------------
    // Renaming Connections
    // ------------------------------------------------------------------------
    assign rat_src1_ar = src1_valid ? rs1 : 5'd0;
    assign rat_src2_ar = src2_valid ? rs2 : 5'd0;
    assign rat_dest_ar = dest_valid ? rd  : 5'd0;

    assign fl_alloc_en = dispatch_en && dest_valid;

    assign rat_alloc_en      = dispatch_en && dest_valid;
    assign rat_alloc_dest_ar = rd;
    assign rat_alloc_new_pr  = fl_alloc_pr;

    wire [`PR_WIDTH-1:0] dest_phys_reg = dest_valid ? fl_alloc_pr : `ZERO_PR;

    // ------------------------------------------------------------------------
    // ROB Allocation Connections
    // ------------------------------------------------------------------------
    assign rob_alloc_en          = dispatch_en;
    assign rob_alloc_arch_dest   = dest_valid ? rd : 5'd0;
    assign rob_alloc_tag_new     = dest_phys_reg;
    assign rob_alloc_tag_old     = dest_valid ? rat_dest_old_pr : `ZERO_PR;
    assign rob_alloc_is_store    = is_store;
    assign rob_alloc_sq_idx      = sq_alloc_idx;
    assign rob_alloc_pc          = if_id_pc;
    assign rob_alloc_npc         = if_id_npc;
    assign rob_alloc_pred_taken  = if_id_pred_taken;
    assign rob_alloc_pred_target = if_id_pred_target;
    assign rob_alloc_halt        = is_halt;

    // ------------------------------------------------------------------------
    // Store Queue Allocation Connection
    // ------------------------------------------------------------------------
    assign sq_alloc_en = dispatch_en && is_store;

    // ------------------------------------------------------------------------
    // Reservation Station Allocation Connections
    // ------------------------------------------------------------------------
    assign rs_alloc_en          = dispatch_en;
    assign rs_alloc_fu          = fu_type;
    assign rs_alloc_op          = fu_op;
    assign rs_alloc_rob_idx     = rob_alloc_idx;
    assign rs_alloc_dest_pr     = dest_phys_reg;
    assign rs_alloc_src1_pr     = src1_valid ? rat_src1_pr : `ZERO_PR;
    assign rs_alloc_src1_ready  = src1_valid ? rat_src1_ready : 1'b1;
    assign rs_alloc_src2_pr     = src2_valid ? rat_src2_pr : `ZERO_PR;
    assign rs_alloc_src2_ready  = src2_valid ? rat_src2_ready : 1'b1;
    assign rs_alloc_imm         = imm_val;
    assign rs_alloc_use_imm     = use_imm;
    assign rs_alloc_use_pc      = use_pc;
    assign rs_alloc_pc          = if_id_pc;
    assign rs_alloc_pred_taken  = if_id_pred_taken;
    assign rs_alloc_pred_target = if_id_pred_target;
    assign rs_alloc_sq_idx      = sq_alloc_idx;
    assign rs_alloc_is_branch   = is_branch;
    assign rs_alloc_is_store    = is_store;

endmodule
