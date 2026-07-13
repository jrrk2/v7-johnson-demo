// Johnson demo, MMCM variant.  IDENTICAL to ../johnson/top.v except an
// MMCME2_ADV (200 MHz -> 25 MHz, /8) sits between the IBUFDS and the BUFG
// that clocks counter25_core.  The 28-bit PRBS core is reused unchanged, so
// the ONLY difference from the proven 1-LED-per-~1.3 s Johnson is the MMCM.
//
// Diagnostic intent: this goes through the PROVEN stock-yosys -> nextpnr
// flow (nextpnr places the MMCM and emits its FASM), unlike counter32m which
// went through xml2json's placed JSON.  If the LED walk slows ~8x (one step
// per ~10 s) the MMCM divides correctly here -> the counter32m blur is an
// xml2json problem.  If it still blurs at the ~1 Hz Johnson rate, the gap is
// in nextpnr's MMCM placement/FASM or prjxray's MMCM segbits.
module top (
    input  wire sysclk_p,
    input  wire sysclk_n,
    input  wire rst,
    output wire [7:0] led
);
    wire clk_raw, cnt_clk, cnt_clk_unbuf, clk_fb, mmcm_locked, rst_buf;
    wire [7:0] led_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));

    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"), .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(40.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKIN1_PERIOD(5.000)
    ) mmcm (
        .CLKFBOUT(clk_fb), .CLKFBOUTB(), .CLKOUT0(cnt_clk_unbuf),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBIN(clk_fb), .CLKIN1(clk_raw), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .DADDR(7'h0), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0), .DO(), .DRDY(), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .CLKINSTOPPED(), .CLKFBSTOPPED(), .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(1'b0));

    BUFG bufg (.I(cnt_clk_unbuf), .O(cnt_clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));

    counter25_core core (.clk(cnt_clk), .rst(rst_buf), .led(led_int));

    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
    OBUF obuf4 (.I(led_int[4]), .O(led[4]));
    OBUF obuf5 (.I(led_int[5]), .O(led[5]));
    OBUF obuf6 (.I(led_int[6]), .O(led[6]));
    OBUF obuf7 (.I(led_int[7]), .O(led[7]));
endmodule
