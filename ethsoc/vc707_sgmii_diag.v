// VC707 SGMII diagnostic top: PCS/PMA status observer, NO data path.
//
// Instantiates sgmii_soc alone with the TX AXI-stream tied idle (tvalid=0),
// so the PCS transmits only idles / autoneg config words.  The full 16-bit
// pcspma_status vector plus sticky error latches and clock heartbeats are
// paged onto the 8 LEDs by GPIO DIP switches sw[1:0]:
//
//   sw=00: live status[7:0]
//        [0]=link  [1]=sync  [2]=RUDI(/C/)  [3]=RUDI(/I/)
//        [4]=RUDI(invalid)  [5]=rxdisperr  [6]=rxnotintable  [7]=PHY link
//   sw=01: live status[15:8]   ([9:8]=speed  [10]=duplex  [13:12]=pause)
//   sw=10: sticky (ever since reset):
//        [0]=link  [1]=sync  [2]=/C/ seen  [3]=/I/ seen
//        [4]=RUDI invalid  [5]=disperr  [6]=notintable  [7]=AN restarted (link dropped after link)
//   sw=11: liveness: [0]=hb cpu_clk  [1]=hb eth_clk  [2]=hb rx_clk
//        [3]=rx_axis_tvalid seen  [4]=mac_gmii_tx_en seen  [5]=tx_axis_tready
//        [6]=resetn  [7]=mmcm_locked
//
// Clock/reset plumbing identical to vc707_arp.v.
`default_nettype none
module top (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led,
    input  wire [1:0] sw,
    input  wire       sgmii_rxp, sgmii_rxn,
    output wire       sgmii_txp, sgmii_txn,
    input  wire       sgmii_refclk_p, sgmii_refclk_n,
    output wire       eth_rst_n,
    inout  wire       eth_mdio,
    output wire       eth_mdc
);
    // ---------------- clocks / reset (identical to vc707_arp) --------------
    wire sysclk_ibuf, sysclk, cpu_clk;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    BUFG sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));
    wire mmcm_fb, mmcm_clkout0, mmcm_locked;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"),
        .CLKIN1_PERIOD(5.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(20.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5)
    ) cpu_mmcm (
        .CLKIN1(sysclk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb), .CLKOUT0(mmcm_clkout0),
        .RST(rst), .PWRDWN(1'b0), .LOCKED(mmcm_locked),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG cpu_bufg (.I(mmcm_clkout0), .O(cpu_clk));

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst || !mmcm_locked) resetn_cnt <= 0; else resetn_cnt <= resetn_cnt + !resetn;
    wire rst_sync = !resetn;

    // ---------------- MDIO idle (nothing programs the PHY here) ------------
    assign eth_mdio = 1'bz;
    assign eth_mdc  = 1'b0;
    assign uart_tx  = 1'b1;

    // ---------------- sgmii_soc, TX idle -----------------------------------
    wire        eth_clk, rx_clk;
    wire [7:0]  rx_axis_tdata;
    wire        rx_axis_tvalid, rx_axis_tlast, rx_axis_tuser;
    wire        tx_axis_tready, mac_gmii_tx_en;
    wire [15:0] pcspma_status;

    sgmii_soc i_sgmii (
        .clk_int         (cpu_clk),
        .rst_int         (rst_sync),
        .eth_clk         (eth_clk),
        .sgmii_rxp       (sgmii_rxp),
        .sgmii_rxn       (sgmii_rxn),
        .sgmii_txp       (sgmii_txp),
        .sgmii_txn       (sgmii_txn),
        .sgmii_refclk_p  (sgmii_refclk_p),
        .sgmii_refclk_n  (sgmii_refclk_n),
        .phy_reset_n     (eth_rst_n),
        .mac_gmii_tx_en  (mac_gmii_tx_en),
        .tx_axis_tvalid  (1'b0),
        .tx_axis_tlast   (1'b0),
        .tx_axis_tdata   (8'h0),
        .tx_axis_tready  (tx_axis_tready),
        .tx_axis_tuser   (1'b0),
        .rx_clk          (rx_clk),
        .rx_axis_tdata   (rx_axis_tdata),
        .rx_axis_tvalid  (rx_axis_tvalid),
        .rx_axis_tlast   (rx_axis_tlast),
        .rx_axis_tuser   (rx_axis_tuser),
        .rx_fcs_reg      (),
        .tx_fcs_reg      (),
        .pcspma_status   (pcspma_status),
        .gtrefclk_bufg_out()
    );

    // ---------------- sticky latches (eth_clk domain) -----------------------
    reg [7:0] sticky = 0;      // see page map above
    reg       link_d = 0;
    always @(posedge eth_clk) begin
        link_d <= pcspma_status[0];
        if (pcspma_status[0]) sticky[0] <= 1'b1;
        if (pcspma_status[1]) sticky[1] <= 1'b1;
        if (pcspma_status[2]) sticky[2] <= 1'b1;
        if (pcspma_status[3]) sticky[3] <= 1'b1;
        if (pcspma_status[4]) sticky[4] <= 1'b1;
        if (pcspma_status[5]) sticky[5] <= 1'b1;
        if (pcspma_status[6]) sticky[6] <= 1'b1;
        if (link_d && !pcspma_status[0]) sticky[7] <= 1'b1;   // link achieved then lost
    end
    reg rx_seen = 0, txen_seen = 0;
    always @(posedge rx_clk)  if (rx_axis_tvalid) rx_seen  <= 1'b1;
    always @(posedge eth_clk) if (mac_gmii_tx_en) txen_seen <= 1'b1;

    // ---------------- heartbeats -------------------------------------------
    reg [25:0] hb_cpu = 0;  always @(posedge cpu_clk) hb_cpu <= hb_cpu + 1'b1;
    reg [26:0] hb_eth = 0;  always @(posedge eth_clk) hb_eth <= hb_eth + 1'b1;
    reg [26:0] hb_rx  = 0;  always @(posedge rx_clk)  hb_rx  <= hb_rx  + 1'b1;

    // ---------------- page mux (async sampling into cpu_clk, diag only) ----
    reg [15:0] st0, st1;
    reg [7:0]  sk0, sk1;
    reg [4:0]  ms0, ms1;   // {hb_eth.msb, hb_rx.msb, rx_seen, txen_seen, tready}
    always @(posedge cpu_clk) begin
        st0 <= pcspma_status;  st1 <= st0;
        sk0 <= sticky;         sk1 <= sk0;
        ms0 <= {hb_eth[26], hb_rx[26], rx_seen, txen_seen, tx_axis_tready};
        ms1 <= ms0;
    end

    reg [7:0] page;
    always @(posedge cpu_clk)
        case (sw)
            2'b00: page <= st1[7:0];
            2'b01: page <= st1[15:8];
            2'b10: page <= sk1;
            2'b11: page <= {mmcm_locked, resetn, ms1[0], ms1[1], ms1[2],
                            ms1[3], ms1[4], hb_cpu[25]};
        endcase
    assign led = page;
endmodule
`default_nettype wire
