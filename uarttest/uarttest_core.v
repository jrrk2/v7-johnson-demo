// Minimal output-path smoke test: a free-running counter drives ser_tx (a
// ~97 kHz square wave on AU36) and the LEDs (slow, visible).  No FSM, no
// prescaler.  If the LEDs count AND the UART line toggles, the AU36 output
// path works in the open flow and the telegraph FSM is the remaining issue.
module uarttest_core (
    input  wire clk,
    input  wire rst,
    output wire ser_tx,
    output wire led__0, led__1, led__2, led__3
);
  reg [31:0] cnt = 32'h0;
  always @(posedge clk)
    if (rst) cnt <= 32'h0;
    else     cnt <= cnt + 32'h1;
  assign ser_tx = cnt[10];   // ~97 kHz square wave on AU36
  assign led__0 = cnt[27];
  assign led__1 = cnt[26];
  assign led__2 = cnt[25];
  assign led__3 = cnt[24];
endmodule
