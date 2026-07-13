// VC707 33-bit SYSCLK counter -- minimal CARRY4 reproducer for the open flow.
// IBUFDS(200 MHz SYSCLK) -> BUFG -> 33-bit binary counter.  LEDs show the top
// 8 bits (cnt[32:25]) so they binary-count at a human-visible rate (~6 Hz on
// LED[0]).  A 33-bit counter is a ~9-deep CARRY4 chain -- the smallest design
// that exercises the CARRY4 S/DI feed-through structures that block the open
// (nextpnr) flow for picosoc.
module top (
    input  wire       clk_p, clk_n,
    output wire [7:0] led
);
    wire clk, clk_ibuf;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(clk_ibuf));
    BUFG clk_bufg (.I(clk_ibuf), .O(clk));

    reg [32:0] cnt = 33'd0;
    always @(posedge clk) cnt <= cnt + 33'd1;
    assign led = cnt[32:25];
endmodule
