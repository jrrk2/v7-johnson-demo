// Blackbox stubs for the Xilinx primitives the calculator instantiates, with
// the full Vivado parameter set (yosys's built-in DSP48E1 model lacks the
// config params A_INPUT/USE_MULT/MASK/...).  Used only to give yosys-slang the
// module interfaces; synth_xilinx keeps these as hard primitives and
// nextpnr-xilinx consumes the params.
(* blackbox *) module IBUF (output O, input I); endmodule
(* blackbox *) module OBUF (output O, input I); endmodule
(* blackbox *) module BUFG (output O, input I); endmodule
(* blackbox *) module IBUFDS #(parameter DIFF_TERM="FALSE", parameter IBUF_LOW_PWR="TRUE", parameter IOSTANDARD="DEFAULT")
    (output O, input I, input IB); endmodule

(* blackbox *) module DSP48E1 #(
    parameter A_INPUT="DIRECT", parameter B_INPUT="DIRECT",
    parameter USE_DPORT="FALSE", parameter USE_MULT="MULTIPLY",
    parameter USE_SIMD="ONE48", parameter AUTORESET_PATDET="NO_RESET",
    parameter [47:0] MASK=48'h3fffffffffff, parameter [47:0] PATTERN=48'h0,
    parameter SEL_MASK="MASK", parameter SEL_PATTERN="PATTERN",
    parameter USE_PATTERN_DETECT="NO_PATDET",
    parameter integer ACASCREG=1, parameter integer ADREG=1,
    parameter integer ALUMODEREG=1, parameter integer AREG=1,
    parameter integer BCASCREG=1, parameter integer BREG=1,
    parameter integer CARRYINREG=1, parameter integer CARRYINSELREG=1,
    parameter integer CREG=1, parameter integer DREG=1, parameter integer INMODEREG=1,
    parameter integer MREG=1, parameter integer OPMODEREG=1, parameter integer PREG=1
) (
    input CLK,
    input  [29:0] A,   input  [17:0] B,   input  [47:0] C,   input  [24:0] D,
    input  [6:0]  OPMODE, input [3:0] ALUMODE, input [4:0] INMODE,
    input CARRYIN, input [2:0] CARRYINSEL,
    input  [29:0] ACIN, input [17:0] BCIN, input [47:0] PCIN,
    input CARRYCASCIN, input MULTSIGNIN,
    input CEA1, input CEA2, input CEAD, input CEALUMODE, input CEB1, input CEB2,
    input CEC, input CECARRYIN, input CECTRL, input CED, input CEINMODE,
    input CEM, input CEP,
    input RSTA, input RSTALLCARRYIN, input RSTALUMODE, input RSTB, input RSTC,
    input RSTCTRL, input RSTD, input RSTINMODE, input RSTM, input RSTP,
    output [47:0] P, output [47:0] PCOUT, output [29:0] ACOUT, output [17:0] BCOUT,
    output CARRYCASCOUT, output MULTSIGNOUT, output [3:0] CARRYOUT,
    output OVERFLOW, output PATTERNDETECT, output PATTERNBDETECT, output UNDERFLOW
); endmodule
