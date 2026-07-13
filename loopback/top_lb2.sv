// Loopback triage, rung 2: JTAG host -> demo-system bus.sv -> {gpio.sv, uart.sv}.
// Reproduces the failing Ibex-SoC SBA->bus->GPIO write path in miniature.
//
// BSCAN USER1, 40-bit register, LSB-first:
//   shift in : {24'bx, data[7:0], cmd[7:0]}
//     cmd 0x01 = bus write UART TX   (0x80001004 <= data)
//     cmd 0x02 = set control byte    ([0]=uart internal loopback,
//                                     [1]=LEDs show status instead of gp_o)
//     cmd 0x03 = bus read  UART RX   (0x80001000) -> rd_byte
//     cmd 0x04 = bus read  UART STAT (0x80001008) -> rd_byte
//     cmd 0x05 = bus write GPIO      (0x80000000 <= data)   <- the failing op
//     cmd 0x06 = bus read  GPIO      (0x80000000) -> rd_byte
//   capture  : {hb[7:0], rd_cnt[7:0], rd_byte[7:0], status[7:0], 8'hA5}
//     status = {2'b0, bus_err_seen, lb_en, gnt_seen, rvalid_seen, rst_n, locked}
module top_lb2 (
  input  IO_CLK_P,
  input  IO_CLK_N,
  input  IO_RST,
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

  logic [24:0] hb;
  always_ff @(posedge clk) hb <= hb + 1'b1;

  logic        cmd_tgl;
  logic [15:0] cmd_word;
  always_ff @(posedge bs_update) begin
    if (bs_sel) begin
      cmd_word <= bs_sr[15:0];
      cmd_tgl  <= ~cmd_tgl;
    end
  end
  logic [2:0] cmd_sync;
  always_ff @(posedge clk) cmd_sync <= {cmd_sync[1:0], cmd_tgl};
  wire cmd_pulse = cmd_sync[2] ^ cmd_sync[1];

  // ---------------- JTAG bus host ----------------
  logic        host_req, host_we;
  logic [31:0] host_addr, host_wdata;
  logic [3:0]  host_be;
  logic        host_gnt, host_rvalid, host_err;
  logic [31:0] host_rdata;
  logic [7:0]  ctrl_q, rd_byte_q, rd_cnt_q;
  logic        gnt_seen, rvalid_seen, err_seen;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      host_req <= 1'b0; host_we <= 1'b0; host_be <= 4'hF;
      ctrl_q <= 8'h00; gnt_seen <= 1'b0;
    end else begin
      if (host_req && host_gnt)
        host_req <= 1'b0;            // single-beat: drop after grant
      if (host_gnt) gnt_seen <= 1'b1;
      if (cmd_pulse) begin
        case (cmd_word[15:8])
          8'h01: begin host_req <= 1'b1; host_we <= 1'b1; host_addr <= 32'h80001004;
                       host_wdata <= {24'b0, cmd_word[7:0]}; end
          8'h02: ctrl_q <= cmd_word[7:0];
          8'h03: begin host_req <= 1'b1; host_we <= 1'b0; host_addr <= 32'h80001000; end
          8'h04: begin host_req <= 1'b1; host_we <= 1'b0; host_addr <= 32'h80001008; end
          8'h05: begin host_req <= 1'b1; host_we <= 1'b1; host_addr <= 32'h80000000;
                       host_wdata <= {24'b0, cmd_word[7:0]}; end
          8'h06: begin host_req <= 1'b1; host_we <= 1'b0; host_addr <= 32'h80000000; end
          default: ;
        endcase
      end
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_byte_q <= 8'h00; rd_cnt_q <= 8'h00; rvalid_seen <= 1'b0; err_seen <= 1'b0;
    end else begin
      if (host_rvalid) begin
        rd_byte_q   <= host_rdata[7:0];
        rd_cnt_q    <= rd_cnt_q + 1;
        rvalid_seen <= 1'b1;
      end
      if (host_err) err_seen <= 1'b1;
    end
  end

  wire [7:0] status = {2'b00, err_seen, ctrl_q[0], gnt_seen, rvalid_seen, rst_n, locked};
  always_ff @(posedge bs_drck) begin
    if (bs_sel && bs_capture)
      bs_sr <= {hb[24:17], rd_cnt_q, rd_byte_q, status, 8'hA5};
    else if (bs_sel && bs_shift)
      bs_sr <= {bs_tdi, bs_sr[39:1]};
  end

  // ---------------- bus + devices ----------------
  localparam int unsigned NrDevices = 2;
  localparam int unsigned NrHosts = 1;
  logic        device_req[NrDevices];
  logic [31:0] device_addr[NrDevices];
  logic        device_we[NrDevices];
  logic [3:0]  device_be[NrDevices];
  logic [31:0] device_wdata[NrDevices];
  logic        device_rvalid[NrDevices];
  logic [31:0] device_rdata[NrDevices];
  logic        device_err[NrDevices];
  logic [31:0] cfg_device_addr_base[NrDevices];
  logic [31:0] cfg_device_addr_mask[NrDevices];
  assign cfg_device_addr_base[0] = 32'h80000000;          // gpio
  assign cfg_device_addr_mask[0] = ~32'(4 * 1024 - 1);
  assign cfg_device_addr_base[1] = 32'h80001000;          // uart
  assign cfg_device_addr_mask[1] = ~32'(4 * 1024 - 1);
  assign device_err[0] = 1'b0;
  assign device_err[1] = 1'b0;

  logic h_req[NrHosts];
  logic [31:0] h_addr[NrHosts];
  logic h_we[NrHosts];
  logic [3:0] h_be[NrHosts];
  logic [31:0] h_wdata[NrHosts];
  logic h_gnt[NrHosts], h_rvalid[NrHosts], h_err[NrHosts];
  logic [31:0] h_rdata[NrHosts];
  assign h_req[0] = host_req;
  assign h_addr[0] = host_addr;
  assign h_we[0] = host_we;
  assign h_be[0] = host_be;
  assign h_wdata[0] = host_wdata;
  assign host_gnt = h_gnt[0];
  assign host_rvalid = h_rvalid[0];
  assign host_rdata = h_rdata[0];
  assign host_err = h_err[0];

  bus #(
    .NrDevices(NrDevices), .NrHosts(NrHosts),
    .DataWidth(32), .AddressWidth(32)
  ) u_bus (
    .clk_i(clk), .rst_ni(rst_n),
    .host_req_i(h_req), .host_gnt_o(h_gnt),
    .host_addr_i(h_addr), .host_we_i(h_we), .host_be_i(h_be),
    .host_wdata_i(h_wdata), .host_rvalid_o(h_rvalid),
    .host_rdata_o(h_rdata), .host_err_o(h_err),
    .device_req_o(device_req), .device_addr_o(device_addr),
    .device_we_o(device_we), .device_be_o(device_be),
    .device_wdata_o(device_wdata), .device_rvalid_i(device_rvalid),
    .device_rdata_i(device_rdata), .device_err_i(device_err),
    .cfg_device_addr_base, .cfg_device_addr_mask);

  logic [7:0] gp_o;
  gpio #(
    .GpiWidth(1), .GpoWidth(8)
  ) u_gpio (
    .clk_i(clk), .rst_ni(rst_n),
    .device_req_i(device_req[0]), .device_addr_i(device_addr[0]),
    .device_we_i(device_we[0]), .device_be_i(device_be[0]),
    .device_wdata_i(device_wdata[0]), .device_rvalid_o(device_rvalid[0]),
    .device_rdata_o(device_rdata[0]),
    .gp_i(1'b0), .gp_o(gp_o));

  logic uart_tx_int, uart_rx_in;
  assign uart_rx_in = ctrl_q[0] ? uart_tx_int : UART_RX;
  assign UART_TX = uart_tx_int;
  uart #(
    .ClockFrequency(50_000_000), .BaudRate(115_200)
  ) u_uart (
    .clk_i(clk), .rst_ni(rst_n),
    .device_req_i(device_req[1]), .device_addr_i(device_addr[1]),
    .device_we_i(device_we[1]), .device_be_i(device_be[1]),
    .device_wdata_i(device_wdata[1]), .device_rvalid_o(device_rvalid[1]),
    .device_rdata_o(device_rdata[1]),
    .uart_rx_i(uart_rx_in), .uart_irq_o(), .uart_tx_o(uart_tx_int));

  // ---------------- LEDs ----------------
  assign LED = ctrl_q[1] ? {locked, rst_n, hb[24], gnt_seen,
                            rvalid_seen, err_seen, ctrl_q[0], 1'b0}
                         : gp_o;
endmodule
