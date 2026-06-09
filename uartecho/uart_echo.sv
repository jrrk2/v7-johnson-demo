// uart_echo — bidirectional UART demo.  Receives a byte over RX, toggles the
// ASCII case bit (bit 5, 0x20: 'A'<->'a'), and transmits it back over TX.
//
// Built from the pulp-platform/apb_uart core blocks (uart_baudgen,
// uart_receiver, uart_transmitter + slib_* helpers), wired exactly as the
// full apb_uart does — 16x oversampled RX clock, 2x TX clock, 8N1 — but
// without the APB register file / FIFOs.  One byte in flight at a time, which
// is fine for interactive use (the echo of a char finishes long before the
// next typed char arrives).
//
//   200 MHz sysclk; DIVIDER = 200e6 / (16 * 115200) ~= 109  -> ~114.7 kBaud
//   (within UART's ~2-3% tolerance of 115200).
module uart_echo (
    input  wire       clk,
    input  wire       rst,        // active-high (CPU_RESET button)
    input  wire       rx,         // serial in  (host -> FPGA, AU33)
    output wire       tx,         // serial out (FPGA -> host, AU36)
    output wire [3:0] led
);
    localparam [15:0] DIVIDER = 16'd109;   // 200 MHz / (16 * 115200)
    localparam [1:0]  WLS = 2'b11;         // 8 data bits
    localparam        STB = 1'b0;          // 1 stop bit
    localparam        PEN = 1'b0, EPS = 1'b0, SP = 1'b0;  // no parity
    localparam        BC  = 1'b0;          // no break

    wire        baudtick16x, baudtick2x, rclk, sin_sync;
    reg         baudoutn;
    wire        rxfinished, txfinished, sout;
    wire [7:0]  rxdata;
    wire        pe, fe, bi;

    // ── clocking (mirrors apb_uart) ──────────────────────────────────────
    uart_baudgen bg16 (
        .CLK(clk), .RST(rst), .CE(1'b1), .CLEAR(1'b0),
        .DIVIDER(DIVIDER), .BAUDTICK(baudtick16x));

    // TX clock = 16x / 8 = 2x baud
    slib_clock_div #(.RATIO(8)) bg2 (
        .CLK(clk), .RST(rst), .CE(baudtick16x), .Q(baudtick2x));

    // BAUDOUTN is low for one cycle per 16x tick; its rising edge is the RX
    // 16x sampling clock (same construction as apb_uart).
    always @(posedge clk or posedge rst)
        if (rst) baudoutn <= 1'b1;
        else begin
            baudoutn <= 1'b0;
            if (baudtick16x == 1'b0) baudoutn <= 1'b1;
        end
    slib_edge_detect rclk_gen (
        .CLK(clk), .RST(rst), .D(baudoutn), .RE(rclk), .FE());

    // synchronise the async serial input
    slib_input_sync sin_is (.CLK(clk), .RST(rst), .D(rx), .Q(sin_sync));

    // ── receiver ─────────────────────────────────────────────────────────
    uart_receiver rxu (
        .CLK(clk), .RST(rst), .RXCLK(rclk), .RXCLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP),
        .SIN(sin_sync),
        .PE(pe), .FE(fe), .BI(bi), .DOUT(rxdata), .RXFINISHED(rxfinished));

    // ── echo FSM: capture a byte, toggle case bit, drive the transmitter ──
    // No-FIFO version (no RAM): one byte in flight at a time.  Fine for
    // interactive typing; a streamed burst faster than the echo round-trip
    // can drop bytes.  Kept RAM-free so it maps to LUTs/FFs only — the open
    // flow has not yet been validated with block/distributed RAM.
    reg [7:0] hold;
    reg       pending;
    reg [7:0] tsr;
    reg       txstart;
    reg [1:0] st;
    reg [3:0] rxcount;
    localparam IDLE = 2'd0, START = 2'd1, RUN = 2'd2, ENDS = 2'd3;

    always @(posedge clk or posedge rst)
        if (rst) begin
            hold <= 8'd0; pending <= 1'b0; rxcount <= 4'd0;
        end else begin
            if (rxfinished) begin
                hold    <= rxdata ^ 8'h20;   // toggle ASCII upper/lower case
                pending <= 1'b1;
                rxcount <= rxcount + 4'd1;
            end else if (st == ENDS) begin
                pending <= 1'b0;
            end
        end

    // TX start handshake, copied from apb_uart's TX state machine: TXSTART is
    // held high from IDLE through RUN until the transmitter reports FINISHED.
    always @(posedge clk or posedge rst)
        if (rst) begin
            st <= IDLE; tsr <= 8'd0; txstart <= 1'b0;
        end else begin
            txstart <= 1'b0;
            case (st)
                IDLE:  if (pending) begin txstart <= 1'b1; st <= START; end
                START: begin tsr <= hold; txstart <= 1'b1; st <= RUN; end
                RUN:   begin txstart <= 1'b1; if (txfinished) st <= ENDS; end
                ENDS:  st <= IDLE;
                default: st <= IDLE;
            endcase
        end

    uart_transmitter txu (
        .CLK(clk), .RST(rst), .TXCLK(baudtick2x),
        .TXSTART(txstart), .CLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP), .BC(BC),
        .DIN(tsr),
        .TXFINISHED(txfinished), .SOUT(sout));

    assign tx  = sout;
    assign led = rxcount;   // visible: increments once per received character
endmodule
