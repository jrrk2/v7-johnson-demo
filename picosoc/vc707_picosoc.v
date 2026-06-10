// VC707 PicoSoC — no MMCM variant.  IBUFDS → BUFG → /2 divider → BUFG →
// 100 MHz cpu_clk.  picorv32 places at ~120-150 MHz on the open flow, so the
// raw 200 MHz sysclk is divided by two in fabric instead of using an MMCM.
module top (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led
);
    wire sysclk_ibuf, sysclk, cpu_clk;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    BUFG sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));

    reg clkdiv2 = 1'b0;
    always @(posedge sysclk) clkdiv2 <= ~clkdiv2;
    BUFG cpu_bufg (.I(clkdiv2), .O(cpu_clk));

    reg [5:0] resetn_cnt = 0;
    wire resetn = &resetn_cnt;
    always @(posedge cpu_clk)
        if (rst) resetn_cnt <= 0;
        else     resetn_cnt <= resetn_cnt + !resetn;

    wire iomem_valid;
    reg  iomem_ready;
    wire [3:0]  iomem_wstrb;
    wire [31:0] iomem_addr, iomem_wdata;
    reg  [31:0] iomem_rdata;
    reg  [31:0] gpio;
    assign led = gpio[7:0];

    always @(posedge cpu_clk) begin
        if (!resetn) begin gpio <= 0; iomem_ready <= 0; end
        else begin
            iomem_ready <= 0;
            if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h03) begin
                iomem_ready <= 1;
                iomem_rdata <= gpio;
                if (iomem_wstrb[0]) gpio[ 7: 0] <= iomem_wdata[ 7: 0];
                if (iomem_wstrb[1]) gpio[15: 8] <= iomem_wdata[15: 8];
                if (iomem_wstrb[2]) gpio[23:16] <= iomem_wdata[23:16];
                if (iomem_wstrb[3]) gpio[31:24] <= iomem_wdata[31:24];
            end
        end
    end

    picosoc_noflash soc (
        .clk(cpu_clk), .resetn(resetn),
        .iomem_valid(iomem_valid), .iomem_ready(iomem_ready),
        .iomem_wstrb(iomem_wstrb), .iomem_addr(iomem_addr),
        .iomem_wdata(iomem_wdata), .iomem_rdata(iomem_rdata),
        .irq_5(1'b0), .irq_6(1'b0), .irq_7(1'b0),
        .ser_tx(uart_tx), .ser_rx(uart_rx)
    );
endmodule
