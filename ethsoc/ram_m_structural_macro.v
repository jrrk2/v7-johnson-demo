// Structural RAM32M_MACRO / RAM64M_MACRO for the open flow: decompose the Vivado
// multi-port distributed-RAM macros into the exact leaf primitives and
// instance names Vivado's Unisim Transform creates (RAMA, RAMA_D1, ...)
// so a placement dump from the DCP applies 1:1 after yosys `flatten`
// (hierarchy separator '/' in Vivado <-> '.' in yosys).
//
// nextpnr-xilinx pack_dram consumes raw RAMD32/RAMS32/RAMD64E cells;
// declare them as blackboxes (cells_sim.v does not define them).
//
// All instances in this design have INIT_*=0; the INIT split is still
// forwarded for completeness (RAM32M_MACRO: INIT_X[2n]=bit0, [2n+1]=bit1).

(* blackbox, keep *) module RAMD32 (output O, input CLK, I, WE,
  input RADR0, RADR1, RADR2, RADR3, RADR4,
  input WADR0, WADR1, WADR2, WADR3, WADR4);
  parameter [31:0] INIT = 32'h0;
  parameter [0:0] IS_CLK_INVERTED = 1'b0;
endmodule

(* blackbox, keep *) module RAMS32 (output O, input CLK, I, WE,
  input ADR0, ADR1, ADR2, ADR3, ADR4);
  parameter [31:0] INIT = 32'h0;
  parameter [0:0] IS_CLK_INVERTED = 1'b0;
endmodule

(* blackbox, keep *) module RAMD64E (output O, input CLK, I, WE,
  input RADR0, RADR1, RADR2, RADR3, RADR4, RADR5,
  input WADR0, WADR1, WADR2, WADR3, WADR4, WADR5, WADR6, WADR7);
  parameter [63:0] INIT = 64'h0;
  parameter [0:0] IS_CLK_INVERTED = 1'b0;
endmodule

module RAM32M_MACRO (
  output [1:0] DOA, output [1:0] DOB, output [1:0] DOC, output [1:0] DOD,
  input [4:0] ADDRA, input [4:0] ADDRB, input [4:0] ADDRC, input [4:0] ADDRD,
  input [1:0] DIA, input [1:0] DIB, input [1:0] DIC, input [1:0] DID,
  input WCLK, input WE);
  parameter [63:0] INIT_A = 64'h0, INIT_B = 64'h0, INIT_C = 64'h0, INIT_D = 64'h0;
  parameter [0:0] IS_WCLK_INVERTED = 1'b0;

  function [31:0] half; input [63:0] v; input integer bit_idx; integer n; begin
    for (n = 0; n < 32; n = n + 1) half[n] = v[2*n + bit_idx];
  end endfunction

  RAMD32 #(.INIT(half(INIT_A,0)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMA (
    .CLK(WCLK), .WE(WE), .I(DIA[0]), .O(DOA[0]),
    .RADR0(ADDRA[0]), .RADR1(ADDRA[1]), .RADR2(ADDRA[2]), .RADR3(ADDRA[3]), .RADR4(ADDRA[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMD32 #(.INIT(half(INIT_A,1)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMA_D1 (
    .CLK(WCLK), .WE(WE), .I(DIA[1]), .O(DOA[1]),
    .RADR0(ADDRA[0]), .RADR1(ADDRA[1]), .RADR2(ADDRA[2]), .RADR3(ADDRA[3]), .RADR4(ADDRA[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMD32 #(.INIT(half(INIT_B,0)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMB (
    .CLK(WCLK), .WE(WE), .I(DIB[0]), .O(DOB[0]),
    .RADR0(ADDRB[0]), .RADR1(ADDRB[1]), .RADR2(ADDRB[2]), .RADR3(ADDRB[3]), .RADR4(ADDRB[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMD32 #(.INIT(half(INIT_B,1)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMB_D1 (
    .CLK(WCLK), .WE(WE), .I(DIB[1]), .O(DOB[1]),
    .RADR0(ADDRB[0]), .RADR1(ADDRB[1]), .RADR2(ADDRB[2]), .RADR3(ADDRB[3]), .RADR4(ADDRB[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMD32 #(.INIT(half(INIT_C,0)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMC (
    .CLK(WCLK), .WE(WE), .I(DIC[0]), .O(DOC[0]),
    .RADR0(ADDRC[0]), .RADR1(ADDRC[1]), .RADR2(ADDRC[2]), .RADR3(ADDRC[3]), .RADR4(ADDRC[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMD32 #(.INIT(half(INIT_C,1)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMC_D1 (
    .CLK(WCLK), .WE(WE), .I(DIC[1]), .O(DOC[1]),
    .RADR0(ADDRC[0]), .RADR1(ADDRC[1]), .RADR2(ADDRC[2]), .RADR3(ADDRC[3]), .RADR4(ADDRC[4]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]));
  RAMS32 #(.INIT(half(INIT_D,0)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMD (
    .CLK(WCLK), .WE(WE), .I(DID[0]), .O(DOD[0]),
    .ADR0(ADDRD[0]), .ADR1(ADDRD[1]), .ADR2(ADDRD[2]), .ADR3(ADDRD[3]), .ADR4(ADDRD[4]));
  RAMS32 #(.INIT(half(INIT_D,1)), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMD_D1 (
    .CLK(WCLK), .WE(WE), .I(DID[1]), .O(DOD[1]),
    .ADR0(ADDRD[0]), .ADR1(ADDRD[1]), .ADR2(ADDRD[2]), .ADR3(ADDRD[3]), .ADR4(ADDRD[4]));
endmodule

module RAM64M_MACRO (
  output DOA, output DOB, output DOC, output DOD,
  input [5:0] ADDRA, input [5:0] ADDRB, input [5:0] ADDRC, input [5:0] ADDRD,
  input DIA, input DIB, input DIC, input DID,
  input WCLK, input WE);
  parameter [63:0] INIT_A = 64'h0, INIT_B = 64'h0, INIT_C = 64'h0, INIT_D = 64'h0;
  parameter [0:0] IS_WCLK_INVERTED = 1'b0;

  RAMD64E #(.INIT(INIT_A), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMA (
    .CLK(WCLK), .WE(WE), .I(DIA), .O(DOA),
    .RADR0(ADDRA[0]), .RADR1(ADDRA[1]), .RADR2(ADDRA[2]), .RADR3(ADDRA[3]), .RADR4(ADDRA[4]), .RADR5(ADDRA[5]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]), .WADR5(ADDRD[5]));
  RAMD64E #(.INIT(INIT_B), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMB (
    .CLK(WCLK), .WE(WE), .I(DIB), .O(DOB),
    .RADR0(ADDRB[0]), .RADR1(ADDRB[1]), .RADR2(ADDRB[2]), .RADR3(ADDRB[3]), .RADR4(ADDRB[4]), .RADR5(ADDRB[5]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]), .WADR5(ADDRD[5]));
  RAMD64E #(.INIT(INIT_C), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMC (
    .CLK(WCLK), .WE(WE), .I(DIC), .O(DOC),
    .RADR0(ADDRC[0]), .RADR1(ADDRC[1]), .RADR2(ADDRC[2]), .RADR3(ADDRC[3]), .RADR4(ADDRC[4]), .RADR5(ADDRC[5]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]), .WADR5(ADDRD[5]));
  RAMD64E #(.INIT(INIT_D), .IS_CLK_INVERTED(IS_WCLK_INVERTED)) RAMD (
    .CLK(WCLK), .WE(WE), .I(DID), .O(DOD),
    .RADR0(ADDRD[0]), .RADR1(ADDRD[1]), .RADR2(ADDRD[2]), .RADR3(ADDRD[3]), .RADR4(ADDRD[4]), .RADR5(ADDRD[5]),
    .WADR0(ADDRD[0]), .WADR1(ADDRD[1]), .WADR2(ADDRD[2]), .WADR3(ADDRD[3]), .WADR4(ADDRD[4]), .WADR5(ADDRD[5]));
endmodule
