// ============================================================================
// File: ooo_axi_wrapper.v
// Description: Top-Level AXI-Lite Slave Wrapper for Scalar RV64IM OoO Core.
//              Enables host interaction via PYNQ Python (pynq.Overlay).
//              Features:
//              - 32-bit AXI4-Lite Slave interface (Control, Status, Registers)
//              - Core Reset control & WFI / Halt monitoring
//              - Hardware Performance Counters (Cycles, Retired, Mispredictions)
//              - Dual-port Memory Port B Muxing for Host Read/Write programming
//              - Committed Architectural Register (x0 - x31) direct readback port
// Standard Verilog-2001
// ============================================================================

`timescale 1ns/100ps
`include "defs.v"

module ooo_axi_wrapper #(
    parameter ENABLE_BRANCH_PREDICTOR = 1,
    parameter C_S_AXI_DATA_WIDTH      = 32,
    parameter C_S_AXI_ADDR_WIDTH      = 8
)(
    // AXI4-Lite Slave Interface
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output reg                               s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output reg                               s_axi_wready,
    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output reg                               s_axi_arready,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready
);

    // ========================================================================
    // Internal Control & Status Registers
    // ========================================================================
    reg         reg_core_rst;         // Bit 0: Hold core in reset
    reg         reg_perf_clr;         // Bit 1: Clear performance counters
    reg [15:0]  reg_mem_addr;         // Target byte address for memory access
    reg [31:0]  reg_mem_wdata_lo;     // Lower 32 bits to write into memory
    reg [31:0]  reg_mem_wdata_hi;     // Upper 32 bits to write into memory
    reg         reg_mem_we_pulse;     // Write strobe to BRAM
    reg [4:0]   reg_arch_sel;         // Architectural register index (0 to 31)

    // Performance Counters
    reg [31:0]  perf_cycle_cnt;
    reg [31:0]  perf_retire_cnt;
    reg [31:0]  perf_mispred_cnt;

    // Processor Core Status
    wire        core_halt;
    wire        core_retire_valid;
    wire        core_retire_is_mispred;
    wire [`XLEN-1:0]     core_retire_pc;
    wire [`AR_WIDTH-1:0] core_retire_arch_dest;
    wire [`PR_WIDTH-1:0] core_retire_tag_new;
    wire [`PR_WIDTH-1:0] core_retire_tag_old;

    // Memory Wires
    wire             imem_en;
    wire [`XLEN-1:0] imem_addr;
    wire [`ILEN-1:0] imem_inst;
    wire             core_dmem_en;
    wire             core_dmem_wen;
    wire [`XLEN-1:0] core_dmem_addr;
    wire [`XLEN-1:0] core_dmem_wdata;
    wire [7:0]       core_dmem_byte_en;
    wire [`XLEN-1:0] dmem_rdata;

    // ========================================================================
    // Memory Port B Mux (Host vs Core Access)
    // ========================================================================
    // Host has access to Port B when core is in reset or when halted
    wire host_mem_access = reg_core_rst | core_halt;

    wire             dmem_en      = host_mem_access ? 1'b1 : core_dmem_en;
    wire             dmem_wen     = host_mem_access ? reg_mem_we_pulse : core_dmem_wen;
    wire [`XLEN-1:0] dmem_addr    = host_mem_access ? {48'd0, reg_mem_addr} : core_dmem_addr;
    wire [`XLEN-1:0] dmem_wdata   = host_mem_access ? {reg_mem_wdata_hi, reg_mem_wdata_lo} : core_dmem_wdata;
    wire [7:0]       dmem_byte_en = host_mem_access ? 8'hFF : core_dmem_byte_en;

    // ========================================================================
    // Core & Memory Instantiation
    // ========================================================================
    memory #(
        .MEM_SIZE_BYTES(65536)
    ) u_mem (
        .clk          (s_axi_aclk),
        .rst          (!s_axi_aresetn),
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

    core #(
        .ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR)
    ) u_core (
        .clk              (s_axi_aclk),
        .rst              (reg_core_rst || !s_axi_aresetn),
        .imem_en          (imem_en),
        .imem_addr        (imem_addr),
        .imem_inst        (imem_inst),
        .dmem_en          (core_dmem_en),
        .dmem_wen         (core_dmem_wen),
        .dmem_addr        (core_dmem_addr),
        .dmem_wdata       (core_dmem_wdata),
        .dmem_byte_en     (core_dmem_byte_en),
        .dmem_rdata       (dmem_rdata),
        .halt             (core_halt),
        .retire_valid     (core_retire_valid),
        .retire_pc        (core_retire_pc),
        .retire_arch_dest (core_retire_arch_dest),
        .retire_tag_new   (core_retire_tag_new),
        .retire_tag_old   (core_retire_tag_old),
        .retire_is_mispred(core_retire_is_mispred)
    );

    // ========================================================================
    // Committed Architectural Register Readout
    // ========================================================================
    wire [`PR_WIDTH-1:0] arch_pr_tag = u_core.u_rrat.rrat[reg_arch_sel];
    wire [`XLEN-1:0]     arch_reg_val = (reg_arch_sel == 5'd0) ? 64'd0 : u_core.u_prf.prf[arch_pr_tag];

    // ========================================================================
    // Hardware Performance Counters
    // ========================================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || reg_perf_clr) begin
            perf_cycle_cnt   <= 32'd0;
            perf_retire_cnt  <= 32'd0;
            perf_mispred_cnt <= 32'd0;
        end else if (!reg_core_rst && !core_halt) begin
            perf_cycle_cnt <= perf_cycle_cnt + 32'd1;

            if (core_retire_valid) begin
                perf_retire_cnt <= perf_retire_cnt + 32'd1;
                if (core_retire_is_mispred) begin
                    perf_mispred_cnt <= perf_mispred_cnt + 32'd1;
                end
            end
        end
    end

    // ========================================================================
    // AXI4-Lite Write Channel
    // ========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready    <= 1'b0;
            s_axi_wready     <= 1'b0;
            s_axi_bvalid     <= 1'b0;
            s_axi_bresp      <= 2'b00;
            reg_core_rst     <= 1'b1; // Default: hold core in reset until host releases
            reg_perf_clr     <= 1'b0;
            reg_mem_addr     <= 16'd0;
            reg_mem_wdata_lo <= 32'd0;
            reg_mem_wdata_hi <= 32'd0;
            reg_mem_we_pulse <= 1'b0;
            reg_arch_sel     <= 5'd0;
            axi_awaddr       <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            reg_mem_we_pulse <= 1'b0; // Always clear single-cycle write strobe

            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                axi_awaddr    <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            // Write Register Decode
            if (s_axi_awready && s_axi_wready) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY

                case (axi_awaddr[7:0])
                    8'h00: begin // REG_CTRL
                        reg_core_rst <= s_axi_wdata[0];
                        reg_perf_clr <= s_axi_wdata[1];
                    end
                    8'h14: reg_mem_addr     <= s_axi_wdata[15:0];
                    8'h18: reg_mem_wdata_lo <= s_axi_wdata;
                    8'h1C: reg_mem_wdata_hi <= s_axi_wdata;
                    8'h20: reg_mem_we_pulse <= s_axi_wdata[0]; // Pulse BRAM write
                    8'h30: reg_arch_sel     <= s_axi_wdata[4:0];
                    default: ;
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ========================================================================
    // AXI4-Lite Read Channel
    // ========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
            axi_araddr    <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                axi_araddr    <= s_axi_araddr;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // Read Register Decode
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY

                case (axi_araddr[7:0])
                    8'h00: s_axi_rdata <= {30'd0, reg_perf_clr, reg_core_rst};
                    8'h04: s_axi_rdata <= {29'd0, core_retire_is_mispred, core_retire_valid, core_halt};
                    8'h08: s_axi_rdata <= perf_cycle_cnt;
                    8'h0C: s_axi_rdata <= perf_retire_cnt;
                    8'h10: s_axi_rdata <= perf_mispred_cnt;
                    8'h14: s_axi_rdata <= {16'd0, reg_mem_addr};
                    8'h18: s_axi_rdata <= reg_mem_wdata_lo;
                    8'h1C: s_axi_rdata <= reg_mem_wdata_hi;
                    8'h24: s_axi_rdata <= dmem_rdata[31:0];      // REG_MEM_RDATA_LO
                    8'h28: s_axi_rdata <= dmem_rdata[63:32];     // REG_MEM_RDATA_HI
                    8'h30: s_axi_rdata <= {27'd0, reg_arch_sel};
                    8'h34: s_axi_rdata <= arch_reg_val[31:0];    // REG_ARCH_VAL_LO
                    8'h38: s_axi_rdata <= arch_reg_val[63:32];   // REG_ARCH_VAL_HI
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
