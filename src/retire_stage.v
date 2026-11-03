// ============================================================================
// File: retire_stage.v
// Description: In-Order Retirement Stage for Scalar RV64IM OoO Processor.
//              Commits architectural state at ROB head.
//              Updates Architectural Map Table (RRAT).
//              Reclaims superseded physical registers (Told) to Free List.
//              Triggers in-order Store Queue commits to Data Memory.
//              Initiates precise recovery upon branch misprediction retirement.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module retire_stage (
    // ROB Head Interface
    input  wire                   rob_retire_ready,
    input  wire [`ROB_WIDTH-1:0]  rob_retire_rob_idx,
    input  wire [`AR_WIDTH-1:0]   rob_retire_arch_dest,
    input  wire [`PR_WIDTH-1:0]   rob_retire_tag_new,
    input  wire [`PR_WIDTH-1:0]   rob_retire_tag_old,
    input  wire                   rob_retire_is_store,
    input  wire [`SQ_WIDTH-1:0]   rob_retire_sq_idx,
    input  wire [`XLEN-1:0]       rob_retire_pc,
    input  wire [`XLEN-1:0]       rob_retire_npc,
    input  wire                   rob_retire_pred_taken,
    input  wire [`XLEN-1:0]       rob_retire_pred_target,
    input  wire                   rob_retire_mispredicted,
    input  wire [`XLEN-1:0]       rob_retire_correct_target,
    input  wire                   rob_retire_halt,
    output wire                   rob_retire_ack,

    // RRAT Commit Interface
    output wire                   rrat_commit_en,
    output wire [`AR_WIDTH-1:0]   rrat_commit_arch_dest,
    output wire [`PR_WIDTH-1:0]   rrat_commit_tag_new,

    // Free List Reclaim Interface
    output wire                   fl_free_en,
    output wire [`PR_WIDTH-1:0]   fl_free_pr,

    // Store Queue Memory Commit Interface
    output wire                   sq_commit_en,
    output wire [`SQ_WIDTH-1:0]   sq_commit_idx,

    // Branch Misprediction Pipeline Recovery Interface
    output wire                   recover_en,
    output wire [`XLEN-1:0]       recover_target,

    // Processor Halt Output
    output wire                   halt,

    // Retire Monitor / Debug Signals
    output wire                   retire_valid,
    output wire [`XLEN-1:0]       retire_pc,
    output wire [`AR_WIDTH-1:0]   retire_arch_dest,
    output wire [`PR_WIDTH-1:0]   retire_tag_new,
    output wire [`PR_WIDTH-1:0]   retire_tag_old,
    output wire                   retire_is_mispred
);

    assign retire_valid      = rob_retire_ready;
    assign rob_retire_ack    = rob_retire_ready;

    // RRAT Commit
    assign rrat_commit_en        = rob_retire_ready && (rob_retire_arch_dest != `AR_WIDTH'd0);
    assign rrat_commit_arch_dest = rob_retire_arch_dest;
    assign rrat_commit_tag_new   = rob_retire_tag_new;

    // Free List Reclaim (superseded physical register Told)
    assign fl_free_en = rob_retire_ready && (rob_retire_tag_old != `ZERO_PR);
    assign fl_free_pr = rob_retire_tag_old;

    // Store Queue Memory Commit
    assign sq_commit_en  = rob_retire_ready && rob_retire_is_store;
    assign sq_commit_idx = rob_retire_sq_idx;

    // Branch Misprediction Recovery
    assign recover_en     = rob_retire_ready && rob_retire_mispredicted;
    assign recover_target = rob_retire_correct_target;

    // Halt
    assign halt = rob_retire_ready && rob_retire_halt;

    // Retire Monitor
    assign retire_pc         = rob_retire_pc;
    assign retire_arch_dest  = rob_retire_arch_dest;
    assign retire_tag_new    = rob_retire_tag_new;
    assign retire_tag_old    = rob_retire_tag_old;
    assign retire_is_mispred = rob_retire_mispredicted;

endmodule
