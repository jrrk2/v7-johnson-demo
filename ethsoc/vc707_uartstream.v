// Self-reporting open-flow diagnostic: continuously transmit '@'+rxcnt[3:0]
// (~12 chars/s).  A single host serial read tests TX (bytes arrive) and RX
// (payload advances when the host sends bytes) with no eyes on the board.
// Clocking identical to vc707_uartecho.  Reuses uart_tx/uart_rx from
// vc707_ethloop.v (synth -top uartstream, read both files).
`default_nettype none
module uartstream (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led
);
    wire sysclk_ibuf, sysclk, cpu_clk;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    BUFG sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));
    wire mmcm_fb, mmcm_clkout0, mmcm_locked;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"),
        .CLKIN1_PERIOD(5.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(20.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5)
    ) cpu_mmcm (
        .CLKIN1(sysclk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb), .CLKOUT0(mmcm_clkout0),
        .RST(rst), .PWRDWN(1'b0), .LOCKED(mmcm_locked),
        .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0));
    BUFG cpu_bufg (.I(mmcm_clkout0), .O(cpu_clk));

    reg [5:0] rcnt = 0; wire resetn = &rcnt;
    always @(posedge cpu_clk) if (rst||!mmcm_locked) rcnt<=0; else rcnt<=rcnt+!resetn;
    wire rst_sync = !resetn;

    wire [7:0] urx_data; wire urx_stb, utx_busy;
    reg  [7:0] txb; reg utx_stb;
    uart_rx #(.DIV(434)) u_rx (.clk(cpu_clk),.rst(rst_sync),.rx(uart_rx),.data(urx_data),.stb(urx_stb));
    uart_tx #(.DIV(434)) u_tx (.clk(cpu_clk),.rst(rst_sync),.data(txb),.stb(utx_stb),.tx(uart_tx),.busy(utx_busy));

    reg [23:0] rxcnt;
    reg [21:0] tick;                        // 2^22/50MHz ~ 84ms period
    always @(posedge cpu_clk) begin
        utx_stb <= 1'b0;
        if (rst_sync) begin rxcnt<=0; tick<=0; end
        else begin
            if (urx_stb) rxcnt<=rxcnt+1;
            tick<=tick+1;
            if (tick==0 && !utx_busy) begin
                txb <= 8'h40 | {4'b0,rxcnt[3:0]};   // '@'..'O'
                utx_stb <= 1'b1;
            end
        end
    end
    reg [24:0] hbeat; always @(posedge cpu_clk) hbeat<=hbeat+1;
    assign led = {mmcm_locked, resetn, hbeat[24], rxcnt[4:0]};
endmodule
`default_nettype wire
