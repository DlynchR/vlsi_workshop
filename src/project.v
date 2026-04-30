/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
 
`default_nettype none
 
module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
 
  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out[7:4]  = 0;
  assign uio_out = 0;
  assign uio_oe[7:1]  = 0;
 
  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, uio_in[7:1], 1'b0};
 
  assign uio_oe[0] = 1'b0; // Set all IOs to input mode
 
  mux_2to1_4b U0 (
  .a_i(ui_in[3:0]),
  .b_i(uio_in[7:4]),
  .s_i(uio_oe[0]),
  .q_o(uio_out[3:0]) );
 
 
 
endmodule