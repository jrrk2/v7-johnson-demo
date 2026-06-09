// uarttxprbs — TX-ONLY demo using a PRBS (LFSR) byte generator instead of an
// arithmetic counter.  The open-flow CARRY4 counter encoding is buggy (the
// arithmetic counter in uarttxonly came out stuck at 0x00), so this uses an
// 8-bit maximal-length LFSR (taps 8,6,5,4 -> period 255) which needs only a
// shift register + XOR feedback (LUTs, NO carry chain).  That sidesteps the
// carry bug and gives a working, host-verifiable open-flow demo: the host
// replicates the same LFSR and checks the received byte stream.
//
//   transmit current lfsr byte, then advance after each frame completes.
//   LFSR: fb = lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3];  lfsr <= {lfsr[6:0], fb};
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

    // 8-bit maximal LFSR (Fibonacci, taps 8,6,5,4).  Pure shift + XOR: no CARRY4.
    localparam [7:0] SEED = 8'hFF;
    reg [7:0] lfsr;
    wire fb = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

    reg       txstart;
    reg [1:0] st;
    localparam IDLE = 2'd0, START = 2'd1, RUN = 2'd2, ENDS = 2'd3;

    always @(posedge clk or posedge rst_buf)
        if (rst_buf) begin
            st <= IDLE; txstart <= 1'b0; lfsr <= SEED;
        end else begin
            txstart <= 1'b0;
            case (st)
                IDLE:  begin txstart <= 1'b1; st <= START; end
                START: begin txstart <= 1'b1; st <= RUN; end
                RUN:   begin txstart <= 1'b1;
                            if (txfinished) begin lfsr <= {lfsr[6:0], fb}; st <= ENDS; end end
                ENDS:  st <= IDLE;
                default: st <= IDLE;
            endcase
        end

    uart_transmitter txu (
        .CLK(clk), .RST(rst_buf), .TXCLK(baudtick2x),
        .TXSTART(txstart), .CLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP), .BC(BC),
        .DIN(lfsr),
        .TXFINISHED(txfinished), .SOUT(sout));

    assign tx = sout;

    wire [7:0] led_int = lfsr;
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
    OBUF obuf4 (.I(led_int[4]), .O(led[4]));
    OBUF obuf5 (.I(led_int[5]), .O(led[5]));
    OBUF obuf6 (.I(led_int[6]), .O(led[6]));
    OBUF obuf7 (.I(led_int[7]), .O(led[7]));
endmodule
