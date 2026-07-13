// VC707 MAC-swap reflector on the frozen eth_macro (FIFO-word boundary).
//
// The open-flow macro-merge pilot: ALL user logic here is fresh yosys +
// nextpnr (placement AND routing); only eth_macro (PCS/PMA + GTX + MAC +
// packer/unpacker + eth-side FIFO halves) is a Vivado-implemented macro with
// locked placement (placement_macro.txt) and routing (eth_macro.routes).
//
// Word-level streaming MAC swap at 50 MHz: 8x{tlast,data} byte slots per
// 72-bit word, slot 0 first.  A frame [dst6][src6][rest...] is re-emitted as
// [src6][dst6][rest...]; the macro's MAC appends a fresh FCS (the reflected
// payload still carries the original FCS bytes at its tail — 4 harmless
// trailing bytes, same semantics as vc707_reflect).  Frames with tlast in
// word 0 or 1 (<17 bytes, runts) are passed through unswapped.
//
// LEDs: led[7]=heartbeat  led[6]=pcspma link-ish  led[5]=rx_overflow
//       led[3:0]=reflected frame count
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
    // ---------------- clocks / reset (same scaffold as vc707_reflect) -----
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
    reg [24:0] hb = 0;
    always @(posedge cpu_clk) hb <= hb + 1'b1;

    // ---------------- frozen eth macro -------------------------------------
    wire [5:0]  rx_wr_gray, rx_rd_gray, tx_rd_gray, tx_wr_gray;
    wire [4:0]  rx_rd_addr, tx_rd_addr;
    wire [71:0] rx_rd_data, tx_rd_data;
    wire [15:0] pcspma_status;
    wire        rx_overflow;

    eth_macro u_macro (
        .clk_int(cpu_clk),
        .rst_int(rst_sync),
        .sgmii_rxp(sgmii_rxp), .sgmii_rxn(sgmii_rxn),
        .sgmii_txp(sgmii_txp), .sgmii_txn(sgmii_txn),
        .sgmii_refclk_p(sgmii_refclk_p), .sgmii_refclk_n(sgmii_refclk_n),
        .phy_reset_n(),
        .eth_clk_o(), .gtrefclk_bufg_o(),
        .rx_rd_gray(rx_rd_gray), .rx_wr_gray(rx_wr_gray),
        .rx_rd_addr(rx_rd_addr), .rx_rd_data(rx_rd_data),
        .tx_rd_gray(tx_rd_gray), .tx_wr_gray(tx_wr_gray),
        .tx_rd_addr(tx_rd_addr), .tx_rd_data(tx_rd_data),
        .pcspma_status(pcspma_status),
        .rx_fcs_reg(), .tx_fcs_reg(),
        .rx_overflow(rx_overflow));

    // ---------------- msoc-side FIFO halves --------------------------------
    wire        rxq_empty, txq_full;
    wire [71:0] rxw;
    reg         rxq_rd, txq_wr;
    reg  [71:0] txw;

    async_fifo_rd #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_rxq (
        .rd_clk(cpu_clk), .rd_rst(rst_sync),
        .rd_en(rxq_rd), .rd_data(rxw), .rd_empty(rxq_empty),
        .rd_gray(rx_rd_gray), .wr_gray(rx_wr_gray),
        .rd_addr(rx_rd_addr), .rd_data_mem(rx_rd_data));

    async_fifo_wr #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_txq (
        .wr_clk(cpu_clk), .wr_rst(rst_sync),
        .wr_en(txq_wr), .wr_data(txw), .wr_full(txq_full),
        .wr_gray(tx_wr_gray), .rd_gray(tx_rd_gray),
        .rd_addr(tx_rd_addr), .rd_data(tx_rd_data));

    // ---------------- word-level streaming MAC swap ------------------------
    function tlast_in(input [71:0] w);
        tlast_in = w[8]|w[17]|w[26]|w[35]|w[44]|w[53]|w[62]|w[71];
    endfunction
    // slot extract/insert helpers via part select: slot i = w[i*9 +: 9]

    localparam W0 = 2'd0, W1 = 2'd1, W1B = 2'd2, STREAM = 2'd3;
    reg [1:0]  st;
    reg [71:0] r0, r1b;      // word0 hold; pending swapped word1
    reg [3:0]  tx_count;

    // swapped word0/word1 from r0 (=word0) and rxw (=word1); slot i = w[i*9 +: 9]
    //  w0' slots 0..5 = src bytes 0..5 = r0.s6, r0.s7, rxw.s0..s3 ; slots 6,7 = r0.s0, r0.s1
    wire [71:0] w0_swap = { r0[17:9], r0[8:0],
                            rxw[35:27], rxw[26:18], rxw[17:9], rxw[8:0],
                            r0[71:63], r0[62:54] };
    //  w1' slots 0..3 = dst bytes 2..5 = r0.s2..s5 ; slots 4..7 = rxw.s4..s7
    wire [71:0] w1_swap = { rxw[71:36], r0[53:45], r0[44:36], r0[35:27], r0[26:18] };

    always @(posedge cpu_clk)
        if (rst_sync) begin
            st <= W0; rxq_rd <= 0; txq_wr <= 0; tx_count <= 0;
            r0 <= 0; r1b <= 0; txw <= 0;
        end else begin
            rxq_rd <= 1'b0;
            txq_wr <= 1'b0;
            case (st)
                W0: if (!rxq_empty && !rxq_rd && !txq_full) begin
                        if (tlast_in(rxw)) begin            // runt: pass through
                            txw <= rxw; txq_wr <= 1'b1;
                            tx_count <= tx_count + 1'b1;
                        end else begin
                            r0 <= rxw;
                            st <= W1;
                        end
                        rxq_rd <= 1'b1;
                    end
                W1: if (!rxq_empty && !rxq_rd && !txq_full) begin
                        if (tlast_in(rxw)) begin            // <17B frame: unswapped
                            txw <= r0; txq_wr <= 1'b1;
                            r1b <= rxw;                     // reuse W1B to emit word1 raw
                            st <= W1B;
                        end else begin
                            txw <= w0_swap; txq_wr <= 1'b1;
                            r1b <= w1_swap;
                            st <= W1B;
                        end
                        rxq_rd <= 1'b1;
                    end
                W1B: if (!txq_full) begin                    // emit held word1
                        txw <= r1b; txq_wr <= 1'b1;
                        if (tlast_in(r1b)) begin
                            tx_count <= tx_count + 1'b1;
                            st <= W0;
                        end else
                            st <= STREAM;
                    end
                STREAM: if (!rxq_empty && !rxq_rd && !txq_full) begin
                        txw <= rxw; txq_wr <= 1'b1;
                        rxq_rd <= 1'b1;
                        if (tlast_in(rxw)) begin
                            tx_count <= tx_count + 1'b1;
                            st <= W0;
                        end
                    end
            endcase
        end

    // ---------------- pins --------------------------------------------------
    // explicit IO buffers: this design is synthesised with -noiopad (auto
    // buffer insertion would also buffer the GT pads, which pack_gt_xc7
    // needs raw), so fabric IO is buffered by hand here.
    wire [7:0] led_i = { hb[24], pcspma_status[0], rx_overflow, 1'b0, tx_count };
    genvar gl;
    generate for (gl = 0; gl < 8; gl = gl + 1) begin : lbuf
        OBUF led_obuf (.I(led_i[gl]), .O(led[gl]));
    end endgenerate
    OBUF rstn_obuf (.I(~rst_sync), .O(eth_rst_n));
    OBUF mdc_obuf  (.I(1'b0),      .O(eth_mdc));
    OBUF uart_obuf (.I(1'b1),      .O(uart_tx));
    IOBUF mdio_iobuf (.I(1'b0), .T(1'b1), .O(), .IO(eth_mdio));
    wire _unused_rx = uart_rx;
endmodule
`default_nettype wire
