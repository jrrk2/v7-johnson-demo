// eth_macro — the frozen 125 MHz Ethernet island for the open flow.
//
// Contains everything clocked by eth_clk/rx_clk: the SGMII PCS/PMA + GTX +
// MAC (sgmii_soc), the RX byte->word packer with the RX FIFO write half
// (pointer + distributed-RAM array), and the TX word->byte unpacker with the
// TX FIFO read half.  Implemented once by Vivado OOC (hold-clean), then
// imported into the nextpnr flow as a placed+routed macro.
//
// Boundary discipline: no same-clock FF->FF arc crosses this module's
// interface.  The crossings are
//   * Gray pointers (each side consumes the far pointer through a 2-flop
//     synchroniser inside its own half) — async by construction;
//   * the distributed-RAM read ports (rx_rd_addr in / rx_rd_data out and
//     tx_rd_addr out / tx_rd_data in) — combinational, consumed only when
//     the async-FIFO occupancy argument guarantees the addressed entry is
//     stable;
//   * quasi-static debug/status (fcs regs, pcspma_status) — unsynchronised
//     reads, same as the pre-split design.
`default_nettype none
(* keep_hierarchy = "yes" *)
module eth_macro (
    input  wire         clk_int,        // free-running clock for PCS/PMA IP
    input  wire         rst_int,

    // SGMII serial pins + 125 MHz refclk
    input  wire         sgmii_rxp,
    input  wire         sgmii_rxn,
    output wire         sgmii_txp,
    output wire         sgmii_txn,
    input  wire         sgmii_refclk_p,
    input  wire         sgmii_refclk_n,
    output wire         phy_reset_n,

    // clock exports (top-level use)
    output wire         eth_clk_o,
    output wire         gtrefclk_bufg_o,

    // RX FIFO boundary (write half + RAM inside; read half in msoc region)
    input  wire [5:0]   rx_rd_gray,
    output wire [5:0]   rx_wr_gray,
    input  wire [4:0]   rx_rd_addr,
    output wire [71:0]  rx_rd_data,

    // TX FIFO boundary (read half inside; write half + RAM in msoc region)
    output wire [5:0]   tx_rd_gray,
    input  wire [5:0]   tx_wr_gray,
    output wire [4:0]   tx_rd_addr,
    input  wire [71:0]  tx_rd_data,

    // quasi-static status
    output wire [15:0]  pcspma_status,
    output wire [31:0]  rx_fcs_reg,
    output wire [31:0]  tx_fcs_reg,
    output wire         rx_overflow     // sticky debug flag (rx_clk domain)
);
    wire        eth_clk;
    wire        rx_clk;
    assign eth_clk_o = eth_clk;

    // AXIS between MAC and converters
    wire [7:0]  rx_axis_tdata;
    wire        rx_axis_tvalid, rx_axis_tlast, rx_axis_tuser;
    wire [7:0]  tx_axis_tdata;
    wire        tx_axis_tvalid, tx_axis_tready, tx_axis_tlast, tx_axis_tuser;
    wire        mac_gmii_tx_en;

    // ---- RX: packer -> FIFO write half (rx_clk) --------------------------
    wire        rxf_wr_en, rxf_wr_full;
    wire [71:0] rxf_wr_data;

    rx_axis_packer u_rx_pack (
        .clk(rx_clk), .rst(rst_int),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tlast(rx_axis_tlast),
        .wr_en(rxf_wr_en), .wr_data(rxf_wr_data), .wr_full(rxf_wr_full),
        .overflow(rx_overflow));

    async_fifo_wr #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_rxf_wr (
        .wr_clk(rx_clk), .wr_rst(rst_int),
        .wr_en(rxf_wr_en), .wr_data(rxf_wr_data), .wr_full(rxf_wr_full),
        .wr_gray(rx_wr_gray), .rd_gray(rx_rd_gray),
        .rd_addr(rx_rd_addr), .rd_data(rx_rd_data));

    // ---- TX: FIFO read half -> unpacker (eth_clk) ------------------------
    wire        txf_rd_en, txf_rd_empty;
    wire [71:0] txf_rd_data;

    async_fifo_rd #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_txf_rd (
        .rd_clk(eth_clk), .rd_rst(rst_int),
        .rd_en(txf_rd_en), .rd_data(txf_rd_data), .rd_empty(txf_rd_empty),
        .rd_gray(tx_rd_gray), .wr_gray(tx_wr_gray),
        .rd_addr(tx_rd_addr), .rd_data_mem(tx_rd_data));

    tx_axis_unpacker u_tx_unpack (
        .clk(eth_clk), .rst(rst_int),
        .rd_data(txf_rd_data), .rd_empty(txf_rd_empty), .rd_en(txf_rd_en),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tuser(tx_axis_tuser));

    // ---- PCS/PMA + GTX + MAC ---------------------------------------------
    sgmii_soc sgmii_soc1 (
        .clk_int(clk_int),
        .rst_int(rst_int),
        .eth_clk(eth_clk),
        .sgmii_rxp(sgmii_rxp),
        .sgmii_rxn(sgmii_rxn),
        .sgmii_txp(sgmii_txp),
        .sgmii_txn(sgmii_txn),
        .sgmii_refclk_p(sgmii_refclk_p),
        .sgmii_refclk_n(sgmii_refclk_n),
        .phy_reset_n(phy_reset_n),
        .mac_gmii_tx_en(mac_gmii_tx_en),
        .rx_clk(rx_clk),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tuser(tx_axis_tuser),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),
        .rx_fcs_reg(rx_fcs_reg),
        .tx_fcs_reg(tx_fcs_reg),
        .pcspma_status(pcspma_status),
        .gtrefclk_bufg_out(gtrefclk_bufg_o));
endmodule
`default_nettype wire
