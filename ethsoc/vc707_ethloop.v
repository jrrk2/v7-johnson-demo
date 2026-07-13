// VC707 processor-free ethernet <-> UART hex bridge.
//
// Purpose: a minimal design that exercises the SGMII eth datapath
// (framing_top_sgmii + PCS/PMA + GT + MAC + the RX/TX packet buffers) with
// NO CPU, NO firmware, NO progmem.  Two small state machines drive the same
// core_lsu_* buffer interface that picosoc used to drive:
//
//   * RX-dump FSM  (owns UART TX): eth_init(promiscuous) once, then poll the
//     receive-status register, and for every packet that lands in an eth RX
//     ring buffer, stream its bytes out of the UART as ASCII hex + CRLF, then
//     acknowledge the buffer.
//
//   * TX-load FSM  (owns UART RX): collect ASCII hex digit-pairs arriving on
//     the UART into 32-bit words written straight into the eth TX buffer (the
//     "existing eth buffer" reused as the UART staging buffer); a CR or LF
//     flushes the frame (pad to 60) and triggers transmission (TPLR write).
//     Bytes that arrive while a bus op or a previous send is in flight are
//     dropped (overrun), as requested.
//
// A tiny 2-port priority arbiter (TX-load has priority for its rare writes)
// serialises the two FSMs onto the single 64-bit framing_top bus.
//
// Everything else (MMCM 200->50 MHz, POR reset, MDIO tristate, pcspma sync,
// the framing_top_sgmii instance) is identical to vc707_ethsoc.v so this is a
// drop-in top with the same ports / same xdc.  Goal: a much smaller netlist
// than the full SoC, shrinking the pip-encoding search space for the open
// flow, while still driving the real eth datapath end to end.
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
    // ---------------- clocks / reset (identical to vc707_ethsoc.v) --------
    wire sysclk_ibuf, sysclk, cpu_clk, eth_int_clk;
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
    assign eth_int_clk = cpu_clk;

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst || !mmcm_locked) resetn_cnt <= 0;
        else                     resetn_cnt <= resetn_cnt + !resetn;
    wire rst_sync = !resetn;

    // ---------------- MDIO tristate ---------------------------------------
    wire phy_mdio_i, phy_mdio_o, phy_mdio_oe;
    assign eth_mdio   = phy_mdio_oe ? phy_mdio_o : 1'bz;
    assign phy_mdio_i = eth_mdio;

    // ---------------- pcspma status sync ----------------------------------
    wire [15:0] pcspma_status;
    reg  [15:0] status_sync0, status_sync1;
    always @(posedge cpu_clk) begin
        status_sync0 <= pcspma_status;
        status_sync1 <= status_sync0;
    end

    // ==================================================================
    //  Bus master to framing_top_sgmii (single outstanding, 2 cycles)
    //  T0: drive ce_d/we_d/addr/wdata/be ; T1: framing_rdata valid, latch.
    //  Matches the RTL read latency: ce_d_dly (asserted in T1) gates the
    //  register/buffer read mux, so rdata is valid exactly in T1.
    // ==================================================================
    localparam [1:0] OWN_NONE = 2'd0, OWN_RXD = 2'd1, OWN_TXL = 2'd2;

    reg         rxd_req, rxd_we;   reg [16:0] rxd_addr;   reg [31:0] rxd_wdata;
    reg         txl_req, txl_we;   reg [16:0] txl_addr;   reg [31:0] txl_wdata;

    reg  [1:0]  bm_st;             // 0 idle, 1 T0, 2 T1
    reg  [1:0]  bm_owner;
    reg  [16:0] bm_addr;   reg [31:0] bm_wdata;   reg bm_we;
    reg  [31:0] bm_rdata;  reg bm_done;           // bm_done: 1-cycle pulse

    wire [63:0] framing_rdata;
    wire        eth_ce    = (bm_st == 2'd1);
    wire        eth_we_d  = eth_ce & bm_we;
    wire [7:0]  eth_be    = bm_we ? (bm_addr[2] ? 8'hF0 : 8'h0F) : 8'h00;
    wire [63:0] eth_wdata = {bm_wdata, bm_wdata};

    always @(posedge cpu_clk) begin
        if (rst_sync) begin
            bm_st <= 2'd0; bm_owner <= OWN_NONE; bm_done <= 1'b0;
        end else begin
            bm_done <= 1'b0;
            case (bm_st)
              2'd0: if (!bm_done) begin           // IDLE - arbitrate (TXL first)
                                                   // (skip the bm_done cycle so a
                                                   // still-high req can't re-fire)
                  if (txl_req) begin
                      bm_owner <= OWN_TXL; bm_addr <= txl_addr;
                      bm_wdata <= txl_wdata; bm_we <= txl_we; bm_st <= 2'd1;
                  end else if (rxd_req) begin
                      bm_owner <= OWN_RXD; bm_addr <= rxd_addr;
                      bm_wdata <= rxd_wdata; bm_we <= rxd_we; bm_st <= 2'd1;
                  end
              end
              2'd1: bm_st <= 2'd2;                // T0: ce asserted this cycle
              2'd2: begin                         // T1: rdata valid
                  bm_rdata <= bm_addr[2] ? framing_rdata[63:32]
                                         : framing_rdata[31:0];
                  bm_done  <= 1'b1;
                  bm_st    <= 2'd0;
              end
              default: bm_st <= 2'd0;
            endcase
        end
    end
    wire bm_done_rxd = bm_done & (bm_owner == OWN_RXD);
    wire bm_done_txl = bm_done & (bm_owner == OWN_TXL);

    // ==================================================================
    //  UART  (50 MHz / 115200 = 434)
    // ==================================================================
    localparam integer BAUDDIV = 434;
    reg  [7:0] uch;              // char to transmit (driven by RX-dump FSM)
    reg        utx_stb; wire utx_busy;
    uart_tx #(.DIV(BAUDDIV)) u_tx (
        .clk(cpu_clk), .rst(rst_sync), .data(uch), .stb(utx_stb),
        .tx(uart_tx), .busy(utx_busy));
    wire [7:0] urx_data; wire urx_stb;
    uart_rx #(.DIV(BAUDDIV)) u_rx (
        .clk(cpu_clk), .rst(rst_sync), .rx(uart_rx),
        .data(urx_data), .stb(urx_stb));

    // hex helpers
    function [7:0] hexc(input [3:0] n);
        hexc = (n < 4'd10) ? (8'h30 + n) : (8'h41 + (n - 4'd10)); // 0-9 A-F
    endfunction
    function ishex(input [7:0] c);
        ishex = (c >= 8'h30 && c <= 8'h39) || (c >= 8'h41 && c <= 8'h46) ||
                (c >= 8'h61 && c <= 8'h66);
    endfunction
    function [3:0] hexv(input [7:0] c);
        hexv = (c <= 8'h39) ? (c - 8'h30) :
               (c <= 8'h46) ? (c - 8'h41 + 4'd10) : (c - 8'h61 + 4'd10);
    endfunction

    // eth register offsets (byte addresses within the 0x04000000 window)
    localparam [16:0] O_MACLO = 17'h00800, O_MACHI = 17'h00808,
                      O_TPLR  = 17'h00810, O_RFCS  = 17'h00828,
                      O_RSR   = 17'h00830, O_RPLR  = 17'h00C00,
                      O_TXBUF = 17'h01000, O_RXBUF = 17'h10000;
    localparam [31:0] MACHI_ALLPKTS = 32'h0040_0000;   // promiscuous
    localparam [31:0] MACLO_VAL = 32'h0100_8907;       // MAC 00:23:01:00:89:07
    localparam [31:0] MACHI_VAL = 32'h0000_0023 | MACHI_ALLPKTS;

    // ==================================================================
    //  RX-dump FSM  (owns UART TX + bus reads)
    // ==================================================================
    localparam [3:0]
      S_IN0=0, S_IN1=1, S_IN2=2,           // eth_init: MACLO, MACHI, RFCS
      S_POLL=3, S_LEN=4, S_RDW=5, S_EMIT=6, S_EOL0=7, S_EOL1=8, S_ACK=9,
      S_BUS=10, S_CHR=11, S_CHW=12;
    reg [3:0]  st, st_ret;
    reg [4:0]  firstbuf;
    reg [10:0] rxlen, byteidx;
    reg [1:0]  nb;                          // byte within 32-bit word
    reg [31:0] word;
    reg [1:0]  emitph;                      // 0 hi-nib, 1 lo-nib, 2 advance
    wire [7:0] curbyte = word >> {nb, 3'b000};

    always @(posedge cpu_clk) begin
        if (rst_sync) begin
            st <= S_IN0; rxd_req <= 0; rxd_we <= 0; utx_stb <= 0;
            firstbuf <= 0; rxlen <= 0; byteidx <= 0; nb <= 0; emitph <= 0;
        end else begin
            utx_stb <= 1'b0;
            case (st)
              // ---- eth_init ----
              S_IN0: begin rxd_addr<=O_MACLO; rxd_wdata<=MACLO_VAL; rxd_we<=1;
                           rxd_req<=1; st_ret<=S_IN1; st<=S_BUS; end
              S_IN1: begin rxd_addr<=O_MACHI; rxd_wdata<=MACHI_VAL; rxd_we<=1;
                           rxd_req<=1; st_ret<=S_IN2; st<=S_BUS; end
              S_IN2: begin rxd_addr<=O_RFCS;  rxd_wdata<=32'd31;    rxd_we<=1;
                           rxd_req<=1; st_ret<=S_POLL; st<=S_BUS; end
              // ---- poll receive status ----
              S_POLL: begin rxd_addr<=O_RSR; rxd_we<=0; rxd_req<=1;
                            st_ret<=S_LEN; st<=S_BUS; end
              S_LEN: begin
                  if (bm_rdata[15]) begin                    // RECV_DONE
                      firstbuf <= bm_rdata[4:0];
                      rxd_addr <= O_RPLR | {bm_rdata[4:0], 3'b000};
                      rxd_we<=0; rxd_req<=1; st_ret<=S_RDW; st<=S_BUS;
                  end else st <= S_POLL;
              end
              S_RDW: begin
                  if (byteidx == 0)                           // RPLR length
                      rxlen <= (bm_rdata[10:0] > 11'd4)
                                 ? (bm_rdata[10:0] - 11'd4) : 11'd0;
                  nb <= 0; emitph <= 0;
                  rxd_addr <= O_RXBUF | (firstbuf << 11) | byteidx;
                  rxd_we<=0; rxd_req<=1; st_ret<=S_EMIT; st<=S_BUS;
              end
              S_EMIT: begin
                  if (rxlen == 0) st <= S_EOL0;
                  else case (emitph)
                    2'd0: begin uch<=hexc(curbyte[7:4]); emitph<=1;
                                st_ret<=S_EMIT; st<=S_CHR; end
                    2'd1: begin uch<=hexc(curbyte[3:0]); emitph<=2;
                                st_ret<=S_EMIT; st<=S_CHR; end
                    default: begin
                        emitph <= 0;
                        if (byteidx + 1 >= rxlen) st <= S_EOL0;
                        else if (nb == 2'd3) begin
                            byteidx <= byteidx + 1; st <= S_RDW;
                        end else begin
                            byteidx <= byteidx + 1; nb <= nb + 1;
                        end
                    end
                  endcase
              end
              S_EOL0: begin uch<=8'h0D; st_ret<=S_EOL1; st<=S_CHR; end
              S_EOL1: begin uch<=8'h0A; st_ret<=S_ACK;  st<=S_CHR; end
              S_ACK: begin
                  rxd_addr<=O_RSR; rxd_wdata<={27'b0, firstbuf + 5'd1};
                  rxd_we<=1; rxd_req<=1; byteidx<=0; st_ret<=S_POLL; st<=S_BUS;
              end
              // ---- shared bus wait (latch RX word when returning to EMIT) --
              S_BUS: if (bm_done_rxd) begin
                        rxd_req<=0;
                        if (st_ret==S_EMIT) word<=bm_rdata;
                        st<=st_ret;
                     end
              // ---- shared char send ----
              S_CHR: begin utx_stb<=1'b1; st<=S_CHW; end
              S_CHW: if (!utx_busy) st<=st_ret;
              default: st <= S_POLL;
            endcase
        end
    end
    wire rxd_inited = (st != S_IN0 && st != S_IN1 && st != S_IN2);

    // ==================================================================
    //  TX-load FSM  (owns UART RX + bus writes)
    //  Collect hex pairs into 32-bit words, write them into the eth TX
    //  buffer, CR/LF flushes (pad to 60) + TPLR trigger.  Overruns dropped.
    // ==================================================================
    localparam [3:0]
      T_IDLE=0, T_CHKW=1, T_ACC=2, T_WRW=3, T_FLUSHW=4,
      T_PAD=5, T_PADW=6, T_TRIG=7, T_TRIGW=8;
    reg [3:0]  tst;
    reg        havehi, dropping;
    reg [3:0]  hinib;
    reg [15:0] wp;                          // byte write pointer
    reg [31:0] wacc;                        // 32-bit word being filled
    reg [15:0] sendlen, padidx;

    // 1-deep UART-RX capture; a byte arriving while one is pending = overrun
    reg        rxpend; reg [7:0] rxbyte;
    wire       txl_consume = rxpend &
                   ( (tst==T_ACC) |
                     (tst==T_IDLE & ~(rxd_inited & ishex(rxbyte))) );
    always @(posedge cpu_clk) begin
        if (rst_sync) rxpend <= 1'b0;
        else if (urx_stb & ~rxpend) begin rxpend<=1'b1; rxbyte<=urx_data; end
        else if (txl_consume) rxpend <= 1'b0;
    end
    wire [7:0] newbyte = {hinib, hexv(rxbyte)};

    always @(posedge cpu_clk) begin
        if (rst_sync) begin
            tst<=T_IDLE; txl_req<=0; txl_we<=0; havehi<=0; wp<=0; wacc<=0;
            dropping<=0; sendlen<=0; padidx<=0;
        end else begin
            case (tst)
              T_IDLE: begin
                  havehi<=0; wp<=0; wacc<=0; dropping<=0;
                  if (rxd_inited && rxpend && ishex(rxbyte)) begin
                      txl_addr<=O_TPLR; txl_we<=0; txl_req<=1; tst<=T_CHKW;
                  end
              end
              T_CHKW: if (bm_done_txl) begin
                  txl_req<=0; dropping<=bm_rdata[31]; tst<=T_ACC;  // busy->drop
              end
              T_ACC: if (rxpend) begin
                  if (rxbyte==8'h0D || rxbyte==8'h0A) begin        // terminator
                      if (dropping || wp==0) tst<=T_IDLE;
                      else if (wp[1:0]!=0) begin                   // partial word
                          txl_addr<=O_TXBUF | {1'b0,wp[15:2],2'b00};
                          txl_wdata<=wacc; txl_we<=1; txl_req<=1; tst<=T_FLUSHW;
                      end else tst<=T_PAD;
                  end else if (ishex(rxbyte)) begin
                      if (!havehi) begin hinib<=hexv(rxbyte); havehi<=1; end
                      else begin
                          havehi<=0;
                          if (!dropping && wp<16'd2040) begin
                              case (wp[1:0])
                                2'd0: wacc[ 7: 0] <= newbyte;
                                2'd1: wacc[15: 8] <= newbyte;
                                2'd2: wacc[23:16] <= newbyte;
                                2'd3: wacc[31:24] <= newbyte;
                              endcase
                              if (wp[1:0]==2'd3) begin
                                  txl_addr<=O_TXBUF | {1'b0,wp[15:2],2'b00};
                                  txl_wdata<={newbyte, wacc[23:0]};
                                  txl_we<=1; txl_req<=1; tst<=T_WRW;
                              end
                              wp<=wp+16'd1;
                          end
                      end
                  end
                  // else: separator (space etc.) - ignore, byte consumed
              end
              T_WRW: if (bm_done_txl) begin txl_req<=0; wacc<=0; tst<=T_ACC; end
              T_FLUSHW: if (bm_done_txl) begin
                  txl_req<=0; wacc<=0;
                  sendlen <= (wp<16'd60)?16'd60:wp;
                  padidx  <= {1'b0,wp[15:2],2'b00} + 16'd4;
                  tst<=T_PAD;
              end
              T_PAD: begin
                  if (wp[1:0]==0) begin       // arrived word-aligned
                      sendlen <= (wp<16'd60)?16'd60:wp;
                      padidx  <= {1'b0,wp[15:2],2'b00};
                  end
                  if (padidx >= ((sendlen+16'd3) & ~16'd3)) tst<=T_TRIG;
                  else begin
                      txl_addr<=O_TXBUF | {1'b0,padidx}; txl_wdata<=32'd0;
                      txl_we<=1; txl_req<=1; tst<=T_PADW;
                  end
              end
              T_PADW: if (bm_done_txl) begin
                  txl_req<=0; padidx<=padidx+16'd4; tst<=T_PAD;
              end
              T_TRIG: begin
                  txl_addr<=O_TPLR; txl_wdata<={16'b0,sendlen};
                  txl_we<=1; txl_req<=1; tst<=T_TRIGW;
              end
              T_TRIGW: if (bm_done_txl) begin txl_req<=0; tst<=T_IDLE; end
              default: tst<=T_IDLE;
            endcase
        end
    end

    // LEDs: liveness + link status (no picosoc gpio anymore)
    reg [25:0] hb;
    always @(posedge cpu_clk) hb <= hb + 1;
    assign led = {mmcm_locked, resetn, hb[25], rxd_inited, status_sync1[3:0]};

    // ==================================================================
    //  framing_top_sgmii  (identical instantiation to vc707_ethsoc.v)
    // ==================================================================
    framing_top_sgmii eth (
        .msoc_clk       (cpu_clk),
        .core_lsu_addr  (bm_addr),
        .core_lsu_wdata (eth_wdata),
        .core_lsu_be    (eth_be),
        .ce_d           (eth_ce),
        .we_d           (eth_we_d),
        .framing_sel    (eth_ce),
        .framing_rdata  (framing_rdata),
        .clk_int        (eth_int_clk),
        .rst_int        (rst_sync),
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
        .eth_irq        (),
        .pcspma_status_o(pcspma_status),
        .eth_clk_o      (),
        .gtrefclk_bufg_o()
    );
endmodule

// ---------------------------------------------------------------------
//  UART transmitter: 8N1, LSB first.  Pulse stb (1 cycle) when !busy.
//  busy = active | stb so the caller can safely poll !busy after stb.
// ---------------------------------------------------------------------
module uart_tx #(parameter integer DIV = 434) (
    input  wire       clk, rst,
    input  wire [7:0] data,
    input  wire       stb,
    output wire       tx,
    output wire       busy
);
    reg [9:0]  sh    = 10'h3FF;
    reg [15:0] cnt   = 0;
    reg [3:0]  nbits = 0;
    reg        active= 0;
    assign busy = active | stb;
    assign tx   = active ? sh[0] : 1'b1;
    always @(posedge clk)
        if (rst) begin active<=0; sh<=10'h3FF; cnt<=0; nbits<=0; end
        else if (!active) begin
            if (stb) begin sh<={1'b1,data,1'b0}; active<=1; cnt<=DIV-1; nbits<=0; end
        end else if (cnt==0) begin
            if (nbits==4'd9) active<=0;
            sh<={1'b1,sh[9:1]}; cnt<=DIV-1; nbits<=nbits+1;
        end else cnt<=cnt-1;
endmodule

// ---------------------------------------------------------------------
//  UART receiver: 8N1, LSB first.  stb pulses 1 cycle with data valid.
// ---------------------------------------------------------------------
module uart_rx #(parameter integer DIV = 434) (
    input  wire       clk, rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        stb
);
    reg        rx1=1, rx2=1, active=0;
    reg [15:0] cnt=0;
    reg [3:0]  nbits=0;
    reg [7:0]  sh=0;
    always @(posedge clk) begin
        rx1 <= rx; rx2 <= rx1; stb <= 1'b0;
        if (rst) begin active<=0; cnt<=0; nbits<=0; end
        else if (!active) begin
            // start = falling edge (rx2 high, rx1 low); edge-detect avoids
            // re-triggering on a still-low last data bit after a byte.
            if (rx2 & ~rx1) begin active<=1; cnt<=DIV + (DIV>>1) - 1; nbits<=0; end
        end else if (cnt==0) begin
            sh <= {rx2, sh[7:1]}; cnt <= DIV-1; nbits <= nbits+1;
            if (nbits==4'd7) begin active<=0; data<={rx2,sh[7:1]}; stb<=1'b1; end
        end else cnt <= cnt-1;
    end
endmodule
`default_nettype wire
