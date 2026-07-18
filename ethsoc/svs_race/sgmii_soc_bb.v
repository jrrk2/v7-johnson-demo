(* black_box *)
module sgmii_soc (
    input  wire         clk_int,
    input  wire         rst_int,
    output wire         eth_clk,
    input  wire         sgmii_rxp,
    input  wire         sgmii_rxn,
    output wire         sgmii_txp,
    output wire         sgmii_txn,
    input  wire         sgmii_refclk_p,
    input  wire         sgmii_refclk_n,
    output wire         phy_reset_n,
    output wire         mac_gmii_tx_en,
    input  wire         tx_axis_tvalid,
    input  wire         tx_axis_tlast,
    input  wire [7:0]   tx_axis_tdata,
    output wire         tx_axis_tready,
    input  wire         tx_axis_tuser,
    output wire         rx_clk,
    output wire [7:0]   rx_axis_tdata,
    output wire         rx_axis_tvalid,
    output wire         rx_axis_tlast,
    output wire         rx_axis_tuser,
    output wire [31:0]  rx_fcs_reg,
    output wire [31:0]  tx_fcs_reg,
    output wire [15:0]  pcspma_status,
    output wire         gtrefclk_bufg_out
);
endmodule
