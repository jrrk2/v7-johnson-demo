// VC707 PicoSoC + lowRISC SGMII ethernet (framing_top_sgmii).
// Clocks: 200 MHz LVDS sysclk -> /2 = 100 MHz cpu_clk (msoc_clk),
//         -> /4 = 50 MHz independent clock for the PCS/PMA IP (its
//         DrpClkRate is 50.0); 125 MHz MAC clock comes out of the IP.
// Memory map: 0x0300_0000 gpio/LEDs, 0x0300_0004 pcspma_status (RO),
//             0x0400_0000..0x0401_FFFF ethernet (framing_top, 17-bit).
// eth_irq -> picorv32 irq[5].
module top (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led,
    // SGMII (GTX bank 117) + PHY management
    input  wire       sgmii_rxp, sgmii_rxn,
    output wire       sgmii_txp, sgmii_txn,
    input  wire       sgmii_refclk_p, sgmii_refclk_n,
    output wire       eth_rst_n,
    inout  wire       eth_mdio,
    output wire       eth_mdc
);
    wire sysclk_ibuf, sysclk, cpu_clk, eth_int_clk;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    BUFG sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));

    reg clkdiv2 = 1'b0;
    reg [1:0] clkdiv4 = 2'b0;
    always @(posedge sysclk) begin
        clkdiv2 <= ~clkdiv2;
        clkdiv4 <= clkdiv4 + 1'b1;
    end
    BUFG cpu_bufg (.I(clkdiv2), .O(cpu_clk));
    BUFG eth_bufg (.I(clkdiv4[1]), .O(eth_int_clk));

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst) resetn_cnt <= 0;
        else     resetn_cnt <= resetn_cnt + !resetn;

    // MDIO tristate
    wire phy_mdio_i, phy_mdio_o, phy_mdio_oe;
    assign eth_mdio = phy_mdio_oe ? phy_mdio_o : 1'bz;
    assign phy_mdio_i = eth_mdio;

    // PCS/PMA status, synchronized into the CPU domain (quasi-static)
    wire [15:0] pcspma_status;
    reg  [15:0] status_sync0, status_sync1;
    always @(posedge cpu_clk) begin
        status_sync0 <= pcspma_status;
        status_sync1 <= status_sync0;
    end

    wire iomem_valid;
    reg  iomem_ready;
    wire [3:0]  iomem_wstrb;
    wire [31:0] iomem_addr, iomem_wdata;
    reg  [31:0] iomem_rdata;
    reg  [31:0] gpio;
    assign led = gpio[7:0];

    wire gpio_sel = iomem_valid && iomem_addr[31:24] == 8'h03;
    wire eth_sel  = iomem_valid && iomem_addr[31:24] == 8'h04;

    // ------------------------------------------------------------------
    // 64 -> 32 bus shim for framing_top_sgmii: addr[2] selects the word
    // half; wstrb maps onto the matching byte-enable lane.  Reads are
    // registered in framing_top (ce in cycle 0, rdata valid in cycle 1).
    // ------------------------------------------------------------------
    reg        eth_ce, eth_resp;
    wire       eth_irq;
    wire [63:0] framing_rdata;
    reg  [16:0] eth_addr_q;
    reg  [63:0] eth_wdata_q;
    reg  [7:0]  eth_be_q;
    reg         eth_we_q, eth_half_q;

    always @(posedge cpu_clk) begin
        if (!resetn) begin
            eth_ce <= 1'b0; eth_resp <= 1'b0;
        end else begin
            eth_ce   <= 1'b0;
            eth_resp <= eth_ce;
            if (eth_sel && !eth_ce && !eth_resp && !iomem_ready) begin
                eth_ce      <= 1'b1;
                eth_addr_q  <= iomem_addr[16:0];
                eth_wdata_q <= {iomem_wdata, iomem_wdata};
                eth_be_q    <= iomem_addr[2] ? {iomem_wstrb, 4'b0000}
                                             : {4'b0000, iomem_wstrb};
                eth_we_q    <= |iomem_wstrb;
                eth_half_q  <= iomem_addr[2];
            end
        end
    end

    always @(posedge cpu_clk) begin
        if (!resetn) begin gpio <= 0; iomem_ready <= 0; iomem_rdata <= 0; end
        else begin
            iomem_ready <= 0;
            if (gpio_sel && !iomem_ready) begin
                iomem_ready <= 1;
                if (iomem_addr[3:0] == 4'h4)
                    iomem_rdata <= {16'b0, status_sync1};
                else begin
                    iomem_rdata <= gpio;
                    if (iomem_wstrb[0]) gpio[ 7: 0] <= iomem_wdata[ 7: 0];
                    if (iomem_wstrb[1]) gpio[15: 8] <= iomem_wdata[15: 8];
                    if (iomem_wstrb[2]) gpio[23:16] <= iomem_wdata[23:16];
                    if (iomem_wstrb[3]) gpio[31:24] <= iomem_wdata[31:24];
                end
            end
            if (eth_resp && !iomem_ready) begin
                iomem_ready <= 1;
                iomem_rdata <= eth_half_q ? framing_rdata[63:32]
                                          : framing_rdata[31:0];
            end
        end
    end

    framing_top_sgmii eth (
        .msoc_clk       (cpu_clk),
        .core_lsu_addr  (eth_addr_q),
        .core_lsu_wdata (eth_wdata_q),
        .core_lsu_be    (eth_be_q),
        .ce_d           (eth_ce),
        .we_d           (eth_ce & eth_we_q),
        .framing_sel    (eth_ce),
        .framing_rdata  (framing_rdata),
        .clk_int        (eth_int_clk),
        .rst_int        (!resetn),
        .sgmii_rxp      (sgmii_rxp),
        .sgmii_rxn      (sgmii_rxn),
        .sgmii_txp      (sgmii_txp),
        .sgmii_txn      (sgmii_txn),
        .sgmii_refclk_p (sgmii_refclk_p),
        .sgmii_refclk_n (sgmii_refclk_n),
        .phy_reset_n    (eth_rst_n),
        .phy_mdio_i     (phy_mdio_i),
        .phy_mdio_o     (phy_mdio_o),
        .phy_mdio_oe    (phy_mdio_oe),
        .phy_mdc        (eth_mdc),
        .eth_irq        (eth_irq),
        .pcspma_status_o(pcspma_status)
    );

    picosoc_noflash soc (
        .clk(cpu_clk), .resetn(resetn),
        .iomem_valid(iomem_valid), .iomem_ready(iomem_ready),
        .iomem_wstrb(iomem_wstrb), .iomem_addr(iomem_addr),
        .iomem_wdata(iomem_wdata), .iomem_rdata(iomem_rdata),
        .irq_5(eth_irq), .irq_6(1'b0), .irq_7(1'b0),
        .ser_tx(uart_tx), .ser_rx(uart_rx)
    );
endmodule
