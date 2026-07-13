// Specimen v2: GT refclk (IBUFDS_GTE2, quad 113) -> BUFG -> FF -> LED.
// The refclk->BUFG net is FIXED_ROUTE'd through one target
// HCLK_CMT_L CK_IN<n> <- MUX_CLK_<m> (= MGT clock spine) pip by solve2.tcl.
module top (
    input  wire refclk_p, refclk_n,
    output wire led
);
    wire refclk, clk;
    IBUFDS_GTE2 ib (.I(refclk_p), .IB(refclk_n), .CEB(1'b0), .O(refclk), .ODIV2());
    BUFG bg (.I(refclk), .O(clk));
    reg [24:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign led = cnt[24];
endmodule
