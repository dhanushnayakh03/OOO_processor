// ============================================================================
// File: rob.v
// Description: Reorder Buffer (ROB) for RV64IM OoO Processor.
//              32-entry circular FIFO.
//              Allocates in-order at Dispatch, marks completion out-of-order,
//              retires in-order at Head.
//              Supports branch misprediction recovery flush and WFI/Halt tracking.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module rob (
    input  wire                   clk,
    input  wire                   rst,

    // Pipeline Recovery
    input  wire                   recover_en,

    // Allocation Interface (Dispatch Stage)
    input  wire                   alloc_en,
    input  wire [`AR_WIDTH-1:0]   alloc_arch_dest,
    input  wire [`PR_WIDTH-1:0]   alloc_tag_new,
    input  wire [`PR_WIDTH-1:0]   alloc_tag_old,
    input  wire                   alloc_is_store,
    input  wire [`SQ_WIDTH-1:0]   alloc_sq_idx,
    input  wire [`XLEN-1:0]       alloc_pc,
    input  wire [`XLEN-1:0]       alloc_npc,
    input  wire                   alloc_pred_taken,
    input  wire [`XLEN-1:0]       alloc_pred_target,
    input  wire                   alloc_halt,
    output wire [`ROB_WIDTH-1:0]  alloc_rob_idx,
    output wire                   rob_full,

    // Complete Interface (CDB / Complete Stage)
    input  wire                   complete_valid,
    input  wire [`ROB_WIDTH-1:0]  complete_rob_idx,
    input  wire                   complete_branch_en,
    input  wire                   complete_mispredicted,
    input  wire [`XLEN-1:0]       complete_correct_target,

    // Retire Interface (Retire Stage)
    output wire                   retire_ready,
    output wire [`ROB_WIDTH-1:0]  retire_rob_idx,
    output wire [`AR_WIDTH-1:0]   retire_arch_dest,
    output wire [`PR_WIDTH-1:0]   retire_tag_new,
    output wire [`PR_WIDTH-1:0]   retire_tag_old,
    output wire                   retire_is_store,
    output wire [`SQ_WIDTH-1:0]   retire_sq_idx,
    output wire [`XLEN-1:0]       retire_pc,
    output wire [`XLEN-1:0]       retire_npc,
    output wire                   retire_pred_taken,
    output wire [`XLEN-1:0]       retire_pred_target,
    output wire                   retire_mispredicted,
    output wire [`XLEN-1:0]       retire_correct_target,
    output wire                   retire_halt,
    input  wire                   retire_ack
);

    // Parallel flat arrays for ROB table (Verilog-2001 compatible)
    reg                   rob_valid          [0:`ROB_ENTRIES-1];
    reg                   rob_completed      [0:`ROB_ENTRIES-1];
    reg [`AR_WIDTH-1:0]   rob_arch_dest      [0:`ROB_ENTRIES-1];
    reg [`PR_WIDTH-1:0]   rob_tag_new        [0:`ROB_ENTRIES-1];
    reg [`PR_WIDTH-1:0]   rob_tag_old        [0:`ROB_ENTRIES-1];
    reg                   rob_is_store       [0:`ROB_ENTRIES-1];
    reg [`SQ_WIDTH-1:0]   rob_sq_idx         [0:`ROB_ENTRIES-1];
    reg [`XLEN-1:0]       rob_pc             [0:`ROB_ENTRIES-1];
    reg [`XLEN-1:0]       rob_npc            [0:`ROB_ENTRIES-1];
    reg                   rob_pred_taken     [0:`ROB_ENTRIES-1];
    reg [`XLEN-1:0]       rob_pred_target    [0:`ROB_ENTRIES-1];
    reg                   rob_mispredicted   [0:`ROB_ENTRIES-1];
    reg [`XLEN-1:0]       rob_correct_target [0:`ROB_ENTRIES-1];
    reg                   rob_halt           [0:`ROB_ENTRIES-1];

    reg [`ROB_WIDTH-1:0]  head;
    reg [`ROB_WIDTH-1:0]  tail;
    reg [`ROB_WIDTH:0]    count;

    assign rob_full      = (count == `ROB_ENTRIES);
    assign alloc_rob_idx = tail;

    // Retire outputs from head entry
    assign retire_ready           = rob_valid[head] && rob_completed[head];
    assign retire_rob_idx         = head;
    assign retire_arch_dest       = rob_arch_dest[head];
    assign retire_tag_new         = rob_tag_new[head];
    assign retire_tag_old         = rob_tag_old[head];
    assign retire_is_store        = rob_is_store[head];
    assign retire_sq_idx          = rob_sq_idx[head];
    assign retire_pc              = rob_pc[head];
    assign retire_npc             = rob_npc[head];
    assign retire_pred_taken      = rob_pred_taken[head];
    assign retire_pred_target     = rob_pred_target[head];
    assign retire_mispredicted    = rob_mispredicted[head];
    assign retire_correct_target  = rob_correct_target[head];
    assign retire_halt            = rob_halt[head];

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            for (i = 0; i < `ROB_ENTRIES; i = i + 1) begin
                rob_valid[i]          <= 1'b0;
                rob_completed[i]      <= 1'b0;
                rob_arch_dest[i]      <= `AR_WIDTH'd0;
                rob_tag_new[i]        <= `ZERO_PR;
                rob_tag_old[i]        <= `ZERO_PR;
                rob_is_store[i]       <= 1'b0;
                rob_sq_idx[i]         <= `SQ_WIDTH'd0;
                rob_pc[i]             <= 64'd0;
                rob_npc[i]            <= 64'd0;
                rob_pred_taken[i]     <= 1'b0;
                rob_pred_target[i]    <= 64'd0;
                rob_mispredicted[i]   <= 1'b0;
                rob_correct_target[i] <= 64'd0;
                rob_halt[i]           <= 1'b0;
            end
            head  <= `ROB_WIDTH'd0;
            tail  <= `ROB_WIDTH'd0;
            count <= {(`ROB_WIDTH+1){1'b0}};
        end else begin
            // 1. Completion update (out-of-order)
            if (complete_valid) begin
                rob_completed[complete_rob_idx] <= 1'b1;
                if (complete_branch_en) begin
                    rob_mispredicted[complete_rob_idx]   <= complete_mispredicted;
                    rob_correct_target[complete_rob_idx] <= complete_correct_target;
                end
            end

            // 2. Allocation at tail (in-order)
            if (alloc_en && !rob_full) begin
                rob_valid[tail]          <= 1'b1;
                rob_completed[tail]      <= 1'b0;
                rob_arch_dest[tail]      <= alloc_arch_dest;
                rob_tag_new[tail]        <= alloc_tag_new;
                rob_tag_old[tail]        <= alloc_tag_old;
                rob_is_store[tail]       <= alloc_is_store;
                rob_sq_idx[tail]         <= alloc_sq_idx;
                rob_pc[tail]             <= alloc_pc;
                rob_npc[tail]            <= alloc_npc;
                rob_pred_taken[tail]     <= alloc_pred_taken;
                rob_pred_target[tail]    <= alloc_pred_target;
                rob_mispredicted[tail]   <= 1'b0;
                rob_correct_target[tail] <= 64'd0;
                rob_halt[tail]           <= alloc_halt;
                tail                     <= tail + 5'd1;
            end

            // 3. Retirement at head (in-order)
            if (retire_ready && retire_ack) begin
                rob_valid[head]     <= 1'b0;
                rob_completed[head] <= 1'b0;
                head                <= head + 5'd1;
            end

            // 4. Entry count management
            case ({alloc_en && !rob_full, retire_ready && retire_ack})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ; // 2'b00 or 2'b11: count unchanged
            endcase
        end
    end

endmodule
