// ============================================================================
// File: tb_single_step.v
// Description: Step-by-step testbench for tracing a single instruction lifetime.
//              Preloads "addi x1, x0, 42" followed by "wfi", dumps single_inst.vcd,
//              and logs cycle-by-cycle pipeline progression.
// ============================================================================

`timescale 1ns/100ps
`include "defs.v"

module tb_single_step;

    reg clk;
    reg rst;

    // Clock generation: 10ns period (100MHz)
    always #5 clk = ~clk;

    // Memory wires
    wire [`XLEN-1:0] imem_addr;
    wire [`ILEN-1:0] imem_inst;
    wire             dmem_en;
    wire             dmem_wen;
    wire [`XLEN-1:0] dmem_addr;
    wire [`XLEN-1:0] dmem_wdata;
    wire [7:0]       dmem_byte_en;
    wire [`XLEN-1:0] dmem_rdata;

    // Core status wires
    wire             halt;
    wire             retire_valid;
    wire [`XLEN-1:0] retire_pc;
    wire [4:0]       retire_arch_dest;
    wire [5:0]       retire_tag_new;
    wire [5:0]       retire_tag_old;
    wire             retire_is_mispred;

    // Instantiate Memory
    memory #(
        .MEM_SIZE_BYTES(65536)
    ) u_mem (
        .clk          (clk),
        .rst          (rst),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_inst),
        .dmem_en      (dmem_en),
        .dmem_wen     (dmem_wen),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_rdata   (dmem_rdata)
    );

    // Instantiate Core
    core #(
        .ENABLE_BRANCH_PREDICTOR(1)
    ) u_core (
        .clk              (clk),
        .rst              (rst),
        .imem_addr        (imem_addr),
        .imem_inst        (imem_inst),
        .dmem_en          (dmem_en),
        .dmem_wen         (dmem_wen),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_byte_en     (dmem_byte_en),
        .dmem_rdata       (dmem_rdata),
        .halt             (halt),
        .retire_valid     (retire_valid),
        .retire_pc        (retire_pc),
        .retire_arch_dest (retire_arch_dest),
        .retire_tag_new   (retire_tag_new),
        .retire_tag_old   (retire_tag_old),
        .retire_is_mispred(retire_is_mispred)
    );

    integer cycle_count;
    integer i;

    initial begin
        // VCD Dump for waveform inspection
        $dumpfile("single_inst.vcd");
        $dumpvars(0, tb_single_step);

        clk = 0;
        rst = 1;
        cycle_count = 0;

        // Initialize memory array with NOPs
        for (i = 0; i < 8192; i = i + 1) begin
            u_mem.mem_array[i] = {`NOP_INST, `NOP_INST};
        end

        // Program to execute:
        // PC 0x0: addi x1, x0, 42  (32'h02a00093)
        // PC 0x4: wfi              (32'h10500073)
        u_mem.mem_array[0] = {32'h10500073, 32'h02a00093};

        $display("=========================================================================================");
        $display("   SCALAR OUT-OF-ORDER PROCESSOR: SINGLE INSTRUCTION LIFETIME TRACER                     ");
        $display("   Instruction: 'addi x1, x0, 42'  (Hex: 0x02a00093) at PC = 0x0                        ");
        $display("=========================================================================================");

        // Hold reset for 3 cycles
        #30;
        @(negedge clk);
        rst = 0;
        $display("[TIME: %0t ns] Reset released. Starting execution...", $time);
    end

    // Cycle-by-cycle pipeline stage monitor
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;
        end
    end

    always @(negedge clk) begin
        if (!rst) begin
            $display("\n-----------------------------------------------------------------------------------------");
            $display(">>> CYCLE %0d  (Time: %0t ns)", cycle_count, $time);
            $display("-----------------------------------------------------------------------------------------");

            // 1. Fetch Stage
            $display(" [1. FETCH]   PC: 0x%0h | IMEM Inst: 0x%08h | IF/ID Valid: %b (PC: 0x%0h, Inst: 0x%08h)",
                     imem_addr, imem_inst,
                     u_core.u_fetch.if_id_valid, u_core.u_fetch.if_id_pc, u_core.u_fetch.if_id_inst);

            // 2. Dispatch Stage & Rename
            $display(" [2. DISP]    Stall: %b | Alloc PR: p%0d (Told: p%0d) -> ROB[%0d], RS slot",
                     u_core.dispatch_stall,
                     u_core.fl_alloc_pr, u_core.rat_dest_old_pr, u_core.rob_alloc_idx);

            // 3. Reservation Station & Issue
            $display(" [3. ISSUE]   Issue Valid: %b | FU: %0d | Dest: p%0d | OpA: 0x%0h, OpB: 0x%0h",
                     u_core.issue_valid, u_core.issue_fu, u_core.issue_dest_pr,
                     u_core.u_issue.ex_op_a, u_core.u_issue.ex_op_b);

            // 4. ALU Execution
            $display(" [4. ALU/EX]  ALU Active: %b | ALU Output Buffer Valid: %b (Dest: p%0d, Result: 0x%0h)",
                     u_core.u_fu_alu.is_alu_active,
                     u_core.u_fu_alu.fu_c_valid, u_core.u_fu_alu.fu_c_dest_pr, u_core.u_fu_alu.fu_c_data);

            // 5. Complete / CDB Broadcast
            $display(" [5. CDB]     CDB Valid: %b | Tag: p%0d | Data: 0x%0h (%0d) | Target ROB: [%0d]",
                     u_core.cdb_valid, u_core.cdb_pr, u_core.cdb_data, u_core.cdb_data, u_core.cdb_rob_idx);

            // 6. Retire Stage
            $display(" [6. RETIRE]  Retire Valid: %b | PC: 0x%0h | Arch Dest: x%0d <= p%0d (Freed Told: p%0d)",
                     retire_valid, retire_pc, retire_arch_dest, retire_tag_new, retire_tag_old);

            // Architectural State Monitor
            $display(" [ARCH-RAT]   x1 mapped to p%0d | PRF[p32] = 0x%0h (%0d)",
                     u_core.u_rrat.rrat[1],
                     u_core.u_prf.prf[32], u_core.u_prf.prf[32]);

            // Termination check
            if (halt) begin
                $display("\n=========================================================================================");
                $display(">>> SUCCESS: Core Halt reached! Instruction retired cleanly.");
                $display("    Architectural Register x1 = %0d (0x%0h)", u_core.u_prf.prf[u_core.u_rrat.rrat[1]], u_core.u_prf.prf[u_core.u_rrat.rrat[1]]);
                $display("    Waveform dumped to 'single_inst.vcd'.");
                $display("=========================================================================================\n");
                $finish;
            end

            if (cycle_count > 25) begin
                $display("\n[TIMEOUT] Reached cycle 25 without halt. Dumping state and exiting.");
                $finish;
            end
        end
    end

endmodule
