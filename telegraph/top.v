// Wrapper: instantiates IBUFDS + BUFG + IBUF + OBUF primitives around
// the telegraph_core child — same pattern (and same 200 MHz LVDS clock
// path) as the johnson demo's top.v, which the SVS wrapped-inner recipe
// expects: primitive instances at the wrapper, behavioural body in the
// child.
module top (
    input  wire sysclk_p,
    input  wire sysclk_n,
    input  wire rst,            // CPU_RESET button, active-high when pressed
    output wire ser_tx,         // FPGA -> host UART TX (AU36)
    output wire [3:0] led
);
    wire clk_raw, clk, rst_buf, ser_tx_int;
    wire [3:0] led_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));

    // Active-high reset (CPU_RESET button) passed straight through; the
    // child handles the polarity.  The SVS wrapped-inner recipe only
    // accepts plain nets at child pins, not inline expressions.
    telegraph_core core (
        .clk(clk),
        .rst(rst_buf),
        .ser_tx(ser_tx_int),
        .led__0(led_int[0]),
        .led__1(led_int[1]),
        .led__2(led_int[2]),
        .led__3(led_int[3])
    );

    OBUF obuf_tx (.I(ser_tx_int), .O(ser_tx));
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
endmodule
