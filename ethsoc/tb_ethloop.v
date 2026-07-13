`timescale 1ns/1ps
`default_nettype none
module tb;
  reg clk=0, rst=1, uart_rx=1;
  wire uart_tx; wire [7:0] led;
  wire sgmii_txp, sgmii_txn, eth_rst_n, eth_mdc, eth_mdio;

  always #2.5 clk = ~clk;         // 200 MHz sysclk -> MMCM -> 50 MHz cpu_clk

  top dut(.clk_p(clk),.clk_n(~clk),.rst(rst),.uart_tx(uart_tx),.uart_rx(uart_rx),
     .led(led),.sgmii_rxp(1'b0),.sgmii_rxn(1'b1),.sgmii_txp(sgmii_txp),
     .sgmii_txn(sgmii_txn),.sgmii_refclk_p(1'b0),.sgmii_refclk_n(1'b1),
     .eth_rst_n(eth_rst_n),.eth_mdio(eth_mdio),.eth_mdc(eth_mdc));

  localparam real BITNS = 434.0*20.0;   // 8680 ns per UART bit

  // ---- UART TX capture (decode dut.uart_tx serial into cap[]) ----
  reg [7:0] cap [0:255]; integer ncap=0; integer k; reg [7:0] cb;
  initial forever begin
    @(negedge uart_tx);
    #(BITNS*1.5);
    for (k=0;k<8;k=k+1) begin cb[k]=uart_tx; #(BITNS); end
    cap[ncap]=cb; ncap=ncap+1;
  end

  // ---- UART RX driver (send a byte to dut.uart_rx) ----
  task uart_send(input [7:0] b); integer i; begin
    uart_rx=0; #(BITNS);
    for (i=0;i<8;i=i+1) begin uart_rx=b[i]; #(BITNS); end
    uart_rx=1; #(BITNS);
  end endtask

  // trace received UART bytes (TX-load path)
  always @(posedge dut.cpu_clk)
    if (dut.u_rx.stb) $display("  [urx rx=%02x(%c)]", dut.u_rx.data, dut.u_rx.data);

  integer i, base, errs=0;
  reg [8*16-1:0] got;
  initial begin
    // reset: hold long enough for POR counter (needs LOCKED + 64 cycles)
    repeat(200) @(posedge clk);
    rst=0;
    // wait for eth_init to complete
    wait(dut.rxd_inited); repeat(20) @(posedge clk);
    $display("--- init done (led=%b) ---", led);

    // ================= Phase A: RX -> UART hex dump =================
    base = 0*2048;
    dut.eth.rx_mem[base+0]=8'hDE; dut.eth.rx_mem[base+1]=8'hAD;
    dut.eth.rx_mem[base+2]=8'hBE; dut.eth.rx_mem[base+3]=8'hEF;
    ncap=0;
    dut.eth.inject_rx(5'd0, 8);       // len incl 4-byte FCS -> payload 4
    // wait for 10 chars: "DEADBEEF\r\n"
    for (i=0;i<60000 && ncap<10;i=i+1) @(posedge dut.cpu_clk);
    $write("Phase A UART dump: \"");
    for (i=0;i<ncap;i=i+1)
      if (cap[i]==8'h0D) $write("\\r"); else if (cap[i]==8'h0A) $write("\\n");
      else $write("%c", cap[i]);
    $display("\"  (%0d chars)", ncap);
    if (ncap>=10 && cap[0]=="D"&&cap[1]=="E"&&cap[2]=="A"&&cap[3]=="D"&&
        cap[4]=="B"&&cap[5]=="E"&&cap[6]=="E"&&cap[7]=="F"&&
        cap[8]==8'h0D&&cap[9]==8'h0A)
      $display("Phase A PASS: dump = DEADBEEF CRLF");
    else begin $display("Phase A FAIL"); errs=errs+1; end
    repeat(1000) @(posedge dut.cpu_clk);  // let S_ACK RSR write complete
    // firstbuf should have advanced (ack), avail cleared
    if (dut.eth.firstbuf==5'd1) $display("Phase A ack OK (firstbuf=1)");
    else begin $display("Phase A ack FAIL firstbuf=%0d",dut.eth.firstbuf); errs=errs+1; end

    // ================= Phase B: UART hex -> eth TX =================
    // send "010203040506\n"  -> 6 bytes, padded to 60, TPLR trigger
    uart_send("0"); uart_send("1");
    uart_send("0"); uart_send("2");
    uart_send("0"); uart_send("3");
    uart_send("0"); uart_send("4");
    uart_send("0"); uart_send("5");
    uart_send("0"); uart_send("6");
    uart_send(8'h0A);                  // LF terminator
    // allow padding + trigger
    repeat(4000) @(posedge clk);
    $display("Phase B: tx_mem[0..7]=%02x %02x %02x %02x %02x %02x %02x %02x  twords=%0d len=%0d",
      dut.eth.tx_mem[0],dut.eth.tx_mem[1],dut.eth.tx_mem[2],dut.eth.tx_mem[3],
      dut.eth.tx_mem[4],dut.eth.tx_mem[5],dut.eth.tx_mem[6],dut.eth.tx_mem[7],
      dut.eth.twords, dut.eth.tx_packet_length);
    if (dut.eth.tx_mem[0]==8'h01&&dut.eth.tx_mem[1]==8'h02&&dut.eth.tx_mem[2]==8'h03&&
        dut.eth.tx_mem[3]==8'h04&&dut.eth.tx_mem[4]==8'h05&&dut.eth.tx_mem[5]==8'h06&&
        dut.eth.twords==1 && dut.eth.tx_packet_length==60)
      $display("Phase B PASS: 6 bytes loaded, padded to 60, triggered");
    else begin $display("Phase B FAIL"); errs=errs+1; end

    $display("=== %s (errs=%0d) ===", errs==0?"ALL PASS":"FAIL", errs);
    $finish;
  end

  initial begin #60_000_000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
