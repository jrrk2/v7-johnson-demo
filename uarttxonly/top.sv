// uarttxonly — TX-ONLY diagnostic.  Continuously transmits an incrementing
// 8-bit counter (0,1,2,...,255,0,...) over UART TX, back-to-back, using the
// same apb_uart transmitter and timing as uartecho.  No receiver.
//
// Purpose: isolate the UART TRANSMITTER.  The host reads the serial stream and
// checks it counts cleanly 0..255.  If every value transmits correctly, TX is
// good and the open-flow echo corruption must be in RX sampling; if specific
// byte values come out wrong, the fault is (also) in TX.  Verifiable directly
// over /dev/ttyUSB0 (no LEDs / no host->FPGA path needed).
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       rst,        // CPU_RESET button, active-high
    output wire       tx,         // USB-UART FPGA -> host (AU36)
    output wire [7:0] led
);
    wire clk_raw, clk, rst_buf;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));

    localparam [15:0] DIVIDER = 16'd109;
    localparam [1:0]  WLS = 2'b11;
    localparam        STB = 1'b0, PEN = 1'b0, EPS = 1'b0, SP = 1'b0, BC = 1'b0;

    wire baudtick16x, baudtick2x, txfinished, sout;

    uart_baudgen bg16 (
        .CLK(clk), .RST(rst_buf), .CE(1'b1), .CLEAR(1'b0),
        .DIVIDER(DIVIDER), .BAUDTICK(baudtick16x));
    slib_clock_div #(.RATIO(8)) bg2 (
        .CLK(clk), .RST(rst_buf), .CE(baudtick16x), .Q(baudtick2x));

    // Transmit a free-running byte counter, back to back.  Same TXSTART
    // handshake as uartecho: held high from IDLE through RUN until TXFINISHED.
    reg [7:0] dat;
    reg       txstart;
    reg [1:0] st;
    localparam IDLE = 2'd0, START = 2'd1, RUN = 2'd2, ENDS = 2'd3;

    always @(posedge clk or posedge rst_buf)
        if (rst_buf) begin
            st <= IDLE; txstart <= 1'b0; dat <= 8'd0;
        end else begin
            txstart <= 1'b0;
            case (st)
                IDLE:  begin txstart <= 1'b1; st <= START; end
                START: begin txstart <= 1'b1; st <= RUN; end
                RUN:   begin txstart <= 1'b1;
                            if (txfinished) begin dat <= dat + 8'd1; st <= ENDS; end end
                ENDS:  st <= IDLE;
                default: st <= IDLE;
            endcase
        end

    uart_transmitter txu (
        .CLK(clk), .RST(rst_buf), .TXCLK(baudtick2x),
        .TXSTART(txstart), .CLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP), .BC(BC),
        .DIN(dat),
        .TXFINISHED(txfinished), .SOUT(sout));

    assign tx = sout;

    wire [7:0] led_int = dat;
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
    OBUF obuf4 (.I(led_int[4]), .O(led[4]));
    OBUF obuf5 (.I(led_int[5]), .O(led[5]));
    OBUF obuf6 (.I(led_int[6]), .O(led[6]));
    OBUF obuf7 (.I(led_int[7]), .O(led[7]));
endmodule
