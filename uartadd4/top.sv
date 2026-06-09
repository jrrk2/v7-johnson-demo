// uartadd4 — UART as carry-free plumbing around an ADD4 device-under-test.
//
//   UART-RX byte  ==>  [ ADD4 DUT: out = in + 4 ]  ==>  UART-TX byte
//
// The receiver (uart_rx_lfsr) uses LFSR/shift timing only -> no CARRY4, so the
// UART link is reliable in the open flow (the stock arithmetic-counter receiver
// is corrupted by the open-flow CARRY4 encoding bug).  The ONLY intentional
// carry in the design is the ADD4 adder, which is therefore the isolated DUT:
// the host sends a byte (adder input), the FPGA returns byte+4 (adder output),
// directly exercising the open-flow CARRY4 encoding through a trustworthy link.
//
// 200 MHz sysclk; 115200 8N1 (DIVIDER = 200e6/(16*115200) ~= 109).
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       rst,        // CPU_RESET button, active-high
    input  wire       rx,         // USB-UART host -> FPGA (AU33)
    output wire       tx,         // USB-UART FPGA -> host (AU36)
    output wire [7:0] led
);
    wire clk_raw, clk, rst_buf, rx_buf, tx_int;

    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
    BUFG bufg (.I(clk_raw), .O(clk));
    IBUF ibuf_rst (.I(rst), .O(rst_buf));
    IBUF ibuf_rx  (.I(rx),  .O(rx_buf));

    localparam [15:0] DIVIDER = 16'd109;
    localparam [1:0]  WLS = 2'b11;            // 8 data bits
    localparam        STB=1'b0, PEN=1'b0, EPS=1'b0, SP=1'b0, BC=1'b0;

    // ── clocking: LFSR (PRBS) dividers, fully carry-free ────────────────────
    // baudtick16x = 16x baud = clk/109 (7-bit LFSR);  baudtick2x = /8 of that.
    // Replaces the arithmetic uart_baudgen / slib_clock_div so NO divider uses a
    // CARRY4 -- the open-flow CARRY4 counter bug can't corrupt the baud rate.
    wire baudtick16x, baudtick2x;
    lfsr_div #(.W(7), .TAPS(7'h60), .SEED(7'h7F), .TERMINAL(7'h77)) bg16 (
        .clk(clk), .rst(rst_buf), .ce(1'b1), .tick(baudtick16x));
    lfsr_div #(.W(4), .TAPS(4'hC), .SEED(4'hF), .TERMINAL(4'h9)) bg2 (
        .clk(clk), .rst(rst_buf), .ce(baudtick16x), .tick(baudtick2x));

    // ── receiver: LFSR-timed, carry-free (baudtick16x = 16x sample enable) ──
    wire        sin_sync, rxdone;
    wire [7:0]  rxbyte;
    slib_input_sync sin_is (.CLK(clk), .RST(rst_buf), .D(rx_buf), .Q(sin_sync));
    uart_rx_lfsr rxu (
        .clk(clk), .rst(rst_buf), .rxtick(baudtick16x), .sin(sin_sync),
        .dout(rxbyte), .rxdone(rxdone));

    // ── device-under-test: running sum = current byte + previous byte ──
    //    an 8-bit + 8-bit adder -> a real CARRY4 (the only intentional carry).
    reg [7:0] hold;
    reg [7:0] prev;
    reg       pending;
    reg [1:0] st;
    reg [7:0] tsr;
    reg       txstart;
    wire      txfinished, sout;
    localparam IDLE=2'd0, START=2'd1, RUN=2'd2, ENDS=2'd3;

    always @(posedge clk or posedge rst_buf)
        if (rst_buf) begin hold<=8'd0; prev<=8'd0; pending<=1'b0; end
        else begin
            if (rxdone) begin
                // <<< DUT: running sum, current byte + previous byte (8-bit
                //     CARRY4 adder); output low 8 bits (mod 256) >>>
                hold    <= rxbyte + prev;
                prev    <= rxbyte;
                pending <= 1'b1;
            end else if (st==ENDS) pending <= 1'b0;
        end

    // ── transmitter (proven carry-OK in the open flow by the PRBS demo) ─────
    always @(posedge clk or posedge rst_buf)
        if (rst_buf) begin st<=IDLE; tsr<=8'd0; txstart<=1'b0; end
        else begin
            txstart <= 1'b0;
            case (st)
                IDLE:  if (pending) begin txstart<=1'b1; st<=START; end
                START: begin tsr<=hold; txstart<=1'b1; st<=RUN; end
                RUN:   begin txstart<=1'b1; if (txfinished) st<=ENDS; end
                ENDS:  st<=IDLE;
                default: st<=IDLE;
            endcase
        end

    uart_transmitter txu (
        .CLK(clk), .RST(rst_buf), .TXCLK(baudtick2x),
        .TXSTART(txstart), .CLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP), .BC(BC),
        .DIN(tsr), .TXFINISHED(txfinished), .SOUT(sout));

    assign tx_int = sout;
    OBUF obuf_tx (.I(tx_int), .O(tx));

    wire [7:0] led_int = hold;          // last adder output
    OBUF obuf0 (.I(led_int[0]), .O(led[0]));
    OBUF obuf1 (.I(led_int[1]), .O(led[1]));
    OBUF obuf2 (.I(led_int[2]), .O(led[2]));
    OBUF obuf3 (.I(led_int[3]), .O(led[3]));
    OBUF obuf4 (.I(led_int[4]), .O(led[4]));
    OBUF obuf5 (.I(led_int[5]), .O(led[5]));
    OBUF obuf6 (.I(led_int[6]), .O(led[6]));
    OBUF obuf7 (.I(led_int[7]), .O(led[7]));
endmodule
