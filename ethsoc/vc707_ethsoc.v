// VC707 PicoSoC + lowRISC SGMII ethernet (framing_top_sgmii).
// Clocks: 200 MHz LVDS sysclk -> MMCME2_ADV -> 50 MHz cpu_clk (= msoc_clk
//         = the IP's independent clock; DrpClkRate is 50.0, and cva6 ran
//         the framing core at 50 MHz).  An MMCM rather than fabric FF
//         dividers: derived clocks ride the dedicated low-skew tree with
//         phase compensation, avoiding the divider-clock hold/skew issues
//         seen in STA (and Vivado-verified Fmax of the nextpnr placement
//         is ~73 MHz, so 100 MHz cpu_clk is out for now anyway).
//         125 MHz MAC clock comes out of the PCS/PMA IP's own MMCM.
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

`ifdef CLK125
    // Single 125 MHz domain: cpu/msoc = userclk2 from the PCS/PMA IP's MMCM;
    // the IP's independent clock = gtrefclk through the IP's BUFG (free-
    // running from the PHY crystal).  The IP is reset by the button alone -
    // the POR counter runs on userclk2, which only ticks once the GT and
    // its MMCM are up, so it naturally waits for the clock lineage.
    wire eth_clk_o, gtrefclk_bufg_o;
    assign cpu_clk = eth_clk_o;
    // independent_clock must NOT derive from the GT refclk (UG476 DRC
    // REQP-1584: it feeds the PLL lock detectors).  Derive 50 MHz from
    // sysclk via an MMCM: compensated and BUFG-driven end to end -- a
    // fabric ripple divider clocked by the unbuffered IBUFDS output has
    // hold hazards once the open flow routes it.
    // 200 MHz x5 = 1 GHz VCO; /20 = 50 MHz.
    wire mmcm_fb, mmcm_clkout0, mmcm_locked;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"),
        .CLKIN1_PERIOD(5.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(20.000), .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5)
    ) eth_mmcm (
        .CLKIN1(sysclk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb),
        .CLKOUT0(mmcm_clkout0),
        .RST(rst), .PWRDWN(1'b0), .LOCKED(mmcm_locked),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG eth_bufg (.I(mmcm_clkout0), .O(eth_int_clk));
`else

    // 200 MHz x5 = 1 GHz VCO; /20 = 50 MHz
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
    assign eth_int_clk = cpu_clk;   // one 50 MHz domain for SoC + IP
    wire eth_clk_o, gtrefclk_bufg_o;   // unused in MMCM mode
`endif

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst || !mmcm_locked) resetn_cnt <= 0;
        else                     resetn_cnt <= resetn_cnt + !resetn;

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

    // JTAG USER1 debug register: read SoC liveness + PCS/PMA status over
    // the programming cable, independent of UART/pins.  Shift 32 bits out
    // of USER1: {hb[1:0], mmcm_locked, resetn, gpio[3:0], status[15:0],
    // 8'hA5}.  The 0xA5 signature shifts out first and proves the chain.
`ifndef NO_JTAG
    wire bs_capture, bs_drck, bs_sel, bs_shift, bs_tdi;
    reg [31:0] bs_sr;
    reg [25:0] bs_hb;
    always @(posedge cpu_clk) bs_hb <= bs_hb + 1;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan (
        .CAPTURE(bs_capture), .DRCK(bs_drck), .RESET(), .RUNTEST(),
        .SEL(bs_sel), .SHIFT(bs_shift), .TCK(), .TDI(bs_tdi),
        .TDO(bs_sr[0]), .TMS(), .UPDATE());
    always @(posedge bs_drck)
        if (bs_sel && bs_capture)
            bs_sr <= {bs_hb[25:24], mmcm_locked, resetn, gpio[3:0], status_sync1, 8'hA5};
        else if (bs_sel && bs_shift)
            bs_sr <= {bs_tdi, bs_sr[31:1]};
`endif

`ifdef LED_DEBUG
    // Bypass diagnostics: LD7=MMCM locked, LD6=resetn, LD5/4=cpu_clk
    // heartbeats, LD3=eth_clk-domain heartbeat (via framing's pcspma sync
    // clock domain n/a - use eth_int), LD2=iomem_valid flicker.
    reg [25:0] hb_cpu = 0;
    always @(posedge cpu_clk) hb_cpu <= hb_cpu + 1;
    reg [25:0] hb_eth = 0;
    always @(posedge eth_int_clk) hb_eth <= hb_eth + 1;
    assign led = {mmcm_locked, resetn, hb_cpu[25], hb_cpu[24],
                  iomem_valid, hb_eth[25], hb_eth[24], gpio[0]};
`else
    assign led = gpio[7:0];
`endif

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
`ifdef CLK125
        .rst_int        (rst),
`else
        .rst_int        (!resetn),
`endif
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
        .pcspma_status_o(pcspma_status),
        .eth_clk_o      (eth_clk_o),
        .gtrefclk_bufg_o(gtrefclk_bufg_o)
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
