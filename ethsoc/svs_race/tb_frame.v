`timescale 1ns/1ps
// Lockstep race: framing_top_sgmii RTL vs SVS netlist, eth_macro stubbed
// identically on both sides. Random bus traffic; compare framing_rdata and
// side outputs each cycle.
module tb_frame;
    reg clk = 0; always #4 clk = ~clk;
    reg rst = 1;
    reg [31:0] lfsr = 32'h5eed5eed;
    always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

    reg [16:0] addr; reg [63:0] wdata; reg [7:0] be; reg ce, we, sel;
    always @(posedge clk) begin
        // register-space-heavy random traffic
        addr  <= {lfsr[1] ? 4'h0 : lfsr[5:2], lfsr[12:0]};
        wdata <= {lfsr, lfsr[15:0], lfsr[31:16]};
        be    <= 8'hFF;
        ce    <= lfsr[3] | lfsr[7];
        we    <= lfsr[4];
        sel   <= 1'b1;
    end

    wire [63:0] r_rd, s_rd; wire r_irq, s_irq;
    wire r_mdo, s_mdo, r_moe, s_moe, r_mdc, s_mdc;

    framing_top_sgmii ref_f (
        .msoc_clk(clk), .core_lsu_addr(addr), .core_lsu_wdata(wdata),
        .core_lsu_be(be), .ce_d(ce), .we_d(we), .framing_sel(sel),
        .framing_rdata(r_rd), .clk_int(clk), .rst_int(rst),
        .sgmii_rxp(1'b0), .sgmii_rxn(1'b1), .sgmii_txp(), .sgmii_txn(),
        .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1), .phy_reset_n(),
        .phy_mdio_i(lfsr[9]), .phy_mdio_o(r_mdo), .phy_mdio_oe(r_moe),
        .phy_mdc(r_mdc), .eth_irq(r_irq), .pcspma_status_o(),
        .eth_clk_o(), .gtrefclk_bufg_o());
    framing_svs dut_f (
        .msoc_clk(clk), .core_lsu_addr(addr), .core_lsu_wdata(wdata),
        .core_lsu_be(be), .ce_d(ce), .we_d(we), .framing_sel(sel),
        .framing_rdata(s_rd), .clk_int(clk), .rst_int(rst),
        .sgmii_rxp(1'b0), .sgmii_rxn(1'b1), .sgmii_txp(), .sgmii_txn(),
        .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1), .phy_reset_n(),
        .phy_mdio_i(lfsr[9]), .phy_mdio_o(s_mdo), .phy_mdio_oe(s_moe),
        .phy_mdc(s_mdc), .eth_irq(s_irq), .pcspma_status_o(),
        .eth_clk_o(), .gtrefclk_bufg_o());

    integer errors = 0;
    task chk(input [127:0] tag, input [127:0] a, input [127:0] b);
        if (!rst && a !== b && (^a) !== 1'bx) begin
            if (errors < 12)
                $display("DIFF %0s t=%0t ref=%h svs=%h", tag, $time, a, b);
            errors = errors + 1;
        end
    endtask
    always @(posedge clk) begin
        chk("rdata", r_rd, s_rd);
        chk("irq", r_irq, s_irq);
        chk("mdo", r_mdo, s_mdo);
        chk("moe", r_moe, s_moe);
        chk("mdc", r_mdc, s_mdc);
    end
    initial begin
        repeat (20) @(posedge clk);
        rst <= 0;
        repeat (8000) @(posedge clk);
        if (errors == 0) $display("FRAMESIM PASS");
        else $display("FRAMESIM FAIL errors=%0d", errors);
        $finish;
    end
endmodule
