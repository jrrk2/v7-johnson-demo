// Top wrapper for the UART echo demo: IBUFDS+BUFG for the 200 MHz LVDS
// sysclk, IBUF on rst and rx, OBUF on tx and the LEDs.  Same primitive-at-
// -wrapper pattern as johnson/telegraph.
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       rst,        // CPU_RESET button, active-high
    input  wire       rx,         // USB-UART host -> FPGA (AU33)
    output wire       tx,         // USB-UART FPGA -> host (AU36)
    output wire [3:0] led
);
    wire clk_raw, clk, rst_buf, rx_buf, tx_int;
    wire [3:0] led_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));
    IBUF ibuf_rx  (.I(rx),  .O(rx_buf));

    uart_echo core (
        .clk(clk),
        .rst(rst_buf),
        .rx(rx_buf),
        .tx(tx_int),
        .led(led_int)
    );

    OBUF obuf_tx (.I(tx_int), .O(tx));
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
endmodule
