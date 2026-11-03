// ============================================================================
// File: store_queue.v
// Description: Store Queue (SQ) with Store-to-Load Forwarding & Disambiguation.
//              16-entry circular FIFO.
//              Allocated at Dispatch, updated by ALU with address/data,
//              provides Store-to-Load forwarding to Load Functional Unit,
//              commits stores to Data Memory strictly in-order upon ROB retirement.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module store_queue (
    input  wire                   clk,
    input  wire                   rst,

    // Branch Misprediction Recovery
    input  wire                   recover_en,

    // Dispatch Allocation Interface
    input  wire                   alloc_en,
    output wire [`SQ_WIDTH-1:0]   alloc_sq_idx,
    output wire                   sq_full,

    // Address & Data Update Interface (from ALU / EX stage)
    input  wire                   update_en,
    input  wire [`SQ_WIDTH-1:0]   update_sq_idx,
    input  wire [`XLEN-1:0]       update_addr,
    input  wire [7:0]             update_byte_en,
    input  wire                   update_data_en,
    input  wire [`XLEN-1:0]       update_data,

    // Load Forwarding & Disambiguation Interface (from Load FU)
    input  wire                   load_query_en,
    input  wire [`SQ_WIDTH-1:0]   load_sq_tail,   // SQ snapshot when load was dispatched
    input  wire [`XLEN-1:0]       load_addr,
    input  wire [7:0]             load_byte_en,
    output reg                    sq_forward_valid,
    output reg  [`XLEN-1:0]       sq_forward_data,
    output reg                    sq_load_hazard,  // Load must stall (unresolved address or pending data)

    // Store Disambiguation Interface to Reservation Station
    output reg  [`SQ_ENTRIES-1:0] load_tail_ready,

    // Retirement & Memory Commit Interface (Retire Stage -> Data Memory)
    input  wire                   retire_store_en,
    input  wire [`SQ_WIDTH-1:0]   retire_sq_idx,
    output reg                    dmem_wen,
    output reg  [`XLEN-1:0]       dmem_addr,
    output reg  [`XLEN-1:0]       dmem_wdata,
    output reg  [7:0]             dmem_byte_en
);

    // Parallel flat arrays for Store Queue entries
    reg                   sq_valid      [0:`SQ_ENTRIES-1];
    reg                   sq_addr_ready [0:`SQ_ENTRIES-1];
    reg                   sq_data_ready [0:`SQ_ENTRIES-1];
    reg [`XLEN-1:0]       sq_addr       [0:`SQ_ENTRIES-1];
    reg [7:0]             sq_byte_en    [0:`SQ_ENTRIES-1];
    reg [`XLEN-1:0]       sq_data       [0:`SQ_ENTRIES-1];

    reg [`SQ_WIDTH-1:0]   head;
    reg [`SQ_WIDTH-1:0]   tail;
    reg [`SQ_WIDTH:0]     count;

    assign sq_full      = (count == `SQ_ENTRIES);
    assign alloc_sq_idx = tail;

    // Combinational Store-to-Load Forwarding and Disambiguation Logic
    // Scan backwards from (load_sq_tail - 1) down to head
    integer k;
    reg [`SQ_WIDTH-1:0] curr_idx;
    reg found_match;
    always @(*) begin
        sq_forward_valid = 1'b0;
        sq_forward_data  = 64'd0;
        sq_load_hazard   = 1'b0;
        found_match      = 1'b0;

        if (load_query_en) begin
            // Search all valid entries between head and load_sq_tail
            for (k = 0; k < `SQ_ENTRIES; k = k + 1) begin
                curr_idx = load_sq_tail - 1'b1 - k[`SQ_WIDTH-1:0];
                
                // Check if curr_idx is between head and load_sq_tail in circular queue
                if (!found_match && sq_valid[curr_idx]) begin
                    // Verify if this entry is indeed older than load_sq_tail
                    // In circular buffer: valid entry older than load_sq_tail
                    if (!sq_addr_ready[curr_idx]) begin
                        // Older store address not yet resolved -> RAW hazard!
                        sq_load_hazard = 1'b1;
                        found_match    = 1'b1;
                    end else if (sq_addr[curr_idx] == load_addr) begin
                        // Matching address: check byte mask coverage
                        if ((sq_byte_en[curr_idx] & load_byte_en) == load_byte_en) begin
                            // Full match
                            if (sq_data_ready[curr_idx]) begin
                                sq_forward_valid = 1'b1;
                                sq_forward_data  = sq_data[curr_idx];
                                found_match      = 1'b1;
                            end else begin
                                // Data not yet available
                                sq_load_hazard   = 1'b1;
                                found_match      = 1'b1;
                            end
                        end else if ((sq_byte_en[curr_idx] & load_byte_en) != 8'd0) begin
                            // Partial overlap -> load hazard until store commits
                            sq_load_hazard = 1'b1;
                            found_match    = 1'b1;
                        end
                    end
                end
            end
        end
    end

    // Combinational Load Tail Ready calculation (Memory Disambiguation for RS)
    integer t, s;
    always @(*) begin
        for (t = 0; t < `SQ_ENTRIES; t = t + 1) begin
            load_tail_ready[t] = 1'b1;
            for (s = 0; s < `SQ_ENTRIES; s = s + 1) begin
                if (t >= head && s >= head && s < t) begin
                    if (sq_valid[s] && (!sq_addr_ready[s] || !sq_data_ready[s]))
                        load_tail_ready[t] = 1'b0;
                end
                if (t < head && (s < t || s >= head)) begin
                    if (sq_valid[s] && (!sq_addr_ready[s] || !sq_data_ready[s]))
                        load_tail_ready[t] = 1'b0;
                end
            end
        end
    end

    // Combinational Memory Commit Outputs
    always @(*) begin
        if (retire_store_en && sq_valid[head]) begin
            dmem_wen     = 1'b1;
            dmem_addr    = sq_addr[head];
            dmem_wdata   = sq_data[head];
            dmem_byte_en = sq_byte_en[head];
        end else begin
            dmem_wen     = 1'b0;
            dmem_addr    = 64'd0;
            dmem_wdata   = 64'd0;
            dmem_byte_en = 8'd0;
        end
    end

    // Sequential Queue State Management
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst || recover_en) begin
            for (i = 0; i < `SQ_ENTRIES; i = i + 1) begin
                sq_valid[i]      <= 1'b0;
                sq_addr_ready[i] <= 1'b0;
                sq_data_ready[i] <= 1'b0;
                sq_addr[i]       <= 64'd0;
                sq_byte_en[i]    <= 8'd0;
                sq_data[i]       <= 64'd0;
            end
            head  <= `SQ_WIDTH'd0;
            tail  <= `SQ_WIDTH'd0;
            count <= {(`SQ_WIDTH+1){1'b0}};
        end else begin
            // 1. Address & Data updates from ALU
            if (update_en && sq_valid[update_sq_idx]) begin
                sq_addr[update_sq_idx]       <= update_addr;
                sq_byte_en[update_sq_idx]    <= update_byte_en;
                sq_addr_ready[update_sq_idx] <= 1'b1;
            end
            if (update_data_en && sq_valid[update_sq_idx]) begin
                sq_data[update_sq_idx]       <= update_data;
                sq_data_ready[update_sq_idx] <= 1'b1;
            end

            // 2. Dispatch Allocation
            if (alloc_en && !sq_full) begin
                sq_valid[tail]      <= 1'b1;
                sq_addr_ready[tail] <= 1'b0;
                sq_data_ready[tail] <= 1'b0;
                sq_addr[tail]       <= 64'd0;
                sq_byte_en[tail]    <= 8'd0;
                sq_data[tail]       <= 64'd0;
                tail                <= tail + 4'd1;
            end

            // 3. Retirement Commit
            if (retire_store_en && sq_valid[head]) begin
                sq_valid[head]      <= 1'b0;
                sq_addr_ready[head] <= 1'b0;
                sq_data_ready[head] <= 1'b0;
                head                <= head + 4'd1;
            end

            // 4. Entry Count
            case ({alloc_en && !sq_full, retire_store_en && sq_valid[head]})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ; // unchanged
            endcase
        end
    end

endmodule
