// In-context implementation harness for eth_macro: a minimal real top with
// bonded package pins (sysclk, SGMII, GT refclk) so Vivado can legally place
// the IBUFDS_GTE2/GTX (the OOC flow cannot: OOC IO sites are "not bonded").
// The macro's fabric logic is confined to a reserved pblock
// (build_eth_macro_harness.tcl); the msoc-side boundary ports are kept alive
// by dummy cpu_clk FF rings that are discarded at macro extraction.
`default_nettype none
module eth_macro_harness (
    input  wire clk_p,
    input  wire clk_n,
    input  wire rst,
    input  wire sgmii_rxp,
    input  wire sgmii_rxn,
    output wire sgmii_txp,
    output wire sgmii_txn,
    input  wire sgmii_refclk_p,
    input  wire sgmii_refclk_n,
    output wire [7:0] led
);
    // ---- sysclk -> 50 MHz cpu_clk (identical scaffold to vc707_ethloop) --
    wire sysclk_ibuf, sysclk, cpu_clk;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    BUFG sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));

    wire mmcm_fb, mmcm_clkout0, mmcm_locked;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"),
        .CLKIN1_PERIOD(5.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(20.000), .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5)
    ) cpu_mmcm (
        .CLKIN1(sysclk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb),
        .CLKOUT0(mmcm_clkout0),
        .RST(rst), .PWRDWN(1'b0), .LOCKED(mmcm_locked),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG cpu_bufg (.I(mmcm_clkout0), .O(cpu_clk));

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst || !mmcm_locked) resetn_cnt <= 0;
        else                     resetn_cnt <= resetn_cnt + !resetn;
    wire rst_sync = !resetn;

    // ---- dummy msoc-side boundary anchors (discarded at extraction) ------
    wire [5:0]  rx_wr_gray, tx_rd_gray;
    wire [71:0] rx_rd_data;
    wire [4:0]  tx_rd_addr;
    wire [15:0] pcspma_status;
    wire [31:0] rx_fcs_reg, tx_fcs_reg;
    wire        rx_overflow, phy_reset_n, eth_clk_o, gtrefclk_bufg_o;

    reg  [5:0]  rx_rd_gray = 0, tx_wr_gray = 0;
    reg  [4:0]  rx_rd_addr = 0;
    reg  [71:0] tx_rd_data = 0;
    always @(posedge cpu_clk) begin
        rx_rd_gray <= rx_rd_gray + {5'b0, ^rx_wr_gray};
        tx_wr_gray <= tx_wr_gray + {5'b0, ^tx_rd_gray};
        rx_rd_addr <= rx_rd_addr + 1'b1;
        tx_rd_data <= {tx_rd_data[70:0], ^rx_rd_data ^ (^tx_rd_addr)};
    end

    assign led = {rx_overflow, phy_reset_n, ^pcspma_status, ^rx_fcs_reg,
                  ^tx_fcs_reg, ^rx_rd_data, ^rx_wr_gray, ^tx_rd_gray};

    eth_macro u_macro (
        .clk_int(cpu_clk),
        .rst_int(rst_sync),
        .sgmii_rxp(sgmii_rxp), .sgmii_rxn(sgmii_rxn),
        .sgmii_txp(sgmii_txp), .sgmii_txn(sgmii_txn),
        .sgmii_refclk_p(sgmii_refclk_p), .sgmii_refclk_n(sgmii_refclk_n),
        .phy_reset_n(phy_reset_n),
        .eth_clk_o(eth_clk_o),
        .gtrefclk_bufg_o(gtrefclk_bufg_o),
        .rx_rd_gray(rx_rd_gray), .rx_wr_gray(rx_wr_gray),
        .rx_rd_addr(rx_rd_addr), .rx_rd_data(rx_rd_data),
        .tx_rd_gray(tx_rd_gray), .tx_wr_gray(tx_wr_gray),
        .tx_rd_addr(tx_rd_addr), .tx_rd_data(tx_rd_data),
        .pcspma_status(pcspma_status),
        .rx_fcs_reg(rx_fcs_reg),
        .tx_fcs_reg(tx_fcs_reg),
        .rx_overflow(rx_overflow));
endmodule
`default_nettype wire
