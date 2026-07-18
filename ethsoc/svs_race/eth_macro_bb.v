(* black_box *)
module eth_macro (
    input  wire         clk_int,
    input  wire         rst_int,
    input  wire         sgmii_rxp,
    input  wire         sgmii_rxn,
    output wire         sgmii_txp,
    output wire         sgmii_txn,
    input  wire         sgmii_refclk_p,
    input  wire         sgmii_refclk_n,
    output wire         phy_reset_n,
    output wire         eth_clk_o,
    output wire         gtrefclk_bufg_o,
    input  wire [5:0]   rx_rd_gray,
    output wire [5:0]   rx_wr_gray,
    input  wire [4:0]   rx_rd_addr,
    output wire [71:0]  rx_rd_data,
    output wire [5:0]   tx_rd_gray,
    input  wire [5:0]   tx_wr_gray,
    output wire [4:0]   tx_rd_addr,
    input  wire [71:0]  tx_rd_data,
    output wire [15:0]  pcspma_status,
    output wire [31:0]  rx_fcs_reg,
    output wire [31:0]  tx_fcs_reg,
    output wire         rx_overflow
);
endmodule
