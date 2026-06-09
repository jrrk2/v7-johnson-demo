// uartrxled — RX-ONLY diagnostic.  Receives a byte over UART RX (same apb_uart
// front-end and timing as uartecho) and latches it onto the 8 user LEDs.  No
// transmitter at all.
//
// Purpose: isolate the UART RECEIVER from the transmitter.  The open-flow echo
// corrupts bytes in a data-dependent, baud-independent way; this proves whether
// the corruption is in RX sampling (LEDs show the wrong byte) or in TX (LEDs
// show the correct byte, so the fault must be downstream).
//
//   Type a byte; LED[7:0] = that byte.  e.g. 'A' (0x41) -> LEDs 0100_0001.
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       rst,        // CPU_RESET button, active-high
    input  wire       rx,         // USB-UART host -> FPGA (AU33)
    output wire [7:0] led
);
    wire clk_raw, clk, rst_buf, rx_buf;
    wire [7:0] led_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));
    IBUF ibuf_rx  (.I(rx),  .O(rx_buf));

    localparam [15:0] DIVIDER = 16'd109;   // 200 MHz / (16 * 115200)
    localparam [1:0]  WLS = 2'b11;         // 8 data bits
    localparam        STB = 1'b0, PEN = 1'b0, EPS = 1'b0, SP = 1'b0;

    wire        baudtick16x, rclk, sin_sync, rxfinished;
    reg         baudoutn;
    wire [7:0]  rxdata;
    wire        pe, fe, bi;

    // RX clocking — identical to uartecho (16x oversample via baudoutn edge).
    uart_baudgen bg16 (
        .CLK(clk), .RST(rst_buf), .CE(1'b1), .CLEAR(1'b0),
        .DIVIDER(DIVIDER), .BAUDTICK(baudtick16x));
    always @(posedge clk or posedge rst_buf)
        if (rst_buf) baudoutn <= 1'b1;
        else begin
            baudoutn <= 1'b0;
            if (baudtick16x == 1'b0) baudoutn <= 1'b1;
        end
    slib_edge_detect rclk_gen (
        .CLK(clk), .RST(rst_buf), .D(baudoutn), .RE(rclk), .FE());
    slib_input_sync sin_is (.CLK(clk), .RST(rst_buf), .D(rx_buf), .Q(sin_sync));

    uart_receiver rxu (
        .CLK(clk), .RST(rst_buf), .RXCLK(rclk), .RXCLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP),
        .SIN(sin_sync),
        .PE(pe), .FE(fe), .BI(bi), .DOUT(rxdata), .RXFINISHED(rxfinished));

    // Latch the received byte onto the LEDs.
    reg [7:0] led_reg;
    always @(posedge clk or posedge rst_buf)
        if (rst_buf)         led_reg <= 8'd0;
        else if (rxfinished) led_reg <= rxdata;
    assign led_int = led_reg;

    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
    OBUF obuf4 (.I(led_int[4]), .O(led[4]));
    OBUF obuf5 (.I(led_int[5]), .O(led[5]));
    OBUF obuf6 (.I(led_int[6]), .O(led[6]));
    OBUF obuf7 (.I(led_int[7]), .O(led[7]));
endmodule
