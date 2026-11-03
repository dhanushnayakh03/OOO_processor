// ============================================================================
// File: issue_stage.v
// Description: Issue Stage for Scalar RV64IM OoO Processor.
//              Reads operand values from Physical Register File (PRF).
//              Performs operand muxing (PC / Immediate / Register Data).
//              Latches decoded instruction and operands into the IS/EX pipeline register.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module issue_stage (
    input  wire                   clk,
    input  wire                   rst,

    // Branch Misprediction Recovery
    input  wire                   recover_en,

    // Issue Interface from Reservation Station
    input  wire                   issue_valid,
    input  wire [2:0]             issue_fu,
    input  wire [4:0]             issue_op,
    input  wire [`ROB_WIDTH-1:0]  issue_rob_idx,
    input  wire [`PR_WIDTH-1:0]   issue_dest_pr,
    input  wire [`PR_WIDTH-1:0]   issue_src1_pr,
    input  wire [`PR_WIDTH-1:0]   issue_src2_pr,
    input  wire [`XLEN-1:0]       issue_imm,
    input  wire                   issue_use_imm,
    input  wire                   issue_use_pc,
    input  wire [`XLEN-1:0]       issue_pc,
    input  wire                   issue_pred_taken,
    input  wire [`XLEN-1:0]       issue_pred_target,
    input  wire [`SQ_WIDTH-1:0]   issue_sq_idx,
    input  wire                   issue_is_branch,
    input  wire                   issue_is_store,

    // Physical Register File Read Ports
    output wire [`PR_WIDTH-1:0]   prf_read_pr1,
    input  wire [`XLEN-1:0]       prf_read_data1,
    output wire [`PR_WIDTH-1:0]   prf_read_pr2,
    input  wire [`XLEN-1:0]       prf_read_data2,

    // IS/EX Pipeline Register Outputs to Functional Units
    output reg                    ex_valid,
    output reg  [2:0]             ex_fu,
    output reg  [4:0]             ex_op,
    output reg  [`ROB_WIDTH-1:0]  ex_rob_idx,
    output reg  [`PR_WIDTH-1:0]   ex_dest_pr,
    output reg  [`XLEN-1:0]       ex_op_a,
    output reg  [`XLEN-1:0]       ex_op_b,
    output reg  [`XLEN-1:0]       ex_store_data,
    output reg  [`XLEN-1:0]       ex_imm,
    output reg  [`XLEN-1:0]       ex_pc,
    output reg                    ex_pred_taken,
    output reg  [`XLEN-1:0]       ex_pred_target,
    output reg  [`SQ_WIDTH-1:0]   ex_sq_idx,
    output reg                    ex_is_branch,
    output reg                    ex_is_store
);

    // Read PRF
    assign prf_read_pr1 = issue_src1_pr;
    assign prf_read_pr2 = issue_src2_pr;

    // Combinational Operand Muxing
    always @(*) begin
        ex_valid       = issue_valid;
        ex_fu          = issue_fu;
        ex_op          = issue_op;
        ex_rob_idx     = issue_rob_idx;
        ex_dest_pr     = issue_dest_pr;
        ex_op_a        = issue_use_pc  ? issue_pc  : prf_read_data1;
        ex_op_b        = issue_use_imm ? issue_imm : prf_read_data2;
        ex_store_data  = prf_read_data2; // Raw store data from rs2
        ex_imm         = issue_imm;
        ex_pc          = issue_pc;
        ex_pred_taken  = issue_pred_taken;
        ex_pred_target = issue_pred_target;
        ex_sq_idx      = issue_sq_idx;
        ex_is_branch   = issue_is_branch;
        ex_is_store    = issue_is_store;
    end

endmodule
