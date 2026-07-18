`timescale 1ns/1ps
// Closed-loop: golden framing RTL + eth_player on BOTH sides; pair A drives
// RTL arp_ctrl, pair B drives the SVS netlist. Compare arp outputs and the
// captured TX reply words.
module tb_loop;
    reg clk = 0; always #4 clk = ~clk;
    reg rst = 1;
    wire rst_n = ~rst;

    // ---------------- pair A: RTL arp ----------------
    wire [16:0] a_addr; wire [63:0] a_wd; wire [7:0] a_be;
    wire a_ce, a_we, a_sel; wire [63:0] a_rd;
    wire a_led; wire [15:0] a_rc; wire [3:0] a_db;
    framing_top_sgmii fA (
        .msoc_clk(clk), .core_lsu_addr(a_addr), .core_lsu_wdata(a_wd),
        .core_lsu_be(a_be), .ce_d(a_ce), .we_d(a_we), .framing_sel(a_sel),
        .framing_rdata(a_rd), .clk_int(clk), .rst_int(rst),
        .sgmii_rxp(1'b0), .sgmii_rxn(1'b1), .sgmii_txp(), .sgmii_txn(),
        .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1), .phy_reset_n(),
        .phy_mdio_i(1'b0), .phy_mdio_o(), .phy_mdio_oe(),
        .phy_mdc(), .eth_irq(), .pcspma_status_o(),
        .eth_clk_o(), .gtrefclk_bufg_o());
    arp_ctrl #(.FPGA_MAC(48'h02_00_00_4B_41_31), .FPGA_IP(32'hC0_A8_01_64)) aA (
        .clk(clk), .rst_n(rst_n),
        .core_lsu_addr(a_addr), .core_lsu_wdata(a_wd), .core_lsu_be(a_be),
        .ce_d(a_ce), .we_d(a_we), .framing_sel(a_sel), .framing_rdata(a_rd),
        .led_arp(a_led), .reply_count(a_rc), .dbg_state(a_db));

    // ---------------- pair B: SVS arp ----------------
    wire [16:0] b_addr; wire [63:0] b_wd; wire [7:0] b_be;
    wire b_ce, b_we, b_sel; wire [63:0] b_rd;
    wire b_led; wire [15:0] b_rc; wire [3:0] b_db;
    framing_top_sgmii fB (
        .msoc_clk(clk), .core_lsu_addr(b_addr), .core_lsu_wdata(b_wd),
        .core_lsu_be(b_be), .ce_d(b_ce), .we_d(b_we), .framing_sel(b_sel),
        .framing_rdata(b_rd), .clk_int(clk), .rst_int(rst),
        .sgmii_rxp(1'b0), .sgmii_rxn(1'b1), .sgmii_txp(), .sgmii_txn(),
        .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1), .phy_reset_n(),
        .phy_mdio_i(1'b0), .phy_mdio_o(), .phy_mdio_oe(),
        .phy_mdc(), .eth_irq(), .pcspma_status_o(),
        .eth_clk_o(), .gtrefclk_bufg_o());
    arp_svs aB (
        .clk(clk), .rst_n(rst_n),
        .core_lsu_addr(b_addr), .core_lsu_wdata(b_wd), .core_lsu_be(b_be),
        .ce_d(b_ce), .we_d(b_we), .framing_sel(b_sel), .framing_rdata(b_rd),
        .led_arp(b_led), .reply_count(b_rc), .dbg_state(b_db));

    integer errors = 0;
    task chk(input [127:0] tag, input [127:0] a, input [127:0] b);
        if (!rst && a !== b && (^a) !== 1'bx) begin
            if (errors < 15)
                $display("DIFF %0s t=%0t ref=%h svs=%h", tag, $time, a, b);
            errors = errors + 1;
        end
    endtask
    always @(posedge clk) begin
        chk("addr", a_addr, b_addr);
        chk("ce", a_ce, b_ce);
        chk("we", a_we, b_we);
        chk("wd", a_wd, b_wd);
        chk("rc", a_rc, b_rc);
        chk("dbg", a_db, b_db);
    end
    initial begin
        repeat (20) @(posedge clk);
        rst <= 0;
        repeat (20000) @(posedge clk);
        $display("A reply_count=%0d dbg=%h  B reply_count=%0d dbg=%h",
                 a_rc, a_db, b_rc, b_db);
        $display("A capN=%0d  B capN=%0d",
                 fA.eth_macro1.cap_n, fB.eth_macro1.cap_n);
        if (fA.eth_macro1.cap_n > 0)
            $display("A cap0=%h cap1=%h", fA.eth_macro1.cap[0], fA.eth_macro1.cap[1]);
        if (fB.eth_macro1.cap_n > 0)
            $display("B cap0=%h cap1=%h", fB.eth_macro1.cap[0], fB.eth_macro1.cap[1]);
        if (errors == 0) $display("LOOPSIM PASS");
        else $display("LOOPSIM FAIL errors=%0d", errors);
        $finish;
    end
endmodule
