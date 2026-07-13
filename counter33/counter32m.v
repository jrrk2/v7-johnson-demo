// VC707 32-bit counter clocked by an MMCM-derived 25 MHz (200 MHz * 5 / 40),
// like picosoc.  At 25 MHz the fabric-routed carry chain easily meets timing,
// so the open (nextpnr) flow should count cleanly (vs the 200 MHz-direct
// counter32 which over-clocked the fabric carry chain).  led = cnt[29:22]
// (led[0] ~3 Hz, visible).
module top (
    input  wire       clk_p, clk_n,
    output wire [7:0] led
);
    wire sysclk_ibuf, cnt_clk, cnt_clk_unbuf, clk_fb, mmcm_locked;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"), .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(40.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKIN1_PERIOD(5.000)
    ) cnt_mmcm (
        .CLKFBOUT(clk_fb), .CLKFBOUTB(), .CLKOUT0(cnt_clk_unbuf),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBIN(clk_fb), .CLKIN1(sysclk_ibuf), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .DADDR(7'h0), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0), .DO(), .DRDY(), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .CLKINSTOPPED(), .CLKFBSTOPPED(), .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG cnt_bufg (.I(cnt_clk_unbuf), .O(cnt_clk));

    // Tap the TOP 8 bits so every cnt bit stays live -- if the LED tap stops
    // below cnt[31], opt_design prunes the dead high bits and ties the top
    // CARRY4's S inputs to GND, which the pinned-carry packer turns into a
    // floating GND feed-through LUT HeAP can't place.  cnt[31:24] keeps the
    // full 32-bit carry chain (matches the proven counter32).  At 25 MHz
    // led[0]=cnt[24] ~0.75 Hz -- slow but clearly visible.
    reg [31:0] cnt = 32'd0;
    always @(posedge cnt_clk) cnt <= cnt + 32'd1;
    assign led = cnt[31:24];
endmodule
