// ============================================================================
// File: free_list.v
// Description: Free List for Physical Register File management (R10K style).
//              Maintains available speculative physical registers in a FIFO.
//              Allocates new physical registers at Dispatch.
//              Reclaims old physical registers (Told) at Retirement.
//              Instantaneously reconstructs free registers from RRAT on branch recovery.
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
    output wire [`PR_WIDTH-1:0]                  alloc_pr,
    output wire                                  fl_empty,

    // Reclamation interface (Retire Stage)
    input  wire                                  free_en,
    input  wire [`PR_WIDTH-1:0]                  free_pr
);

    localparam FL_CAPACITY = `NUM_PHYS_REGS - `NUM_ARCH_REGS; // 64 - 32 = 32

    reg [`PR_WIDTH-1:0] fl_queue [0:FL_CAPACITY-1];
    reg [4:0]           head;
    reg [4:0]           tail;
    reg [5:0]           count;

    assign fl_empty = (count == 6'd0);
    assign alloc_pr = fl_queue[head];

    integer i, r, arch_idx, free_idx;
    reg in_rrat;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initially, p32 to p63 are free
            for (i = 0; i < FL_CAPACITY; i = i + 1) begin
                fl_queue[i] <= 6'd32 + i[5:0];
            end
            head  <= 5'd0;
            tail  <= 5'd0;
            count <= FL_CAPACITY[5:0];
        end else if (recover_en) begin
            // Reconstruct free list from RRAT
            // Any physical register (1..63) not in the RRAT is free
            free_idx = 0;
            for (r = 1; r < `NUM_PHYS_REGS; r = r + 1) begin
                in_rrat = 1'b0;
                for (arch_idx = 0; arch_idx < `NUM_ARCH_REGS; arch_idx = arch_idx + 1) begin
                    if (rrat_mappings[arch_idx * `PR_WIDTH +: `PR_WIDTH] == r[5:0]) begin
                        in_rrat = 1'b1;
                    end
                end
                if (!in_rrat && (free_idx < FL_CAPACITY)) begin
                    fl_queue[free_idx] <= r[5:0];
                    free_idx = free_idx + 1;
                end
            end
            head  <= 5'd0;
            tail  <= 5'd0;
            count <= FL_CAPACITY[5:0];
        end else begin
            case ({alloc_en && !fl_empty, free_en && (free_pr != `ZERO_PR)})
                2'b10: begin
                    // Allocate only
                    head  <= head + 5'd1;
                    count <= count - 6'd1;
                end
                2'b01: begin
                    // Free only
                    fl_queue[tail] <= free_pr;
                    tail           <= tail + 5'd1;
                    count          <= count + 6'd1;
                end
                2'b11: begin
                    // Simultaneous allocate and free
                    head           <= head + 5'd1;
                    fl_queue[tail] <= free_pr;
                    tail           <= tail + 5'd1;
                    // count remains unchanged
                end
                default: ; // Idle
            endcase
        end
    end

endmodule
