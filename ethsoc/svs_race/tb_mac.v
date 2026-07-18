`timescale 1ns/1ps
// RTL eth_mac_1g vs SVS gate-mapped funcsim netlist: one GMII RX frame in,
// AXIS out compared; one AXIS TX frame in, GMII out compared.
module tb_mac;
    reg clk = 0; always #4 clk = ~clk;
    reg rst = 1;

    // ---- RX stimulus ----
    reg [7:0] gmii_rxd = 0;
    reg gmii_rx_dv = 0, gmii_rx_er = 0;

    // ---- TX stimulus ----
    reg [7:0] tx_tdata = 0;
    reg tx_tvalid = 0, tx_tlast = 0, tx_tuser = 0;

    wire [7:0] r_rx_tdata, s_rx_tdata;
    wire r_rx_tvalid, s_rx_tvalid, r_rx_tlast, s_rx_tlast, r_rx_tuser, s_rx_tuser;
    wire r_tx_tready, s_tx_tready;
    wire [7:0] r_txd, s_txd;
    wire r_tx_en, s_tx_en, r_tx_er, s_tx_er;

    eth_mac_1g #(.ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)) ref_mac (
        .rx_clk(clk), .rx_rst(rst), .tx_clk(clk), .tx_rst(rst),
        .tx_axis_tdata(tx_tdata), .tx_axis_tvalid(tx_tvalid),
        .tx_axis_tready(r_tx_tready), .tx_axis_tlast(tx_tlast), .tx_axis_tuser(tx_tuser),
        .rx_axis_tdata(r_rx_tdata), .rx_axis_tvalid(r_rx_tvalid),
        .rx_axis_tlast(r_rx_tlast), .rx_axis_tuser(r_rx_tuser),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er),
        .gmii_txd(r_txd), .gmii_tx_en(r_tx_en), .gmii_tx_er(r_tx_er),
        .rx_clk_enable(1'b1), .tx_clk_enable(1'b1),
        .rx_mii_select(1'b0), .tx_mii_select(1'b0),
        .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fcs_reg(), .tx_fcs_reg(), .ifg_delay(8'd12));

    mac_svs dut_mac (
        .rx_clk(clk), .rx_rst(rst), .tx_clk(clk), .tx_rst(rst),
        .tx_axis_tdata(tx_tdata), .tx_axis_tvalid(tx_tvalid),
        .tx_axis_tready(s_tx_tready), .tx_axis_tlast(tx_tlast), .tx_axis_tuser(tx_tuser),
        .rx_axis_tdata(s_rx_tdata), .rx_axis_tvalid(s_rx_tvalid),
        .rx_axis_tlast(s_rx_tlast), .rx_axis_tuser(s_rx_tuser),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv), .gmii_rx_er(gmii_rx_er),
        .gmii_txd(s_txd), .gmii_tx_en(s_tx_en), .gmii_tx_er(s_tx_er),
        .rx_clk_enable(1'b1), .tx_clk_enable(1'b1),
        .rx_mii_select(1'b0), .tx_mii_select(1'b0),
        .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fcs_reg(), .tx_fcs_reg(), .ifg_delay(8'd12));

    integer errors = 0;
    integer r_rx_beats = 0, s_rx_beats = 0;
    always @(posedge clk) begin
        if (r_rx_tvalid) r_rx_beats = r_rx_beats + 1;
        if (s_rx_tvalid) s_rx_beats = s_rx_beats + 1;
        if (!rst && (r_rx_tvalid !== s_rx_tvalid || (r_rx_tvalid &&
             (r_rx_tdata !== s_rx_tdata || r_rx_tlast !== s_rx_tlast)))) begin
            if (errors < 10)
                $display("RXDIFF t=%0t ref v=%b d=%02x l=%b | svs v=%b d=%02x l=%b",
                         $time, r_rx_tvalid, r_rx_tdata, r_rx_tlast,
                         s_rx_tvalid, s_rx_tdata, s_rx_tlast);
            errors = errors + 1;
        end
        if (!rst && (r_tx_en !== s_tx_en || (r_tx_en && r_txd !== s_txd))) begin
            if (errors < 10)
                $display("TXDIFF t=%0t ref en=%b d=%02x | svs en=%b d=%02x",
                         $time, r_tx_en, r_txd, s_tx_en, s_txd);
            errors = errors + 1;
        end
    end

    task rx_byte(input [7:0] b);
        begin gmii_rxd <= b; gmii_rx_dv <= 1; @(posedge clk); end
    endtask
    integer i;
    initial begin
        repeat (20) @(posedge clk);
        rst <= 0;
        repeat (20) @(posedge clk);
        // ---- GMII RX frame: preamble+SFD, 60-byte payload, dummy FCS ----
        for (i = 0; i < 7; i = i + 1) rx_byte(8'h55);
        rx_byte(8'hd5);
        for (i = 0; i < 60; i = i + 1) rx_byte(8'h10 + (i & 8'h3f));
        for (i = 0; i < 4; i = i + 1) rx_byte(8'haa);
        gmii_rx_dv <= 0; gmii_rxd <= 0;
        repeat (40) @(posedge clk);
        // ---- AXIS TX frame: 60 bytes ----
        for (i = 0; i < 60; i = i + 1) begin
            tx_tdata <= 8'h20 + (i & 8'h3f); tx_tvalid <= 1;
            tx_tlast <= (i == 59);
            @(posedge clk);
            while (!r_tx_tready) @(posedge clk);
        end
        tx_tvalid <= 0; tx_tlast <= 0;
        repeat (200) @(posedge clk);
        $display("REF rx beats=%0d  SVS rx beats=%0d", r_rx_beats, s_rx_beats);
        if (errors == 0) $display("MACSIM PASS");
        else $display("MACSIM FAIL errors=%0d", errors);
        $finish;
    end
endmodule
