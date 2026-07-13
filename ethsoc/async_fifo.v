// Async FIFO with distributed-RAM storage and Gray-code pointers, SPLIT into
// a write half and a read half so the two halves can live on opposite sides
// of the frozen 125 MHz eth_macro boundary:
//
//   async_fifo_wr : wr_clk logic + the distributed-RAM array + write-side
//                   Gray pointer + rd_gray synchroniser.
//   async_fifo_rd : rd_clk logic + read-side Gray pointer + wr_gray
//                   synchroniser.  Reads the RAM combinationally through
//                   rd_addr / rd_data.
//
// RX direction: write half (rx_clk) INSIDE the macro, read half (msoc_clk)
// outside.  TX direction: write half (msoc_clk) outside, read half (eth_clk)
// inside.  The only boundary-crossing signals are the two Gray pointers
// (each consumed by a 2-flop synchroniser in the far domain — async, single
// bit changes per Gray step) and the combinational RAM read port
// (rd_addr in / rd_data out — stable whenever the read half consumes it,
// by the standard async-FIFO argument).  No same-clock 125 MHz FF->FF arc
// spans the boundary, so nextpnr's lack of hold analysis cannot corrupt it.
//
// Full/empty flags are derived from REGISTERED Gray pointers only: deriving
// wr_full from wr_gray_next creates a combinational loop through
// wr_en & ~wr_full that oscillates at the full boundary (a real hardware
// comb loop; it also fork-bombs event-driven simulators).
`default_nettype none

// ---------------------------------------------------------------------------
// write half: wr-domain pointer logic + distributed-RAM array
// ---------------------------------------------------------------------------
module async_fifo_wr #(
    parameter DATA_WIDTH = 9,
    parameter ADDR_WIDTH = 5
) (
    input  wire                   wr_clk,
    input  wire                   wr_rst,
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output wire                   wr_full,
    // boundary: to/from read half
    output reg  [ADDR_WIDTH:0]    wr_gray,      // -> read-half synchroniser
    input  wire [ADDR_WIDTH:0]    rd_gray,      // from read half (async)
    input  wire [ADDR_WIDTH-1:0]  rd_addr,      // RAM read port (async)
    output wire [DATA_WIDTH-1:0]  rd_data
);
    localparam DEPTH = (1 << ADDR_WIDTH);

    reg  [ADDR_WIDTH:0] wr_bin;
    reg  [ADDR_WIDTH:0] rd_gray_wsync1, rd_gray_wsync2; // rd_gray -> wr_clk

    function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction

    // full when current write gray == read gray with top two bits inverted
    // (write pointer exactly DEPTH ahead of read pointer)
    assign wr_full = (wr_gray == {~rd_gray_wsync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                   rd_gray_wsync2[ADDR_WIDTH-2:0]});

    wire [ADDR_WIDTH:0] wr_bin_next  = wr_bin + (wr_en & ~wr_full);
    wire [ADDR_WIDTH:0] wr_gray_next = bin2gray(wr_bin_next);

    always @(posedge wr_clk)
        if (wr_rst) begin
            wr_bin  <= 0;
            wr_gray <= 0;
            rd_gray_wsync1 <= 0;
            rd_gray_wsync2 <= 0;
        end else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
            rd_gray_wsync1 <= rd_gray;
            rd_gray_wsync2 <= rd_gray_wsync1;
        end

    // ---- storage: sync write, async read ---------------------------------
`ifdef YOSYS
    // open flow (fresh yosys + nextpnr): instantiate per-bit RAM32X1D --
    // nextpnr's whole-slice RAM32M clusters do not survive SA placement
    // (split across slices), while the per-bit path is the battle-tested
    // upstream one.  Requires ADDR_WIDTH == 5.
    wire wr_we = wr_en & ~wr_full;
    genvar gb;
    generate for (gb = 0; gb < DATA_WIDTH; gb = gb + 1) begin : bitram
        RAM32X1D #(.INIT(32'b0)) r (
            .WCLK(wr_clk), .WE(wr_we), .D(wr_data[gb]),
            .A0(wr_bin[0]), .A1(wr_bin[1]), .A2(wr_bin[2]),
            .A3(wr_bin[3]), .A4(wr_bin[4]),
            .DPRA0(rd_addr[0]), .DPRA1(rd_addr[1]), .DPRA2(rd_addr[2]),
            .DPRA3(rd_addr[3]), .DPRA4(rd_addr[4]),
            .DPO(rd_data[gb]), .SPO());
    end endgenerate
`else
    (* ram_style = "distributed" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    always @(posedge wr_clk)
        if (!wr_rst && wr_en && !wr_full)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    assign rd_data = mem[rd_addr];   // async (combinational) read
`endif
endmodule

// ---------------------------------------------------------------------------
// read half: rd-domain pointer logic (RAM lives in the write half)
// ---------------------------------------------------------------------------
module async_fifo_rd #(
    parameter DATA_WIDTH = 9,
    parameter ADDR_WIDTH = 5
) (
    input  wire                   rd_clk,
    input  wire                   rd_rst,
    input  wire                   rd_en,
    output wire [DATA_WIDTH-1:0]  rd_data,
    output wire                   rd_empty,
    // boundary: to/from write half
    output reg  [ADDR_WIDTH:0]    rd_gray,      // -> write-half synchroniser
    input  wire [ADDR_WIDTH:0]    wr_gray,      // from write half (async)
    output wire [ADDR_WIDTH-1:0]  rd_addr,      // RAM read port
    input  wire [DATA_WIDTH-1:0]  rd_data_mem
);
    reg  [ADDR_WIDTH:0] rd_bin;
    reg  [ADDR_WIDTH:0] wr_gray_rsync1, wr_gray_rsync2; // wr_gray -> rd_clk

    function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction

    assign rd_empty = (rd_gray == wr_gray_rsync2);
    assign rd_addr  = rd_bin[ADDR_WIDTH-1:0];
    assign rd_data  = rd_data_mem;

    wire [ADDR_WIDTH:0] rd_bin_next  = rd_bin + (rd_en & ~rd_empty);
    wire [ADDR_WIDTH:0] rd_gray_next = bin2gray(rd_bin_next);

    always @(posedge rd_clk)
        if (rd_rst) begin
            rd_bin  <= 0;
            rd_gray <= 0;
            wr_gray_rsync1 <= 0;
            wr_gray_rsync2 <= 0;
        end else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
            wr_gray_rsync1 <= wr_gray;
            wr_gray_rsync2 <= wr_gray_rsync1;
        end
endmodule

// ---------------------------------------------------------------------------
// monolithic wrapper (verification convenience / single-region uses)
// ---------------------------------------------------------------------------
module async_fifo #(
    parameter DATA_WIDTH = 9,
    parameter ADDR_WIDTH = 5        // 32 entries default
) (
    input  wire                   wr_clk,
    input  wire                   wr_rst,
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    output wire                   wr_full,
    input  wire                   rd_clk,
    input  wire                   rd_rst,
    input  wire                   rd_en,
    output wire [DATA_WIDTH-1:0]  rd_data,
    output wire                   rd_empty
);
    wire [ADDR_WIDTH:0]   wr_gray, rd_gray;
    wire [ADDR_WIDTH-1:0] rd_addr;
    wire [DATA_WIDTH-1:0] rd_data_mem;

    async_fifo_wr #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_wr (
        .wr_clk(wr_clk), .wr_rst(wr_rst), .wr_en(wr_en), .wr_data(wr_data),
        .wr_full(wr_full),
        .wr_gray(wr_gray), .rd_gray(rd_gray),
        .rd_addr(rd_addr), .rd_data(rd_data_mem));

    async_fifo_rd #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_rd (
        .rd_clk(rd_clk), .rd_rst(rd_rst), .rd_en(rd_en), .rd_data(rd_data),
        .rd_empty(rd_empty),
        .rd_gray(rd_gray), .wr_gray(wr_gray),
        .rd_addr(rd_addr), .rd_data_mem(rd_data_mem));
endmodule
`default_nettype wire
