`timescale 1ns/1ns

module systolic_array_tb;

  // --------------------------------------------------------------------------
  // Parameters & Local Variables
  // --------------------------------------------------------------------------
  localparam DATA_WIDTH = 8;
  localparam CLK_PERIOD = 10;  // 10 ns = 100 MHz

  // We'll run multiple tests in sequence.
  // For each test, we store:
  //    w00, w01, w10, w11, x0, x1, and the expected y0, y1
  // The results are: 
  //    y0 = (x0 * w00) + (x1 * w10)
  //    y1 = (x0 * w01) + (x1 * w11)
  //
  // NOTE: In the provided design, psum_out is only 8 bits, so the results
  //       may wrap around (overflow) if the sum exceeds 8 bits (255 for unsigned).
  //       If you want to test overflow behavior, see the last test case.

  // We'll store multiple test vectors in arrays.
  // Increase TEST_COUNT if you add more test vectors.
  localparam TEST_COUNT = 7;

  reg [DATA_WIDTH-1:0] w00_test [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] w01_test [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] w10_test [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] w11_test [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] x0_test  [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] x1_test  [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] y0_exp   [0:TEST_COUNT-1];
  reg [DATA_WIDTH-1:0] y1_exp   [0:TEST_COUNT-1];

  // --------------------------------------------------------------------------
  // Testbench signals
  // --------------------------------------------------------------------------
  reg                      clk;
  reg                      reset;
  reg                      load_weights;
  reg                      start;
  reg  [DATA_WIDTH-1:0]    w00, w01, w10, w11;
  reg  [DATA_WIDTH-1:0]    x0,  x1;
  wire [DATA_WIDTH-1:0]    y0,  y1;
  wire                     done;

  // --------------------------------------------------------------------------
  // Instantiate the DUT (Device Under Test)
  // --------------------------------------------------------------------------
  systolic_array #(
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk         (clk),
    .reset       (reset),
    .load_weights(load_weights),
    .start       (start),
    .w00         (w00),
    .w01         (w01),
    .w10         (w10),
    .w11         (w11),
    .x0          (x0),
    .x1          (x1),
    .y0          (y0),
    .y1          (y1),
    .done        (done)
  );

  // --------------------------------------------------------------------------
  // Clock Generation
  // --------------------------------------------------------------------------
  always begin
    clk = 1'b0; 
    #(CLK_PERIOD/2);
    clk = 1'b1; 
    #(CLK_PERIOD/2);
  end

  // --------------------------------------------------------------------------
  // Test Vector Initialization
  // --------------------------------------------------------------------------
  initial begin
    // Test 0: Simple: All weights = 1, x0=2, x1=3
    //   y0 = 2*1 + 3*1 = 5
    //   y1 = 2*1 + 3*1 = 5
    w00_test[0] = 8'd1; w01_test[0] = 8'd1; w10_test[0] = 8'd1; w11_test[0] = 8'd1;
    x0_test[0]  = 8'd2; x1_test[0]  = 8'd3;
    y0_exp[0]   = 8'd5; y1_exp[0]   = 8'd5;

    // Test 1: Another normal case
    //   w00=2, w01=3, w10=4, w11=5, x0=6, x1=7
    //   y0 = 6*2 + 7*4 = 12 + 28 = 40 (0x28)
    //   y1 = 6*3 + 7*5 = 18 + 35 = 53 (0x35)
    w00_test[1] = 8'd2;  w01_test[1] = 8'd3;  w10_test[1] = 8'd4;  w11_test[1] = 8'd5;
    x0_test[1]  = 8'd6;  x1_test[1]  = 8'd7;
    y0_exp[1]   = 8'd40; y1_exp[1]   = 8'd53;

    // Test 2: Check zero weights
    //   w00=0, w01=0, w10=0, w11=0, x0=10, x1=20
    //   y0 = 10*0 + 20*0 = 0
    //   y1 = 10*0 + 20*0 = 0
    w00_test[2] = 8'd0;  w01_test[2] = 8'd0;  w10_test[2] = 8'd0;  w11_test[2] = 8'd0;
    x0_test[2]  = 8'd10; x1_test[2]  = 8'd20;
    y0_exp[2]   = 8'd0;  y1_exp[2]   = 8'd0;

    // Test 3: Check zero inputs
    //   w00=5, w01=4, w10=3, w11=2, x0=0, x1=0
    //   y0 = 0*5 + 0*3 = 0
    //   y1 = 0*4 + 0*2 = 0
    w00_test[3] = 8'd5;  w01_test[3] = 8'd4;  w10_test[3] = 8'd3;  w11_test[3] = 8'd2;
    x0_test[3]  = 8'd0;  x1_test[3]  = 8'd0;
    y0_exp[3]   = 8'd0;  y1_exp[3]   = 8'd0;

    // Test 4: Check maximum values (unsigned interpretation)
    //   w00=255, w01=255, w10=255, w11=255, x0=255, x1=255
    //   The multiplication 255*255 = 65025 decimal = 0xFE01 in 16 bits,
    //   but only lower 8 bits stored => 0x01. Then psum_in + 0x01 => might cause repeated overflow.
    //   Pipeline flow for y0 =>  (255*255)(LSB only) + (255*255)(LSB only) ...
    //   This test will show how it saturates/overflows within 8 bits.
    //   Expected result is not typical for "true multiply," it's the truncated 8-bit result:
    //   The design does: psum_out <= (psum_in + (input_in * weight_reg)) & 0xFF
    //   So 255*255=65025 => 8-bit truncated = 0x01
    //   So y0 = 0x01 + 0x01 = 0x02, y1 = 0x01 + 0x01 = 0x02 in final pipeline stage
    //   (Because of the pipeline, the final sums can shift. Let's keep it simple 
    //    and say we expect 2 for both. For a pure 2×2 multiply, "real" result is 255*255*2=~130050, 
    //    but we are only capturing LSB in each step.)
    w00_test[4] = 8'hFF; w01_test[4] = 8'hFF; w10_test[4] = 8'hFF; w11_test[4] = 8'hFF;
    x0_test[4]  = 8'hFF; x1_test[4]  = 8'hFF;
    y0_exp[4]   = 8'd2;  y1_exp[4]   = 8'd2;

    // Test 5: Mixed smaller large values for partial demonstration
    //   w00=100, w01=150, w10=200, w11=250, x0=8, x1=3
    //   y0 = 8*100 + 3*200 = 800 + 600 = 1400 => truncated to 8 bits => 1400 mod 256 = 1400 - 5*256= 1400-1280=120
    //   y1 = 8*150 + 3*250 = 1200 + 750 = 1950 => mod 256 => 1950 - 7*256= 1950-1792=158
    w00_test[5] = 8'd100; w01_test[5] = 8'd150; w10_test[5] = 8'd200; w11_test[5] = 8'd250;
    x0_test[5]  = 8'd8;   x1_test[5]  = 8'd3;
    y0_exp[5]   = 8'd120; y1_exp[5]   = 8'd158;

    // Test 6: Minimal/edge case (all zeros) repeated, to show no glitch
    //   wXX=0, xX=0 => y0=0, y1=0
    w00_test[6] = 8'd0;  w01_test[6] = 8'd0;  w10_test[6] = 8'd0;  w11_test[6] = 8'd0;
    x0_test[6]  = 8'd0;  x1_test[6]  = 8'd0;
    y0_exp[6]   = 8'd0;  y1_exp[6]   = 8'd0;
  end

  // --------------------------------------------------------------------------
  // Main Test Sequence
  // --------------------------------------------------------------------------
  integer i;
  initial begin
    // Display header
    $display("==========================================");
    $display(" Starting 2x2 Systolic Array Testbench...");
    $display("==========================================");

    // Initialize signals
    clk           = 1'b0;
    reset         = 1'b1;
    load_weights  = 1'b0;
    start         = 1'b0;
    w00           = {DATA_WIDTH{1'b0}};
    w01           = {DATA_WIDTH{1'b0}};
    w10           = {DATA_WIDTH{1'b0}};
    w11           = {DATA_WIDTH{1'b0}};
    x0            = {DATA_WIDTH{1'b0}};
    x1            = {DATA_WIDTH{1'b0}};

    // Wait a few cycles before deasserting reset
    #(5*CLK_PERIOD);
    reset = 1'b0;
    #(2*CLK_PERIOD);

    // Run through each test
    for (i = 0; i < TEST_COUNT; i = i + 1) begin
      // 1) Load the weights
      w00 = w00_test[i];
      w01 = w01_test[i];
      w10 = w10_test[i];
      w11 = w11_test[i];

      // Assert load_weights for at least one cycle so the PEs can latch the new weights
      load_weights = 1'b1;
      #(CLK_PERIOD);
      load_weights = 1'b0;

      // 2) Apply inputs and start
      x0    = x0_test[i];
      x1    = x1_test[i];
      start = 1'b1;

      // Wait for done to assert
      wait(done === 1'b1);

      // Once done is high for at least one cycle, we can capture the outputs.
      //   (You could wait for the negedge of done as well if the design pulses it, 
      //    but in this example, once it goes high it remains high until start is deasserted)
      #(CLK_PERIOD);

      // 3) Compare with expected
      if ((y0 === y0_exp[i]) && (y1 === y1_exp[i])) begin
        $display("Test %0d PASSED. y0=%0d, y1=%0d (Expected %0d, %0d)",
                  i, y0, y1, y0_exp[i], y1_exp[i]);
      end else begin
        $display("Test %0d FAILED. y0=%0d, y1=%0d (Expected %0d, %0d)",
                  i, y0, y1, y0_exp[i], y1_exp[i]);
      end

      // Deassert start and wait a couple of cycles before next test
      start = 1'b0;
      #(2*CLK_PERIOD);
    end

    // End of all tests
    $display("==========================================");
    $display(" All tests completed.");
    $display("==========================================");

    $finish;
  end

endmodule