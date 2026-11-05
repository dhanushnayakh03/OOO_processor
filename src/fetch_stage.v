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
    output wire                   imem_en,
    output wire [`XLEN-1:0]       imem_addr,
    input  wire [`ILEN-1:0]       imem_inst,

    // IF/ID Pipeline Register Outputs
    output reg                    if_id_valid,
    output reg  [`XLEN-1:0]       if_id_pc,
    output reg  [`XLEN-1:0]       if_id_npc,
    output wire [`ILEN-1:0]       if_id_inst,
    output reg                    if_id_pred_taken,
    output reg  [`XLEN-1:0]       if_id_pred_target
);

    reg [`XLEN-1:0] pc;
    wire [`XLEN-1:0] pc_plus_4 = pc + 64'd4;

    // Immediately present recover_target to BRAM on misprediction
    assign imem_addr  = recover_en ? recover_target : pc;
    assign imem_en    = !stall || recover_en;
    assign if_id_inst = imem_inst;

    // Next sequential or predicted PC for IF1
    wire [`XLEN-1:0] next_fetch_pc = pred_taken ? pred_target : pc_plus_4;

    always @(posedge clk) begin
        if (rst) begin
            pc                <= 64'd0;
            if_id_valid       <= 1'b0;
            if_id_pc          <= 64'd0;
            if_id_npc         <= 64'd0;
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 64'd0;
        end else if (recover_en) begin
            // Recovery redirection: BRAM was presented with recover_target this cycle.
            // Advance PC to recover_target + 4 for the next fetch cycle.
            // Target instruction is available at BRAM output in the next cycle.
            pc                <= recover_target + 64'd4;
            if_id_valid       <= 1'b1;
            if_id_pc          <= recover_target;
            if_id_npc         <= recover_target + 64'd4;
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 64'd0;
        end else if (!stall) begin
            // Steady-state 1.0 IPC streaming
            if_id_valid       <= 1'b1;
            if_id_pc          <= pc;
            if_id_npc         <= pc_plus_4;
            if_id_pred_taken  <= pred_taken;
            if_id_pred_target <= pred_target;

            pc                <= next_fetch_pc;
        end
        // If stall == 1:
        // imem_en is 0: BRAM output is held unchanged by hardware clock enable.
        // pc and if_id registers are held unchanged.
    end

endmodule
