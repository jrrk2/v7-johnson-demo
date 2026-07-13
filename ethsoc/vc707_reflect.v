// VC707 minimal SGMII MAC-swap reflector.
//
// Builds on vc707_crccount: PCS/PMA front end -> axis_gmii_rx (deframe + CRC) ->
// a single-frame store-and-forward buffer that SWAPS the dst/src MAC addresses
// -> axis_gmii_tx (reframe + new FCS) -> PCS TX.  No CPU, no UART, no register
// file, no big packet buffer -- just enough to bounce each received good-CRC
// frame back to its sender through the open flow's TX chain.  Tests whether the
// open-flow TX cone works in a minimal context (the full ethloop TX is dead).
//
// A received frame  [dst][src][type][payload][fcs]  is reflected as
//                   [src][dst][type][payload][new fcs]  -> goes back to sender.
//
// LEDs:  led[7]=heartbeat  led[6]=mmcm_locked  led[5]=link  led[4]=sync
//        led[3:0] = reflected (TX) frame count[3:0]
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
    // ---------------- clocks / reset ---------------------------------------
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
    reg [24:0] hb = 0;
    always @(posedge cpu_clk) hb <= hb + 1'b1;

    // ---------------- SGMII PCS/PMA ----------------------------------------
    wire        userclk2, resetdone, mmcm_locked_pcs, sgmii_clk_en;
    wire [7:0]  gmii_rxd;
    wire        gmii_rx_dv, gmii_rx_er;
    wire [7:0]  gmii_txd;
    wire        gmii_tx_en, gmii_tx_er;
    wire [15:0] status_vector;
    wire [1:0]  pcspma_speed = status_vector[11:10];
    wire [15:0] an_adv_config_vector;
    assign an_adv_config_vector[15]    = 1'b1;
    assign an_adv_config_vector[14]    = 1'b1;
    assign an_adv_config_vector[13:12] = 2'b01;
    assign an_adv_config_vector[11:10] = 2'b10;
    assign an_adv_config_vector[9:0]   = 10'b0000000001;

    gig_ethernet_pcs_pma_0 i_pcs (
        .gtrefclk_p(sgmii_refclk_p), .gtrefclk_n(sgmii_refclk_n),
        .gtrefclk_out(), .gtrefclk_bufg_out(),
        .txp(sgmii_txp), .txn(sgmii_txn), .rxp(sgmii_rxp), .rxn(sgmii_rxn),
        .resetdone(resetdone), .userclk_out(), .userclk2_out(userclk2),
        .rxuserclk_out(), .rxuserclk2_out(), .independent_clock_bufg(cpu_clk),
        .pma_reset_out(), .mmcm_locked_out(mmcm_locked_pcs),
        .sgmii_clk_r(), .sgmii_clk_f(), .sgmii_clk_en(sgmii_clk_en),
        .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er),
        .gmii_isolate(),
        .configuration_vector(5'b10000), .an_interrupt(),
        .an_adv_config_vector(an_adv_config_vector), .an_restart_config(1'b0),
        .speed_is_10_100(pcspma_speed != 2'b10), .speed_is_100(pcspma_speed == 2'b01),
        .status_vector(status_vector), .reset(rst_sync), .signal_detect(1'b1),
        .gt0_qplloutclk_out(), .gt0_qplloutrefclk_out()
    );

    // ---------------- RX-domain reset sync (userclk2) ----------------------
    reg [3:0] rxrst_sync;
    wire      rx_rst;
    always @(posedge userclk2 or negedge mmcm_locked_pcs)
        if (!mmcm_locked_pcs) rxrst_sync <= 4'hF; else rxrst_sync <= {rxrst_sync[2:0], ~resetdone};
    assign rx_rst = rxrst_sync[3];

    // ---------------- RX deframe + CRC (userclk2) --------------------------
    wire [7:0] rx_td;  wire rx_tv, rx_tl, rx_tu;
    axis_gmii_rx i_rx (
        .clk(userclk2), .rst(rx_rst),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er),
        .m_axis_tdata(rx_td), .m_axis_tvalid(rx_tv), .m_axis_tlast(rx_tl), .m_axis_tuser(rx_tu),
        .clk_enable(sgmii_clk_en), .mii_select(1'b0),
        .error_bad_frame(), .error_bad_fcs(), .fcs_reg()
    );

    // ---------------- single-frame reflect buffer (userclk2) ---------------
    // half-duplex: capture a whole good frame, then transmit it MAC-swapped.
    reg [7:0]  mem [0:2047];
    reg [10:0] wa;              // RX write index (counts bytes incl FCS)
    reg        rx_mode;         // 1 = capturing, 0 = transmitting
    reg        resync;          // after TX, wait for a tlast before capturing
    reg        capturing;       // inside a frame we are storing
    reg        frame_rdy;
    reg [10:0] tx_len;          // #bytes to transmit (frame incl header, no FCS)

    // TX read + MAC swap (1-cycle BRAM read latency, prefetched)
    reg [10:0] rd_addr;
    reg [7:0]  rd_q;
    always @(posedge userclk2) rd_q <= mem[rd_addr];

    reg        s_tv;  reg [7:0] s_td;  reg s_tl;
    wire       s_tr;                    // axis_gmii_tx tready
    reg [10:0] tidx;
    reg [15:0] tx_count;                // reflected frame counter

    function [10:0] swp(input [10:0] i);
        swp = (i < 11'd6) ? (i + 11'd6) : (i < 11'd12) ? (i - 11'd6) : i;
    endfunction

    localparam RS_IDLE=3'd0, RS_W1=3'd1, RS_PRIME=3'd2, RS_RUN=3'd3, RS_DONE=3'd4;
    reg [2:0] ts;

    always @(posedge userclk2) begin
        if (rx_rst) begin
            wa<=0; rx_mode<=1; resync<=1; capturing<=0; frame_rdy<=0;
            ts<=RS_IDLE; s_tv<=0; tx_count<=0; tidx<=0;
        end else begin
            // ---- RX capture side (only while rx_mode) ----
            if (rx_mode) begin
                // hold the write index at 0 between frames so byte0 -> mem[0]
                if (!capturing && !resync) wa <= 11'd0;
                if (resync) begin
                    // drop bytes until the in-flight frame ends, then resync
                    if (rx_tv && rx_tl) resync <= 1'b0;
                end else if (rx_tv) begin
                    capturing <= 1'b1;
                    mem[wa] <= rx_td;        // wa held at 0 for byte0, then increments
                    wa <= wa + 1'b1;
                    if (rx_tl) begin
                        capturing <= 1'b0;
                        if (!rx_tu && (wa >= 11'd17)) begin  // good FCS + >= 14+4 bytes
                            tx_len   <= (wa + 11'd1) - 11'd4; // drop 4 FCS bytes
                            frame_rdy<= 1'b1;
                            rx_mode  <= 1'b0;                 // switch to TX
                        end
                    end
                end
            end

            // ---- TX read side (only while !rx_mode) ----
            case (ts)
                RS_IDLE: if (!rx_mode && frame_rdy) begin
                             tidx <= 0; rd_addr <= swp(11'd0); s_tv <= 1'b0; ts <= RS_W1;
                         end
                RS_W1:   begin                          // settle: rd_q loads byte0 next cycle
                             rd_addr <= swp(11'd1);      // point at byte1 (held through PRIME)
                             ts <= RS_PRIME;
                         end
                RS_PRIME: begin                         // rd_q now = byte0 (real)
                             s_td <= rd_q; s_tv <= 1'b1; s_tl <= (tx_len==11'd1);
                             ts <= RS_RUN;               // rd_addr stays swp(1) -> rd_q=byte1 next
                         end
                RS_RUN: if (s_tv && s_tr) begin
                            if (tidx == tx_len-1'b1) begin
                                s_tv <= 1'b0; ts <= RS_DONE;
                            end else begin
                                tidx    <= tidx + 1'b1;
                                s_td    <= rd_q;                 // prefetched byte(tidx+1)
                                s_tl    <= (tidx+11'd2 == tx_len);
                                rd_addr <= swp(tidx + 11'd2);
                            end
                        end
                RS_DONE: begin
                            tx_count  <= tx_count + 1'b1;
                            frame_rdy <= 1'b0;
                            rx_mode   <= 1'b1;              // back to RX
                            resync    <= 1'b1;             // resync to next frame start
                            ts        <= RS_IDLE;
                         end
            endcase
        end
    end

    // ---------------- TX reframe + FCS (userclk2) --------------------------
    axis_gmii_tx #(.ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)) i_tx (
        .clk(userclk2), .rst(rx_rst),
        .s_axis_tdata(s_td), .s_axis_tvalid(s_tv), .s_axis_tready(s_tr),
        .s_axis_tlast(s_tl), .s_axis_tuser(1'b0),
        .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .clk_enable(sgmii_clk_en), .mii_select(1'b0), .ifg_delay(8'd12), .fcs_reg()
    );

    // ---------------- LEDs (sync count to cpu_clk) -------------------------
    reg [15:0] cnt_s0, cnt_s1;  reg [1:0] st_s0, st_s1;
    always @(posedge cpu_clk) begin
        cnt_s0 <= tx_count; cnt_s1 <= cnt_s0;
        st_s0  <= status_vector[1:0]; st_s1 <= st_s0;
    end
    assign led = { hb[24], mmcm_locked_pcs, st_s1[0], st_s1[1], cnt_s1[3:0] };

    assign eth_rst_n = ~rst_sync;
    assign eth_mdc   = 1'b0;
    assign eth_mdio  = 1'bz;
    assign uart_tx   = 1'b1;
endmodule
`default_nettype wire
