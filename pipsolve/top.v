// Minimal specimen: sysclk -> MMCM (left CMT) -> BUFG -> FF -> LED.
// The CLKOUT0->BUFG net gets FIXED_ROUTE'd through one target
// HCLK_CMT_L CK_IN<n> <- MUX_CLK_<m> pip by solve.tcl.
module top (
    input  wire clk_p, clk_n,
    output wire led
);
    wire clkin, clk0, cpu_clk;
    IBUFDS ib (.I(clk_p), .IB(clk_n), .O(clkin));
    wire fb;
    MMCME2_ADV #(
        .CLKIN1_PERIOD(5.0), .CLKFBOUT_MULT_F(5.0),
        .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(20.0)
    ) mmcm (
        .CLKIN1(clkin), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(fb), .CLKFBOUT(fb), .CLKOUT0(clk0),
        .RST(1'b0), .PWRDWN(1'b0),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG bg (.I(clk0), .O(cpu_clk));
    reg [24:0] cnt = 0;
    always @(posedge cpu_clk) cnt <= cnt + 1;
    assign led = cnt[24];
endmodule
