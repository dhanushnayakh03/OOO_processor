// ============================================================================
// File: fu_mult.v
// Description: Pipelined Multiplier for RV64M instructions.
//              Supports MUL, MULH, MULHSU, MULHU, and MULW.
//              2-cycle pipelined latency.
//              Holds result in output FU/C register until granted by CDB arbiter.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module fu_mult (
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

    // CDB Arbiter Interface (FU/C Output Pipeline Register)
    input  wire                   mult_grant,
    output reg                    fu_c_valid,
    output reg  [`ROB_WIDTH-1:0]  fu_c_rob_idx,
    output reg  [`PR_WIDTH-1:0]   fu_c_dest_pr,
    output reg  [`XLEN-1:0]       fu_c_data
);

    wire is_mult_active = ex_valid && (ex_fu == `FU_MULT);

    // ------------------------------------------------------------------------
    // Pipeline Stage 1 Registers (Cycle 1)
    // ------------------------------------------------------------------------
    reg                   s1_valid;
    reg [2:0]             s1_op;
    reg [`ROB_WIDTH-1:0]  s1_rob_idx;
    reg [`PR_WIDTH-1:0]   s1_dest_pr;
    reg [`XLEN-1:0]       s1_op_a;
    reg [`XLEN-1:0]       s1_op_b;

    // ------------------------------------------------------------------------
    // Pipeline Stage 2 Registers (Cycle 2)
    // ------------------------------------------------------------------------
    reg                   s2_valid;
    reg [2:0]             s2_op;
    reg [`ROB_WIDTH-1:0]  s2_rob_idx;
    reg [`PR_WIDTH-1:0]   s2_dest_pr;
    reg [`XLEN-1:0]       s2_op_a;
    reg [`XLEN-1:0]       s2_op_b;

    // ------------------------------------------------------------------------
    // Pipeline Stage 3 Registers (Cycle 3)
    // ------------------------------------------------------------------------
    reg                   s3_valid;
    reg [2:0]             s3_op;
    reg [`ROB_WIDTH-1:0]  s3_rob_idx;
    reg [`PR_WIDTH-1:0]   s3_dest_pr;
    reg [`XLEN-1:0]       s3_op_a;
    reg [`XLEN-1:0]       s3_op_b;

    always @(posedge clk) begin // sync: recover_en must NOT be an async clear (FPGA)
        if (rst || recover_en) begin
            s1_valid   <= 1'b0;
            s1_op      <= 3'd0;
            s1_rob_idx <= `ROB_WIDTH'd0;
            s1_dest_pr <= `ZERO_PR;
            s1_op_a    <= 64'd0;
            s1_op_b    <= 64'd0;

            s2_valid   <= 1'b0;
            s2_op      <= 3'd0;
            s2_rob_idx <= `ROB_WIDTH'd0;
            s2_dest_pr <= `ZERO_PR;
            s2_op_a    <= 64'd0;
            s2_op_b    <= 64'd0;

            s3_valid   <= 1'b0;
            s3_op      <= 3'd0;
            s3_rob_idx <= `ROB_WIDTH'd0;
            s3_dest_pr <= `ZERO_PR;
            s3_op_a    <= 64'd0;
            s3_op_b    <= 64'd0;
        end else begin
            // Stage 1
            s1_valid   <= is_mult_active;
            s1_op      <= ex_op[2:0];
            s1_rob_idx <= ex_rob_idx;
            s1_dest_pr <= ex_dest_pr;
            s1_op_a    <= ex_op_a;
            s1_op_b    <= ex_op_b;

            // Stage 2
            s2_valid   <= s1_valid;
            s2_op      <= s1_op;
            s2_rob_idx <= s1_rob_idx;
            s2_dest_pr <= s1_dest_pr;
            s2_op_a    <= s1_op_a;
            s2_op_b    <= s1_op_b;

            // Stage 3
            s3_valid   <= s2_valid;
            s3_op      <= s2_op;
            s3_rob_idx <= s2_rob_idx;
            s3_dest_pr <= s2_dest_pr;
            s3_op_a    <= s2_op_a;
            s3_op_b    <= s2_op_b;
        end
    end

    // ------------------------------------------------------------------------
    // Multiplication Core (Computes across 128-bit products at Stage 3)
    // ------------------------------------------------------------------------
    wire signed [63:0] s_a = s3_op_a;
    wire signed [63:0] s_b = s3_op_b;
    wire        [63:0] u_a = s3_op_a;
    wire        [63:0] u_b = s3_op_b;

    wire signed [127:0] prod_ss = s_a * s_b;
    wire signed [127:0] prod_su = s_a * $signed({1'b0, u_b});
    wire        [127:0] prod_uu = u_a * u_b;

    wire signed [31:0] s_a_w = s3_op_a[31:0];
    wire signed [31:0] s_b_w = s3_op_b[31:0];
    wire signed [63:0] prod_w = s_a_w * s_b_w;

    reg [`XLEN-1:0] mult_result;
    always @(*) begin
        case (s3_op)
            `MULT_MUL:    mult_result = prod_ss[63:0];
            `MULT_MULH:   mult_result = prod_ss[127:64];
            `MULT_MULHSU: mult_result = prod_su[127:64];
            `MULT_MULHU:  mult_result = prod_uu[127:64];
            `MULT_MULW:   mult_result = {{32{prod_w[31]}}, prod_w[31:0]};
            default:      mult_result = prod_ss[63:0];
        endcase
    end

    // ------------------------------------------------------------------------
    // Pipeline Stage 4 / FU/C Output Register (Cycle 4)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin // sync: recover_en must NOT be an async clear (FPGA)
        if (rst || recover_en) begin
            fu_c_valid   <= 1'b0;
            fu_c_rob_idx <= `ROB_WIDTH'd0;
            fu_c_dest_pr <= `ZERO_PR;
            fu_c_data    <= 64'd0;
        end else begin
            if (mult_grant) begin
                fu_c_valid <= 1'b0;
            end

            if (s3_valid) begin
                fu_c_valid   <= 1'b1;
                fu_c_rob_idx <= s3_rob_idx;
                fu_c_dest_pr <= s3_dest_pr;
                fu_c_data    <= mult_result;
            end
        end
    end

endmodule
