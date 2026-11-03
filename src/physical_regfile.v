// ============================================================================
// File: physical_regfile.v
// Description: Unified Physical Register File (PRF) for RV64IM OoO Processor.
//              64 physical registers, each 64-bit wide.
//              Physical register p0 is hardwired to 64'd0.
//              2 asynchronous read ports with write-forwarding;
//              1 synchronous write port from Common Data Bus (CDB).
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module physical_regfile (
    input  wire                   clk,
    input  wire                   rst,

    // Read Port 1
    input  wire [`PR_WIDTH-1:0]   read_pr1,
    output wire [`XLEN-1:0]       read_data1,

    // Read Port 2
    input  wire [`PR_WIDTH-1:0]   read_pr2,
    output wire [`XLEN-1:0]       read_data2,

    // CDB Write Port
    input  wire                   cdb_valid,
    input  wire [`PR_WIDTH-1:0]   cdb_pr,
    input  wire [`XLEN-1:0]       cdb_data
);

    reg [`XLEN-1:0] prf [0:`NUM_PHYS_REGS-1];

    // Read Port 1 with synchronous write forwarding & p0 hardwired to zero
    assign read_data1 = (read_pr1 == `ZERO_PR) ? 64'd0 :
                        (cdb_valid && (cdb_pr == read_pr1)) ? cdb_data :
                        prf[read_pr1];

    // Read Port 2 with synchronous write forwarding & p0 hardwired to zero
    assign read_data2 = (read_pr2 == `ZERO_PR) ? 64'd0 :
                        (cdb_valid && (cdb_pr == read_pr2)) ? cdb_data :
                        prf[read_pr2];

    // Synchronous PRF Write
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < `NUM_PHYS_REGS; i = i + 1) begin
                prf[i] <= 64'd0;
            end
        end else if (cdb_valid && (cdb_pr != `ZERO_PR)) begin
            prf[cdb_pr] <= cdb_data;
        end
    end

endmodule
