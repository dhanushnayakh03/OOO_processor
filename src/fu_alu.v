// ============================================================================
// File: fu_alu.v
// Description: Arithmetic Logic Unit (ALU) for Scalar RV64IM OoO Processor.
//              Executes 64-bit and 32-bit (W-type) integer arithmetic/logic.
//              Calculates effective address and byte alignment for Store instructions.
//              Holds result in output FU/C register until granted by CDB arbiter.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module fu_alu (
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
    input  wire [`XLEN-1:0]       ex_store_data,
    input  wire [`XLEN-1:0]       ex_imm,
    input  wire [`SQ_WIDTH-1:0]   ex_sq_idx,
    input  wire                   ex_is_store,

    // Store Queue Update Interface
    output reg                    sq_update_en,
    output reg  [`SQ_WIDTH-1:0]   sq_update_idx,
    output reg  [`XLEN-1:0]       sq_update_addr,
    output reg  [7:0]             sq_update_byte_en,
    output reg                    sq_update_data_en,
    output reg  [`XLEN-1:0]       sq_update_data,

    // CDB Arbiter Interface (FU/C Output Pipeline Register)
    input  wire                   alu_grant,
    output reg                    fu_c_valid,
    output reg  [`ROB_WIDTH-1:0]  fu_c_rob_idx,
    output reg  [`PR_WIDTH-1:0]   fu_c_dest_pr,
    output reg  [`XLEN-1:0]       fu_c_data
);

    wire is_alu_active = ex_valid && (ex_fu == `FU_ALU);

    // ------------------------------------------------------------------------
    // Store Address Calculation & Byte Alignment
    // ------------------------------------------------------------------------
    wire [`XLEN-1:0] store_effective_addr = ex_op_a + ex_imm;
    wire [2:0]       byte_offset          = store_effective_addr[2:0];
    reg  [7:0]       computed_byte_en;
    reg  [`XLEN-1:0] computed_store_data;

    always @(*) begin
        computed_byte_en    = 8'd0;
        computed_store_data = 64'd0;
        if (ex_is_store) begin
            case (ex_op[1:0])
                `FUNCT3_SB: begin
                    computed_byte_en    = 8'b00000001 << byte_offset;
                    computed_store_data = {56'd0, ex_store_data[7:0]} << (byte_offset * 8);
                end
                `FUNCT3_SH: begin
                    computed_byte_en    = 8'b00000011 << {byte_offset[2:1], 1'b0};
                    computed_store_data = {48'd0, ex_store_data[15:0]} << ({byte_offset[2:1], 1'b0} * 8);
                end
                `FUNCT3_SW: begin
                    computed_byte_en    = byte_offset[2] ? 8'b11110000 : 8'b00001111;
                    computed_store_data = byte_offset[2] ? {ex_store_data[31:0], 32'd0} : {32'd0, ex_store_data[31:0]};
                end
                `FUNCT3_SD: begin
                    computed_byte_en    = 8'b11111111;
                    computed_store_data = ex_store_data;
                end
                default: ;
            endcase
        end
    end

    // Sequential Update to Store Queue
    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            sq_update_en      <= 1'b0;
            sq_update_idx     <= `SQ_WIDTH'd0;
            sq_update_addr    <= 64'd0;
            sq_update_byte_en <= 8'd0;
            sq_update_data_en <= 1'b0;
            sq_update_data    <= 64'd0;
        end else if (is_alu_active && ex_is_store) begin
            sq_update_en      <= 1'b1;
            sq_update_idx     <= ex_sq_idx;
            sq_update_addr    <= store_effective_addr;
            sq_update_byte_en <= computed_byte_en;
            sq_update_data_en <= 1'b1;
            sq_update_data    <= computed_store_data;
        end else begin
            sq_update_en      <= 1'b0;
            sq_update_data_en <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Arithmetic & Logic Computation
    // ------------------------------------------------------------------------
    reg [`XLEN-1:0] alu_result;
    wire [31:0]     op_a_32 = ex_op_a[31:0];
    wire [31:0]     op_b_32 = ex_op_b[31:0];
    wire [4:0]      shamt_w = ex_op_b[4:0];
    wire [5:0]      shamt   = ex_op_b[5:0];

    wire [31:0] res_addw = op_a_32 + op_b_32;
    wire [31:0] res_subw = op_a_32 - op_b_32;
    wire [31:0] res_sllw = op_a_32 << shamt_w;
    wire [31:0] res_srlw = op_a_32 >> shamt_w;
    wire [31:0] res_sraw = $signed(op_a_32) >>> shamt_w;

    always @(*) begin
        alu_result = 64'd0;
        case (ex_op)
            `ALU_ADD:    alu_result = ex_op_a + ex_op_b;
            `ALU_SUB:    alu_result = ex_op_a - ex_op_b;
            `ALU_SLL:    alu_result = ex_op_a << shamt;
            `ALU_SLT:    alu_result = ($signed(ex_op_a) < $signed(ex_op_b)) ? 64'd1 : 64'd0;
            `ALU_SLTU:   alu_result = (ex_op_a < ex_op_b) ? 64'd1 : 64'd0;
            `ALU_XOR:    alu_result = ex_op_a ^ ex_op_b;
            `ALU_SRL:    alu_result = ex_op_a >> shamt;
            `ALU_SRA:    alu_result = $signed(ex_op_a) >>> shamt;
            `ALU_OR:     alu_result = ex_op_a | ex_op_b;
            `ALU_AND:    alu_result = ex_op_a & ex_op_b;

            // 32-bit Word Operations (sign-extended to 64 bits)
            `ALU_ADDW:   alu_result = {{32{res_addw[31]}}, res_addw};
            `ALU_SUBW:   alu_result = {{32{res_subw[31]}}, res_subw};
            `ALU_SLLW:   alu_result = {{32{res_sllw[31]}}, res_sllw};
            `ALU_SRLW:   alu_result = {{32{res_srlw[31]}}, res_srlw};
            `ALU_SRAW:   alu_result = {{32{res_sraw[31]}}, res_sraw};

            `ALU_PASS_B: alu_result = ex_op_b;

            default:     alu_result = ex_is_store ? 64'd0 : (ex_op_a + ex_op_b);
        endcase
    end

    // ------------------------------------------------------------------------
    // FU/C Output Pipeline Register
    // ------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            fu_c_valid   <= 1'b0;
            fu_c_rob_idx <= `ROB_WIDTH'd0;
            fu_c_dest_pr <= `ZERO_PR;
            fu_c_data    <= 64'd0;
        end else begin
            if (alu_grant) begin
                fu_c_valid <= 1'b0;
            end

            if (is_alu_active) begin
                fu_c_valid   <= 1'b1;
                fu_c_rob_idx <= ex_rob_idx;
                fu_c_dest_pr <= ex_dest_pr;
                fu_c_data    <= alu_result;
            end
        end
    end

endmodule
