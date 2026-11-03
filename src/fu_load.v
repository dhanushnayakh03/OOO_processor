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

    // Data Memory outputs (active if load does not hit in SQ and no hazard)
    assign dmem_ren   = is_load_active && !sq_forward_valid && !sq_load_hazard;
    assign dmem_raddr = effective_addr;

    // ------------------------------------------------------------------------
    // Raw Data Selection (SQ Forwarded Data or Memory Data)
    // ------------------------------------------------------------------------
    wire [`XLEN-1:0] raw_data = sq_forward_valid ? sq_forward_data : dmem_rdata;

    // Extract properly aligned and extended load value
    reg [`XLEN-1:0] formatted_data;
    wire [7:0]      raw_byte = raw_data >> (byte_offset * 8);
    wire [15:0]     raw_half = raw_data >> ({byte_offset[2:1], 1'b0} * 8);
    wire [31:0]     raw_word = byte_offset[2] ? raw_data[63:32] : raw_data[31:0];

    always @(*) begin
        case (funct3)
            `FUNCT3_LB:  formatted_data = {{56{raw_byte[7]}}, raw_byte};
            `FUNCT3_LBU: formatted_data = {56'd0, raw_byte};
            `FUNCT3_LH:  formatted_data = {{48{raw_half[15]}}, raw_half};
            `FUNCT3_LHU: formatted_data = {48'd0, raw_half};
            `FUNCT3_LW:  formatted_data = {{32{raw_word[31]}}, raw_word};
            `FUNCT3_LWU: formatted_data = {32'd0, raw_word};
            `FUNCT3_LD:  formatted_data = raw_data;
            default:     formatted_data = raw_data;
        endcase
    end

    // ------------------------------------------------------------------------
    // FU/C Output Pipeline Register
    // ------------------------------------------------------------------------
    wire load_success = is_load_active && !sq_load_hazard;

    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            fu_c_valid   <= 1'b0;
            fu_c_rob_idx <= `ROB_WIDTH'd0;
            fu_c_dest_pr <= `ZERO_PR;
            fu_c_data    <= 64'd0;
        end else begin
            if (load_grant) begin
                fu_c_valid <= 1'b0;
            end

            if (load_success) begin
                fu_c_valid   <= 1'b1;
                fu_c_rob_idx <= ex_rob_idx;
                fu_c_dest_pr <= ex_dest_pr;
                fu_c_data    <= formatted_data;
            end
        end
    end

endmodule
