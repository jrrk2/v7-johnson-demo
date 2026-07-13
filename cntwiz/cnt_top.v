// Minimal clock bisect: Clocking-Wizard MMCM (diff 200 MHz in, 50 MHz out)
// + free-running counter on LEDs.  led[7] = MMCM LOCKED, led[6:0] =
// counter taps (block of different blink rates).
module cnt_top (
    input  wire clk_p,
    input  wire clk_n,
    input  wire rst,
    output wire [7:0] led
);
    wire clk50, locked;
    clk_wiz_0 wiz (
        .clk_in1_p(clk_p), .clk_in1_n(clk_n),
        .reset(rst), .locked(locked), .clk_out1(clk50)
    );
    reg [25:0] cnt = 26'd0;
    always @(posedge clk50) cnt <= cnt + 1'b1;
    assign led = {locked, cnt[25:19]};
endmodule
