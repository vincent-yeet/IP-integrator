`timescale 1ns/1ns
//=============================================================================
// systolic_controller
//
// Pipeline / latency controller for the 2x2 weight-stationary systolic_array.
// This is the glue the spec's `intent` asks for: it staggers the per-row
// `valid` strobes into the PE mesh so the anti-diagonal wavefront lines up,
// captures the bottom-row partial sums into REGISTERED outputs y0/y1, and
// drives `done`.
//
// Why a stagger is needed
// -----------------------
// Each weight_stationary_pe has 1-cycle latency, and a whole row shares one
// `valid`. But the east-forwarded activation (input_out -> input_in) and the
// south-forwarded partial sum (psum_out -> psum_in) each lag their producer by
// one cycle. So PE(r,c) is only fed correct operands on cycle (r + c) -- the
// classic anti-diagonal wavefront. Because a row shares one valid, row r is
// held valid across the 2 cycles its two PEs need: [r, r + (COLS-1)].
//
//   cnt:        0     1     2     3
//   row0_valid: 1     1     0     0     (pe00 @0, pe01 @1)
//   row1_valid: 0     1     1     0     (pe10 @1, pe11 @2)
//
// pe11 (bottom-right, the last PE in the wavefront) finishes its MAC at the
// edge ending cnt==2, so both bottom-row psum_out values are stable during
// cnt==3 -- that is when we latch y0/y1 and raise done. Latency start->done is
// 4 cycles, which is the minimum for this wavefront.
//=============================================================================
module systolic_controller #(
  parameter DATA_WIDTH = 8
)(
  input  wire                  clk,
  input  wire                  reset,        // active-high async reset
  input  wire                  start,        // begin a computation
  input  wire                  load_weights, // weight-load phase: keep array idle

  // bottom-row partial sums returning from the array
  input  wire [DATA_WIDTH-1:0] col0_psum,    // pe10.psum_out (column 0 result)
  input  wire [DATA_WIDTH-1:0] col1_psum,    // pe11.psum_out (column 1 result)

  // staggered per-row compute strobes driven into the mesh
  output wire                  row0_valid,   // -> pe00.valid, pe01.valid
  output wire                  row1_valid,   // -> pe10.valid, pe11.valid

  // registered results + status
  output reg  [DATA_WIDTH-1:0] y0,
  output reg  [DATA_WIDTH-1:0] y1,
  output reg                   done
);

  // Anti-diagonal wavefront windows for a 2x2 array (see header).
  localparam [2:0] CAPTURE = 3'd3;  // (ROWS-1)+(COLS-1)+1

  reg        running;
  reg  [2:0] cnt;

  // row r valid across cnt in [r, r + (COLS-1)]  (COLS-1 == 1 here)
  assign row0_valid = running & ((cnt == 3'd0) | (cnt == 3'd1));
  assign row1_valid = running & ((cnt == 3'd1) | (cnt == 3'd2));

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      running <= 1'b0;
      cnt     <= 3'd0;
      y0      <= {DATA_WIDTH{1'b0}};
      y1      <= {DATA_WIDTH{1'b0}};
      done    <= 1'b0;
    end
    else if (load_weights) begin
      // Weights are being latched into the PEs this cycle; do not compute.
      running <= 1'b0;
      cnt     <= 3'd0;
      done    <= 1'b0;
    end
    else if (!start) begin
      // start deasserted between tests: clear done and return to idle.
      running <= 1'b0;
      cnt     <= 3'd0;
      done    <= 1'b0;
    end
    else if (!running && !done) begin
      // start seen and no run in flight: kick off the wavefront.
      running <= 1'b1;
      cnt     <= 3'd0;
    end
    else if (running) begin
      cnt <= cnt + 3'd1;
      if (cnt == CAPTURE) begin
        // bottom-row psums are stable now -> register them and finish.
        y0      <= col0_psum;
        y1      <= col1_psum;
        done    <= 1'b1;   // held until start deasserts (handled above)
        running <= 1'b0;
      end
    end
    // once done is high with start still asserted, no branch fires: hold.
  end

endmodule
