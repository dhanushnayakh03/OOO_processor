// ============================================================================
// File: fu_load.v
// Description: Load Functional Unit for Scalar RV64IM OoO Processor.
//              Calculates effective address, queries Store Queue for forwarding,
//              or loads directly from Data Memory on cache/SQ miss.
//              Performs byte alignment and sign/zero-extension for LB, LH, LW, LD, LBU, LHU, LWU.
//              Holds result in output FU/C register until granted by CDB arbiter.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module fu_load (
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
    input  wire [`XLEN-1:0]       ex_imm,
    input  wire [`SQ_WIDTH-1:0]   ex_sq_idx,

    // Store Queue Query & Forwarding Interface
    output wire                   sq_query_en,
    output wire [`SQ_WIDTH-1:0]   sq_load_sq_tail,
    output wire [`XLEN-1:0]       sq_load_addr,
    output wire [7:0]             sq_load_byte_en,
    input  wire                   sq_forward_valid,
    input  wire [`XLEN-1:0]       sq_forward_data,
    input  wire                   sq_load_hazard,

    // Data Memory Read Interface
    output wire                   dmem_ren,
    output wire [`XLEN-1:0]       dmem_raddr,
    input  wire [`XLEN-1:0]       dmem_rdata,

    // Readiness to Reservation Station
    output wire                   fu_load_ready,

    // CDB Arbiter Interface (FU/C Output Pipeline Register)
    input  wire                   load_grant,
    output reg                    fu_c_valid,
    output reg  [`ROB_WIDTH-1:0]  fu_c_rob_idx,
    output reg  [`PR_WIDTH-1:0]   fu_c_dest_pr,
    output reg  [`XLEN-1:0]       fu_c_data
);

    wire is_load_active = ex_valid && (ex_fu == `FU_LOAD);

    // ------------------------------------------------------------------------
    // Effective Address & Byte Mask Calculation
    // ------------------------------------------------------------------------
    wire [`XLEN-1:0] effective_addr = ex_op_a + ex_imm;
    wire [2:0]       byte_offset    = effective_addr[2:0];
    wire [2:0]       funct3         = ex_op[2:0];

    reg [7:0] load_mask;
    always @(*) begin
        case (funct3)
            `FUNCT3_LB, `FUNCT3_LBU: load_mask = 8'b00000001 << byte_offset;
            `FUNCT3_LH, `FUNCT3_LHU: load_mask = 8'b00000011 << {byte_offset[2:1], 1'b0};
            `FUNCT3_LW, `FUNCT3_LWU: load_mask = byte_offset[2] ? 8'b11110000 : 8'b00001111;
            `FUNCT3_LD:              load_mask = 8'b11111111;
            default:                 load_mask = 8'b11111111;
        endcase
    end

    // SQ Query outputs
    assign sq_query_en     = is_load_active;
    assign sq_load_sq_tail = ex_sq_idx;
    assign sq_load_addr    = effective_addr;
    assign sq_load_byte_en = load_mask;

    // Data Memory outputs (active when load misses in SQ and has no hazard)
    assign dmem_ren   = is_load_active && !sq_forward_valid && !sq_load_hazard;
    assign dmem_raddr = effective_addr;

    // ------------------------------------------------------------------------
    // Format Function for Byte / Half / Word / Doubleword
    // ------------------------------------------------------------------------
    function [`XLEN-1:0] format_load_val;
        input [2:0]       f3;
        input [2:0]       offset;
        input [`XLEN-1:0] raw;
        reg [7:0]         b;
        reg [15:0]        h;
        reg [31:0]        w;
        begin
            b = raw >> (offset * 8);
            h = raw >> ({offset[2:1], 1'b0} * 8);
            w = offset[2] ? raw[63:32] : raw[31:0];
            case (f3)
                `FUNCT3_LB:  format_load_val = {{56{b[7]}}, b};
                `FUNCT3_LBU: format_load_val = {56'd0, b};
                `FUNCT3_LH:  format_load_val = {{48{h[15]}}, h};
                `FUNCT3_LHU: format_load_val = {48'd0, h};
                `FUNCT3_LW:  format_load_val = {{32{w[31]}}, w};
                `FUNCT3_LWU: format_load_val = {32'd0, w};
                `FUNCT3_LD:  format_load_val = raw;
                default:     format_load_val = raw;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Synchronous BRAM Pipeline Register & Arbiter Interface
    // ------------------------------------------------------------------------
    reg                   bram_pending;
    reg [`ROB_WIDTH-1:0]  bram_rob_idx;
    reg [`PR_WIDTH-1:0]   bram_dest_pr;
    reg [2:0]             bram_offset;
    reg [2:0]             bram_funct3;

    assign fu_load_ready = !bram_pending && (!fu_c_valid || load_grant);

    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            fu_c_valid   <= 1'b0;
            fu_c_rob_idx <= `ROB_WIDTH'd0;
            fu_c_dest_pr <= `ZERO_PR;
            fu_c_data    <= 64'd0;
            bram_pending <= 1'b0;
            bram_rob_idx <= `ROB_WIDTH'd0;
            bram_dest_pr <= `ZERO_PR;
            bram_offset  <= 3'd0;
            bram_funct3  <= 3'd0;
        end else begin
            // 1. Clear output buffer when granted by CDB
            if (load_grant) begin
                fu_c_valid <= 1'b0;
            end

            // 2. Stage 2: Synchronous BRAM read response arrives
            if (bram_pending) begin
                fu_c_valid   <= 1'b1;
                fu_c_rob_idx <= bram_rob_idx;
                fu_c_dest_pr <= bram_dest_pr;
                fu_c_data    <= format_load_val(bram_funct3, bram_offset, dmem_rdata);
                bram_pending <= 1'b0;
            end

            // 3. Stage 1: Load issued from Issue Stage
            if (is_load_active) begin
                if (sq_forward_valid) begin
                    // Store Queue forward hit (immediate)
                    fu_c_valid   <= 1'b1;
                    fu_c_rob_idx <= ex_rob_idx;
                    fu_c_dest_pr <= ex_dest_pr;
                    fu_c_data    <= format_load_val(funct3, byte_offset, sq_forward_data);
                end else if (!sq_load_hazard) begin
                    // BRAM read initiated; response arrives next cycle
                    bram_pending <= 1'b1;
                    bram_rob_idx <= ex_rob_idx;
                    bram_dest_pr <= ex_dest_pr;
                    bram_offset  <= byte_offset;
                    bram_funct3  <= funct3;
                end
            end
        end
    end

endmodule
