// Blackbox stub for framing_top_sgmii (the whole frozen `eth` block:
// msoc-side framing/FIFO logic + the hold-critical eth_macro).  Used when
// synthesising the USER logic (arp_ctrl + top glue) so synth_xilinx cannot
// touch or const-fold through the frozen block.  The real implementation
// (eth_gold_ym.v, yosys pass-through of the golden DCP) replaces this module
// at json-merge time, carrying its golden placement + routing.
(* blackbox *)
module framing_top_sgmii
  (
  input  wire         msoc_clk,
  input  wire [16:0]  core_lsu_addr,
  input  wire [63:0]  core_lsu_wdata,
  input  wire [7:0]   core_lsu_be,
  input  wire         ce_d,
  input  wire         we_d,
  input  wire         framing_sel,
  output wire [63:0]  framing_rdata,
  input  wire         clk_int,
  input  wire         rst_int,
  input  wire         sgmii_rxp,
  input  wire         sgmii_rxn,
  output wire         sgmii_txp,
  output wire         sgmii_txn,
  input  wire         sgmii_refclk_p,
  input  wire         sgmii_refclk_n,
  output wire         phy_reset_n,
  input  wire         phy_mdio_i,
  output wire         phy_mdio_o,
  output wire         phy_mdio_oe,
  output wire         phy_mdc,
  output wire         eth_irq,
  output wire [15:0]  pcspma_status_o,
  output wire         eth_clk_o,
  output wire         gtrefclk_bufg_o
   );
endmodule
