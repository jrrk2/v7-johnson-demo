// uartpll — minimal clock/PLL diagnostic.  Continuously transmits a constant
// byte 'U' (0x55 = 01010101, ideal for baud/clock verification) over UART TX.
//
// Default: sysclk 200 MHz -> PLLE2_ADV -> 100 MHz -> BUFG -> clk.  Purpose: find
// out whether a PLLE2-derived clock works in the open flow (MMCM is dead on HW;
// the DSP calc needs a sub-200 MHz clock, so a working PLL lets us divide sysclk
// down).  Build with -verilog_define NO_PLL to bypass the PLL and clock straight
// from sysclk (baseline sanity that the open flow + this nextpnr still produce a
// live sysclk design at all).
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       user_clock_p,   // Si570 USER_CLOCK (AK34), reprogrammed to 125 MHz
    input  wire       user_clock_n,   // (AL34)
    input  wire       sgmii_clk_p,    // SGMIICLK_Q0 125 MHz MGTREFCLK0_113 (AH8)
    input  wire       sgmii_clk_n,    // (AH7)
    input  wire       rst,        // CPU_RESET button, active-high
    output wire       tx,         // USB-UART FPGA -> host (AU36)
    output wire [7:0] led
);
    wire clk_raw, clk, rst_buf;

`ifdef USE_SGMII
    // Real SGMII 125 MHz reference clock on MGTREFCLK0_113 (AH8/AH7).  GT refclks
    // reach fabric via IBUFDS_GTE2.O -> BUFG (the full 125 MHz; this nextpnr's
    // pack_io supports IBUFDS_GTE2.O straight into a BUFG/BUFH/BUFR).
    wire gt_o;
    IBUFDS_GTE2 #(.CLKCM_CFG("TRUE"), .CLKRCV_TRST("TRUE"), .CLKSWING_CFG(2'b11))
        ibufds_gte (.I(sgmii_clk_p), .IB(sgmii_clk_n), .CEB(1'b0),
                    .O(gt_o), .ODIV2());
    assign clk_raw = gt_o;
`elsif USE_USERCLK
    // Si570 USER_CLOCK reprogrammed to 125 MHz.
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(user_clock_p), .IB(user_clock_n), .O(clk_raw));
`else
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
`endif
    IBUF ibuf_rst (.I(rst), .O(rst_buf));

`ifdef USE_SGMII
    // 125 MHz (SGMII refclk via IBUFDS_GTE2.O) straight to fabric, NO PLL.
    // baud = clk/(DIVIDER*8).  125e6/(136*8) = 114890 ~ 115200.
    BUFG bufg (.I(clk_raw), .O(clk));
    localparam [15:0] DIVIDER = 16'd136;
    wire clk_ready = 1'b1;
`elsif USE_USERCLK
    // Si570 USER_CLOCK straight to fabric, NO PLL.  Chain divides by 16:
    // baud = clk/(DIVIDER*16).  Si570 default = 156.25 MHz (no reprogramming):
    // 156.25e6/(85*16) = 114889 ~ 115200 (standard rate, reads cleanly with stty).
    BUFG bufg (.I(clk_raw), .O(clk));
    localparam [15:0] DIVIDER = 16'd85;
    wire clk_ready = 1'b1;
`elsif NO_PLL
    BUFG bufg (.I(clk_raw), .O(clk));
    localparam [15:0] DIVIDER = 16'd109;        // 200e6/109/16 = 114678 ~ 115200
    wire clk_ready = 1'b1;
`else
    wire clk_pll, pll_fb, pll_locked;
    PLLE2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(5.000),                  // 200 MHz in
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT(4),                      // VCO = 200*4 = 800 MHz
        .CLKOUT0_DIVIDE(8),                     // 800/8 = 100 MHz
        .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .STARTUP_WAIT("FALSE")
    ) pll (
        .CLKIN1(clk_raw), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(pll_fb), .CLKFBOUT(pll_fb),
        .CLKOUT0(clk_pll),
        .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll_locked),
        .RST(rst_buf), .PWRDWN(1'b0),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0), .DO(), .DRDY()
    );
    BUFG bufg (.I(clk_pll), .O(clk));
    localparam [15:0] DIVIDER = 16'd54;         // @100MHz -> baud ~230400
    // Do NOT gate on pll_locked: if the open flow mis-encodes the LOCKED status
    // output (never asserts) but the VCO/CLKOUT is fine, gating would wrongly hold
    // reset.  Run on the PLL clock unconditionally; expose locked on LED[0] instead.
    wire clk_ready = 1'b1;
`endif

    // Hold reset until the clock is ready (PLL locked).
    wire rst_all = rst_buf | ~clk_ready;

    localparam [1:0] WLS = 2'b11;               // 8 data bits
    localparam       STB = 1'b0, PEN = 1'b0, EPS = 1'b0, SP = 1'b0, BC = 1'b0;

    wire baudtick16x, baudtick2x, txfinished, sout;
    uart_baudgen bg16 (.CLK(clk), .RST(rst_all), .CE(1'b1), .CLEAR(1'b0),
        .DIVIDER(DIVIDER), .BAUDTICK(baudtick16x));
    slib_clock_div #(.RATIO(8)) bg2 (.CLK(clk), .RST(rst_all), .CE(baudtick16x), .Q(baudtick2x));

    // Back-to-back transmit of the constant byte 0x55.
    reg       txstart;
    reg [1:0] st;
    localparam IDLE = 2'd0, START = 2'd1, RUN = 2'd2, ENDS = 2'd3;
    always @(posedge clk or posedge rst_all)
        if (rst_all) begin st <= IDLE; txstart <= 1'b0; end
        else begin
            txstart <= 1'b0;
            case (st)
                IDLE:  begin txstart <= 1'b1; st <= START; end
                START: begin txstart <= 1'b1; st <= RUN; end
                RUN:   begin txstart <= 1'b1; if (txfinished) st <= ENDS; end
                ENDS:  st <= IDLE;
                default: st <= IDLE;
            endcase
        end

    uart_transmitter txu (
        .CLK(clk), .RST(rst_all), .TXCLK(baudtick2x),
        .TXSTART(txstart), .CLEAR(1'b0),
        .WLS(WLS), .STB(STB), .PEN(PEN), .EPS(EPS), .SP(SP), .BC(BC),
        .DIN(8'h55),
        .TXFINISHED(txfinished), .SOUT(sout));
    assign tx = sout;

    // LED[0] = clk_ready (PLL locked); LED[7] = slow heartbeat (blinks if clk alive).
    reg [26:0] hb;
    always @(posedge clk or posedge rst_all)
        if (rst_all) hb <= 27'd0; else hb <= hb + 27'd1;
    wire [7:0] led_int = {hb[26], 6'b0, clk_ready};
    OBUF o0(.I(led_int[0]),.O(led[0])); OBUF o1(.I(led_int[1]),.O(led[1]));
    OBUF o2(.I(led_int[2]),.O(led[2])); OBUF o3(.I(led_int[3]),.O(led[3]));
    OBUF o4(.I(led_int[4]),.O(led[4])); OBUF o5(.I(led_int[5]),.O(led[5]));
    OBUF o6(.I(led_int[6]),.O(led[6])); OBUF o7(.I(led_int[7]),.O(led[7]));
endmodule
