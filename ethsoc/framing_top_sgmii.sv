// See LICENSE for license details.
//
// FIFO-boundary restructure for the open flow: all 125 MHz logic (PCS/PMA +
// GTX + MAC + byte/word converters + eth-side async-FIFO halves) lives in
// eth_macro, which the open flow imports as a frozen Vivado-implemented
// macro.  Everything in THIS module is clocked by msoc_clk only: CSRs, the
// msoc-side FIFO halves, the single-clock packet BRAMs and the drain/push
// FSMs.  The only macro-boundary signals are Gray pointers (async, 2-flop
// synchronised on the consuming side) and combinational distributed-RAM read
// ports — no same-clock arc crosses the boundary, so nextpnr's missing hold
// analysis cannot corrupt the datapath.
//
// The CPU-visible register map and buffer layout are unchanged from the
// pre-split framing_top_sgmii.
`default_nettype none

module framing_top_sgmii
  (
  input wire          msoc_clk,
  input wire [16:0]   core_lsu_addr,
  input wire [63:0]   core_lsu_wdata,
  input wire [7:0]    core_lsu_be,
  input wire          ce_d,
  input wire          we_d,
  input wire          framing_sel,
  output logic [63:0] framing_rdata,

    // Internal clock
  input wire          clk_int,
  input wire          rst_int,

    /*
     * Ethernet: 1000BASE-X SGMII
     */
  input wire          sgmii_rxp,
  input wire          sgmii_rxn,
  output wire         sgmii_txp,
  output wire         sgmii_txn,
  input wire          sgmii_refclk_p,
  input wire          sgmii_refclk_n,
  output wire         phy_reset_n,

  input wire          phy_mdio_i,
  output reg          phy_mdio_o,
  output reg          phy_mdio_oe,
  output wire         phy_mdc,

  output reg          eth_irq,
  output wire [15:0]  pcspma_status_o,
  output wire         eth_clk_o,
  output wire         gtrefclk_bufg_o
   );

logic       phy_mdclk;
assign phy_mdc = phy_mdclk;

logic [16:0] core_lsu_addr_dly;

logic [47:0] mac_address;
logic [10:0] tx_packet_length;
wire  [10:0] rx_length_rd;
logic        ce_d_dly, avail;
logic [63:0] framing_rdata_pkt, framing_wdata_pkt;
logic [4:0]  firstbuf, nextbuf, lastbuf;
logic        sync, irq_en;
logic        cooked, loopback, promiscuous;
logic [3:0]  spare;

wire [15:0]  pcspma_status;
wire [31:0]  tx_fcs_reg, rx_fcs_reg;
wire [31:0]  tx_fcs_reg_rev, rx_fcs_reg_rev;

// ===========================================================================
//  eth_macro (frozen 125 MHz island) + macro-boundary FIFO halves
// ===========================================================================
wire [5:0]  rx_rd_gray, rx_wr_gray, tx_rd_gray, tx_wr_gray;
wire [4:0]  rx_rd_addr, tx_rd_addr;
wire [71:0] rx_rd_data, tx_rd_data;
wire        rx_overflow;

eth_macro eth_macro1 (
    .clk_int(clk_int),
    .rst_int(rst_int),
    .sgmii_rxp(sgmii_rxp),
    .sgmii_rxn(sgmii_rxn),
    .sgmii_txp(sgmii_txp),
    .sgmii_txn(sgmii_txn),
    .sgmii_refclk_p(sgmii_refclk_p),
    .sgmii_refclk_n(sgmii_refclk_n),
    .phy_reset_n(phy_reset_n),
    .eth_clk_o(eth_clk_o),
    .gtrefclk_bufg_o(gtrefclk_bufg_o),
    .rx_rd_gray(rx_rd_gray), .rx_wr_gray(rx_wr_gray),
    .rx_rd_addr(rx_rd_addr), .rx_rd_data(rx_rd_data),
    .tx_rd_gray(tx_rd_gray), .tx_wr_gray(tx_wr_gray),
    .tx_rd_addr(tx_rd_addr), .tx_rd_data(tx_rd_data),
    .pcspma_status(pcspma_status),
    .rx_fcs_reg(rx_fcs_reg),
    .tx_fcs_reg(tx_fcs_reg),
    .rx_overflow(rx_overflow));

// msoc-side RX FIFO read half (write half + RAM inside the macro)
wire        rxm_rd_en, rxm_empty;
wire [71:0] rxm_data;
async_fifo_rd #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_rxf_rd (
    .rd_clk(msoc_clk), .rd_rst(rst_int),
    .rd_en(rxm_rd_en), .rd_data(rxm_data), .rd_empty(rxm_empty),
    .rd_gray(rx_rd_gray), .wr_gray(rx_wr_gray),
    .rd_addr(rx_rd_addr), .rd_data_mem(rx_rd_data));

// msoc-side TX FIFO write half (read half inside the macro)
wire        txm_wr_en, txm_full;
wire [71:0] txm_wr_data;
async_fifo_wr #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) u_txf_wr (
    .wr_clk(msoc_clk), .wr_rst(rst_int),
    .wr_en(txm_wr_en), .wr_data(txm_wr_data), .wr_full(txm_full),
    .wr_gray(tx_wr_gray), .rd_gray(tx_rd_gray),
    .rd_addr(tx_rd_addr), .rd_data(tx_rd_data));

// ===========================================================================
//  single-clock packet BRAMs (port A = FSM, port B = CPU bus)
// ===========================================================================
logic [7:0] rx_word_addr;
wire [63:0] rx_word;
wire        rx_pop = ~rxm_empty;
assign rxm_rd_en = rx_pop;

wire [63:0] tx_bram_dout;
logic [7:0] tx_raddr;
wire        tx_bram_en;

dualmem64 #(.ADDR_WIDTH(13)) RAMB16_inst_rx (
    .clka(msoc_clk),
    .dina(rx_word),
    .addra({nextbuf[4:0], rx_word_addr}),
    .wea({2{rx_pop}}),
    .ena(rx_pop),
    .douta(),
    .clkb(msoc_clk),
    .dinb(core_lsu_wdata),
    .addrb(core_lsu_addr[15:3]),
    .web(we_d ? {(|core_lsu_be[7:4]),(|core_lsu_be[3:0])} : 2'b0),
    .enb(ce_d & framing_sel & core_lsu_addr[16]),   // RX buffers at 0x10000
    .doutb(framing_rdata_pkt));

dualmem64 #(.ADDR_WIDTH(9)) RAMB16_inst_tx (
    .clka(msoc_clk),
    .dina(64'b0),
    .addra({1'b0, tx_raddr}),
    .wea(2'b0),
    .ena(tx_bram_en),
    .douta(tx_bram_dout),
    .clkb(msoc_clk),
    .dinb(core_lsu_wdata),
    .addrb(core_lsu_addr[11:3]),
    .web(we_d ? {(|core_lsu_be[7:4]),(|core_lsu_be[3:0])} : 2'b0),
    .enb(ce_d & framing_sel & (core_lsu_addr[16:12]==5'b00001)), // TX at 0x1000
    .doutb(framing_wdata_pkt));

// ===========================================================================
//  RX drain FSM (msoc_clk): FIFO word -> BRAM, filter + length bookkeeping
// ===========================================================================
logic [47:0] rx_dest_mac;

// unpack the head word's byte slots
wire [8:0] rs [0:7];
genvar gi;
generate for (gi = 0; gi < 8; gi = gi + 1) begin : rslot
    assign rs[gi] = rxm_data[gi*9 +: 9];
end endgenerate
assign rx_word = {rs[7][7:0],rs[6][7:0],rs[5][7:0],rs[4][7:0],
                  rs[3][7:0],rs[2][7:0],rs[1][7:0],rs[0][7:0]};

wire       rx_has_tlast = rs[0][8]|rs[1][8]|rs[2][8]|rs[3][8]|rs[4][8]|rs[5][8]|rs[6][8]|rs[7][8];
wire [2:0] rx_tpos = rs[0][8] ? 3'd0 : rs[1][8] ? 3'd1 : rs[2][8] ? 3'd2 :
                     rs[3][8] ? 3'd3 : rs[4][8] ? 3'd4 : rs[5][8] ? 3'd5 :
                     rs[6][8] ? 3'd6 : 3'd7;
wire [10:0] rx_len = {rx_word_addr, 3'b000} + rx_tpos + 1'b1;

// dest MAC: first 6 bytes of the frame, first byte = MSB (matches old shift)
wire [47:0] rx_dmac_now = {rs[0][7:0],rs[1][7:0],rs[2][7:0],rs[3][7:0],rs[4][7:0],rs[5][7:0]};
wire [47:0] rx_dmac_eff = (rx_word_addr == 0) ? rx_dmac_now : rx_dest_mac;
wire        rx_accept = (rx_dmac_eff[47:24]==24'h01005E) | (&rx_dmac_eff) |
                        (mac_address == rx_dmac_eff) | promiscuous;
// same buffer-availability expression as the pre-split design
wire        rx_room = nextbuf != (firstbuf+lastbuf)&31;

always @(posedge msoc_clk)
  if (rst_int)
    begin
       rx_word_addr <= 'b0;
       rx_dest_mac <= 'b0;
       sync <= 1'b0;
    end
  else if (rx_pop)
    begin
       if (rx_word_addr == 0)
         rx_dest_mac <= rx_dmac_now;
       if (rx_has_tlast)
         begin
            rx_word_addr <= 'b0;
            sync <= rx_accept & rx_room;   // readback visibility only
         end
       else
         rx_word_addr <= rx_word_addr + 1'b1;
    end

// ===========================================================================
//  TX push FSM (msoc_clk): BRAM word -> FIFO with tlast flags
// ===========================================================================
logic       tx_active, tx_pend_v;
logic [7:0] tx_pend_addr;
wire [7:0]  tx_words_total = (tx_packet_length + 11'd7) >> 3;
wire        tx_stall = tx_pend_v & txm_full;
assign      tx_bram_en = tx_active & ~tx_stall;

// pack BRAM word + tlast flags for the FIFO
wire [10:0] tx_gbase = {tx_pend_addr, 3'b000};
generate for (gi = 0; gi < 8; gi = gi + 1) begin : tslot
    assign txm_wr_data[gi*9 +: 9] = {(tx_gbase + gi) == (tx_packet_length - 1'b1),
                                     tx_bram_dout[gi*8 +: 8]};
end endgenerate
assign txm_wr_en = tx_pend_v & ~txm_full;

wire tx_start = framing_sel & we_d & (&core_lsu_be[3:0]) &
                (core_lsu_addr[16:11]==6'b000001) & (core_lsu_addr[6:3]==4'd2);
wire tx_abort = framing_sel & we_d & (&core_lsu_be[3:0]) &
                (core_lsu_addr[16:11]==6'b000001) & (core_lsu_addr[6:3]==4'd3);

// tx_busy: FSM active or FIFO not yet drained by the macro
logic [5:0] tx_rd_gray_sync1, tx_rd_gray_sync2;
wire tx_fifo_busy = (tx_wr_gray != tx_rd_gray_sync2);
wire tx_busy = tx_active | tx_fifo_busy;

always @(posedge msoc_clk)
  if (rst_int)
    begin
       tx_active <= 1'b0;
       tx_pend_v <= 1'b0;
       tx_raddr <= 'b0;
       tx_pend_addr <= 'b0;
       tx_rd_gray_sync1 <= 'b0;
       tx_rd_gray_sync2 <= 'b0;
    end
  else
    begin
       tx_rd_gray_sync1 <= tx_rd_gray;
       tx_rd_gray_sync2 <= tx_rd_gray_sync1;
       if (tx_start)
         begin
            tx_active <= 1'b1;
            tx_pend_v <= 1'b0;
            tx_raddr <= 'b0;
         end
       else if (tx_abort)
         begin
            tx_active <= 1'b0;
            tx_pend_v <= 1'b0;
         end
       else if (tx_active & (tx_words_total == 0))
         tx_active <= 1'b0;               // zero-length start: nothing to send
       else if (tx_active & ~tx_stall)
         begin
            // stage 0: issue BRAM read
            tx_pend_v <= (tx_raddr < tx_words_total);
            tx_pend_addr <= tx_raddr;
            if (tx_raddr < tx_words_total)
              tx_raddr <= tx_raddr + 1'b1;
            // stage 1: word for tx_pend_addr pushed this cycle (txm_wr_en)
            if (tx_pend_v & (tx_pend_addr == tx_words_total - 1'b1))
              begin
                 tx_active <= 1'b0;
                 tx_pend_v <= 1'b0;
              end
         end
    end

// ===========================================================================
//  CSRs (register map unchanged)
// ===========================================================================
always @(posedge msoc_clk)
  if (rst_int)
    begin
    core_lsu_addr_dly <= 0;
    mac_address <= 48'H230100890702;
    tx_packet_length <= 0;
    cooked <= 1'b0;
    loopback <= 1'b0;
    spare <= 4'b0;
    promiscuous <= 1'b0;
    phy_mdio_oe <= 1'b0;
    phy_mdio_o <= 1'b0;
    phy_mdclk <= 1'b0;
    firstbuf <= 5'b0;
    lastbuf <= 5'b0;
    nextbuf <= 5'b0;
    eth_irq <= 1'b0;
    irq_en <= 1'b0;
    ce_d_dly <= 1'b0;
    avail = 1'b0;
    end
  else
    begin
    core_lsu_addr_dly <= core_lsu_addr;
    ce_d_dly <= ce_d;
    avail = nextbuf != firstbuf;
    eth_irq <= avail & irq_en; // make eth_irq go away immediately if irq_en is low
    if (rx_pop & rx_has_tlast & rx_accept & rx_room)
      nextbuf <= nextbuf + 1'b1;
    if (framing_sel&we_d&(&core_lsu_be[3:0])&(core_lsu_addr[16:11]==6'b000001))
      case(core_lsu_addr[6:3])
        0: mac_address[31:0] <= core_lsu_wdata;
        1: {irq_en,promiscuous,spare,loopback,cooked,mac_address[47:32]} <= core_lsu_wdata;
        2: begin tx_packet_length <= core_lsu_wdata; end /* tx payload size; starts push FSM */
        3: begin tx_packet_length <= 0; end             /* abort */
        4: begin {phy_mdio_oe,phy_mdio_o,phy_mdclk} <= core_lsu_wdata; end
        5: begin lastbuf <= core_lsu_wdata[4:0]; end
        6: begin firstbuf <= core_lsu_wdata[4:0]; end
        default:;
      endcase
    end

   always @* casez({ce_d_dly,core_lsu_addr_dly[16:3]})
    15'b100_0001_0???_0000 : framing_rdata = mac_address[31:0];                                        // 0x0800
    15'b100_0001_0???_0001 : framing_rdata = {irq_en, promiscuous, spare, loopback, cooked, mac_address[47:32]}; // 0x0808
    15'b100_00??_????_0010 : framing_rdata = {tx_busy, 4'b0, tx_pend_addr, 3'b0, 5'b0, tx_packet_length}; // 0x0810
    15'b100_0001_0???_0011 : framing_rdata = tx_fcs_reg_rev;                                           // 0x0818
    15'b100_0001_0???_0100 : framing_rdata = {phy_mdio_i,phy_mdio_oe,phy_mdio_o,phy_mdclk};           // 0x0820
    15'b100_0001_0???_0101 : framing_rdata = rx_fcs_reg_rev;                                           // 0x0828
    15'b100_0001_0???_0110 : framing_rdata = {rx_overflow, sync, eth_irq, avail, lastbuf, nextbuf, firstbuf}; // 0x0830
    15'b100_0001_1??_????? : framing_rdata = rx_length_rd;                                             // 0x0C00 RPLR (32 entries)
    15'b100_001?_???????? : framing_rdata = framing_wdata_pkt;                                           // 0x1000 TX buffer
    15'b1_1?_????????????  : framing_rdata = framing_rdata_pkt;                                         // 0x10000 RX buffers (64KB)
    default: framing_rdata = 'h0;
    endcase

   assign 	    tx_fcs_reg_rev = {tx_fcs_reg[0],tx_fcs_reg[1],tx_fcs_reg[2],tx_fcs_reg[3],
                                          tx_fcs_reg[4],tx_fcs_reg[5],tx_fcs_reg[6],tx_fcs_reg[7],
                                          tx_fcs_reg[8],tx_fcs_reg[9],tx_fcs_reg[10],tx_fcs_reg[11],
                                          tx_fcs_reg[12],tx_fcs_reg[13],tx_fcs_reg[14],tx_fcs_reg[15],
                                          tx_fcs_reg[16],tx_fcs_reg[17],tx_fcs_reg[18],tx_fcs_reg[19],
                                          tx_fcs_reg[20],tx_fcs_reg[21],tx_fcs_reg[22],tx_fcs_reg[23],
                                          tx_fcs_reg[24],tx_fcs_reg[25],tx_fcs_reg[26],tx_fcs_reg[27],
                                          tx_fcs_reg[28],tx_fcs_reg[29],tx_fcs_reg[30],tx_fcs_reg[31]};
   assign 	    rx_fcs_reg_rev = {rx_fcs_reg[0],rx_fcs_reg[1],rx_fcs_reg[2],rx_fcs_reg[3],
                                          rx_fcs_reg[4],rx_fcs_reg[5],rx_fcs_reg[6],rx_fcs_reg[7],
                                          rx_fcs_reg[8],rx_fcs_reg[9],rx_fcs_reg[10],rx_fcs_reg[11],
                                          rx_fcs_reg[12],rx_fcs_reg[13],rx_fcs_reg[14],rx_fcs_reg[15],
                                          rx_fcs_reg[16],rx_fcs_reg[17],rx_fcs_reg[18],rx_fcs_reg[19],
                                          rx_fcs_reg[20],rx_fcs_reg[21],rx_fcs_reg[22],rx_fcs_reg[23],
                                          rx_fcs_reg[24],rx_fcs_reg[25],rx_fcs_reg[26],rx_fcs_reg[27],
                                          rx_fcs_reg[28],rx_fcs_reg[29],rx_fcs_reg[30],rx_fcs_reg[31]};

// ---- RPLR storage: 32 x 11 dual-port LUTRAM ------------------------------
// (explicit RAM32X1D under yosys: nextpnr's whole-slice RAM32M clusters get
// split by SA placement — same workaround as async_fifo storage)
wire rplr_we = rx_pop & rx_has_tlast & rx_accept & rx_room;
`ifdef YOSYS
genvar grl;
generate for (grl = 0; grl < 11; grl = grl + 1) begin : rplr
    RAM32X1D #(.INIT(32'b0)) r (
        .WCLK(msoc_clk), .WE(rplr_we), .D(rx_len[grl]),
        .A0(nextbuf[0]), .A1(nextbuf[1]), .A2(nextbuf[2]),
        .A3(nextbuf[3]), .A4(nextbuf[4]),
        .DPRA0(core_lsu_addr_dly[3]), .DPRA1(core_lsu_addr_dly[4]),
        .DPRA2(core_lsu_addr_dly[5]), .DPRA3(core_lsu_addr_dly[6]),
        .DPRA4(core_lsu_addr_dly[7]),
        .DPO(rx_length_rd[grl]), .SPO());
end endgenerate
`else
logic [10:0] rx_length_axis[0:31];
always @(posedge msoc_clk)
    if (rplr_we)
        rx_length_axis[nextbuf] <= rx_len;
assign rx_length_rd = rx_length_axis[core_lsu_addr_dly[7:3]];
`endif

assign pcspma_status_o = pcspma_status;

endmodule // framing_top_sgmii
`default_nettype wire
