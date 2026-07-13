// VC707 minimal SGMII RX front-end CRC counter.
//
// Strips away the MAC, packet buffers, UART and CPU of vc707_ethloop: just the
// proven SGMII PCS/PMA front end -> Forencich axis_gmii_rx (GMII deframe + CRC32
// check) -> a counter of frames that arrive with a VALID FCS -> the GPIO LEDs.
// Everything downstream of the GT runs in the 125 MHz userclk2 domain, so this
// is a tiny timing footprint to test whether the open flow's SGMII receive +
// CRC path works on silicon (vs the full ethloop, whose 125 MHz eth cones are
// timing-marginal in the open flow).
//
// LEDs:  led[7] = heartbeat (design alive, ~3 Hz)
//        led[6] = mmcm_locked  (PCS clocking up)
//        led[5] = status_vector[0]  (SGMII link up)
//        led[4] = status_vector[1]  (sync)
//        led[3:0] = valid_crc_count[3:0]  (low nibble of good-FCS frame count)
// (full count also mirrored: with traffic led[3:0] cycles; if it moves, the open
//  RX front-end + CRC works.  Stuck at 0 with link up = the front-end is broken.)
//
// Same port list / xdc as vc707_ethloop so the existing constraints apply.
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

    // heartbeat on cpu_clk (50 MHz / 2^24 ~ 3 Hz)
    reg [24:0] hb = 0;
    always @(posedge cpu_clk) hb <= hb + 1'b1;

    // ---------------- SGMII PCS/PMA (same config as sgmii_soc) --------------
    wire        userclk2, resetdone, mmcm_locked_pcs, sgmii_clk_en;
    wire [7:0]  gmii_rxd;
    wire        gmii_rx_dv, gmii_rx_er;
    wire [15:0] status_vector;
    wire [1:0]  pcspma_speed = status_vector[11:10];

    wire [15:0] an_adv_config_vector;
    assign an_adv_config_vector[15]    = 1'b1;          // link status
    assign an_adv_config_vector[14]    = 1'b1;          // acknowledge
    assign an_adv_config_vector[13:12] = 2'b01;         // full duplex
    assign an_adv_config_vector[11:10] = 2'b10;         // 1000 Mbps
    assign an_adv_config_vector[9:0]   = 10'b0000000001; // SGMII

    gig_ethernet_pcs_pma_0 i_pcs (
        .gtrefclk_p             (sgmii_refclk_p),
        .gtrefclk_n             (sgmii_refclk_n),
        .gtrefclk_out           (),
        .gtrefclk_bufg_out      (),
        .txp                    (sgmii_txp),
        .txn                    (sgmii_txn),
        .rxp                    (sgmii_rxp),
        .rxn                    (sgmii_rxn),
        .resetdone              (resetdone),
        .userclk_out            (),
        .userclk2_out           (userclk2),
        .rxuserclk_out          (),
        .rxuserclk2_out         (),
        .independent_clock_bufg (cpu_clk),
        .pma_reset_out          (),
        .mmcm_locked_out        (mmcm_locked_pcs),
        .sgmii_clk_r            (),
        .sgmii_clk_f            (),
        .sgmii_clk_en           (sgmii_clk_en),
        .gmii_txd               (8'h00),
        .gmii_tx_en             (1'b0),
        .gmii_tx_er             (1'b0),
        .gmii_rxd               (gmii_rxd),
        .gmii_rx_dv             (gmii_rx_dv),
        .gmii_rx_er             (gmii_rx_er),
        .gmii_isolate           (),
        .configuration_vector   (5'b10000),             // [4]=AN enable
        .an_interrupt           (),
        .an_adv_config_vector   (an_adv_config_vector),
        .an_restart_config      (1'b0),
        .speed_is_10_100        (pcspma_speed != 2'b10),
        .speed_is_100           (pcspma_speed == 2'b01),
        .status_vector          (status_vector),
        .reset                  (rst_sync),
        .signal_detect          (1'b1),
        .gt0_qplloutclk_out     (),
        .gt0_qplloutrefclk_out  ()
    );

    // ---------------- RX-domain reset sync (userclk2) ----------------------
    reg [3:0] rxrst_sync;
    wire      rx_rst;
    always @(posedge userclk2 or negedge mmcm_locked_pcs)
        if (!mmcm_locked_pcs) rxrst_sync <= 4'hF;
        else                  rxrst_sync <= {rxrst_sync[2:0], ~resetdone};
    assign rx_rst = rxrst_sync[3];

    // ---------------- GMII deframe + CRC32 check (Forencich, userclk2) -----
    wire       m_tvalid, m_tlast, m_tuser, bad_fcs;
    wire [31:0] fcs_dbg;
    axis_gmii_rx i_rx (
        .clk            (userclk2),
        .rst            (rx_rst),
        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),
        .m_axis_tdata   (),
        .m_axis_tvalid  (m_tvalid),
        .m_axis_tlast   (m_tlast),
        .m_axis_tuser   (m_tuser),
        .clk_enable     (sgmii_clk_en),
        .mii_select     (1'b0),
        .error_bad_frame(),
        .error_bad_fcs  (bad_fcs),
        .fcs_reg        (fcs_dbg)
    );

    // ---------------- valid-CRC frame counter (userclk2) -------------------
    // A frame ends on (tvalid & tlast).  m_axis_tuser=1 flags bad FCS/error;
    // so a GOOD (valid-CRC) frame is tvalid & tlast & ~tuser.
    reg [15:0] valid_cnt;
    wire good_frame = m_tvalid & m_tlast & ~m_tuser;
    always @(posedge userclk2)
        if (rx_rst) valid_cnt <= 16'd0;
        else if (good_frame) valid_cnt <= valid_cnt + 1'b1;

    // sync a few status bits + the count nibble into cpu_clk for the LEDs
    reg [15:0] cnt_s0, cnt_s1;
    reg [1:0]  st_s0, st_s1;
    always @(posedge cpu_clk) begin
        cnt_s0 <= valid_cnt; cnt_s1 <= cnt_s0;
        st_s0  <= status_vector[1:0]; st_s1 <= st_s0;
    end

    assign led = { hb[24], mmcm_locked_pcs, st_s1[0], st_s1[1], cnt_s1[3:0] };

    // ---------------- tie-offs ---------------------------------------------
    assign eth_rst_n = ~rst_sync;      // release the PHY
    assign eth_mdc   = 1'b0;
    assign eth_mdio  = 1'bz;
    assign uart_tx   = 1'b1;
endmodule
`default_nettype wire
