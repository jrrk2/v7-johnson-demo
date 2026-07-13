// Behavioural sim-only stand-in for sgmii_soc (PCS/PMA + GTX + MAC): loops
// the TX AXIS byte stream back to RX with a MAC-like pacing model, so the
// FIFO-boundary framing_top can be verified in iverilog without unisims.
// Compile this INSTEAD of sgmii_soc.sv (same module name).
//
// Pacing model (mimics axis_gmii_tx/rx at gigabit):
//  * tready: 8-cycle preamble delay at frame start, then continuous;
//  * a captured frame is replayed on rx_axis after a 12-cycle IFG.
`timescale 1ns/1ps
module sgmii_soc (
    input  wire        clk_int,
    input  wire        rst_int,
    output wire        eth_clk,
    input  wire        sgmii_rxp,
    input  wire        sgmii_rxn,
    output wire        sgmii_txp,
    output wire        sgmii_txn,
    input  wire        sgmii_refclk_p,
    input  wire        sgmii_refclk_n,
    output wire        phy_reset_n,
    output wire        mac_gmii_tx_en,
    input  wire [7:0]  tx_axis_tdata,
    input  wire        tx_axis_tvalid,
    output wire        tx_axis_tready,
    input  wire        tx_axis_tlast,
    input  wire        tx_axis_tuser,
    output wire        rx_clk,
    output reg  [7:0]  rx_axis_tdata,
    output reg         rx_axis_tvalid,
    output reg         rx_axis_tlast,
    output wire        rx_axis_tuser,
    output wire [31:0] rx_fcs_reg,
    output wire [31:0] tx_fcs_reg,
    output wire [15:0] pcspma_status,
    output wire        gtrefclk_bufg_out
);
    reg clk125 = 0;
    always #4 clk125 = ~clk125;   // 125 MHz

    assign eth_clk = clk125;
    assign rx_clk  = clk125;
    assign gtrefclk_bufg_out = clk125;
    assign sgmii_txp = 1'b0;
    assign sgmii_txn = 1'b1;
    assign phy_reset_n = 1'b1;
    assign pcspma_status = 16'h0001;
    assign rx_fcs_reg = 32'h0;
    assign tx_fcs_reg = 32'h0;
    assign rx_axis_tuser = 1'b0;

    // ---- TX side: preamble-delayed tready, capture frame ------------------
    reg  [3:0] pre_cnt;
    reg        in_frame;
    assign tx_axis_tready = in_frame & (pre_cnt == 0);
    assign mac_gmii_tx_en = in_frame;

    reg [7:0]  fbuf [0:2047];
    integer    flen;
    reg        frame_done;
    integer    dropped;   // frames aborted with tuser

    always @(posedge clk125)
        if (rst_int) begin
            pre_cnt <= 0; in_frame <= 0; flen = 0; frame_done <= 0; dropped = 0;
        end else begin
            frame_done <= 1'b0;
            if (!in_frame) begin
                if (tx_axis_tvalid) begin
                    in_frame <= 1'b1;
                    pre_cnt <= 4'd8;
                    flen = 0;
                end
            end else begin
                if (pre_cnt != 0) pre_cnt <= pre_cnt - 1'b1;
                else if (tx_axis_tvalid) begin
                    fbuf[flen] = tx_axis_tdata; flen = flen + 1;
                    if (tx_axis_tlast) begin
                        in_frame <= 1'b0;
                        if (tx_axis_tuser) begin dropped = dropped + 1; flen = 0; end
                        else frame_done <= 1'b1;
                    end
                end
                // tvalid gap mid-frame would be an underrun; unpacker never gaps
            end
        end

    // ---- optional self-injection (+inject): play one synthetic broadcast
    // frame into rx_axis after reset, for designs whose TX only follows RX
    // (e.g. the reflector).  inj_req is written only here, read in the clocked
    // block below via the inj_ack handshake.
    reg         inj_req = 0;
    reg         inj_ack = 0;
    reg  [7:0]  inj_buf [0:2047];
    integer     inj_len, k;
    initial if ($test$plusargs("inject")) begin
        inj_len = 60;
        for (k = 0; k < 6;  k = k + 1) inj_buf[k] = 8'hFF;            // dst: broadcast
        for (k = 6; k < 12; k = k + 1) inj_buf[k] = 8'h20 + k[7:0];   // src: 26..31
        for (k = 12; k < 60; k = k + 1) inj_buf[k] = k[7:0] ^ 8'hA5;  // payload
        wait (rst_int === 1'b0);
        #2000;
        inj_req = 1;
        wait (inj_ack);
        inj_req = 0;
    end
    // +inject_arp: broadcast ARP who-has 192.168.1.100 from 02:11:22:33:44:55
    initial if ($test$plusargs("inject_arp")) begin
        for (k = 0; k < 60; k = k + 1) inj_buf[k] = 8'h00;
        for (k = 0; k < 6;  k = k + 1) inj_buf[k] = 8'hFF;                 // dst bcast
        inj_buf[6]=8'h02; inj_buf[7]=8'h11; inj_buf[8]=8'h22;
        inj_buf[9]=8'h33; inj_buf[10]=8'h44; inj_buf[11]=8'h55;            // src
        inj_buf[12]=8'h08; inj_buf[13]=8'h06;                              // ARP
        inj_buf[14]=8'h00; inj_buf[15]=8'h01;                              // htype
        inj_buf[16]=8'h08; inj_buf[17]=8'h00;                              // ptype
        inj_buf[18]=8'h06; inj_buf[19]=8'h04;                              // hlen plen
        inj_buf[20]=8'h00; inj_buf[21]=8'h01;                              // op req
        inj_buf[22]=8'h02; inj_buf[23]=8'h11; inj_buf[24]=8'h22;
        inj_buf[25]=8'h33; inj_buf[26]=8'h44; inj_buf[27]=8'h55;           // sha
        inj_buf[28]=8'hC0; inj_buf[29]=8'hA8; inj_buf[30]=8'h01; inj_buf[31]=8'h01; // spa
        inj_buf[38]=8'hC0; inj_buf[39]=8'hA8; inj_buf[40]=8'h01; inj_buf[41]=8'h64; // tpa .100
        inj_len = 60;
        wait (rst_int === 1'b0);
        #2000;
        inj_req = 1;
        wait (inj_ack);
        inj_req = 0;
    end

    // ---- optional swap-check (+check_swap, with +inject): on the first
    // captured TX frame, verify it is the injected frame with dst/src MACs
    // swapped and payload intact, then report and finish.
    integer ce, ci;
    always @(posedge clk125)
        if (frame_done && $test$plusargs("check_swap")) begin
            ce = 0;
            if (flen < inj_len) begin
                $display("REFLECTM FAIL: reflected len=%0d < %0d", flen, inj_len);
                ce = ce + 1;
            end else begin
                for (ci = 0; ci < 6; ci = ci + 1) begin
                    if (fbuf[ci]   !== inj_buf[6+ci]) begin $display("FAIL dst[%0d]=%h exp %h", ci, fbuf[ci], inj_buf[6+ci]); ce = ce + 1; end
                    if (fbuf[6+ci] !== inj_buf[ci])   begin $display("FAIL src[%0d]=%h exp %h", ci, fbuf[6+ci], inj_buf[ci]); ce = ce + 1; end
                end
                for (ci = 12; ci < inj_len; ci = ci + 1)
                    if (fbuf[ci] !== inj_buf[ci]) begin $display("FAIL pay[%0d]=%h exp %h", ci, fbuf[ci], inj_buf[ci]); ce = ce + 1; end
            end
            if (ce == 0) $display("REFLECTM OK: MAC-swapped frame reflected, payload intact (len=%0d)", flen);
            else $display("REFLECTM FAIL: %0d errors", ce);
            $finish;
        end

    // ---- RX side: replay captured frame after IFG -------------------------
    integer  ridx, rlen;
    reg [3:0] ifg;
    reg      playing;

    always @(posedge clk125)
        if (rst_int) begin
            rx_axis_tvalid <= 0; rx_axis_tlast <= 0; rx_axis_tdata <= 0;
            playing <= 0; ridx = 0; rlen = 0; ifg <= 0; inj_ack <= 0;
        end else begin
            if (!playing) begin
                rx_axis_tvalid <= 0; rx_axis_tlast <= 0;
                if (inj_req && !inj_ack) begin
                    for (k = 0; k < inj_len; k = k + 1) fbuf[k] = inj_buf[k];
                    rlen = inj_len; ridx = 0; ifg <= 4'd12; playing <= 1;
                    inj_ack <= 1;
                end
                else if (frame_done) begin
                    rlen = flen; ridx = 0; ifg <= 4'd12; playing <= 1;
                end
            end else if (ifg != 0)
                ifg <= ifg - 1'b1;
            else begin
                rx_axis_tdata  <= fbuf[ridx];
                rx_axis_tvalid <= 1'b1;
                rx_axis_tlast  <= (ridx == rlen - 1);
                ridx = ridx + 1;
                if (ridx == rlen) playing <= 0;
            end
        end
endmodule
