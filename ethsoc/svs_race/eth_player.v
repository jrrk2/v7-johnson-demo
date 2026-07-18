`timescale 1ns/1ps
// eth_macro stand-in: plays one canned ARP request into the RX FIFO
// interface and drains/captures the TX reply. Same ports as eth_macro.
module eth_macro (
    input  wire        clk_int,
    input  wire        rst_int,
    input  wire        sgmii_rxp, sgmii_rxn,
    output wire        sgmii_txp, sgmii_txn,
    input  wire        sgmii_refclk_p, sgmii_refclk_n,
    output wire        phy_reset_n,
    output wire        eth_clk_o,
    output wire        gtrefclk_bufg_o,
    input  wire [5:0]  rx_rd_gray,
    output reg  [5:0]  rx_wr_gray,
    input  wire [4:0]  rx_rd_addr,
    output wire [71:0] rx_rd_data,
    output reg  [5:0]  tx_rd_gray,
    input  wire [5:0]  tx_wr_gray,
    output reg  [4:0]  tx_rd_addr,
    input  wire [71:0] tx_rd_data,
    output wire [15:0] pcspma_status,
    output wire [31:0] rx_fcs_reg,
    output wire [31:0] tx_fcs_reg,
    output wire        rx_overflow
);
    assign sgmii_txp = 0; assign sgmii_txn = 1;
    assign phy_reset_n = 1; assign eth_clk_o = clk_int;
    assign gtrefclk_bufg_o = clk_int;
    assign pcspma_status = 16'h0003;
    assign rx_fcs_reg = 0; assign tx_fcs_reg = 0; assign rx_overflow = 0;

    function [5:0] b2g(input [5:0] b); b2g = b ^ (b >> 1); endfunction

    // ---- canned ARP request: who-has 192.168.1.100 from 10.0.0.1 ----
    // 60 bytes -> 8 x 72-bit words ({tlast,data} 9 bits per byte, LSB first)
    reg [7:0] frame [0:59];
    integer i;
    initial begin
        for (i = 0; i < 60; i = i + 1) frame[i] = 8'h00;
        for (i = 0; i < 6; i = i + 1) frame[i] = 8'hff;         // dst bcast
        frame[6]=8'haa; frame[7]=8'hbb; frame[8]=8'hcc;
        frame[9]=8'hdd; frame[10]=8'hee; frame[11]=8'hf0;       // src
        frame[12]=8'h08; frame[13]=8'h06;                        // ethertype ARP
        frame[14]=8'h00; frame[15]=8'h01;                        // htype
        frame[16]=8'h08; frame[17]=8'h00;                        // ptype
        frame[18]=8'h06; frame[19]=8'h04;                        // hlen plen
        frame[20]=8'h00; frame[21]=8'h01;                        // oper request
        frame[22]=8'haa; frame[23]=8'hbb; frame[24]=8'hcc;
        frame[25]=8'hdd; frame[26]=8'hee; frame[27]=8'hf0;      // sha
        frame[28]=8'h0a; frame[29]=8'h00; frame[30]=8'h00; frame[31]=8'h01; // spa
        // tha zero
        frame[38]=8'hc0; frame[39]=8'ha8; frame[40]=8'h01; frame[41]=8'h64; // tpa
    end
    reg [71:0] rxmem [0:31];
    reg [5:0]  rx_wbin;
    integer w, b, byi;
    reg [71:0] wv;

    assign rx_rd_data = rxmem[rx_rd_addr];

    // play the frame once, shortly after reset deasserts
    reg [15:0] boot = 0;
    reg played = 0;
    always @(posedge clk_int) begin
        if (rst_int) begin
            rx_wbin <= 0; rx_wr_gray <= 0; boot <= 0; played <= 0;
        end else begin
            boot <= boot + 1;
            if (!played && boot == 16'd200) begin
                for (w = 0; w < 8; w = w + 1) begin
                    wv = 72'd0;
                    for (b = 0; b < 8; b = b + 1) begin
                        byi = w*8 + b;
                        if (byi < 60)
                            wv = wv | ({63'b0, (byi == 59), frame[byi]} << (9*b));
                    end
                    rxmem[w] = wv;
                end
                played <= 1;
                rx_wbin <= 6'd8;
            end
            rx_wr_gray <= b2g(played ? rx_wbin : 6'd0);
        end
    end

    // ---- TX drain + capture ----
    reg [5:0] tx_rbin;
    reg [71:0] cap [0:31];
    reg [5:0] cap_n = 0;
    always @(posedge clk_int) begin
        if (rst_int) begin
            tx_rbin <= 0; tx_rd_gray <= 0; tx_rd_addr <= 0; cap_n <= 0;
        end else begin
            tx_rd_addr <= tx_rbin[4:0];
            if (tx_wr_gray != b2g(tx_rbin)) begin
                cap[cap_n[4:0]] <= tx_rd_data;
                cap_n <= cap_n + 1;
                tx_rbin <= tx_rbin + 1;
            end
            tx_rd_gray <= b2g(tx_rbin);
        end
    end
endmodule
