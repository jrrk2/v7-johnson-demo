// 125 MHz AXIS byte-stream <-> 72-bit FIFO-word converters for the eth_macro
// boundary.  A FIFO word carries 8 x {tlast, data[7:0]} byte slots, slot 0
// first.  Bytes after a tlast-flagged slot within a word are padding and are
// never examined by the consumer.
//
// Width rationale: the msoc side runs at 50 MHz and moves one 72-bit word per
// cycle (400 MB/s), comfortably above the 125 MB/s GbE byte rate in both
// directions, so the shallow distributed-RAM FIFOs can neither overflow (RX)
// nor underrun (TX) while the msoc FSMs stream continuously.
`default_nettype none

// ---------------------------------------------------------------------------
// RX: pack the MAC's AXIS byte stream into 72-bit words (rx_clk domain).
// Flushes on the 8th byte or on tlast.  If the FIFO is full at flush time the
// word is dropped and the sticky overflow flag set (debug only; cannot happen
// while the msoc drain FSM runs).
// ---------------------------------------------------------------------------
module rx_axis_packer (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_axis_tdata,
    input  wire        rx_axis_tvalid,
    input  wire        rx_axis_tlast,
    output reg         wr_en,
    output reg  [71:0] wr_data,
    input  wire        wr_full,
    output reg         overflow      // sticky
);
    reg [2:0]  cnt;
    reg [71:0] acc;

    wire [71:0] acc_ins = acc | ({63'b0, rx_axis_tlast, rx_axis_tdata} << {cnt, 3'b0} << cnt);
    // ({tlast,data} << 9*cnt): 9*cnt = 8*cnt + cnt

    always @(posedge clk)
        if (rst) begin
            cnt <= 0; acc <= 0; wr_en <= 0; wr_data <= 0; overflow <= 0;
        end else begin
            wr_en <= 1'b0;
            if (rx_axis_tvalid) begin
                if (rx_axis_tlast || cnt == 3'd7) begin
                    wr_data <= acc_ins;
                    wr_en   <= 1'b1;
                    if (wr_full) overflow <= 1'b1;
                    acc <= 0;
                    cnt <= 0;
                end else begin
                    acc <= acc_ins;
                    cnt <= cnt + 1'b1;
                end
            end
        end
endmodule

// ---------------------------------------------------------------------------
// TX: unpack 72-bit FIFO words into the MAC's AXIS byte stream (eth_clk
// domain).  First-word-fall-through: rd_data is the FIFO head whenever
// !rd_empty.  Starts as soon as the head word is visible (the msoc pusher
// fills 3.2x faster than GMII drains, so a started frame cannot underrun
// while the pusher streams).  A mid-frame empty FIFO aborts the frame with
// tlast+tuser (poisons the FCS).
// ---------------------------------------------------------------------------
module tx_axis_unpacker (
    input  wire        clk,
    input  wire        rst,
    // FIFO read half (FWFT)
    input  wire [71:0] rd_data,
    input  wire        rd_empty,
    output reg         rd_en,
    // AXIS to MAC
    output wire [7:0]  tx_axis_tdata,
    output reg         tx_axis_tvalid,
    input  wire        tx_axis_tready,
    output wire        tx_axis_tlast,
    output reg         tx_axis_tuser
);
    reg [71:0] wbuf;
    reg [2:0]  idx;

    wire [8:0] slot = wbuf >> ({idx, 3'b0} + idx);   // {tlast, data} at 9*idx
    assign tx_axis_tdata = tx_axis_tuser ? 8'h00 : slot[7:0];
    assign tx_axis_tlast = tx_axis_tuser ? 1'b1  : slot[8];

    always @(posedge clk)
        if (rst) begin
            wbuf <= 0; idx <= 0; rd_en <= 0;
            tx_axis_tvalid <= 0; tx_axis_tuser <= 0;
        end else begin
            rd_en <= 1'b0;
            if (!tx_axis_tvalid) begin
                if (!rd_empty && !rd_en) begin   // !rd_en: head updates the cycle after a pop
                    wbuf <= rd_data;
                    rd_en <= 1'b1;
                    idx <= 0;
                    tx_axis_tvalid <= 1'b1;
                end
            end else if (tx_axis_tready) begin
                if (tx_axis_tlast) begin         // frame done (or abort byte sent)
                    tx_axis_tvalid <= 1'b0;
                    tx_axis_tuser  <= 1'b0;
                    idx <= 0;
                end else if (idx == 3'd7) begin
                    if (!rd_empty && !rd_en) begin
                        wbuf <= rd_data;
                        rd_en <= 1'b1;
                        idx <= 0;
                    end else begin
                        tx_axis_tuser <= 1'b1;   // underrun: abort with bad FCS
                    end
                end else
                    idx <= idx + 1'b1;
            end
        end
endmodule
`default_nettype wire
