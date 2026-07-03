`timescale 1ns/1ns
//=============================================================================
// systolic_array  (top level)
//
// 2x2 weight-stationary systolic array built from four weight_stationary_pe
// PEs plus the systolic_controller glue. Matches the interface expected by
// submodules/systolic_array_tb.sv.
//
// Layout (r = row, c = col), instances pe{r}{c}:
//
//        col0            col1
//      +-------+       +-------+
// row0 | pe00  |--in-->| pe01  |     activations flow west -> east
//      | w00   |       | w01   |
//      +---+---+       +---+---+
//          | psum          | psum   partial sums flow north -> south
//          v               v
//      +---+---+       +---+---+
// row1 | pe10  |--in-->| pe11  |
//      | w10   |       | w11   |
//      +---+---+       +---+---+
//          |               |
//         y0(col0)        y1(col1)   (registered in the controller)
//
//   Top-row psum_in tied to 0. West-edge input_in fed from x0 (row0) / x1 (row1).
//   Results: y0 = x0*w00 + x1*w10 ; y1 = x0*w01 + x1*w11 (each truncated to 8b).
//=============================================================================
module systolic_array #(
  parameter DATA_WIDTH = 8
)(
  input  wire                  clk,
  input  wire                  reset,        // active-high async reset
  input  wire                  load_weights, // hold high >=1 cycle to latch weights
  input  wire                  start,        // begin a computation

  input  wire [DATA_WIDTH-1:0] w00, w01,     // stationary weights, row 0
  input  wire [DATA_WIDTH-1:0] w10, w11,     // stationary weights, row 1

  input  wire [DATA_WIDTH-1:0] x0,           // row 0 activation
  input  wire [DATA_WIDTH-1:0] x1,           // row 1 activation

  output wire [DATA_WIDTH-1:0] y0,           // registered result, column 0
  output wire [DATA_WIDTH-1:0] y1,           // registered result, column 1
  output wire                  done          // high once y0/y1 are valid
);

  localparam ROWS = 2;
  localparam COLS = 2;

  // Forwarded PE outputs, indexed [row][col].
  wire [DATA_WIDTH-1:0] pe_input_out [0:ROWS-1][0:COLS-1]; // activation passed east
  wire [DATA_WIDTH-1:0] pe_psum_out  [0:ROWS-1][0:COLS-1]; // partial sum passed south

  // Stationary weight matrix: weight_mat[r][c] holds w{r}{c}.
  wire [DATA_WIDTH-1:0] weight_mat [0:ROWS-1][0:COLS-1];
  assign weight_mat[0][0] = w00;
  assign weight_mat[0][1] = w01;
  assign weight_mat[1][0] = w10;
  assign weight_mat[1][1] = w11;

  // West-edge activation into column 0 of each row.
  wire [DATA_WIDTH-1:0] row_in [0:ROWS-1];
  assign row_in[0] = x0;
  assign row_in[1] = x1;

  // Per-row compute strobes from the controller.
  wire            row0_valid, row1_valid;
  wire [ROWS-1:0] row_valid = {row1_valid, row0_valid}; // row_valid[r]

  // -------------------------------------------------------------------------
  // PE mesh: identical PE instantiated per (r,c) with neighbor/boundary wiring.
  // -------------------------------------------------------------------------
  genvar r, c;
  generate
    for (r = 0; r < ROWS; r = r + 1) begin : gen_row
      for (c = 0; c < COLS; c = c + 1) begin : gen_col
        // input_in: west edge -> external row activation; else from west PE.
        // (c ? c-1 : 0 keeps the array index in bounds for the c==0 edge; the
        //  ternary selects row_in there so the index value is irrelevant.)
        wire [DATA_WIDTH-1:0] input_in_w =
              (c == 0) ? row_in[r] : pe_input_out[r][(c == 0) ? 0 : c-1];
        // psum_in: top edge -> const 0; else from north PE.
        wire [DATA_WIDTH-1:0] psum_in_w =
              (r == 0) ? {DATA_WIDTH{1'b0}} : pe_psum_out[(r == 0) ? 0 : r-1][c];

        weight_stationary_pe #(.DATA_WIDTH(DATA_WIDTH)) pe (
          .clk        (clk),
          .reset      (reset),
          .load_weight(load_weights),          // control: shared weight-load
          .valid      (row_valid[r]),          // control: this row's strobe
          .input_in   (input_in_w),            // west neighbour / x{r}
          .weight     (weight_mat[r][c]),      // external stationary weight
          .psum_in    (psum_in_w),             // north neighbour / 0
          .input_out  (pe_input_out[r][c]),    // -> east neighbour
          .psum_out   (pe_psum_out[r][c])      // -> south neighbour / result
        );
      end
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Controller: staggers row valids, registers the bottom-row psums to y0/y1.
  // -------------------------------------------------------------------------
  systolic_controller #(.DATA_WIDTH(DATA_WIDTH)) ctrl (
    .clk         (clk),
    .reset       (reset),
    .start       (start),
    .load_weights(load_weights),
    .col0_psum   (pe_psum_out[ROWS-1][0]),     // pe10.psum_out
    .col1_psum   (pe_psum_out[ROWS-1][1]),     // pe11.psum_out
    .row0_valid  (row0_valid),
    .row1_valid  (row1_valid),
    .y0          (y0),
    .y1          (y1),
    .done        (done)
  );

endmodule
