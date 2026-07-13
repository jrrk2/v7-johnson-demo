// VC707 32-bit SYSCLK counter -- clean CARRY4 case (8 full CARRY4, NO partial
// top carry, so NO const-S unused bits).  Confirms the xml2json placed-JSON flow
// routes end-to-end once the S-routethru + DI-disconnect handling is in place.
module top (
    input  wire       clk_p, clk_n,
    output wire [7:0] led
);
    wire clk, clk_ibuf;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(clk_ibuf));
    BUFG clk_bufg (.I(clk_ibuf), .O(clk));

    reg [31:0] cnt = 32'd0;
    always @(posedge clk) cnt <= cnt + 32'd1;
    assign led = cnt[31:24];
endmodule
