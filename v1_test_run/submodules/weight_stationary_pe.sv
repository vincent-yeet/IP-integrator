`timescale 1ns/1ns

//-----------------------------
// Processing Element
//-----------------------------
module weight_stationary_pe #(
  parameter DATA_WIDTH = 8  // Bit width of weights and activations
)
(
  input  wire                 clk,
  input  wire                 reset,
  input  wire                 load_weight,   // load the weight into the PE if high
  input  wire                 valid,         // signal to indicate new data is valid

  input  wire [DATA_WIDTH-1:0] input_in,     // input from left PE or from memory
  input  wire [DATA_WIDTH-1:0] weight,       // new weight to be loaded
  input  wire [DATA_WIDTH-1:0] psum_in,      // accumulated sum from the PE above

  output reg  [DATA_WIDTH-1:0] input_out,    // pass input to the right PE
  output reg  [DATA_WIDTH-1:0] psum_out      // pass accumulated sum downward
);

  reg [DATA_WIDTH-1:0] weight_reg; // register for holding weight locally

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      weight_reg <= {DATA_WIDTH{1'b0}};
      input_out  <= {DATA_WIDTH{1'b0}};
      psum_out   <= {DATA_WIDTH{1'b0}};
    end 
    else begin
      // Load the new weight if load_weight is high
      if (load_weight) begin
        weight_reg <= weight;
      end

      // Only update psum_out and input_out if 'valid' is high
      if (valid) begin
        psum_out  <= psum_in + (input_in * weight_reg);
        input_out <= input_in;
      end
      else begin
        // Hold the old values when not valid
        psum_out  <= psum_out;
        input_out <= input_out;
      end
    end
  end

endmodule