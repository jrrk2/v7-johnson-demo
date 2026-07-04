// VC707 PicoSoC — no MMCM variant.  IBUFDS → BUFG → /2 divider → BUFG →
// 100 MHz cpu_clk.  picorv32 places at ~120-150 MHz on the open flow, so the
// raw 200 MHz sysclk is divided by two in fabric instead of using an MMCM.
module top (
    input  wire       clk_p, clk_n, rst,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [7:0] led
);
    // cpu_clk from an MMCM at 25 MHz (200 MHz * 5 / 40).  The open flow only
    // meets ~75 MHz on picorv32, so the previous 100 MHz fabric /2 clock was
    // over-clocked (suspected residual reg_pc/mem_addr corruption); 25 MHz gives
    // a ~3x timing margin and a clean DLL-locked clock.
    wire sysclk_ibuf, cpu_clk, cpu_clk_unbuf, clk_fb, mmcm_locked;
    IBUFDS #(.DIFF_TERM("TRUE"), .IBUF_LOW_PWR("FALSE"), .IOSTANDARD("LVDS"))
        sysclk_ibufds (.I(clk_p), .IB(clk_n), .O(sysclk_ibuf));
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"), .STARTUP_WAIT("FALSE"),
        .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(5.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(40.000), .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKIN1_PERIOD(5.000)
    ) cpu_mmcm (
        .CLKFBOUT(clk_fb), .CLKFBOUTB(), .CLKOUT0(cpu_clk_unbuf),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBIN(clk_fb), .CLKIN1(sysclk_ibuf), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .DADDR(7'h0), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0), .DO(), .DRDY(), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .CLKINSTOPPED(), .CLKFBSTOPPED(), .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG cpu_bufg (.I(cpu_clk_unbuf), .O(cpu_clk));

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

    // ---- JTAG-loaded reset PC + reset-hold (USER1 UPDATE path) ----
    //   Sources reg_pc's reset value from a JTAG-shifted register instead of
    //   the hardwired PROGADDR_RESET constant, so the reset PC does NOT depend
    //   on the routed VCC/GND constant network.  jtag_hold keeps the CPU in
    //   reset while the PC is loaded; release to run from jtag_pc.
    wire        bs_update;
    reg  [31:0] jtag_pc   = 32'h0010_0000;
    reg         jtag_hold = 1'b1;
    // JTAG control of execution REMOVED: the CPU free-runs as soon as the
    // power-up reset counter deasserts, no BSCAN UPDATE release required.
    // The reset PC still comes from jtag_pc's register INIT (0x00100000,
    // delivered via FF INIT, not the routed const network).  jtag_hold is
    // now decorative (shown in the probe only).
    wire        resetn_cpu = resetn;

    wire        dbg_mem_valid, dbg_mem_ready, dbg_mem_instr, dbg_progmem_ready;
    wire [31:0] dbg_mem_addr, dbg_reg_pc;
    picosoc_noflash soc (
        .clk(cpu_clk), .resetn(resetn_cpu),
        .progaddr_reset_i(jtag_pc),
        .iomem_valid(iomem_valid), .iomem_ready(iomem_ready),
        .iomem_wstrb(iomem_wstrb), .iomem_addr(iomem_addr),
        .iomem_wdata(iomem_wdata), .iomem_rdata(iomem_rdata),
        .irq_5(1'b0), .irq_6(1'b0), .irq_7(1'b0),
        .ser_tx(uart_tx), .ser_rx(uart_rx),
        .dbg_mem_valid(dbg_mem_valid), .dbg_mem_ready(dbg_mem_ready),
        .dbg_mem_instr(dbg_mem_instr), .dbg_mem_addr(dbg_mem_addr),
        .dbg_progmem_ready(dbg_progmem_ready), .dbg_reg_pc(dbg_reg_pc)
    );

    // ---- CPU-bus fetch-stall monitors (cpu_clk domain) ----
    //  valid_cnt : # cycles mem_valid is high (RAW, NOT gated by ready)
    //              -> >0 means the CPU IS requesting; ==0 means core frozen.
    //  ready_cnt : # cycles mem_ready is high.
    //  req_addr  : mem_addr latched at the FIRST mem_valid (what it fetches first;
    //              PROGADDR_RESET=0x00100000 expected -> req_addr[23:0]=0x100000).
    //  pm_ready_seen / instr_first / req_set : sticky flags.
    reg [7:0]  valid_cnt = 8'h0, ready_cnt = 8'h0;
    reg [23:0] req_addr = 24'h0;
    reg        req_set = 1'b0, pm_ready_seen = 1'b0, instr_first = 1'b0;
    always @(posedge cpu_clk) begin
        if (dbg_mem_valid)        valid_cnt <= valid_cnt + 1'b1;
        if (dbg_mem_ready)        ready_cnt <= ready_cnt + 1'b1;
        if (dbg_progmem_ready)    pm_ready_seen <= 1'b1;
        if (dbg_mem_valid && !req_set) begin
            req_addr    <= dbg_mem_addr[23:0];
            instr_first <= dbg_mem_instr;
            req_set     <= 1'b1;
        end
    end

    // ---- read-only USER1 BSCAN probe (cpu_clk domain; no UPDATE/cmd path) ----
    //   capture: {hb[15:0], gpio_wr_cnt[7:0], gpio[7:0], 8'hA5}
    //   hb increments => cpu_clk alive; gpio_wr_cnt increments => CPU running firmware
    wire bs_sel, bs_capture, bs_shift, bs_drck, bs_drck_raw, bs_tdi;
    reg  [63:0] bs_sr;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan (
        .CAPTURE(bs_capture), .DRCK(bs_drck_raw), .RESET(), .RUNTEST(),
        .SEL(bs_sel), .SHIFT(bs_shift), .TCK(), .TDI(bs_tdi),
        .TDO(bs_sr[0]), .TMS(), .UPDATE(bs_update));
    // Buffer the BSCANE2 DRCK onto a global low-skew clock so the 64-bit bs_sr
    // shift/capture is coherent across both flows (the open prjxray flow and the
    // hybrid Vivado flow); without it bs_drck routes on fabric with uncontrolled
    // skew and the multi-bit reg_pc readback comes out as garbage.
    BUFG jtag_drck_bufg (.I(bs_drck_raw), .O(bs_drck));
    reg [15:0] hb = 16'h0;
    reg [7:0]  gpio_wr_cnt = 8'h0;
    always @(posedge cpu_clk) begin
        hb <= hb + 1'b1;
        if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h03 && |iomem_wstrb)
            gpio_wr_cnt <= gpio_wr_cnt + 1'b1;
    end
    //   capture (64b): {reg_pc[23:0], req_addr[15:0], gpio_wr_cnt[3:0], hb[3:0],
    //                   pm_ready_seen, req_set, instr_first, jtag_hold, 4'b0, 8'hA5}
    //   reg_pc[23:0] vs req_addr[15:0]: if reg_pc=0x100000 but mem_addr garbage,
    //   the mem_la_addr mux corrupts a correct reg_pc; if reg_pc itself is wrong,
    //   the jtag_pc->progaddr_reset_i->reg_pc delivery is broken.
    always @(posedge bs_drck) begin
        if (bs_sel && bs_capture)
            bs_sr <= {dbg_reg_pc[23:0], req_addr[15:0], gpio_wr_cnt[3:0], hb[3:0],
                      pm_ready_seen, req_set, instr_first, jtag_hold, 4'b0, 8'hA5};
        else if (bs_sel && bs_shift)
            bs_sr <= {bs_tdi, bs_sr[63:1]};
    end
    // Latch the JTAG-written reset-PC + reset-hold on DR UPDATE (USER1).
    always @(posedge bs_update) if (bs_sel) begin
        jtag_pc   <= bs_sr[31:0];
        jtag_hold <= bs_sr[32];
    end
endmodule
