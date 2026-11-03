// ============================================================================
// File: complete_stage.v
// Description: Complete Stage & Common Data Bus (CDB) Arbiter for Scalar OoO.
//              Arbitrates among the 4 Functional Units (MULT, LOAD, BRANCH, ALU).
//              Broadcasts result on CDB to wake up RS operands, update Map Table,
//              write to Physical Register File (PRF), and mark ROB completion.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module complete_stage (
    // Inputs from Multiplier FU
    input  wire                   fu_mult_valid,
    input  wire [`ROB_WIDTH-1:0]  fu_mult_rob_idx,
    input  wire [`PR_WIDTH-1:0]   fu_mult_dest_pr,
    input  wire [`XLEN-1:0]       fu_mult_data,
    output reg                    fu_mult_grant,

    // Inputs from Load FU
    input  wire                   fu_load_valid,
    input  wire [`ROB_WIDTH-1:0]  fu_load_rob_idx,
    input  wire [`PR_WIDTH-1:0]   fu_load_dest_pr,
    input  wire [`XLEN-1:0]       fu_load_data,
    output reg                    fu_load_grant,

    // Inputs from Branch FU
    input  wire                   fu_branch_valid,
    input  wire [`ROB_WIDTH-1:0]  fu_branch_rob_idx,
    input  wire [`PR_WIDTH-1:0]   fu_branch_dest_pr,
    input  wire [`XLEN-1:0]       fu_branch_data,
    input  wire                   fu_branch_mispred,
    input  wire [`XLEN-1:0]       fu_branch_target,
    output reg                    fu_branch_grant,

    // Inputs from ALU FU
    input  wire                   fu_alu_valid,
    input  wire [`ROB_WIDTH-1:0]  fu_alu_rob_idx,
    input  wire [`PR_WIDTH-1:0]   fu_alu_dest_pr,
    input  wire [`XLEN-1:0]       fu_alu_data,
    output reg                    fu_alu_grant,

    // Common Data Bus (CDB) Broadcast Outputs
    output reg                    cdb_valid,
    output reg  [`ROB_WIDTH-1:0]  cdb_rob_idx,
    output reg  [`PR_WIDTH-1:0]   cdb_pr,
    output reg  [`XLEN-1:0]       cdb_data,
    output reg                    cdb_branch_en,
    output reg                    cdb_mispredicted,
    output reg  [`XLEN-1:0]       cdb_correct_target
);

    // Fixed Priority Arbiter: MULT > LOAD > BRANCH > ALU
    always @(*) begin
        fu_mult_grant      = 1'b0;
        fu_load_grant      = 1'b0;
        fu_branch_grant    = 1'b0;
        fu_alu_grant       = 1'b0;
        cdb_valid          = 1'b0;
        cdb_rob_idx        = `ROB_WIDTH'd0;
        cdb_pr             = `ZERO_PR;
        cdb_data           = 64'd0;
        cdb_branch_en      = 1'b0;
        cdb_mispredicted   = 1'b0;
        cdb_correct_target = 64'd0;

        if (fu_mult_valid) begin
            fu_mult_grant = 1'b1;
            cdb_valid     = 1'b1;
            cdb_rob_idx   = fu_mult_rob_idx;
            cdb_pr        = fu_mult_dest_pr;
            cdb_data      = fu_mult_data;
        end else if (fu_load_valid) begin
            fu_load_grant = 1'b1;
            cdb_valid     = 1'b1;
            cdb_rob_idx   = fu_load_rob_idx;
            cdb_pr        = fu_load_dest_pr;
            cdb_data      = fu_load_data;
        end else if (fu_branch_valid) begin
            fu_branch_grant    = 1'b1;
            cdb_valid          = 1'b1;
            cdb_rob_idx        = fu_branch_rob_idx;
            cdb_pr             = fu_branch_dest_pr;
            cdb_data           = fu_branch_data;
            cdb_branch_en      = 1'b1;
            cdb_mispredicted   = fu_branch_mispred;
            cdb_correct_target = fu_branch_target;
        end else if (fu_alu_valid) begin
            fu_alu_grant = 1'b1;
            cdb_valid    = 1'b1;
            cdb_rob_idx  = fu_alu_rob_idx;
            cdb_pr       = fu_alu_dest_pr;
            cdb_data     = fu_alu_data;
        end
    end

endmodule
