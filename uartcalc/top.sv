// UART RPN calculator top: 200 MHz LVDS sysclk, USB-UART (tx AU36 / rx AU33).
// Reuses the apb_uart core blocks (8N1, 16x RX / 2x TX clocks) wired exactly as
// uartecho; a tx_sender adapter drives the transmitter from rpn_calc's byte
// stream.  RAM/DSP-free.
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       rst,
    input  wire       rx,
    output wire       tx,
    output wire [3:0] led
);
    wire clk_raw, clk, rst_buf, rx_buf, tx_int;
    wire [3:0] led_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));
    IBUF ibuf_rx  (.I(rx),  .O(rx_buf));

    localparam [15:0] DIVIDER = 16'd109;
    localparam [1:0]  WLS = 2'b11;
    localparam STB=1'b0, PEN=1'b0, EPS=1'b0, SP=1'b0, BC=1'b0;

    wire baudtick16x, baudtick2x, rclk, sin_sync;
    reg  baudoutn;
    wire rxfinished, txfinished, sout;
    wire [7:0] rxdata; wire pe, fe, bi;

    uart_baudgen bg16 (.CLK(clk),.RST(rst_buf),.CE(1'b1),.CLEAR(1'b0),.DIVIDER(DIVIDER),.BAUDTICK(baudtick16x));
    slib_clock_div #(.RATIO(8)) bg2 (.CLK(clk),.RST(rst_buf),.CE(baudtick16x),.Q(baudtick2x));
    always @(posedge clk or posedge rst_buf)
        if (rst_buf) baudoutn <= 1'b1;
        else begin baudoutn <= 1'b0; if (baudtick16x==1'b0) baudoutn <= 1'b1; end
    slib_edge_detect rclk_gen (.CLK(clk),.RST(rst_buf),.D(baudoutn),.RE(rclk),.FE());
    slib_input_sync sin_is (.CLK(clk),.RST(rst_buf),.D(rx_buf),.Q(sin_sync));

    uart_receiver rxu (.CLK(clk),.RST(rst_buf),.RXCLK(rclk),.RXCLEAR(1'b0),
        .WLS(WLS),.STB(STB),.PEN(PEN),.EPS(EPS),.SP(SP),.SIN(sin_sync),
        .PE(pe),.FE(fe),.BI(bi),.DOUT(rxdata),.RXFINISHED(rxfinished));

    // tx_sender: drive the transmitter from a (byte,stb)/rdy stream
    wire [7:0] tx_byte; wire tx_stb, tx_rdy;
    reg  [7:0] tsr; reg txstart; reg [1:0] tst;
    localparam T_IDLE=0, T_START=1, T_RUN=2, T_END=3;
    assign tx_rdy = (tst==T_IDLE);
    always @(posedge clk or posedge rst_buf)
        if (rst_buf) begin tst<=T_IDLE; txstart<=1'b0; tsr<=8'd0; end
        else begin
            txstart<=1'b0;
            case (tst)
              T_IDLE:  if (tx_stb) begin tsr<=tx_byte; tst<=T_START; end
              T_START: begin txstart<=1'b1; tst<=T_RUN; end
              T_RUN:   begin txstart<=1'b1; if (txfinished) tst<=T_END; end
              T_END:   tst<=T_IDLE;
            endcase
        end
    uart_transmitter txu (.CLK(clk),.RST(rst_buf),.TXCLK(baudtick2x),
        .TXSTART(txstart),.CLEAR(1'b0),.WLS(WLS),.STB(STB),.PEN(PEN),.EPS(EPS),.SP(SP),.BC(BC),
        .DIN(tsr),.TXFINISHED(txfinished),.SOUT(sout));

    rpn_calc calc (.clk(clk),.rst(rst_buf),
        .rx_data(rxdata),.rx_valid(rxfinished),
        .tx_byte(tx_byte),.tx_stb(tx_stb),.tx_rdy(tx_rdy),
        .led(led_int));

    assign tx_int = sout;
    OBUF obuf_tx (.I(tx_int), .O(tx));
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
endmodule
