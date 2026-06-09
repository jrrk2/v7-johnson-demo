// byte_fifo — small synchronous byte FIFO (LUT/distributed), used for both the
// LUTs (distributed RAM) not block RAM.  The core pushes a byte and carries on
// at full speed; the FIFO drains to the slow UART transmitter in the background.
// The core only stalls if the FIFO is full (8 unsent bytes), which normal
// calculator output never reaches.
module byte_fifo #(parameter AW = 3) (      // 2^AW = 8 entries
    input  wire       clk,
    input  wire       rst,
    input  wire       wr,                   // push din when !full
    input  wire [7:0] din,
    output wire       full,
    input  wire       rd,                   // pop when !empty
    output wire [7:0] dout,
    output wire       empty
);
    (* ram_style = "distributed" *) reg [7:0] mem [0:(1<<AW)-1];
    reg [AW:0] wp, rp;                       // extra MSB distinguishes full/empty
    assign empty = (wp == rp);
    assign full  = (wp[AW] != rp[AW]) && (wp[AW-1:0] == rp[AW-1:0]);
    assign dout  = mem[rp[AW-1:0]];
    always @(posedge clk or posedge rst)
        if (rst) begin
            wp <= 0; rp <= 0;
        end else begin
            if (wr && !full)  begin mem[wp[AW-1:0]] <= din; wp <= wp + 1'b1; end
            if (rd && !empty)                            rp <= rp + 1'b1;
        end
endmodule
