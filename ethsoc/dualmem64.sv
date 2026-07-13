// Symmetric 64-bit / 64-bit true-dual-port RAM, single or dual clock, built
// from RAMB16_S36_S36 legacy primitives (Vivado retargets them to RAMB36E1;
// yosys uses the _xc7 wrapper in ramb16_compat.v) in 512-word banks.
//
// Replaces the asymmetric dualmem_widen/dualmem_widen8 in the FIFO-boundary
// eth flow: with the 125 MHz framing FSMs moved inside the frozen eth_macro,
// both BRAM ports run on msoc_clk (port A = drain/push FSM, port B = CPU bus),
// so no BRAM clock-domain crossing remains in the nextpnr region.
`default_nettype none
module dualmem64 #(
   parameter ADDR_WIDTH = 13            // 64-bit words; >= 9
)(
   input  wire                  clka,
   input  wire [63:0]           dina,
   input  wire [ADDR_WIDTH-1:0] addra,
   input  wire [1:0]            wea,    // 32-bit lane write enables
   input  wire                  ena,
   output wire [63:0]           douta,
   input  wire                  clkb,
   input  wire [63:0]           dinb,
   input  wire [ADDR_WIDTH-1:0] addrb,
   input  wire [1:0]            web,
   input  wire                  enb,
   output wire [63:0]           doutb
);
   localparam BANK_SEL = ADDR_WIDTH - 9;
   localparam NBANKS   = 1 << BANK_SEL;

`define RAMB16_64      // hardwired: force the RAMB36E1-backed primitive path
`ifdef VC707
 `define RAMB16_64
`endif
`ifdef KINTEX7
 `define RAMB16_64
`endif

`ifdef RAMB16_64
   genvar b, h;
   wire [NBANKS*64-1:0] douta_w, doutb_w;

   reg [ADDR_WIDTH-1:0] addra_dly, addrb_dly;
   always @(posedge clka) addra_dly <= addra;
   always @(posedge clkb) addrb_dly <= addrb;

   wire [BANK_SEL-1:0] banka = (BANK_SEL == 0) ? 1'b0 : addra[ADDR_WIDTH-1:9];
   wire [BANK_SEL-1:0] bankb = (BANK_SEL == 0) ? 1'b0 : addrb[ADDR_WIDTH-1:9];
   wire [BANK_SEL-1:0] banka_dly = (BANK_SEL == 0) ? 1'b0 : addra_dly[ADDR_WIDTH-1:9];
   wire [BANK_SEL-1:0] bankb_dly = (BANK_SEL == 0) ? 1'b0 : addrb_dly[ADDR_WIDTH-1:9];

   assign douta = douta_w >> {banka_dly, 6'b0};
   assign doutb = doutb_w >> {bankb_dly, 6'b0};

   generate
     for (b = 0; b < NBANKS; b = b + 1)
       for (h = 0; h < 2; h = h + 1)   // low/high 32-bit halves
         RAMB16_S36_S36_xc7      // hardwired: RAMB36E1-backed compat cell
         ram_inst (
           .CLKA  ( clka                        ),
           .DOA   ( douta_w[b*64+h*32 +: 32]    ),
           .DOPA  (                             ),
           .ADDRA ( addra[8:0]                  ),
           .DIA   ( dina[h*32 +: 32]            ),
           .DIPA  ( 4'b0                        ),
           .ENA   ( ena & (banka == b)          ),
           .SSRA  ( 1'b0                        ),
           .WEA   ( wea[h] & (banka == b)       ),
           .CLKB  ( clkb                        ),
           .DOB   ( doutb_w[b*64+h*32 +: 32]    ),
           .DOPB  (                             ),
           .ADDRB ( addrb[8:0]                  ),
           .DIB   ( dinb[h*32 +: 32]            ),
           .DIPB  ( 4'b0                        ),
           .ENB   ( enb & (bankb == b)          ),
           .SSRB  ( 1'b0                        ),
           .WEB   ( web[h] & (bankb == b)       )
         );
   endgenerate

`else // behavioural (simulation without unisims)

   reg [63:0] mem [0:(1<<ADDR_WIDTH)-1];
   reg [63:0] douta_r, doutb_r;
   assign douta = douta_r;
   assign doutb = doutb_r;

   always @(posedge clka)
     if (ena) begin
        if (wea[0]) mem[addra][31:0]  <= dina[31:0];
        if (wea[1]) mem[addra][63:32] <= dina[63:32];
        douta_r <= mem[addra];
     end
   always @(posedge clkb)
     if (enb) begin
        if (web[0]) mem[addrb][31:0]  <= dinb[31:0];
        if (web[1]) mem[addrb][63:32] <= dinb[63:32];
        doutb_r <= mem[addrb];
     end
`endif
endmodule
`default_nettype wire
