// ============================================================================
// File: map_table.v
// Description: Speculative Register Alias Table (RAT).
//              Maps 32 architectural registers (x0-x31) to 64 physical registers (p0-p63).
//              Tracks readiness of each physical register.
//              Supports CDB tag snooping, CDB forwarding on read, and RRAT rollback.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module map_table (
    input  wire                                  clk,
    input  wire                                  rst,

    // Recovery from RRAT on branch misprediction
    input  wire                                  recover_en,
    input  wire [`NUM_ARCH_REGS*`PR_WIDTH-1:0]   rrat_mappings,

    // Read Port 1 (Source 1)
    input  wire [`AR_WIDTH-1:0]                  src1_ar,
    output wire [`PR_WIDTH-1:0]                  src1_pr,
    output wire                                  src1_ready,

    // Read Port 2 (Source 2)
    input  wire [`AR_WIDTH-1:0]                  src2_ar,
    output wire [`PR_WIDTH-1:0]                  src2_pr,
    output wire                                  src2_ready,

    // Read Port 3 (Destination - to get Told for ROB)
    input  wire [`AR_WIDTH-1:0]                  dest_ar,
    output wire [`PR_WIDTH-1:0]                  dest_old_pr,

    // Allocation Port (Dispatch Stage)
    input  wire                                  alloc_en,
    input  wire [`AR_WIDTH-1:0]                  alloc_dest_ar,
    input  wire [`PR_WIDTH-1:0]                  alloc_new_pr,

    // CDB Snooping Interface
    input  wire                                  cdb_valid,
    input  wire [`PR_WIDTH-1:0]                  cdb_pr
);

    reg [`PR_WIDTH-1:0] rat_pr    [0:`NUM_ARCH_REGS-1];
    reg                 rat_ready [0:`NUM_ARCH_REGS-1];

    // Read mappings
    assign src1_pr     = (src1_ar == `AR_WIDTH'd0) ? `ZERO_PR : rat_pr[src1_ar];
    assign src1_ready  = (src1_ar == `AR_WIDTH'd0) ? 1'b1 :
                         (rat_ready[src1_ar] || (cdb_valid && (cdb_pr == rat_pr[src1_ar])));

    assign src2_pr     = (src2_ar == `AR_WIDTH'd0) ? `ZERO_PR : rat_pr[src2_ar];
    assign src2_ready  = (src2_ar == `AR_WIDTH'd0) ? 1'b1 :
                         (rat_ready[src2_ar] || (cdb_valid && (cdb_pr == rat_pr[src2_ar])));

    assign dest_old_pr = (dest_ar == `AR_WIDTH'd0) ? `ZERO_PR : rat_pr[dest_ar];

    // Sequential update
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < `NUM_ARCH_REGS; i = i + 1) begin
                rat_pr[i]    <= i[`PR_WIDTH-1:0];
                rat_ready[i] <= 1'b1;
            end
        end else if (recover_en) begin
            // Instantaneous rollback to RRAT committed state
            for (i = 0; i < `NUM_ARCH_REGS; i = i + 1) begin
                rat_pr[i]    <= rrat_mappings[i * `PR_WIDTH +: `PR_WIDTH];
                rat_ready[i] <= 1'b1;
            end
        end else begin
            // CDB snooping: mark physical registers ready when written by CDB
            if (cdb_valid && (cdb_pr != `ZERO_PR)) begin
                for (i = 1; i < `NUM_ARCH_REGS; i = i + 1) begin
                    if (rat_pr[i] == cdb_pr) begin
                        rat_ready[i] <= 1'b1;
                    end
                end
            end

            // Speculative allocation of new destination physical register
            if (alloc_en && (alloc_dest_ar != `AR_WIDTH'd0)) begin
                rat_pr[alloc_dest_ar]    <= alloc_new_pr;
                rat_ready[alloc_dest_ar] <= (cdb_valid && (cdb_pr == alloc_new_pr));
            end
        end
    end

endmodule
