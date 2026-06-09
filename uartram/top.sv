// uartram — pocket-calculator Turing machine over UART, using the FULL apb_uart
// (16550) driven through its APB register interface.  The apb_uart's internal
// TX/RX FIFOs and tested THR/RBR/LSR handshaking replace the hand-rolled
// transmitter handshake (which had a back-to-back re-arm race).  A small APB
// master initialises the UART (115200 8N1) then bridges calc_core's byte stream:
// read RBR on LSR.DR -> input FIFO -> core; core -> output FIFO -> write THR on
// LSR.THRE.  calc_core/ISA unchanged; program/data live in a RAMB18.
// BAUDDIV = clk/(16*115200).  200MHz Si5324 sysclk -> 109 (default).  To run
// off the Si570 USER_CLOCK (USER_CLOCK_P/N) instead, build with the user-clock
// XDC (top_userclk.xdc) and override BAUDDIV: 156.25MHz default -> 85, or if the
// Si570 is reprogrammed to 125MHz -> 68 (eases open-flow timing).
`ifndef BAUDDIV
 `define BAUDDIV 109
`endif
module top (
    input  wire       sysclk_p,       // Si5324 200 MHz  (default clock source)
    input  wire       sysclk_n,
    input  wire       user_clock_p,   // Si570 USER_CLOCK (used when USE_USERCLK is defined)
    input  wire       user_clock_n,
    input  wire       rst,        // CPU_RESET button, active-high
    input  wire       rx,
    output wire       tx,
    output wire [7:0] led
);
    wire clk_raw, clk, rst_buf, rx_buf;
`ifdef USE_USERCLK
    // Si570 programmable USER_CLOCK (build with -verilog_define USE_USERCLK and a
    // matching BAUDDIV; 156.25MHz default -> 85).  sysclk_p/n then go unused.
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(user_clock_p), .IB(user_clock_n), .O(clk_raw));
`else
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        ibufds (.I(sysclk_p), .IB(sysclk_n), .O(clk_raw));
`endif
`ifdef USE_MMCM
    // MMCME2_ADV: clk_raw (assume 200MHz sysclk) -> VCO 1000MHz -> 125MHz core
    // clock.  Pair with -verilog_define BAUDDIV=68.  (Also a DUT for open-flow
    // MMCM support.)  Direct feedback + ZHOLD = clocking-wizard "internal fb".
    wire clk_mmcm, clkfb_o, clkfb_i, mmcm_locked;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"), .STARTUP_WAIT("FALSE"),
        .CLKIN1_PERIOD(5.000), .REF_JITTER1(0.010), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(8.000), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(0.000)
    ) mmcm (
        .CLKIN1(clk_raw), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(clkfb_i), .CLKFBOUT(clkfb_o), .CLKFBOUTB(),
        .CLKOUT0(clk_mmcm), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0), .DO(), .DRDY(),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .LOCKED(mmcm_locked), .CLKINSTOPPED(), .CLKFBSTOPPED(),
        .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG fbbufg (.I(clkfb_o), .O(clkfb_i));   // ZHOLD feedback through a BUFG
    BUFG bufg   (.I(clk_mmcm), .O(clk));
`else
    wire mmcm_locked = 1'b1;
    BUFG bufg (.I(clk_raw), .O(clk));
`endif
    IBUF ibuf_rst (.I(rst), .O(rst_buf));
    IBUF ibuf_rx  (.I(rx),  .O(rx_buf));

    // --- HW 5-sample majority (top-hat) filter on async rx --- CARRY-FREE:
    // majority of 5 bits is a 5-input boolean (one LUT6), no adder/carry chain.
    reg [4:0] rx_sh = 5'b11111;          // power up idle-high
    reg       rx_filt = 1'b1;
    wire fa=rx_sh[0], fb5=rx_sh[1], fc=rx_sh[2], fd=rx_sh[3], fe=rx_sh[4];
    wire maj5 = (fa&fb5&fc)|(fa&fb5&fd)|(fa&fb5&fe)|(fa&fc&fd)|(fa&fc&fe)|
                (fa&fd&fe)|(fb5&fc&fd)|(fb5&fc&fe)|(fb5&fd&fe)|(fc&fd&fe);
    always @(posedge clk) begin
        rx_sh   <= {rx_sh[3:0], rx_buf};
        rx_filt <= maj5;
    end

    // Power-on reset: CARRY-FREE shift register (fills with 1s over 16 clocks),
    // holding reset until por_sr[15] sets.  No down-counter / carry chain.
    reg [15:0] por_sr = 16'd0;
    always @(posedge clk) por_sr <= {por_sr[14:0], 1'b1};
    wire rst_all = rst_buf | ~por_sr[15] | ~mmcm_locked;

    // calc_core, SOFTWARE-UART mode.  apb_uart + byte FIFOs REMOVED (were bypassed):
    // rx = filtered pin level (bit0), always-valid; tx bit-banged via OP_OUTT;
    // tx_rdy tied high.  This also eliminates all of the apb_uart/FIFO CARRY4s.
    wire [7:0] led_int, core_tx;
    wire       core_txbit, core_rx_rd, core_tx_stb;
    calc_core #(.AUTOSTART(1'b1)) core (
        .clk(clk), .rst(rst_all),
        .rx_data({7'b0, rx_filt}), .rx_valid(1'b1), .rx_rd(core_rx_rd),
        .tx_byte(core_tx), .tx_stb(core_tx_stb), .tx_rdy(1'b1),
        .led(led_int), .tx_pin(core_txbit));


    // tx bit-banged by the CPU (OP_OUTT).  HW 5-sample majority (top-hat) filter
    // on the tx line too, to suppress glitches the open-flow routing may add on the
    // long FF->OBUF path (CARRY-FREE 5-input boolean, one LUT6).  tx changes only
    // at the bit rate so the ~5-clock filter delay is negligible.
    reg [4:0] tx_sh = 5'b11111;
    reg       tx_filt = 1'b1;
    wire ta=tx_sh[0], tb5=tx_sh[1], tc=tx_sh[2], td=tx_sh[3], te=tx_sh[4];
    wire tmaj5 = (ta&tb5&tc)|(ta&tb5&td)|(ta&tb5&te)|(ta&tc&td)|(ta&tc&te)|
                 (ta&td&te)|(tb5&tc&td)|(tb5&tc&te)|(tb5&td&te)|(tc&td&te);
    always @(posedge clk) begin
        tx_sh   <= {tx_sh[3:0], core_txbit};
        tx_filt <= tmaj5;
    end
    OBUF obuf_tx (.I(tx_filt), .O(tx));

    // LEDs show calc_core's LED register (led_int), now written explicitly by the
    // OUTL instruction (software-controlled), not the live accumulator.
    OBUF o0 (.I(led_int[0]), .O(led[0]));  OBUF o1 (.I(led_int[1]), .O(led[1]));
    OBUF o2 (.I(led_int[2]), .O(led[2]));  OBUF o3 (.I(led_int[3]), .O(led[3]));
    OBUF o4 (.I(led_int[4]), .O(led[4]));  OBUF o5 (.I(led_int[5]), .O(led[5]));
    OBUF o6 (.I(led_int[6]), .O(led[6]));  OBUF o7 (.I(led_int[7]), .O(led[7]));
endmodule
