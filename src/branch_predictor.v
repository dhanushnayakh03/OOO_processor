// ============================================================================
// File: branch_predictor.v
// Description: Parameterized 2-bit Saturating Counter Branch Target Buffer (BTB).
//              Can be turned ON/OFF via parameter ENABLE_BRANCH_PREDICTOR.
// Standard Verilog-2001
// ============================================================================

`include "defs.v"

module branch_predictor #(
    parameter ENABLE_BRANCH_PREDICTOR = 1,
    parameter ENTRIES                 = `BP_ENTRIES,
    parameter INDEX_WIDTH             = `BP_INDEX_WIDTH
)(
    input  wire                   clk,
    input  wire                   rst,

    // Query from Fetch Stage
    input  wire [`XLEN-1:0]       fetch_pc,
    output reg                    pred_taken,
    output reg  [`XLEN-1:0]       pred_target,

    // Update / Training from Branch Functional Unit
    input  wire                   update_en,
    input  wire [`XLEN-1:0]       update_pc,
    input  wire                   update_actual_taken,
    input  wire [`XLEN-1:0]       update_actual_target
);

    localparam TAG_WIDTH = `XLEN - INDEX_WIDTH - 2;

    generate
        if (ENABLE_BRANCH_PREDICTOR == 0) begin : gen_bp_disabled
            // Static Always-Not-Taken Predictor
            always @(*) begin
                pred_taken  = 1'b0;
                pred_target = fetch_pc + 64'd4;
            end
        end else begin : gen_bp_enabled
            // Dynamic 2-bit Saturating Counter Branch Target Buffer
            reg                 btb_valid  [0:ENTRIES-1];
            reg [TAG_WIDTH-1:0] btb_tag    [0:ENTRIES-1];
            reg [1:0]           btb_state  [0:ENTRIES-1];
            reg [`XLEN-1:0]     btb_target [0:ENTRIES-1];

            // Address hashing: discard 2 low bits (word alignment)
            wire [INDEX_WIDTH-1:0] fetch_idx = fetch_pc[INDEX_WIDTH+1:2];
            wire [TAG_WIDTH-1:0]   fetch_tag = fetch_pc[`XLEN-1:INDEX_WIDTH+2];

            wire [INDEX_WIDTH-1:0] update_idx = update_pc[INDEX_WIDTH+1:2];
            wire [TAG_WIDTH-1:0]   update_tag = update_pc[`XLEN-1:INDEX_WIDTH+2];

            // Fetch Lookup (Combinational)
            always @(*) begin
                if (btb_valid[fetch_idx] && (btb_tag[fetch_idx] == fetch_tag)) begin
                    pred_taken  = (btb_state[fetch_idx] == 2'b10 || btb_state[fetch_idx] == 2'b11);
                    pred_target = pred_taken ? btb_target[fetch_idx] : (fetch_pc + 64'd4);
                end else begin
                    pred_taken  = 1'b0;
                    pred_target = fetch_pc + 64'd4;
                end
            end

            // Training & State Update (Sequential)
            integer i;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    for (i = 0; i < ENTRIES; i = i + 1) begin
                        btb_valid[i]  <= 1'b0;
                        btb_tag[i]    <= {TAG_WIDTH{1'b0}};
                        btb_state[i]  <= 2'b01; // WEAK_NOT_TAKEN
                        btb_target[i] <= 64'd0;
                    end
                end else if (update_en) begin
                    btb_valid[update_idx]  <= 1'b1;
                    btb_tag[update_idx]    <= update_tag;
                    btb_target[update_idx] <= update_actual_target;

                    // 2-bit Saturating Counter Transitions:
                    // 00: Strong NT, 01: Weak NT, 10: Weak T, 11: Strong T
                    case (btb_state[update_idx])
                        2'b00: btb_state[update_idx] <= update_actual_taken ? 2'b01 : 2'b00;
                        2'b01: btb_state[update_idx] <= update_actual_taken ? 2'b10 : 2'b00;
                        2'b10: btb_state[update_idx] <= update_actual_taken ? 2'b11 : 2'b01;
                        2'b11: btb_state[update_idx] <= update_actual_taken ? 2'b11 : 2'b10;
                    endcase
                end
            end
        end
    endgenerate

endmodule
