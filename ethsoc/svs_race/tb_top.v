`timescale 1ns/1ps
// Ultimate closed loop: RTL top vs SVS top netlist, both wrapping the SAME
// RTL framing/arp (+ eth_player). MMCM runs for real in sim.
module tb_top;
    reg clk200 = 0; always #2.5 clk200 = ~clk200;
    reg rst = 1;

    wire [7:0] a_led, b_led;
    wire a_txp, a_txn, b_txp, b_txn;

    top A (.clk_p(clk200), .clk_n(~clk200), .rst(rst),
           .uart_tx(), .uart_rx(1'b1), .led(a_led),
           .sgmii_rxp(1'b0), .sgmii_rxn(1'b1),
           .sgmii_txp(a_txp), .sgmii_txn(a_txn),
           .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1),
           .eth_rst_n(), .eth_mdio(), .eth_mdc());
    top_svs B (.clk_p(clk200), .clk_n(~clk200), .rst(rst),
           .uart_tx(), .led(b_led),
           .sgmii_rxp(1'b0), .sgmii_rxn(1'b1),
           .sgmii_txp(b_txp), .sgmii_txn(b_txn),
           .sgmii_refclk_p(1'b0), .sgmii_refclk_n(1'b1),
           .eth_rst_n(), .eth_mdio(), .eth_mdc());

    initial begin
        #200 rst = 0;
        // let MMCM lock, resetn count, player inject at boot==200, arp reply
        #400000;
        $display("A led=%b reply=%0d  B led=%b reply=%0d",
                 a_led, A.i_arp.reply_count, b_led, B.i_arp_250.reply_count);
        $display("A capN=%0d B capN=%0d",
                 A.eth.eth_macro1.cap_n, B.eth_232.eth_macro1.cap_n);
        if (A.i_arp.reply_count == B.i_arp_250.reply_count
            && A.i_arp.reply_count > 0)
            $display("TOPSIM PASS");
        else
            $display("TOPSIM FAIL");
        $finish;
    end
endmodule
