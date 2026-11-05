// ============================================================================
// File: reservation_station.v
// Description: Reservation Station (RS) for Scalar RV64IM OoO Processor.
//              16 waiting entries.
//              Allocates free slot at Dispatch.
//              Continuously snoops CDB to wake up waiting source operands.
//              Selects ready instructions for Out-of-Order Issue to execution stage.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module reservation_station (
    input  wire                   clk,
    input  wire                   rst,

    // Branch Misprediction Recovery
    input  wire                   recover_en,

    // Dispatch Allocation Interface
    input  wire                   alloc_en,
    input  wire [2:0]             alloc_fu,
    input  wire [4:0]             alloc_op,
    input  wire [`ROB_WIDTH-1:0]  alloc_rob_idx,
    input  wire [`PR_WIDTH-1:0]   alloc_dest_pr,
    input  wire [`PR_WIDTH-1:0]   alloc_src1_pr,
    input  wire                   alloc_src1_ready,
    input  wire [`PR_WIDTH-1:0]   alloc_src2_pr,
    input  wire                   alloc_src2_ready,
    input  wire [`XLEN-1:0]       alloc_imm,
    input  wire                   alloc_use_imm,
    input  wire                   alloc_use_pc,
    input  wire [`XLEN-1:0]       alloc_pc,
    input  wire                   alloc_pred_taken,
    input  wire [`XLEN-1:0]       alloc_pred_target,
    input  wire [`SQ_WIDTH-1:0]   alloc_sq_idx,
    input  wire                   alloc_is_branch,
    input  wire                   alloc_is_store,
    output wire                   rs_full,

    // CDB Tag Snooping Interface
    input  wire                   cdb_valid,
    input  wire [`PR_WIDTH-1:0]   cdb_pr,

    // Functional Unit Readiness (Backpressure from CDB Arbiter)
    input  wire                   alu_ready,
    input  wire                   mult_ready,
    input  wire                   branch_ready,
    input  wire                   load_ready,
    input  wire [`SQ_ENTRIES-1:0] load_tail_ready,

    // Issue Interface (to Issue Stage)
    output reg                    issue_valid,
    output reg  [2:0]             issue_fu,
    output reg  [4:0]             issue_op,
    output reg  [`ROB_WIDTH-1:0]  issue_rob_idx,
    output reg  [`PR_WIDTH-1:0]   issue_dest_pr,
    output reg  [`PR_WIDTH-1:0]   issue_src1_pr,
    output reg  [`PR_WIDTH-1:0]   issue_src2_pr,
    output reg  [`XLEN-1:0]       issue_imm,
    output reg                    issue_use_imm,
    output reg                    issue_use_pc,
    output reg  [`XLEN-1:0]       issue_pc,
    output reg                    issue_pred_taken,
    output reg  [`XLEN-1:0]       issue_pred_target,
    output reg  [`SQ_WIDTH-1:0]   issue_sq_idx,
    output reg                    issue_is_branch,
    output reg                    issue_is_store
);

    // Parallel flat arrays for RS entries (Verilog-2001 compatible)
    reg                   rs_busy        [0:`RS_ENTRIES-1];
    reg [2:0]             rs_fu          [0:`RS_ENTRIES-1];
    reg [4:0]             rs_op          [0:`RS_ENTRIES-1];
    reg [`ROB_WIDTH-1:0]  rs_rob_idx     [0:`RS_ENTRIES-1];
    reg [`PR_WIDTH-1:0]   rs_dest_pr     [0:`RS_ENTRIES-1];
    reg [`PR_WIDTH-1:0]   rs_src1_pr     [0:`RS_ENTRIES-1];
    reg                   rs_src1_ready  [0:`RS_ENTRIES-1];
    reg [`PR_WIDTH-1:0]   rs_src2_pr     [0:`RS_ENTRIES-1];
    reg                   rs_src2_ready  [0:`RS_ENTRIES-1];
    reg [`XLEN-1:0]       rs_imm         [0:`RS_ENTRIES-1];
    reg                   rs_use_imm     [0:`RS_ENTRIES-1];
    reg                   rs_use_pc      [0:`RS_ENTRIES-1];
    reg [`XLEN-1:0]       rs_pc          [0:`RS_ENTRIES-1];
    reg                   rs_pred_taken  [0:`RS_ENTRIES-1];
    reg [`XLEN-1:0]       rs_pred_target [0:`RS_ENTRIES-1];
    reg [`SQ_WIDTH-1:0]   rs_sq_idx      [0:`RS_ENTRIES-1];
    reg                   rs_is_branch   [0:`RS_ENTRIES-1];
    reg                   rs_is_store    [0:`RS_ENTRIES-1];

    // Find free entry for allocation (Priority Encoder)
    reg [`RS_WIDTH-1:0] alloc_slot;
    reg                 found_free;
    integer f;
    always @(*) begin
        alloc_slot = `RS_WIDTH'd0;
        found_free = 1'b0;
        for (f = 0; f < `RS_ENTRIES; f = f + 1) begin
            if (!found_free && !rs_busy[f]) begin
                alloc_slot = f[`RS_WIDTH-1:0];
                found_free = 1'b1;
            end
        end
    end
    assign rs_full = !found_free;

    // Issue Selection (Priority Arbiter: pick oldest ready entry whose FU is ready)
    reg [`RS_WIDTH-1:0] issue_slot;
    reg                 found_ready;
    integer r;
    reg r1, r2, fu_is_ready;
    always @(*) begin
        issue_slot  = `RS_WIDTH'd0;
        found_ready = 1'b0;
        for (r = 0; r < `RS_ENTRIES; r = r + 1) begin
            if (rs_busy[r]) begin
                r1 = rs_src1_ready[r] || (cdb_valid && (cdb_pr != `ZERO_PR) && (rs_src1_pr[r] == cdb_pr));
                r2 = rs_src2_ready[r] || (cdb_valid && (cdb_pr != `ZERO_PR) && (rs_src2_pr[r] == cdb_pr));

                case (rs_fu[r])
                    `FU_ALU:    fu_is_ready = alu_ready;
                    `FU_MULT:   fu_is_ready = mult_ready;
                    `FU_BRANCH: fu_is_ready = branch_ready;
                    `FU_LOAD:   fu_is_ready = load_ready && load_tail_ready[rs_sq_idx[r]];
                    default:    fu_is_ready = 1'b1;
                endcase

                if (!found_ready && r1 && r2 && fu_is_ready) begin
                    issue_slot  = r[`RS_WIDTH-1:0];
                    found_ready = 1'b1;
                end
            end
        end

        issue_valid       = found_ready;
        issue_fu          = rs_fu[issue_slot];
        issue_op          = rs_op[issue_slot];
        issue_rob_idx     = rs_rob_idx[issue_slot];
        issue_dest_pr     = rs_dest_pr[issue_slot];
        issue_src1_pr     = rs_src1_pr[issue_slot];
        issue_src2_pr     = rs_src2_pr[issue_slot];
        issue_imm         = rs_imm[issue_slot];
        issue_use_imm     = rs_use_imm[issue_slot];
        issue_use_pc      = rs_use_pc[issue_slot];
        issue_pc          = rs_pc[issue_slot];
        issue_pred_taken  = rs_pred_taken[issue_slot];
        issue_pred_target = rs_pred_target[issue_slot];
        issue_sq_idx      = rs_sq_idx[issue_slot];
        issue_is_branch   = rs_is_branch[issue_slot];
        issue_is_store    = rs_is_store[issue_slot];
    end

    // Sequential State Management
    integer i;
    always @(posedge clk) begin // sync: recover_en must NOT be an async clear (FPGA)
        if (rst || recover_en) begin
            for (i = 0; i < `RS_ENTRIES; i = i + 1) begin
                rs_busy[i]        <= 1'b0;
                rs_fu[i]          <= `FU_NONE;
                rs_op[i]          <= 5'd0;
                rs_rob_idx[i]     <= `ROB_WIDTH'd0;
                rs_dest_pr[i]     <= `ZERO_PR;
                rs_src1_pr[i]     <= `ZERO_PR;
                rs_src1_ready[i]  <= 1'b0;
                rs_src2_pr[i]     <= `ZERO_PR;
                rs_src2_ready[i]  <= 1'b0;
                rs_imm[i]         <= 64'd0;
                rs_use_imm[i]     <= 1'b0;
                rs_use_pc[i]      <= 1'b0;
                rs_pc[i]          <= 64'd0;
                rs_pred_taken[i]  <= 1'b0;
                rs_pred_target[i] <= 64'd0;
                rs_sq_idx[i]      <= `SQ_WIDTH'd0;
                rs_is_branch[i]   <= 1'b0;
                rs_is_store[i]    <= 1'b0;
            end
        end else begin
            // 1. Tag Snooping on CDB
            if (cdb_valid && (cdb_pr != `ZERO_PR)) begin
                for (i = 0; i < `RS_ENTRIES; i = i + 1) begin
                    if (rs_busy[i]) begin
                        if (rs_src1_pr[i] == cdb_pr) rs_src1_ready[i] <= 1'b1;
                        if (rs_src2_pr[i] == cdb_pr) rs_src2_ready[i] <= 1'b1;
                    end
                end
            end

            // 2. Clear issued entry
            if (issue_valid) begin
                rs_busy[issue_slot] <= 1'b0;
            end

            // 3. Dispatch Allocation into free slot
            if (alloc_en && !rs_full) begin
                rs_busy[alloc_slot]        <= 1'b1;
                rs_fu[alloc_slot]          <= alloc_fu;
                rs_op[alloc_slot]          <= alloc_op;
                rs_rob_idx[alloc_slot]     <= alloc_rob_idx;
                rs_dest_pr[alloc_slot]     <= alloc_dest_pr;
                rs_src1_pr[alloc_slot]     <= alloc_src1_pr;
                rs_src1_ready[alloc_slot]  <= alloc_src1_ready || (cdb_valid && (cdb_pr != `ZERO_PR) && (alloc_src1_pr == cdb_pr));
                rs_src2_pr[alloc_slot]     <= alloc_src2_pr;
                rs_src2_ready[alloc_slot]  <= alloc_src2_ready || (cdb_valid && (cdb_pr != `ZERO_PR) && (alloc_src2_pr == cdb_pr));
                rs_imm[alloc_slot]         <= alloc_imm;
                rs_use_imm[alloc_slot]     <= alloc_use_imm;
                rs_use_pc[alloc_slot]      <= alloc_use_pc;
                rs_pc[alloc_slot]          <= alloc_pc;
                rs_pred_taken[alloc_slot]  <= alloc_pred_taken;
                rs_pred_target[alloc_slot] <= alloc_pred_target;
                rs_sq_idx[alloc_slot]      <= alloc_sq_idx;
                rs_is_branch[alloc_slot]   <= alloc_is_branch;
                rs_is_store[alloc_slot]    <= alloc_is_store;
            end
        end
    end

endmodule
