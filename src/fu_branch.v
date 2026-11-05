// ============================================================================
// File: fu_branch.v
// Description: Branch & Jump Execution Unit for Scalar RV64IM OoO Processor.
//              Resolves branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU).
//              Calculates jump targets for JAL / JALR and link addresses (PC+4).
//              Detects branch mispredictions and trains Branch Predictor.
//              Holds result in output FU/C register until granted by CDB arbiter.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module fu_branch (
    input  wire                   clk,
    input  wire                   rst,

    // Branch Misprediction Recovery
    input  wire                   recover_en,

    // Execution Inputs from Issue Stage
    input  wire                   ex_valid,
    input  wire [2:0]             ex_fu,
    input  wire [4:0]             ex_op,
    input  wire [`ROB_WIDTH-1:0]  ex_rob_idx,
    input  wire [`PR_WIDTH-1:0]   ex_dest_pr,
    input  wire [`XLEN-1:0]       ex_op_a,
    input  wire [`XLEN-1:0]       ex_op_b,
    input  wire [`XLEN-1:0]       ex_imm,
    input  wire [`XLEN-1:0]       ex_pc,
    input  wire                   ex_pred_taken,
    input  wire [`XLEN-1:0]       ex_pred_target,

    // Direct Training to Branch Predictor
    output reg                    bp_update_en,
    output reg  [`XLEN-1:0]       bp_update_pc,
    output reg                    bp_update_actual_taken,
    output reg  [`XLEN-1:0]       bp_update_actual_target,

    // CDB Arbiter Interface (FU/C Output Pipeline Register)
    input  wire                   branch_grant,
    output reg                    fu_c_valid,
    output reg  [`ROB_WIDTH-1:0]  fu_c_rob_idx,
    output reg  [`PR_WIDTH-1:0]   fu_c_dest_pr,
    output reg  [`XLEN-1:0]       fu_c_data,
    output reg                    fu_c_mispredicted,
    output reg  [`XLEN-1:0]       fu_c_correct_target
);

    wire is_branch_active = ex_valid && (ex_fu == `FU_BRANCH);

    // ------------------------------------------------------------------------
    // Branch Condition Evaluation
    // ------------------------------------------------------------------------
    reg taken;
    always @(*) begin
        case (ex_op[2:0])
            `BR_JAL:    taken = 1'b1;
            `BR_JALR:   taken = 1'b1;
            `BR_BEQ:    taken = (ex_op_a == ex_op_b);
            `BR_BNE:    taken = (ex_op_a != ex_op_b);
            `BR_BLT:    taken = ($signed(ex_op_a) < $signed(ex_op_b));
            `BR_BGE:    taken = ($signed(ex_op_a) >= $signed(ex_op_b));
            `BR_BLTU:   taken = (ex_op_a < ex_op_b);
            `BR_BGEU:   taken = (ex_op_a >= ex_op_b);
            default:    taken = 1'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Target Calculation & Misprediction Detection
    // ------------------------------------------------------------------------
    // JALR uses (rs1 + imm) & ~1, whereas conditional branches and JAL use (PC + imm)
    wire [`XLEN-1:0] target_calc   = (ex_op[2:0] == `BR_JALR) ?
                                     ((ex_op_a + ex_imm) & ~64'd1) : (ex_pc + ex_imm);
    wire [`XLEN-1:0] actual_npc    = taken ? target_calc : (ex_pc + 64'd4);

    reg             mispredicted;
    reg [`XLEN-1:0] correct_target;
    always @(*) begin
        if (ex_pred_taken != taken) begin
            mispredicted   = 1'b1;
            correct_target = actual_npc;
        end else if (taken && (ex_pred_target != target_calc)) begin
            mispredicted   = 1'b1;
            correct_target = target_calc;
        end else begin
            mispredicted   = 1'b0;
            correct_target = actual_npc;
        end
    end

    // Link address for JAL / JALR (written to destination register)
    wire [`XLEN-1:0] link_data = ex_pc + 64'd4;

    // ------------------------------------------------------------------------
    // Sequential Predictor Training and FU/C Output Register
    // ------------------------------------------------------------------------
    always @(posedge clk) begin // sync: recover_en must NOT be an async clear (FPGA)
        if (rst || recover_en) begin
            bp_update_en            <= 1'b0;
            bp_update_pc            <= 64'd0;
            bp_update_actual_taken  <= 1'b0;
            bp_update_actual_target <= 64'd0;
            fu_c_valid              <= 1'b0;
            fu_c_rob_idx            <= `ROB_WIDTH'd0;
            fu_c_dest_pr            <= `ZERO_PR;
            fu_c_data               <= 64'd0;
            fu_c_mispredicted       <= 1'b0;
            fu_c_correct_target     <= 64'd0;
        end else begin
            // Clear on CDB grant
            if (branch_grant) begin
                fu_c_valid <= 1'b0;
            end

            // Train Branch Predictor
            if (is_branch_active) begin
                bp_update_en            <= 1'b1;
                bp_update_pc            <= ex_pc;
                bp_update_actual_taken  <= taken;
                bp_update_actual_target <= target_calc;

                fu_c_valid              <= 1'b1;
                fu_c_rob_idx            <= ex_rob_idx;
                fu_c_dest_pr            <= ex_dest_pr;
                fu_c_data               <= link_data;
                fu_c_mispredicted       <= mispredicted;
                fu_c_correct_target     <= correct_target;
            end else begin
                bp_update_en            <= 1'b0;
            end
        end
    end

endmodule
