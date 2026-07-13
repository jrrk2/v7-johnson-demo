// Loopback triage, rung 3: JTAG master -> framing_top_sgmii (lowRISC SGMII
// ethernet).  No processor: packets and configuration registers are read
// and written directly over the FPGA's JTAG (BSCANE2 USER1).
//
// BSCAN USER1, 72-bit register, LSB-first:
//   shift in : {8'bx, wdata[31:0], addr[23:0], cmd[7:0]}
//     cmd 0x01 = eth write word: framing[addr] <= wdata (32-bit, half-of-64)
//     cmd 0x02 = eth read  word: rdata <= framing[addr]
//     cmd 0x03 = control byte  ([0]=LEDs show gp instead of status; gp=wdata[7:0])
//     cmd 0x04 = read pcspma_status into rdata
//   capture  : {hb[15:0], rd_cnt[7:0], rdata[31:0], status[7:0], 8'hA5}
//     status = {3'b0, eth_irq, link_up, busy, rst_n, locked}
// LEDs (default): LD7 locked, LD6 rst_n, LD5 clk hb, LD4 link_up,
//                 LD3 eth_irq, LD2..LD0 gp[2:0]
module top_lb3 (
  input  IO_CLK_P,
  input  IO_CLK_N,
  input  IO_RST,
  output [7:0] LED,
  // SGMII + PHY management (VC707 GTX bank 117)
  input  sgmii_rxp, sgmii_rxn,
  output sgmii_txp, sgmii_txn,
  input  sgmii_refclk_p, sgmii_refclk_n,
  output eth_rst_n,
  inout  eth_mdio,
  output eth_mdc
);
  logic clk, locked, rst_n;
  logic io_clk_buf, clk_unbuf, clk_fb;

  IBUFDS ibuf_clk (.I(IO_CLK_P), .IB(IO_CLK_N), .O(io_clk_buf));
  MMCME2_ADV #(
    .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"), .STARTUP_WAIT("FALSE"),
    .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
    .CLKOUT0_DIVIDE_F(20.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKIN1_PERIOD(5.000)
  ) mmcm (
    .CLKFBOUT(clk_fb), .CLKFBOUTB(), .CLKOUT0(clk_unbuf),
    .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .CLKFBIN(clk_fb), .CLKIN1(io_clk_buf), .CLKIN2(1'b0), .CLKINSEL(1'b1),
    .DADDR(7'h0), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0), .DO(), .DRDY(), .DWE(1'b0),
    .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
    .CLKINSTOPPED(), .CLKFBSTOPPED(), .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
  BUFG bufg_clk (.I(clk_unbuf), .O(clk));
  assign rst_n = locked & ~IO_RST;

  // ---------------- BSCAN USER1, 72-bit ----------------
  logic bs_sel, bs_capture, bs_shift, bs_update, bs_drck, bs_tdi;
  logic [71:0] bs_sr;
  BSCANE2 #(.JTAG_CHAIN(1)) bscan (
    .CAPTURE(bs_capture), .DRCK(bs_drck), .RESET(), .RUNTEST(),
    .SEL(bs_sel), .SHIFT(bs_shift), .TCK(), .TDI(bs_tdi),
    .TDO(bs_sr[0]), .TMS(), .UPDATE(bs_update));

  logic [24:0] hb;
  always_ff @(posedge clk) hb <= hb + 1'b1;

  logic        cmd_tgl;
  logic [63:0] cmd_word;     // {wdata32, addr24, cmd8}
  always_ff @(posedge bs_update) begin
    if (bs_sel) begin
      cmd_word <= bs_sr[63:0];
      cmd_tgl  <= ~cmd_tgl;
    end
  end
  logic [2:0] cmd_sync;
  always_ff @(posedge clk) cmd_sync <= {cmd_sync[1:0], cmd_tgl};
  wire cmd_pulse = cmd_sync[2] ^ cmd_sync[1];
  wire [7:0]  cmd  = cmd_word[7:0];
  wire [23:0] addr = cmd_word[31:8];
  wire [31:0] wdat = cmd_word[63:32];

  // ---------------- eth 32->64 shim (ethsoc pattern) ----------------
  logic        eth_ce, eth_resp, busy;
  wire  [63:0] framing_rdata;
  logic [16:0] eth_addr_q;
  logic [63:0] eth_wdata_q;
  logic [7:0]  eth_be_q;
  logic        eth_we_q, eth_half_q;
  logic [31:0] rdata_q;
  logic [7:0]  rd_cnt_q, gp_q;
  logic        leds_gp;

  wire [15:0] pcspma_status;
  logic [15:0] status_sync0, status_sync1;
  always_ff @(posedge clk) begin
    status_sync0 <= pcspma_status;
    status_sync1 <= status_sync0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      eth_ce <= 1'b0; eth_resp <= 1'b0; busy <= 1'b0;
      gp_q <= 8'h00; leds_gp <= 1'b0;
      rdata_q <= 32'h0; rd_cnt_q <= 8'h0;
    end else begin
      eth_ce   <= 1'b0;
      eth_resp <= eth_ce;
      if (eth_resp) begin
        busy <= 1'b0;
        if (!eth_we_q) begin
          rdata_q  <= eth_half_q ? framing_rdata[63:32] : framing_rdata[31:0];
          rd_cnt_q <= rd_cnt_q + 1;
        end
      end
      if (cmd_pulse) begin
        case (cmd)
          8'h01, 8'h02: begin
            eth_ce      <= 1'b1;
            busy        <= 1'b1;
            eth_addr_q  <= addr[16:0];
            eth_wdata_q <= {wdat, wdat};
            eth_be_q    <= addr[2] ? 8'hF0 : 8'h0F;
            eth_we_q    <= (cmd == 8'h01);
            eth_half_q  <= addr[2];
          end
          8'h03: begin gp_q <= wdat[7:0]; leds_gp <= wdat[8]; end
          8'h04: begin rdata_q <= {16'b0, status_sync1}; rd_cnt_q <= rd_cnt_q + 1; end
          default: ;
        endcase
      end
    end
  end

  wire link_up = status_sync1[0];
  wire eth_irq;
  wire [7:0] status = {3'b000, eth_irq, link_up, busy, rst_n, locked};
  always_ff @(posedge bs_drck) begin
    if (bs_sel && bs_capture)
      bs_sr <= {hb[24:9], rd_cnt_q, rdata_q, status, 8'hA5};
    else if (bs_sel && bs_shift)
      bs_sr <= {bs_tdi, bs_sr[71:1]};
  end

  // ---------------- ethernet ----------------
  logic phy_mdio_i, phy_mdio_o, phy_mdio_oe;
  assign eth_mdio = phy_mdio_oe ? phy_mdio_o : 1'bz;
  assign phy_mdio_i = eth_mdio;
  wire eth_clk_o_unused, gtrefclk_bufg_unused;

  framing_top_sgmii eth (
    .msoc_clk       (clk),
    .core_lsu_addr  (eth_addr_q),
    .core_lsu_wdata (eth_wdata_q),
    .core_lsu_be    (eth_be_q),
    .ce_d           (eth_ce),
    .we_d           (eth_ce & eth_we_q),
    .framing_sel    (eth_ce),
    .framing_rdata  (framing_rdata),
    .clk_int        (clk),
    .rst_int        (!rst_n),
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
    .eth_clk_o      (eth_clk_o_unused),
    .gtrefclk_bufg_o(gtrefclk_bufg_unused)
  );

  assign LED = leds_gp ? gp_q
                       : {locked, rst_n, hb[24], link_up, eth_irq, busy, gp_q[1:0]};
endmodule
