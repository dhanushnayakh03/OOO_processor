// ============================================================================
// File: memory.v
// Description: Dual-Port Unified Memory for Scalar RV64IM OoO Processor.
//              Port A: 32-bit Instruction Fetch (Read-only)
//              Port B: 64-bit Byte-Masked Data Memory (Loads & Stores)
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module memory #(
    parameter MEM_SIZE_BYTES = 32768,             // 32 KB (Address width 12 bits, optimal for BRAM BWWE)
    parameter MEM_DEPTH      = MEM_SIZE_BYTES / 8 // 4096 doublewords (64-bit)
)(
    input  wire                   clk,
    input  wire                   rst,

    // Port A: Instruction Fetch Interface (Read-only)
    input  wire                   imem_en,
    input  wire [`XLEN-1:0]       imem_addr,
    output wire [`ILEN-1:0]       imem_rdata,

    // Port B: Data Memory Interface (Read/Write)
    input  wire                   dmem_en,
    input  wire                   dmem_wen,
    input  wire [`XLEN-1:0]       dmem_addr,
    input  wire [`XLEN-1:0]       dmem_wdata,
    input  wire [7:0]             dmem_byte_en,
    output reg  [`XLEN-1:0]       dmem_rdata
);

    // 64-bit wide unified memory array (inferred as hardware Block RAM)
    // 4096 depth has address width 12, allowing native hardware Byte-Wide Write Enable (BWWE)
    (* ram_style = "block", ram_decomp = "power" *) reg [63:0] mem_array [0:MEM_DEPTH-1];

    // Word and doubleword address decoding (12-bit index for 4096 doublewords)
    wire [11:0] i_index = imem_addr[14:3];
    wire [11:0] d_index = dmem_addr[14:3];

    // ------------------------------------------------------------------------
    // Port A: Instruction Fetch (Synchronous 1-cycle BRAM read with Clock Enable)
    // ------------------------------------------------------------------------
    reg [63:0] i_line;
    reg        i_word_sel;

    always @(posedge clk) begin
        if (imem_en) begin
            i_line     <= mem_array[i_index];
            i_word_sel <= imem_addr[2];
        end
    end

    assign imem_rdata = i_word_sel ? i_line[63:32] : i_line[31:0];

    // ------------------------------------------------------------------------
    // Port B: Data Memory (Synchronous Read & Byte-Masked Write)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (dmem_en) begin
            if (dmem_wen) begin
                if (dmem_byte_en[0]) mem_array[d_index][ 7: 0] <= dmem_wdata[ 7: 0];
                if (dmem_byte_en[1]) mem_array[d_index][15: 8] <= dmem_wdata[15: 8];
                if (dmem_byte_en[2]) mem_array[d_index][23:16] <= dmem_wdata[23:16];
                if (dmem_byte_en[3]) mem_array[d_index][31:24] <= dmem_wdata[31:24];
                if (dmem_byte_en[4]) mem_array[d_index][39:32] <= dmem_wdata[39:32];
                if (dmem_byte_en[5]) mem_array[d_index][47:40] <= dmem_wdata[47:40];
                if (dmem_byte_en[6]) mem_array[d_index][55:48] <= dmem_wdata[55:48];
                if (dmem_byte_en[7]) mem_array[d_index][63:56] <= dmem_wdata[63:56];
            end else begin
                dmem_rdata <= mem_array[d_index];
            end
        end
    end

endmodule
