// Integration test for the FIFO-boundary framing_top_sgmii: CPU bus -> TX
// BRAM -> push FSM -> async FIFO -> 125 MHz unpacker -> (sgmii_soc_stub
// loopback) -> 125 MHz packer -> async FIFO -> drain FSM -> RX BRAM -> CPU
// bus.  Compile with sgmii_soc_stub.v in place of sgmii_soc.sv.
`timescale 1ns/1ps
module tb;
  reg msoc_clk = 0, clk_int = 0, rst_int = 1;
  always #10 msoc_clk = ~msoc_clk;   // 50 MHz
  always #2.5 clk_int = ~clk_int;    // 200 MHz free-run (unused by stub)

  reg  [16:0] core_lsu_addr = 0;
  reg  [63:0] core_lsu_wdata = 0;
  reg  [7:0]  core_lsu_be = 0;
  reg         ce_d = 0, we_d = 0, framing_sel = 0;
  wire [63:0] framing_rdata;
  wire        eth_irq, phy_mdc;
  wire [15:0] pcspma_status_o;

  framing_top_sgmii dut (
    .msoc_clk(msoc_clk),
    .core_lsu_addr(core_lsu_addr),
    .core_lsu_wdata(core_lsu_wdata),
    .core_lsu_be(core_lsu_be),
    .ce_d(ce_d), .we_d(we_d), .framing_sel(framing_sel),
    .framing_rdata(framing_rdata),
    .clk_int(clk_int), .rst_int(rst_int),
    .sgmii_rxp(1'b0), .sgmii_rxn(1'b1),
    .sgmii_txp(), .sgmii_txn(),
    .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1),
    .phy_reset_n(),
    .phy_mdio_i(1'b0), .phy_mdio_o(), .phy_mdio_oe(), .phy_mdc(phy_mdc),
    .eth_irq(eth_irq),
    .pcspma_status_o(pcspma_status_o),
    .eth_clk_o(), .gtrefclk_bufg_o());

  integer errors = 0;

  task bus_write(input [16:0] addr, input [63:0] data, input [7:0] be);
    begin
      @(negedge msoc_clk);
      core_lsu_addr = addr; core_lsu_wdata = data; core_lsu_be = be;
      ce_d = 1; we_d = 1; framing_sel = 1;
      @(negedge msoc_clk);
      ce_d = 0; we_d = 0; framing_sel = 0;
    end
  endtask

  task bus_read(input [16:0] addr, output [63:0] data);
    begin
      @(negedge msoc_clk);
      core_lsu_addr = addr; core_lsu_be = 8'hFF;
      ce_d = 1; we_d = 0; framing_sel = 1;
      @(negedge msoc_clk);      // ce_d_dly high now: rdata valid this cycle
      data = framing_rdata;
      ce_d = 0; framing_sel = 0;
      @(negedge msoc_clk);
    end
  endtask

  reg [63:0] rd, status;
  reg [7:0]  txf [0:127];
  integer i, w, len, tries;
  reg [10:0] rxlen;

  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("tb_framing_fifo.vcd"); $dumpvars(0, tb);
    end
    #200 rst_int = 0;
    #100;

    // configure: 8 RX buffers, broadcast frame passes the filter
    bus_write(17'h0828, 64'd8, 8'hFF);   // lastbuf = 8  (reg 5)
    bus_write(17'h0830, 64'd0, 8'hFF);   // firstbuf = 0 (reg 6)

    // build a 72-byte broadcast frame: FF x6 dst, pattern payload
    len = 72;
    for (i = 0; i < 6;  i = i + 1) txf[i] = 8'hFF;
    for (i = 6; i < len; i = i + 1) txf[i] = i[7:0] ^ 8'h5A;

    // load TX buffer at 0x1000 (64-bit words, little-endian bytes)
    for (w = 0; w < (len+7)/8; w = w + 1)
      bus_write(17'h1000 + w*8,
        {txf[w*8+7],txf[w*8+6],txf[w*8+5],txf[w*8+4],txf[w*8+3],txf[w*8+2],txf[w*8+1],txf[w*8+0]},
        8'hFF);

    // trigger send (reg 2 = payload length)
    bus_write(17'h0810, len, 8'hFF);

    // wait for RX: poll status reg 0x0830 until avail (nextbuf != firstbuf)
    tries = 0;
    status = 0;
    while (!status[15] && tries < 3000) begin  // bit15 = avail
      bus_read(17'h0830, status);
      tries = tries + 1;
    end
    if (!status[15]) begin
      $display("FAIL: no RX frame (status=%h after %0d polls)", status, tries);
      errors = errors + 1;
    end else begin
      // length of buffer 0
      bus_read(17'h0C00, rd);
      rxlen = rd[10:0];
      if (rxlen !== len) begin
        $display("FAIL: rx length %0d != %0d", rxlen, len);
        errors = errors + 1;
      end
      // compare payload from RX buffer 0 (0x10000)
      for (w = 0; w < (len+7)/8; w = w + 1) begin
        bus_read(17'h10000 + w*8, rd);
        for (i = 0; i < 8; i = i + 1)
          if (w*8+i < len && rd[i*8 +: 8] !== txf[w*8+i]) begin
            $display("FAIL: byte %0d got %h exp %h", w*8+i, rd[i*8 +: 8], txf[w*8+i]);
            errors = errors + 1;
          end
      end
      // tx_busy must have cleared
      bus_read(17'h0810, rd);
      if (rd[31]) begin
        $display("FAIL: tx_busy stuck (%h)", rd);
        errors = errors + 1;
      end
      // consume buffer: firstbuf = 1, then avail must drop
      bus_write(17'h0830, 64'd1, 8'hFF);
      bus_read(17'h0830, status);
      if (status[15]) begin
        $display("FAIL: avail stuck after consume (%h)", status);
        errors = errors + 1;
      end
    end

    // second frame: non-matching unicast dst must be FILTERED (dropped)
    for (i = 0; i < 6;  i = i + 1) txf[i] = 8'h11;  // not our MAC, not mcast
    for (w = 0; w < (len+7)/8; w = w + 1)
      bus_write(17'h1000 + w*8,
        {txf[w*8+7],txf[w*8+6],txf[w*8+5],txf[w*8+4],txf[w*8+3],txf[w*8+2],txf[w*8+1],txf[w*8+0]},
        8'hFF);
    bus_write(17'h0810, len, 8'hFF);
    // give it time to loop back, then check no new buffer appeared
    repeat (2000) @(negedge msoc_clk);
    bus_read(17'h0830, status);
    if (status[15]) begin
      $display("FAIL: filtered frame was accepted (%h)", status);
      errors = errors + 1;
    end

    // third frame: our unicast MAC (default 23:01:00:89:07:02, reg order MSB first)
    txf[0]=8'h23; txf[1]=8'h01; txf[2]=8'h00; txf[3]=8'h89; txf[4]=8'h07; txf[5]=8'h02;
    for (w = 0; w < (len+7)/8; w = w + 1)
      bus_write(17'h1000 + w*8,
        {txf[w*8+7],txf[w*8+6],txf[w*8+5],txf[w*8+4],txf[w*8+3],txf[w*8+2],txf[w*8+1],txf[w*8+0]},
        8'hFF);
    bus_write(17'h0810, len, 8'hFF);
    tries = 0; status = 0;
    while (!status[15] && tries < 3000) begin
      bus_read(17'h0830, status);
      tries = tries + 1;
    end
    if (!status[15]) begin
      $display("FAIL: unicast-to-us frame not received");
      errors = errors + 1;
    end else begin
      bus_read(17'h0C08, rd);   // length of buffer 1
      if (rd[10:0] !== len) begin
        $display("FAIL: frame2 length %0d != %0d", rd[10:0], len);
        errors = errors + 1;
      end
    end

    if (errors == 0) $display("FRAMING_FIFO OK: loopback+filter+lengths all pass");
    else $display("FRAMING_FIFO FAIL: %0d errors", errors);
    $finish;
  end

  initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
