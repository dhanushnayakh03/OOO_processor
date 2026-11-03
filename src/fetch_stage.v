// ============================================================================
// File: fetch_stage.v
// Description: Instruction Fetch Stage for the Scalar RV64IM OoO Processor.
//              Manages PC generation, integrates Branch Predictor target mux,
//              handles pipeline stalls and misprediction recovery flushes.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module fetch_stage (
    input  wire                   clk,
    input  wire                   rst,

    // Pipeline Control
    input  wire                   stall,          // Dispatch structural stall
    input  wire                   recover_en,     // Branch misprediction recovery
    input  wire [`XLEN-1:0]       recover_target, // Recovery PC target

    // Branch Predictor Interface
    input  wire                   pred_taken,
    input  wire [`XLEN-1:0]       pred_target,

    // Instruction Memory Interface
    output wire [`XLEN-1:0]       imem_addr,
    input  wire [`ILEN-1:0]       imem_inst,

    // IF/ID Pipeline Register Outputs
    output reg                    if_id_valid,
    output reg  [`XLEN-1:0]       if_id_pc,
    output reg  [`XLEN-1:0]       if_id_npc,
    output reg  [`ILEN-1:0]       if_id_inst,
    output reg                    if_id_pred_taken,
    output reg  [`XLEN-1:0]       if_id_pred_target
);

    reg [`XLEN-1:0] pc;
    wire [`XLEN-1:0] pc_plus_4 = pc + 64'd4;

    assign imem_addr = pc;

    // Next PC Selection Logic
    reg [`XLEN-1:0] next_pc;
    always @(*) begin
        if (recover_en) begin
            next_pc = recover_target;
        end else if (stall) begin
            next_pc = pc;
        end else if (pred_taken) begin
            next_pc = pred_target;
        end else begin
            next_pc = pc_plus_4;
        end
    end

    // PC Update
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 64'd0;
        end else begin
            pc <= next_pc;
        end
    end

    // IF/ID Pipeline Register
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_valid       <= 1'b0;
            if_id_pc          <= 64'd0;
            if_id_npc         <= 64'd0;
            if_id_inst        <= `NOP_INST;
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 64'd0;
        end else if (recover_en) begin
            // Flush IF/ID on branch misprediction
            if_id_valid       <= 1'b0;
            if_id_pc          <= 64'd0;
            if_id_npc         <= 64'd0;
            if_id_inst        <= `NOP_INST;
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 64'd0;
        end else if (!stall) begin
            // Normal fetch latch
            if_id_valid       <= 1'b1;
            if_id_pc          <= pc;
            if_id_npc         <= pc_plus_4;
            if_id_inst        <= imem_inst;
            if_id_pred_taken  <= pred_taken;
            if_id_pred_target <= pred_target;
        end
        // If stall == 1, hold previous IF/ID contents
    end

endmodule
