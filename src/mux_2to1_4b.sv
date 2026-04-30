/*
* Instituto Tecnológico de Costa Rica
* Prof. Dr.-ing. Pablo Mendoza Ponce
* Rev. 1 28 July 2024
*/

`timescale 1ns/1ps

module mux_2to1_4b(
  input logic [3:0]  a_i,
  input logic [3:0]  b_i,
  input logic        s_i,
  output logic [3:0] q_o);
 

 
  //<<<<<<<<<<<< HDL DESCRIPTION HERE >>>>>>>>>>>>>>>>>
 
    always_comb begin
    if (s_i == 1'b0) begin
      q_o = a_i;
    end else    begin
       q_o = b_i;
    end
  end
 
endmodule