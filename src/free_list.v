// ============================================================================
// File: free_list.v
// Description: Synthesizable Bitmask Free List for Physical Register File (R10K style).
//              Uses a 64-bit mask (p0 to p63) for 1-cycle O(1) FPGA synthesis.
//              - Bit i = 1 means physical register p[i] is FREE.
//              - Bit i = 0 means physical register p[i] is ALLOCATED (in RAT/RRAT).
//              - p0 is hardwired to 0 (never free).
//              - Priority encoder selects the lowest free physical register for allocation.
//              - Instantaneous, 100% synthesizable RRAT reconstruction on branch recovery.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module free_list (
    input  wire                                  clk,
    input  wire                                  rst,

    // Branch Misprediction Recovery
    input  wire                                  recover_en,
    input  wire [`NUM_ARCH_REGS*`PR_WIDTH-1:0]   rrat_mappings,

    // Allocation interface (Dispatch Stage)
    input  wire                                  alloc_en,
    output reg  [`PR_WIDTH-1:0]                  alloc_pr,
    output reg                                   fl_empty,

    // Reclamation interface (Retire Stage)
    input  wire                                  free_en,
    input  wire [`PR_WIDTH-1:0]                  free_pr
);

    // 64-bit mask tracking availability of p0..p63
    reg [`NUM_PHYS_REGS-1:0] free_mask;

    // ------------------------------------------------------------------------
    // Combinational Allocation: Priority Encoder (find lowest free register)
    // ------------------------------------------------------------------------
    integer pe_idx;
    always @(*) begin
        alloc_pr = `ZERO_PR;
        fl_empty = 1'b1;
        // Search from 63 down to 1 so the lowest non-zero free index wins
        for (pe_idx = `NUM_PHYS_REGS-1; pe_idx >= 1; pe_idx = pe_idx - 1) begin
            if (free_mask[pe_idx]) begin
                alloc_pr = pe_idx[5:0];
                fl_empty = 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Combinational RRAT check for Recovery (parallel bitmask generation)
    // ------------------------------------------------------------------------
    reg [`NUM_PHYS_REGS-1:0] recovered_free_mask;
    integer a_idx;

    always @(*) begin
        // Start with all physical registers free except p0 (hardwired zero)
        recovered_free_mask = 64'hFFFFFFFFFFFFFFFE;
        // Mark physical registers currently mapped in RRAT as in-use (not free)
        for (a_idx = 1; a_idx < `NUM_ARCH_REGS; a_idx = a_idx + 1) begin
            recovered_free_mask[rrat_mappings[a_idx * `PR_WIDTH +: `PR_WIDTH]] = 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Sequential State Update
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // At reset: p0..p31 are in RRAT (x0..x31), p32..p63 are free
            free_mask[31:0]  <= 32'h00000000;
            free_mask[63:32] <= 32'hFFFFFFFF;
        end else if (recover_en) begin
            // Instantaneous parallel recovery from RRAT bitmask
            free_mask <= recovered_free_mask;
        end else begin
            // Handle simultaneous allocation and reclamation:
            case ({alloc_en && !fl_empty && (alloc_pr != `ZERO_PR), free_en && (free_pr != `ZERO_PR)})
                2'b10: begin
                    free_mask[alloc_pr] <= 1'b0;
                end
                2'b01: begin
                    free_mask[free_pr]  <= 1'b1;
                end
                2'b11: begin
                    if (alloc_pr == free_pr) begin
                        // Same register allocated and freed in same cycle (can happen if reclaimed immediately)
                        free_mask[alloc_pr] <= 1'b0;
                    end else begin
                        free_mask[alloc_pr] <= 1'b0;
                        free_mask[free_pr]  <= 1'b1;
                    end
                end
                default: ; // Idle
            endcase
        end
    end

endmodule
