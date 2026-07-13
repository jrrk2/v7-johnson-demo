// Specimen v3: GTXE2_CHANNEL (X1Y1, quad 113) TXOUTCLK/RXOUTCLK -> BUFG.
// Unconfigured channel - we only need the ROUTE for segbit solving.
module top (
    input  wire refclk_p, refclk_n,
    output wire led
);
    wire refclk;
    IBUFDS_GTE2 ib (.I(refclk_p), .IB(refclk_n), .CEB(1'b0), .O(refclk), .ODIV2());
    wire txoutclk, rxoutclk, clk;
    (* DONT_TOUCH = "TRUE", LOC = "GTXE2_CHANNEL_X1Y1" *)
    GTXE2_CHANNEL gt (
        .GTREFCLK0(refclk),
        .CPLLREFCLKSEL(3'b001),
        .TXOUTCLK(txoutclk),
        .RXOUTCLK(rxoutclk)
    );
`ifdef USE_RX
    BUFG bg (.I(rxoutclk), .O(clk));
`else
    BUFG bg (.I(txoutclk), .O(clk));
`endif
    reg [24:0] cnt = 0;
    always @(posedge clk) cnt <= cnt + 1;
    assign led = cnt[24];
endmodule
