// Black-box declarations for yosys (open flow), after uartram/xil_bb.v.
// RAMB36E1 is left to synth_xilinx's own cell library; the pcs_pma IP is
// black-boxed via its Vivado-generated stub plus the `blackbox` command.
(* blackbox *) module IBUF (output O, input I); endmodule
(* blackbox *) module OBUF (output O, input I); endmodule
(* blackbox *) module BUFG (output O, input I); endmodule
(* blackbox *) module IBUFDS #(parameter DIFF_TERM="FALSE", parameter IBUF_LOW_PWR="TRUE", parameter IOSTANDARD="DEFAULT")
   (output O, input I, input IB); endmodule
