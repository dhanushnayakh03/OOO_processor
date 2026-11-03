// ============================================================================
// File: tb_core.v
// Description: Comprehensive verification testbench for Scalar RV64IM OoO Core.
//              Loads machine code from +MEM=<file.mem> via $readmemh,
//              tracks instruction retirement, computes performance metrics,
//              and dumps committed architectural registers upon HALT / WFI.
// Standard Verilog-2001
// ============================================================================

`timescale 1ns/100ps
`include "defs.v"

module tb_core;

    parameter ENABLE_BP = 1;

    reg clk;
    reg rst;

    // Clock Generation: 10ns period (100 MHz)
    always #5 clk = ~clk;

    // Memory wires
    wire             imem_en;
    wire [`XLEN-1:0] imem_addr;
    wire [`ILEN-1:0] imem_inst;
    wire             dmem_en;
    wire             dmem_wen;
    wire [`XLEN-1:0] dmem_addr;
    wire [`XLEN-1:0] dmem_wdata;
    wire [7:0]       dmem_byte_en;
    wire [`XLEN-1:0] dmem_rdata;

    // Core Status & Retirement Wires
    wire             halt;
    wire             retire_valid;
    wire [`XLEN-1:0] retire_pc;
    wire [4:0]       retire_arch_dest;
    wire [5:0]       retire_tag_new;
    wire [5:0]       retire_tag_old;
    wire             retire_is_mispred;

    // Instantiate Memory (64 KB True Dual-Port Block RAM)
    memory #(
        .MEM_SIZE_BYTES(65536)
    ) u_mem (
        .clk          (clk),
        .rst          (rst),
        .imem_en      (imem_en),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_inst),
        .dmem_en      (dmem_en),
        .dmem_wen     (dmem_wen),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_byte_en (dmem_byte_en),
        .dmem_rdata   (dmem_rdata)
    );

    // Instantiate Out-of-Order Core
    core #(
        .ENABLE_BRANCH_PREDICTOR(ENABLE_BP)
    ) u_core (
        .clk              (clk),
        .rst              (rst),
        .imem_en          (imem_en),
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

    // Performance Metrics
    integer cycle_count;
    integer retired_count;
    integer mispred_count;
    integer i;
    reg [1023:0] mem_filename;
    reg debug_mode;

    initial begin
        $dumpfile("sim_scalar_ooo.vcd");
        $dumpvars(0, tb_core);

        clk           = 0;
        rst           = 1;
        cycle_count   = 0;
        retired_count = 0;
        mispred_count = 0;
        debug_mode    = 0;

        $display("==================================================================");
        $display("   SCALAR RV64IM OUT-OF-ORDER PROCESSOR TESTBENCH");
        $display("   Branch Predictor: %s (2-bit Dynamic BTB)", ENABLE_BP ? "ENABLED" : "DISABLED");
        $display("==================================================================");

        // Check for +DEBUG flag
        if ($test$plusargs("DEBUG")) begin
            debug_mode = 1;
        end

        // Load machine code from +MEM=<path> or default program.mem
        if ($value$plusargs("MEM=%s", mem_filename)) begin
            $display("[TB] Loading external machine code from: %0s", mem_filename);
            $readmemh(mem_filename, u_mem.mem_array);
        end else begin
            $display("[TB] Loading default machine code: program.mem");
            $readmemh("program.mem", u_mem.mem_array);
        end

        // Hold reset for 5 cycles
        #50;
        @(negedge clk);
        rst = 0;
        $display("[TB] Reset released. Out-of-Order processor executing...");
    end

    // Cycle & Performance Accounting
    always @(posedge clk) begin
        if (!rst) begin
            cycle_count <= cycle_count + 1;

            if (retire_valid) begin
                retired_count <= retired_count + 1;
                if (retire_is_mispred) begin
                    mispred_count <= mispred_count + 1;
                end

                $display("[Cycle %0d] RETIRE: PC=0x%0h arch_dest=x%0d tag_new=p%0d tag_old=p%0d mispred=%0d halt=%0d",
                         cycle_count, retire_pc, retire_arch_dest, retire_tag_new, retire_tag_old, retire_is_mispred, halt);
            end

            if (debug_mode) begin
                $display("--- [Cycle %0d] PC=0x%0h IF_Valid=%0b Stall=%0b Issue=%0b ROB_Full=%0b RS_Full=%0b",
                         cycle_count, imem_addr, u_core.if_id_valid, u_core.dispatch_stall,
                         u_core.issue_valid, u_core.rob_full, u_core.rs_full);
            end

            // Halt Condition (WFI / ECALL / Program Exit)
            if (halt) begin
                $display("\n==================================================================");
                $display("   SIMULATION SUCCESS: WFI / HALT instruction committed!");
                $display("==================================================================");
                $display("   Execution Summary:");
                $display("   - Total Cycles:          %0d", cycle_count);
                $display("   - Retired Instructions:  %0d", retired_count + 1);
                $display("   - Branch Mispredictions: %0d", mispred_count);
                if (cycle_count > 0) begin
                    $display("   - Final IPC:             %f", (retired_count + 1.0) / cycle_count);
                    $display("   - Final CPI:             %f", (cycle_count * 1.0) / (retired_count + 1.0));
                end
                $display("==================================================================");
                $display("   Committed Architectural Registers (x0 - x31):");
                for (i = 0; i < 32; i = i + 4) begin
                    $display("   x%02d: 0x%016h  x%02d: 0x%016h  x%02d: 0x%016h  x%02d: 0x%016h",
                             i,   u_core.u_prf.prf[u_core.u_rrat.rrat[i]],
                             i+1, u_core.u_prf.prf[u_core.u_rrat.rrat[i+1]],
                             i+2, u_core.u_prf.prf[u_core.u_rrat.rrat[i+2]],
                             i+3, u_core.u_prf.prf[u_core.u_rrat.rrat[i+3]]);
                end
                $display("==================================================================");
                $display("@@@ Unified Memory contents hex on left, decimal on right: ");
                $display("@@@");
                for (i = 0; i < 8192; i = i + 1) begin
                    if (u_mem.mem_array[i] != 64'd0) begin
                        $display("@@@ mem[%5d] = %016h : %0d", i * 8, u_mem.mem_array[i], u_mem.mem_array[i]);
                    end
                end
                $display("@@@");
                $display("@@@ System halted on WFI instruction");
                $finish;
            end

            // Timeout watchdog
            if (cycle_count > 50000) begin
                $display("\n[ERROR] Simulation timeout reached (%0d cycles)! Core did not halt.", cycle_count);
                $finish;
            end
        end
    end

endmodule
