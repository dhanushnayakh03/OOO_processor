// ============================================================================
// File: arch_map_table.v
// Description: Retirement Register Alias Table (RRAT / Architectural Map Table).
//              Maintains committed architectural-to-physical register mappings.
//              Used for precise state rollback upon branch misprediction recovery.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module arch_map_table (
    input  wire                                  clk,
    input  wire                                  rst,

    // Commit interface from Retire Stage
    input  wire                                  retire_en,
    input  wire [`AR_WIDTH-1:0]                  retire_arch_dest,
    input  wire [`PR_WIDTH-1:0]                  retire_tag_new,

    // Export entire architectural state for recovery (32 * 6 bits = 192 bits)
    output wire [`NUM_ARCH_REGS*`PR_WIDTH-1:0]   rrat_mappings
);

    reg [`PR_WIDTH-1:0] rrat [0:`NUM_ARCH_REGS-1];

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < `NUM_ARCH_REGS; i = i + 1) begin
                rrat[i] <= i[`PR_WIDTH-1:0]; // Initial identity mapping x0->p0, x1->p1, ...
            end
        end else if (retire_en && (retire_arch_dest != `AR_WIDTH'd0)) begin
            rrat[retire_arch_dest] <= retire_tag_new;
        end
    end

    // Pack into flat vector for recovery
    genvar g;
    generate
        for (g = 0; g < `NUM_ARCH_REGS; g = g + 1) begin : gen_rrat_pack
            assign rrat_mappings[g * `PR_WIDTH +: `PR_WIDTH] = rrat[g];
        end
    endgenerate

endmodule
