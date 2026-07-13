// Minimal JTAG<->UART loopback triage design for the VC707 open flow.
// BSCANE2 USER1 carries a 40-bit command/status register:
//   shift in  : {cmd[7:0], data[7:0], 24'bx}   (LSB first)
//     cmd 0x01 = send data[7:0] on UART TX
//     cmd 0x02 = set control = data ([0]=internal loopback enable)
//   capture   : {hb[7:0], rx_cnt[7:0], rx_byte[7:0], status[7:0], 8'hA5}
//     status = {3'b0, lb_en, rx_busy, tx_busy, rst_n, locked}
// LEDs: LD7 locked, LD6 rst_n, LD5 clk heartbeat, LD4 tck heartbeat,
//       LD3 tx_busy(stretched), LD2 rx activity(stretched), LD1 lb_en,
//       LD0 cmd pulse(stretched).
module top_lb (
  input  IO_CLK_P,
  input  IO_CLK_N,
  input  IO_RST,          // CPU_RESET, active high
  output [7:0] LED,
  output UART_TX,
  input  UART_RX
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

  // ---------------- BSCAN USER1 ----------------
  logic bs_sel, bs_capture, bs_shift, bs_update, bs_drck, bs_tdi;
  logic [39:0] bs_sr;
  BSCANE2 #(.JTAG_CHAIN(1)) bscan (
    .CAPTURE(bs_capture), .DRCK(bs_drck), .RESET(), .RUNTEST(),
    .SEL(bs_sel), .SHIFT(bs_shift), .TCK(), .TDI(bs_tdi),
    .TDO(bs_sr[0]), .TMS(), .UPDATE(bs_update));

  // clk-domain state
  logic [7:0] tx_data_q, ctrl_q, rx_byte_q, rx_cnt_q;
  logic       tx_busy, rx_busy;
  logic [24:0] hb;
  always_ff @(posedge clk) hb <= hb + 1'b1;
  logic [12:0] hb_tck;
  always_ff @(posedge bs_drck) hb_tck <= hb_tck + 1'b1;

  // command handshake: TCK -> clk via toggle
  logic        cmd_tgl;       // tck domain
  logic [15:0] cmd_word;      // {cmd, data} latched at UPDATE
  always_ff @(posedge bs_update) begin
    if (bs_sel) begin
      cmd_word <= bs_sr[15:0];
      cmd_tgl  <= ~cmd_tgl;
    end
  end
  logic [2:0] cmd_sync;
  always_ff @(posedge clk) cmd_sync <= {cmd_sync[1:0], cmd_tgl};
  wire cmd_pulse = cmd_sync[2] ^ cmd_sync[1];

  // capture path (status into shifter)
  wire [7:0] status = {3'b000, ctrl_q[0], rx_busy, tx_busy, rst_n, locked};
  always_ff @(posedge bs_drck) begin
    if (bs_sel && bs_capture)
      bs_sr <= {hb[24:17], rx_cnt_q, rx_byte_q, status, 8'hA5};
    else if (bs_sel && bs_shift)
      bs_sr <= {bs_tdi, bs_sr[39:1]};
  end

  // ------------- ibex demo uart.sv behind a device-bus shim -------------
  // cmd 0x01: write data byte to UART TX (device write @0x4)
  // cmd 0x02: control ([0]=internal loopback)
  // cmd 0x03: pop RX byte (device read @0x0), result in rx_byte_q
  // cmd 0x04: read STATUS (device read @0x8), result in rx_byte_q
  logic        dev_req, dev_we, dev_rvalid;
  logic [31:0] dev_addr, dev_wdata, dev_rdata;
  logic        uart_tx_o_int, uart_rx_in;

  always_ff @(posedge clk) begin
    dev_req <= 1'b0; dev_we <= 1'b0;
    if (!rst_n) begin
      ctrl_q <= 8'h00; tx_data_q <= 8'h00;
    end else if (cmd_pulse) begin
      case (cmd_word[15:8])
        8'h01: begin dev_req <= 1'b1; dev_we <= 1'b1; dev_addr <= 32'h4;
                     dev_wdata <= {24'b0, cmd_word[7:0]}; tx_data_q <= cmd_word[7:0]; end
        8'h02: ctrl_q <= cmd_word[7:0];
        8'h03: begin dev_req <= 1'b1; dev_addr <= 32'h0; end
        8'h04: begin dev_req <= 1'b1; dev_addr <= 32'h8; end
        default: ;
      endcase
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rx_byte_q <= 8'h00; rx_cnt_q <= 8'h00;
    end else if (dev_rvalid && !dev_we) begin
      rx_byte_q <= dev_rdata[7:0];
      rx_cnt_q  <= rx_cnt_q + 1;
    end
  end

  assign uart_rx_in = ctrl_q[0] ? uart_tx_o_int : UART_RX;
  assign UART_TX = uart_tx_o_int;
  assign tx_busy = dev_req;          // stretched below anyway
  assign rx_busy = ~uart_rx_in;      // line active = traffic

  uart #(
    .ClockFrequency(50_000_000),
    .BaudRate(115_200)
  ) u_uart (
    .clk_i(clk), .rst_ni(rst_n),
    .device_req_i(dev_req),
    .device_addr_i(dev_addr),
    .device_we_i(dev_we),
    .device_be_i(4'hF),
    .device_wdata_i(dev_wdata),
    .device_rvalid_o(dev_rvalid),
    .device_rdata_o(dev_rdata),
    .uart_rx_i(uart_rx_in),
    .uart_irq_o(),
    .uart_tx_o(uart_tx_o_int)
  );

  // ---------------- LEDs ----------------
  logic [21:0] tx_str, rx_str, cmd_str;
  always_ff @(posedge clk) begin
    tx_str  <= tx_busy   ? '1 : (tx_str  != 0 ? tx_str  - 1 : 0);
    rx_str  <= rx_busy   ? '1 : (rx_str  != 0 ? rx_str  - 1 : 0);
    cmd_str <= cmd_pulse ? '1 : (cmd_str != 0 ? cmd_str - 1 : 0);
  end
  assign LED = {locked, rst_n, hb[24], hb_tck[12],
                tx_str != 0, rx_str != 0, ctrl_q[0], cmd_str != 0};
endmodule
