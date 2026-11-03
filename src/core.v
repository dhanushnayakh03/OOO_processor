// ============================================================================
// File: core.v
// Description: Top-Level RV64IM Scalar Out-of-Order (OoO) Processor Core.
//              Features:
//              - Parameterized Dynamic 2-bit Saturating Counter Branch Predictor
//              - R10K Physical Register File (PRF) & Register Renaming
//              - Speculative RAT & Architectural RRAT
//              - 32-entry Reorder Buffer (ROB)
//              - 16-entry Reservation Station (RS)
//              - Out-of-Order Issue to ALU, Multiplier, Branch, and Load FUs
//              - 16-entry Store Queue with Store-to-Load Forwarding
//              - Common Data Bus (CDB) Priority Arbiter
//              - In-Order Retirement with Instantaneous Misprediction Recovery
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module core #(
    parameter ENABLE_BRANCH_PREDICTOR = 1
)(
    input  wire                   clk,
    input  wire                   rst,

    // Instruction Memory Interface (Port A)
    output wire [`XLEN-1:0]       imem_addr,
    input  wire [`ILEN-1:0]       imem_inst,

    // Data Memory Interface (Port B)
    output wire                   dmem_en,
    output wire                   dmem_wen,
    output wire [`XLEN-1:0]       dmem_addr,
    output wire [`XLEN-1:0]       dmem_wdata,
    output wire [7:0]             dmem_byte_en,
    input  wire [`XLEN-1:0]       dmem_rdata,

    // Processor Execution Status
    output wire                   halt,

    // Retirement Debug & Monitoring Interface
    output wire                   retire_valid,
    output wire [`XLEN-1:0]       retire_pc,
    output wire [`AR_WIDTH-1:0]   retire_arch_dest,
    output wire [`PR_WIDTH-1:0]   retire_tag_new,
    output wire [`PR_WIDTH-1:0]   retire_tag_old,
    output wire                   retire_is_mispred
);

    // ========================================================================
    // Pipeline Control & Recovery Wires
    // ========================================================================
    wire                   dispatch_stall;
    wire                   recover_en;
    wire [`XLEN-1:0]       recover_target;

    // ========================================================================
    // 1. Branch Predictor Wires
    // ========================================================================
    wire                   bp_pred_taken;
    wire [`XLEN-1:0]       bp_pred_target;
    wire                   bp_update_en;
    wire [`XLEN-1:0]       bp_update_pc;
    wire                   bp_update_actual_taken;
    wire [`XLEN-1:0]       bp_update_actual_target;

    branch_predictor #(
        .ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR)
    ) u_bp (
        .clk                   (clk),
        .rst                   (rst),
        .fetch_pc              (imem_addr),
        .pred_taken            (bp_pred_taken),
        .pred_target           (bp_pred_target),
        .update_en             (bp_update_en),
        .update_pc             (bp_update_pc),
        .update_actual_taken   (bp_update_actual_taken),
        .update_actual_target  (bp_update_actual_target)
    );

    // ========================================================================
    // 2. Fetch Stage
    // ========================================================================
    wire                   if_id_valid;
    wire [`XLEN-1:0]       if_id_pc;
    wire [`XLEN-1:0]       if_id_npc;
    wire [`ILEN-1:0]       if_id_inst;
    wire                   if_id_pred_taken;
    wire [`XLEN-1:0]       if_id_pred_target;

    fetch_stage u_fetch (
        .clk                   (clk),
        .rst                   (rst),
        .stall                 (dispatch_stall),
        .recover_en            (recover_en),
        .recover_target        (recover_target),
        .pred_taken            (bp_pred_taken),
        .pred_target           (bp_pred_target),
        .imem_addr             (imem_addr),
        .imem_inst             (imem_inst),
        .if_id_valid           (if_id_valid),
        .if_id_pc              (if_id_pc),
        .if_id_npc             (if_id_npc),
        .if_id_inst            (if_id_inst),
        .if_id_pred_taken      (if_id_pred_taken),
        .if_id_pred_target     (if_id_pred_target)
    );

    // ========================================================================
    // 3. Map Tables (RAT & RRAT) & Free List
    // ========================================================================
    wire [`NUM_ARCH_REGS*`PR_WIDTH-1:0] rrat_mappings;
    wire [`AR_WIDTH-1:0]  rrat_commit_arch_dest;
    wire [`PR_WIDTH-1:0]  rrat_commit_tag_new;
    wire                  rrat_commit_en;

    arch_map_table u_rrat (
        .clk                   (clk),
        .rst                   (rst),
        .retire_en             (rrat_commit_en),
        .retire_arch_dest      (rrat_commit_arch_dest),
        .retire_tag_new        (rrat_commit_tag_new),
        .rrat_mappings         (rrat_mappings)
    );

    wire [`AR_WIDTH-1:0]  rat_src1_ar;
    wire [`PR_WIDTH-1:0]  rat_src1_pr;
    wire                  rat_src1_ready;

    wire [`AR_WIDTH-1:0]  rat_src2_ar;
    wire [`PR_WIDTH-1:0]  rat_src2_pr;
    wire                  rat_src2_ready;

    wire [`AR_WIDTH-1:0]  rat_dest_ar;
    wire [`PR_WIDTH-1:0]  rat_dest_old_pr;

    wire                  rat_alloc_en;
    wire [`AR_WIDTH-1:0]  rat_alloc_dest_ar;
    wire [`PR_WIDTH-1:0]  rat_alloc_new_pr;

    wire                  cdb_valid;
    wire [`PR_WIDTH-1:0]  cdb_pr;
    wire [`XLEN-1:0]      cdb_data;
    wire [`ROB_WIDTH-1:0] cdb_rob_idx;
    wire                  cdb_branch_en;
    wire                  cdb_mispredicted;
    wire [`XLEN-1:0]      cdb_correct_target;

    map_table u_rat (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .rrat_mappings         (rrat_mappings),
        .src1_ar               (rat_src1_ar),
        .src1_pr               (rat_src1_pr),
        .src1_ready            (rat_src1_ready),
        .src2_ar               (rat_src2_ar),
        .src2_pr               (rat_src2_pr),
        .src2_ready            (rat_src2_ready),
        .dest_ar               (rat_dest_ar),
        .dest_old_pr           (rat_dest_old_pr),
        .alloc_en              (rat_alloc_en),
        .alloc_dest_ar         (rat_alloc_dest_ar),
        .alloc_new_pr          (rat_alloc_new_pr),
        .cdb_valid             (cdb_valid),
        .cdb_pr                (cdb_pr)
    );

    wire                  fl_alloc_en;
    wire [`PR_WIDTH-1:0]  fl_alloc_pr;
    wire                  fl_empty;
    wire                  fl_free_en;
    wire [`PR_WIDTH-1:0]  fl_free_pr;

    free_list u_free_list (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .rrat_mappings         (rrat_mappings),
        .alloc_en              (fl_alloc_en),
        .alloc_pr              (fl_alloc_pr),
        .fl_empty              (fl_empty),
        .free_en               (fl_free_en),
        .free_pr               (fl_free_pr)
    );

    // ========================================================================
    // 4. Physical Register File (PRF)
    // ========================================================================
    wire [`PR_WIDTH-1:0]  prf_read_pr1;
    wire [`XLEN-1:0]      prf_read_data1;
    wire [`PR_WIDTH-1:0]  prf_read_pr2;
    wire [`XLEN-1:0]      prf_read_data2;

    physical_regfile u_prf (
        .clk                   (clk),
        .rst                   (rst),
        .read_pr1              (prf_read_pr1),
        .read_data1            (prf_read_data1),
        .read_pr2              (prf_read_pr2),
        .read_data2            (prf_read_data2),
        .cdb_valid             (cdb_valid),
        .cdb_pr                (cdb_pr),
        .cdb_data              (cdb_data)
    );

    // ========================================================================
    // 5. Reorder Buffer (ROB)
    // ========================================================================
    wire                  rob_alloc_en;
    wire [`AR_WIDTH-1:0]  rob_alloc_arch_dest;
    wire [`PR_WIDTH-1:0]  rob_alloc_tag_new;
    wire [`PR_WIDTH-1:0]  rob_alloc_tag_old;
    wire                  rob_alloc_is_store;
    wire [`SQ_WIDTH-1:0]  rob_alloc_sq_idx;
    wire [`XLEN-1:0]      rob_alloc_pc;
    wire [`XLEN-1:0]      rob_alloc_npc;
    wire                  rob_alloc_pred_taken;
    wire [`XLEN-1:0]      rob_alloc_pred_target;
    wire                  rob_alloc_halt;
    wire [`ROB_WIDTH-1:0] rob_alloc_idx;
    wire                  rob_full;

    wire                  rob_retire_ready;
    wire [`ROB_WIDTH-1:0] rob_retire_rob_idx;
    wire [`AR_WIDTH-1:0]  rob_retire_arch_dest;
    wire [`PR_WIDTH-1:0]  rob_retire_tag_new;
    wire [`PR_WIDTH-1:0]  rob_retire_tag_old;
    wire                  rob_retire_is_store;
    wire [`SQ_WIDTH-1:0]  rob_retire_sq_idx;
    wire [`XLEN-1:0]      rob_retire_pc;
    wire [`XLEN-1:0]      rob_retire_npc;
    wire                  rob_retire_pred_taken;
    wire [`XLEN-1:0]      rob_retire_pred_target;
    wire                  rob_retire_mispredicted;
    wire [`XLEN-1:0]      rob_retire_correct_target;
    wire                  rob_retire_halt;
    wire                  rob_retire_ack;

    rob u_rob (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .alloc_en              (rob_alloc_en),
        .alloc_arch_dest       (rob_alloc_arch_dest),
        .alloc_tag_new         (rob_alloc_tag_new),
        .alloc_tag_old         (rob_alloc_tag_old),
        .alloc_is_store        (rob_alloc_is_store),
        .alloc_sq_idx          (rob_alloc_sq_idx),
        .alloc_pc              (rob_alloc_pc),
        .alloc_npc             (rob_alloc_npc),
        .alloc_pred_taken      (rob_alloc_pred_taken),
        .alloc_pred_target     (rob_alloc_pred_target),
        .alloc_halt            (rob_alloc_halt),
        .alloc_rob_idx         (rob_alloc_idx),
        .rob_full              (rob_full),
        .complete_valid        (cdb_valid),
        .complete_rob_idx      (cdb_rob_idx),
        .complete_branch_en    (cdb_branch_en),
        .complete_mispredicted (cdb_mispredicted),
        .complete_correct_target(cdb_correct_target),
        .retire_ready          (rob_retire_ready),
        .retire_rob_idx        (rob_retire_rob_idx),
        .retire_arch_dest      (rob_retire_arch_dest),
        .retire_tag_new        (rob_retire_tag_new),
        .retire_tag_old        (rob_retire_tag_old),
        .retire_is_store       (rob_retire_is_store),
        .retire_sq_idx         (rob_retire_sq_idx),
        .retire_pc             (rob_retire_pc),
        .retire_npc            (rob_retire_npc),
        .retire_pred_taken     (rob_retire_pred_taken),
        .retire_pred_target    (rob_retire_pred_target),
        .retire_mispredicted   (rob_retire_mispredicted),
        .retire_correct_target (rob_retire_correct_target),
        .retire_halt           (rob_retire_halt),
        .retire_ack            (rob_retire_ack)
    );

    // ========================================================================
    // 6. Store Queue (SQ)
    // ========================================================================
    wire                  sq_alloc_en;
    wire [`SQ_WIDTH-1:0]  sq_alloc_idx;
    wire                  sq_full;

    wire                  sq_update_en;
    wire [`SQ_WIDTH-1:0]  sq_update_idx;
    wire [`XLEN-1:0]      sq_update_addr;
    wire [7:0]            sq_update_byte_en;
    wire                  sq_update_data_en;
    wire [`XLEN-1:0]      sq_update_data;

    wire                  sq_query_en;
    wire [`SQ_WIDTH-1:0]  sq_load_sq_tail;
    wire [`XLEN-1:0]      sq_load_addr;
    wire [7:0]            sq_load_byte_en;
    wire                  sq_forward_valid;
    wire [`XLEN-1:0]      sq_forward_data;
    wire                  sq_load_hazard;
    wire [`SQ_ENTRIES-1:0] sq_load_tail_ready;

    wire                  sq_commit_en;
    wire [`SQ_WIDTH-1:0]  sq_commit_idx;

    wire                  sq_dmem_wen;
    wire [`XLEN-1:0]      sq_dmem_addr;
    wire [`XLEN-1:0]      sq_dmem_wdata;
    wire [7:0]            sq_dmem_byte_en;

    store_queue u_sq (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .alloc_en              (sq_alloc_en),
        .alloc_sq_idx          (sq_alloc_idx),
        .sq_full               (sq_full),
        .update_en             (sq_update_en),
        .update_sq_idx         (sq_update_idx),
        .update_addr           (sq_update_addr),
        .update_byte_en        (sq_update_byte_en),
        .update_data_en        (sq_update_data_en),
        .update_data           (sq_update_data),
        .load_query_en         (sq_query_en),
        .load_sq_tail          (sq_load_sq_tail),
        .load_addr             (sq_load_addr),
        .load_byte_en          (sq_load_byte_en),
        .sq_forward_valid      (sq_forward_valid),
        .sq_forward_data       (sq_forward_data),
        .sq_load_hazard        (sq_load_hazard),
        .load_tail_ready       (sq_load_tail_ready),
        .retire_store_en       (sq_commit_en),
        .retire_sq_idx         (sq_commit_idx),
        .dmem_wen              (sq_dmem_wen),
        .dmem_addr             (sq_dmem_addr),
        .dmem_wdata            (sq_dmem_wdata),
        .dmem_byte_en          (sq_dmem_byte_en)
    );

    // ========================================================================
    // 7. Dispatch Stage
    // ========================================================================
    wire                  rs_alloc_en;
    wire [2:0]            rs_alloc_fu;
    wire [4:0]            rs_alloc_op;
    wire [`ROB_WIDTH-1:0] rs_alloc_rob_idx;
    wire [`PR_WIDTH-1:0]  rs_alloc_dest_pr;
    wire [`PR_WIDTH-1:0]  rs_alloc_src1_pr;
    wire                  rs_alloc_src1_ready;
    wire [`PR_WIDTH-1:0]  rs_alloc_src2_pr;
    wire                  rs_alloc_src2_ready;
    wire [`XLEN-1:0]      rs_alloc_imm;
    wire                  rs_alloc_use_imm;
    wire                  rs_alloc_use_pc;
    wire [`XLEN-1:0]      rs_alloc_pc;
    wire                  rs_alloc_pred_taken;
    wire [`XLEN-1:0]      rs_alloc_pred_target;
    wire [`SQ_WIDTH-1:0]  rs_alloc_sq_idx;
    wire                  rs_alloc_is_branch;
    wire                  rs_alloc_is_store;
    wire                  rs_full;

    dispatch_stage u_dispatch (
        .if_id_valid           (if_id_valid),
        .if_id_pc              (if_id_pc),
        .if_id_npc             (if_id_npc),
        .if_id_inst            (if_id_inst),
        .if_id_pred_taken      (if_id_pred_taken),
        .if_id_pred_target     (if_id_pred_target),
        .rob_full              (rob_full),
        .rs_full               (rs_full),
        .fl_empty              (fl_empty),
        .sq_full               (sq_full),
        .stall                 (dispatch_stall),
        .rat_src1_ar           (rat_src1_ar),
        .rat_src1_pr           (rat_src1_pr),
        .rat_src1_ready        (rat_src1_ready),
        .rat_src2_ar           (rat_src2_ar),
        .rat_src2_pr           (rat_src2_pr),
        .rat_src2_ready        (rat_src2_ready),
        .rat_dest_ar           (rat_dest_ar),
        .rat_dest_old_pr       (rat_dest_old_pr),
        .rat_alloc_en          (rat_alloc_en),
        .rat_alloc_dest_ar     (rat_alloc_dest_ar),
        .rat_alloc_new_pr      (rat_alloc_new_pr),
        .fl_alloc_en           (fl_alloc_en),
        .fl_alloc_pr           (fl_alloc_pr),
        .rob_alloc_en          (rob_alloc_en),
        .rob_alloc_arch_dest   (rob_alloc_arch_dest),
        .rob_alloc_tag_new     (rob_alloc_tag_new),
        .rob_alloc_tag_old     (rob_alloc_tag_old),
        .rob_alloc_is_store    (rob_alloc_is_store),
        .rob_alloc_sq_idx      (rob_alloc_sq_idx),
        .rob_alloc_pc          (rob_alloc_pc),
        .rob_alloc_npc         (rob_alloc_npc),
        .rob_alloc_pred_taken  (rob_alloc_pred_taken),
        .rob_alloc_pred_target (rob_alloc_pred_target),
        .rob_alloc_halt        (rob_alloc_halt),
        .rob_alloc_idx         (rob_alloc_idx),
        .sq_alloc_en           (sq_alloc_en),
        .sq_alloc_idx          (sq_alloc_idx),
        .rs_alloc_en           (rs_alloc_en),
        .rs_alloc_fu           (rs_alloc_fu),
        .rs_alloc_op           (rs_alloc_op),
        .rs_alloc_rob_idx      (rs_alloc_rob_idx),
        .rs_alloc_dest_pr      (rs_alloc_dest_pr),
        .rs_alloc_src1_pr      (rs_alloc_src1_pr),
        .rs_alloc_src1_ready   (rs_alloc_src1_ready),
        .rs_alloc_src2_pr      (rs_alloc_src2_pr),
        .rs_alloc_src2_ready   (rs_alloc_src2_ready),
        .rs_alloc_imm          (rs_alloc_imm),
        .rs_alloc_use_imm      (rs_alloc_use_imm),
        .rs_alloc_use_pc       (rs_alloc_use_pc),
        .rs_alloc_pc           (rs_alloc_pc),
        .rs_alloc_pred_taken   (rs_alloc_pred_taken),
        .rs_alloc_pred_target  (rs_alloc_pred_target),
        .rs_alloc_sq_idx       (rs_alloc_sq_idx),
        .rs_alloc_is_branch    (rs_alloc_is_branch),
        .rs_alloc_is_store     (rs_alloc_is_store)
    );

    // ========================================================================
    // 8. Reservation Station (RS)
    // ========================================================================
    wire                  issue_valid;
    wire [2:0]            issue_fu;
    wire [4:0]            issue_op;
    wire [`ROB_WIDTH-1:0] issue_rob_idx;
    wire [`PR_WIDTH-1:0]  issue_dest_pr;
    wire [`PR_WIDTH-1:0]  issue_src1_pr;
    wire [`PR_WIDTH-1:0]  issue_src2_pr;
    wire [`XLEN-1:0]      issue_imm;
    wire                  issue_use_imm;
    wire                  issue_use_pc;
    wire [`XLEN-1:0]      issue_pc;
    wire                  issue_pred_taken;
    wire [`XLEN-1:0]      issue_pred_target;
    wire [`SQ_WIDTH-1:0]  issue_sq_idx;
    wire                  issue_is_branch;
    wire                  issue_is_store;

    reservation_station u_rs (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .alloc_en              (rs_alloc_en),
        .alloc_fu              (rs_alloc_fu),
        .alloc_op              (rs_alloc_op),
        .alloc_rob_idx         (rs_alloc_rob_idx),
        .alloc_dest_pr         (rs_alloc_dest_pr),
        .alloc_src1_pr         (rs_alloc_src1_pr),
        .alloc_src1_ready      (rs_alloc_src1_ready),
        .alloc_src2_pr         (rs_alloc_src2_pr),
        .alloc_src2_ready      (rs_alloc_src2_ready),
        .alloc_imm             (rs_alloc_imm),
        .alloc_use_imm         (rs_alloc_use_imm),
        .alloc_use_pc          (rs_alloc_use_pc),
        .alloc_pc              (rs_alloc_pc),
        .alloc_pred_taken      (rs_alloc_pred_taken),
        .alloc_pred_target     (rs_alloc_pred_target),
        .alloc_sq_idx          (rs_alloc_sq_idx),
        .alloc_is_branch       (rs_alloc_is_branch),
        .alloc_is_store        (rs_alloc_is_store),
        .rs_full               (rs_full),
        .cdb_valid             (cdb_valid),
        .cdb_pr                (cdb_pr),
        .alu_ready             (!fu_alu_valid    || fu_alu_grant),
        .mult_ready            (!fu_mult_valid   || fu_mult_grant),
        .branch_ready          (!fu_branch_valid || fu_branch_grant),
        .load_ready            (!fu_load_valid   || fu_load_grant),
        .load_tail_ready       (sq_load_tail_ready),
        .issue_valid           (issue_valid),
        .issue_fu              (issue_fu),
        .issue_op              (issue_op),
        .issue_rob_idx         (issue_rob_idx),
        .issue_dest_pr         (issue_dest_pr),
        .issue_src1_pr         (issue_src1_pr),
        .issue_src2_pr         (issue_src2_pr),
        .issue_imm             (issue_imm),
        .issue_use_imm         (issue_use_imm),
        .issue_use_pc          (issue_use_pc),
        .issue_pc              (issue_pc),
        .issue_pred_taken      (issue_pred_taken),
        .issue_pred_target     (issue_pred_target),
        .issue_sq_idx          (issue_sq_idx),
        .issue_is_branch       (issue_is_branch),
        .issue_is_store        (issue_is_store)
    );

    // ========================================================================
    // 9. Issue Stage (IS/EX Pipeline Register)
    // ========================================================================
    wire                  ex_valid;
    wire [2:0]            ex_fu;
    wire [4:0]            ex_op;
    wire [`ROB_WIDTH-1:0] ex_rob_idx;
    wire [`PR_WIDTH-1:0]  ex_dest_pr;
    wire [`XLEN-1:0]      ex_op_a;
    wire [`XLEN-1:0]      ex_op_b;
    wire [`XLEN-1:0]      ex_store_data;
    wire [`XLEN-1:0]      ex_imm;
    wire [`XLEN-1:0]      ex_pc;
    wire                  ex_pred_taken;
    wire [`XLEN-1:0]      ex_pred_target;
    wire [`SQ_WIDTH-1:0]  ex_sq_idx;
    wire                  ex_is_branch;
    wire                  ex_is_store;

    issue_stage u_issue (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .issue_valid           (issue_valid),
        .issue_fu              (issue_fu),
        .issue_op              (issue_op),
        .issue_rob_idx         (issue_rob_idx),
        .issue_dest_pr         (issue_dest_pr),
        .issue_src1_pr         (issue_src1_pr),
        .issue_src2_pr         (issue_src2_pr),
        .issue_imm             (issue_imm),
        .issue_use_imm         (issue_use_imm),
        .issue_use_pc          (issue_use_pc),
        .issue_pc              (issue_pc),
        .issue_pred_taken      (issue_pred_taken),
        .issue_pred_target     (issue_pred_target),
        .issue_sq_idx          (issue_sq_idx),
        .issue_is_branch       (issue_is_branch),
        .issue_is_store        (issue_is_store),
        .prf_read_pr1          (prf_read_pr1),
        .prf_read_data1        (prf_read_data1),
        .prf_read_pr2          (prf_read_pr2),
        .prf_read_data2        (prf_read_data2),
        .ex_valid              (ex_valid),
        .ex_fu                 (ex_fu),
        .ex_op                 (ex_op),
        .ex_rob_idx            (ex_rob_idx),
        .ex_dest_pr            (ex_dest_pr),
        .ex_op_a               (ex_op_a),
        .ex_op_b               (ex_op_b),
        .ex_store_data         (ex_store_data),
        .ex_imm                (ex_imm),
        .ex_pc                 (ex_pc),
        .ex_pred_taken         (ex_pred_taken),
        .ex_pred_target        (ex_pred_target),
        .ex_sq_idx             (ex_sq_idx),
        .ex_is_branch          (ex_is_branch),
        .ex_is_store           (ex_is_store)
    );

    // ========================================================================
    // 10. Execution Stage: Functional Units
    // ========================================================================
    // ALU
    wire                  fu_alu_grant;
    wire                  fu_alu_valid;
    wire [`ROB_WIDTH-1:0] fu_alu_rob_idx;
    wire [`PR_WIDTH-1:0]  fu_alu_dest_pr;
    wire [`XLEN-1:0]      fu_alu_data;

    fu_alu u_fu_alu (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .ex_valid              (ex_valid),
        .ex_fu                 (ex_fu),
        .ex_op                 (ex_op),
        .ex_rob_idx            (ex_rob_idx),
        .ex_dest_pr            (ex_dest_pr),
        .ex_op_a               (ex_op_a),
        .ex_op_b               (ex_op_b),
        .ex_store_data         (ex_store_data),
        .ex_imm                (ex_imm),
        .ex_sq_idx             (ex_sq_idx),
        .ex_is_store           (ex_is_store),
        .sq_update_en          (sq_update_en),
        .sq_update_idx         (sq_update_idx),
        .sq_update_addr        (sq_update_addr),
        .sq_update_byte_en     (sq_update_byte_en),
        .sq_update_data_en     (sq_update_data_en),
        .sq_update_data        (sq_update_data),
        .alu_grant             (fu_alu_grant),
        .fu_c_valid            (fu_alu_valid),
        .fu_c_rob_idx          (fu_alu_rob_idx),
        .fu_c_dest_pr          (fu_alu_dest_pr),
        .fu_c_data             (fu_alu_data)
    );

    // Multiplier
    wire                  fu_mult_grant;
    wire                  fu_mult_valid;
    wire [`ROB_WIDTH-1:0] fu_mult_rob_idx;
    wire [`PR_WIDTH-1:0]  fu_mult_dest_pr;
    wire [`XLEN-1:0]      fu_mult_data;

    fu_mult u_fu_mult (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .ex_valid              (ex_valid),
        .ex_fu                 (ex_fu),
        .ex_op                 (ex_op),
        .ex_rob_idx            (ex_rob_idx),
        .ex_dest_pr            (ex_dest_pr),
        .ex_op_a               (ex_op_a),
        .ex_op_b               (ex_op_b),
        .mult_grant            (fu_mult_grant),
        .fu_c_valid            (fu_mult_valid),
        .fu_c_rob_idx          (fu_mult_rob_idx),
        .fu_c_dest_pr          (fu_mult_dest_pr),
        .fu_c_data             (fu_mult_data)
    );

    // Branch FU
    wire                  fu_branch_grant;
    wire                  fu_branch_valid;
    wire [`ROB_WIDTH-1:0] fu_branch_rob_idx;
    wire [`PR_WIDTH-1:0]  fu_branch_dest_pr;
    wire [`XLEN-1:0]      fu_branch_data;
    wire                  fu_branch_mispred;
    wire [`XLEN-1:0]      fu_branch_target;

    fu_branch u_fu_branch (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .ex_valid              (ex_valid),
        .ex_fu                 (ex_fu),
        .ex_op                 (ex_op),
        .ex_rob_idx            (ex_rob_idx),
        .ex_dest_pr            (ex_dest_pr),
        .ex_op_a               (ex_op_a),
        .ex_op_b               (ex_op_b),
        .ex_imm                (ex_imm),
        .ex_pc                 (ex_pc),
        .ex_pred_taken         (ex_pred_taken),
        .ex_pred_target        (ex_pred_target),
        .bp_update_en          (bp_update_en),
        .bp_update_pc          (bp_update_pc),
        .bp_update_actual_taken(bp_update_actual_taken),
        .bp_update_actual_target(bp_update_actual_target),
        .branch_grant          (fu_branch_grant),
        .fu_c_valid            (fu_branch_valid),
        .fu_c_rob_idx          (fu_branch_rob_idx),
        .fu_c_dest_pr          (fu_branch_dest_pr),
        .fu_c_data             (fu_branch_data),
        .fu_c_mispredicted     (fu_branch_mispred),
        .fu_c_correct_target   (fu_branch_target)
    );

    // Load FU
    wire                  fu_load_grant;
    wire                  fu_load_valid;
    wire [`ROB_WIDTH-1:0] fu_load_rob_idx;
    wire [`PR_WIDTH-1:0]  fu_load_dest_pr;
    wire [`XLEN-1:0]      fu_load_data;
    wire                  load_dmem_ren;
    wire [`XLEN-1:0]      load_dmem_raddr;

    fu_load u_fu_load (
        .clk                   (clk),
        .rst                   (rst),
        .recover_en            (recover_en),
        .ex_valid              (ex_valid),
        .ex_fu                 (ex_fu),
        .ex_op                 (ex_op),
        .ex_rob_idx            (ex_rob_idx),
        .ex_dest_pr            (ex_dest_pr),
        .ex_op_a               (ex_op_a),
        .ex_imm                (ex_imm),
        .ex_sq_idx             (ex_sq_idx),
        .sq_query_en           (sq_query_en),
        .sq_load_sq_tail       (sq_load_sq_tail),
        .sq_load_addr          (sq_load_addr),
        .sq_load_byte_en       (sq_load_byte_en),
        .sq_forward_valid      (sq_forward_valid),
        .sq_forward_data       (sq_forward_data),
        .sq_load_hazard        (sq_load_hazard),
        .dmem_ren              (load_dmem_ren),
        .dmem_raddr            (load_dmem_raddr),
        .dmem_rdata            (dmem_rdata),
        .load_grant            (fu_load_grant),
        .fu_c_valid            (fu_load_valid),
        .fu_c_rob_idx          (fu_load_rob_idx),
        .fu_c_dest_pr          (fu_load_dest_pr),
        .fu_c_data             (fu_load_data)
    );

    // Data Memory Port Muxing (Write from Store Queue, Read from Load FU)
    assign dmem_en      = sq_dmem_wen | load_dmem_ren;
    assign dmem_wen     = sq_dmem_wen;
    assign dmem_addr    = sq_dmem_wen ? sq_dmem_addr : load_dmem_raddr;
    assign dmem_wdata   = sq_dmem_wdata;
    assign dmem_byte_en = sq_dmem_byte_en;

    // ========================================================================
    // 11. Complete Stage (CDB Arbiter)
    // ========================================================================
    complete_stage u_complete (
        .fu_mult_valid         (fu_mult_valid),
        .fu_mult_rob_idx       (fu_mult_rob_idx),
        .fu_mult_dest_pr       (fu_mult_dest_pr),
        .fu_mult_data          (fu_mult_data),
        .fu_mult_grant         (fu_mult_grant),
        .fu_load_valid         (fu_load_valid),
        .fu_load_rob_idx       (fu_load_rob_idx),
        .fu_load_dest_pr       (fu_load_dest_pr),
        .fu_load_data          (fu_load_data),
        .fu_load_grant         (fu_load_grant),
        .fu_branch_valid       (fu_branch_valid),
        .fu_branch_rob_idx     (fu_branch_rob_idx),
        .fu_branch_dest_pr     (fu_branch_dest_pr),
        .fu_branch_data        (fu_branch_data),
        .fu_branch_mispred     (fu_branch_mispred),
        .fu_branch_target      (fu_branch_target),
        .fu_branch_grant       (fu_branch_grant),
        .fu_alu_valid          (fu_alu_valid),
        .fu_alu_rob_idx        (fu_alu_rob_idx),
        .fu_alu_dest_pr        (fu_alu_dest_pr),
        .fu_alu_data           (fu_alu_data),
        .fu_alu_grant          (fu_alu_grant),
        .cdb_valid             (cdb_valid),
        .cdb_rob_idx           (cdb_rob_idx),
        .cdb_pr                (cdb_pr),
        .cdb_data              (cdb_data),
        .cdb_branch_en         (cdb_branch_en),
        .cdb_mispredicted      (cdb_mispredicted),
        .cdb_correct_target    (cdb_correct_target)
    );

    // ========================================================================
    // 12. Retire Stage
    // ========================================================================
    retire_stage u_retire (
        .rob_retire_ready      (rob_retire_ready),
        .rob_retire_rob_idx    (rob_retire_rob_idx),
        .rob_retire_arch_dest  (rob_retire_arch_dest),
        .rob_retire_tag_new    (rob_retire_tag_new),
        .rob_retire_tag_old    (rob_retire_tag_old),
        .rob_retire_is_store   (rob_retire_is_store),
        .rob_retire_sq_idx     (rob_retire_sq_idx),
        .rob_retire_pc         (rob_retire_pc),
        .rob_retire_npc        (rob_retire_npc),
        .rob_retire_pred_taken (rob_retire_pred_taken),
        .rob_retire_pred_target(rob_retire_pred_target),
        .rob_retire_mispredicted(rob_retire_mispredicted),
        .rob_retire_correct_target(rob_retire_correct_target),
        .rob_retire_halt       (rob_retire_halt),
        .rob_retire_ack        (rob_retire_ack),
        .rrat_commit_en        (rrat_commit_en),
        .rrat_commit_arch_dest (rrat_commit_arch_dest),
        .rrat_commit_tag_new   (rrat_commit_tag_new),
        .fl_free_en            (fl_free_en),
        .fl_free_pr            (fl_free_pr),
        .sq_commit_en          (sq_commit_en),
        .sq_commit_idx         (sq_commit_idx),
        .recover_en            (recover_en),
        .recover_target        (recover_target),
        .halt                  (halt),
        .retire_valid          (retire_valid),
        .retire_pc             (retire_pc),
        .retire_arch_dest      (retire_arch_dest),
        .retire_tag_new        (retire_tag_new),
        .retire_tag_old        (retire_tag_old),
        .retire_is_mispred     (retire_is_mispred)
    );

endmodule
