(* black_box *)
module arp_ctrl #(
    parameter [47:0] FPGA_MAC = 48'h02_00_00_4B_41_31,
    parameter [31:0] FPGA_IP  = 32'hC0_A8_01_64
) (
    input  wire         clk,
    input  wire         rst_n,
    output wire [16:0]  core_lsu_addr,
    output wire [63:0]  core_lsu_wdata,
    output wire [7:0]   core_lsu_be,
    output wire         ce_d,
    output wire         we_d,
    output wire         framing_sel,
    input  wire  [63:0] framing_rdata,
    output wire         led_arp,
    output wire [15:0]  reply_count,
    output wire [3:0]   dbg_state
);
endmodule
