// VC707 standalone ARP responder.
//
// Same clocking / pins / eth stack as vc707_ethloop (framing_top_sgmii + PCS/PMA
// + MAC + RX/TX BRAMs), but the CPU-free bus master is arp_ctrl (extracted from
// cva6 heavyhash/mine_ctrl): it answers ARP "who-has 192.168.1.100" with an ARP
// reply carrying FPGA_MAC, so the board becomes pingable.  Minimal full RX->TX
// datapath exercise.
`default_nettype none
module top (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led,
    input  wire       sgmii_rxp, sgmii_rxn,
    output wire       sgmii_txp, sgmii_txn,
    input  wire       sgmii_refclk_p, sgmii_refclk_n,
    output wire       eth_rst_n,
    inout  wire       eth_mdio,
    output wire       eth_mdc
);
    // ---------------- clocks / reset (identical to vc707_ethloop) ----------
    // explicit IO buffers: synthesised with -noiopad (auto insertion would
    // also buffer the GT pads, which pack_gt_xc7 needs raw)
    wire rst_i;
    IBUF rst_ibuf (.I(rst), .O(rst_i));
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
        .RST(rst_i), .PWRDWN(1'b0), .LOCKED(mmcm_locked),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG cpu_bufg (.I(mmcm_clkout0), .O(cpu_clk));

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst_i || !mmcm_locked) resetn_cnt <= 0; else resetn_cnt <= resetn_cnt + !resetn;
    wire rst_sync = !resetn;

    reg [25:0] hb = 0;
    always @(posedge cpu_clk) hb <= hb + 1'b1;

    // ---------------- MDIO tristate ---------------------------------------
    wire phy_mdio_i, phy_mdio_o, phy_mdio_oe;
    IOBUF mdio_iobuf (.I(phy_mdio_o), .T(~phy_mdio_oe), .O(phy_mdio_i), .IO(eth_mdio));

    wire eth_rst_n_i, eth_mdc_i;
    OBUF rstn_obuf (.I(eth_rst_n_i), .O(eth_rst_n));
    OBUF mdc_obuf  (.I(eth_mdc_i),  .O(eth_mdc));

    // ---------------- arp_ctrl <-> framing_top bus ------------------------
    wire [16:0] lsu_addr;
    wire [63:0] lsu_wdata;
    wire [7:0]  lsu_be;
    wire        lsu_ce, lsu_we, lsu_sel;
    wire [63:0] framing_rdata;
    wire [15:0] pcspma_status;
    wire        led_arp;
    wire [15:0] reply_count;
    wire [3:0]  arp_dbg;

    framing_top_sgmii eth (
        .msoc_clk       (cpu_clk),
        .core_lsu_addr  (lsu_addr),
        .core_lsu_wdata (lsu_wdata),
        .core_lsu_be    (lsu_be),
        .ce_d           (lsu_ce),
        .we_d           (lsu_we),
        .framing_sel    (lsu_sel),
        .framing_rdata  (framing_rdata),
        .clk_int        (cpu_clk),
        .rst_int        (rst_sync),
        .sgmii_rxp      (sgmii_rxp),
        .sgmii_rxn      (sgmii_rxn),
        .sgmii_txp      (sgmii_txp),
        .sgmii_txn      (sgmii_txn),
        .sgmii_refclk_p (sgmii_refclk_p),
        .sgmii_refclk_n (sgmii_refclk_n),
        .phy_reset_n    (eth_rst_n_i),
        .phy_mdio_i     (phy_mdio_i),
        .phy_mdio_o     (phy_mdio_o),
        .phy_mdio_oe    (phy_mdio_oe),
        .phy_mdc        (eth_mdc_i),
        .eth_irq        (),
        .pcspma_status_o(pcspma_status),
        .eth_clk_o      (),
        .gtrefclk_bufg_o()
    );

    arp_ctrl #(
        .FPGA_MAC (48'h02_00_00_4B_41_31),
        .FPGA_IP  (32'hC0_A8_01_64)          // 192.168.1.100
    ) i_arp (
        .clk            (cpu_clk),
        .rst_n          (~rst_sync),
        .core_lsu_addr  (lsu_addr),
        .core_lsu_wdata (lsu_wdata),
        .core_lsu_be    (lsu_be),
        .ce_d           (lsu_ce),
        .we_d           (lsu_we),
        .framing_sel    (lsu_sel),
        .framing_rdata  (framing_rdata),
        .led_arp        (led_arp),
        .reply_count    (reply_count),
        .dbg_state      (arp_dbg)
    );

    // pcspma_status is in the eth domain; sample for LEDs (async ok)
    reg [1:0] st0, st1;
    always @(posedge cpu_clk) begin st0 <= pcspma_status[1:0]; st1 <= st0; end

    // led[7]=mmcm  [6]=resetn  [5]=link  [4]=sync  [3:1]=reply_count  [0]=cpu_clk hb
    // led[0]=hb[25]: free-running ~0.75Hz heartbeat on cpu_clk, UNGATED by reset --
    // definitively shows whether cpu_clk toggles on silicon (resolves the st1
    // link/sync LEDs possibly reading floating-high while the reset counter is held).
    wire [7:0] led_i = {mmcm_locked, resetn, st1[0], st1[1], reply_count[2:0], hb[25]};
    genvar gl;
    generate for (gl = 0; gl < 8; gl = gl + 1) begin : lbuf
        OBUF led_obuf (.I(led_i[gl]), .O(led[gl]));
    end endgenerate
    OBUF uart_obuf (.I(1'b1), .O(uart_tx));
    wire _unused_rx = uart_rx;
endmodule
`default_nettype wire
