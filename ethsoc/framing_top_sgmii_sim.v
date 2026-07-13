// Behavioral model of framing_top_sgmii's msoc_clk register/buffer interface
// ONLY (no PHY), matching the real RTL's 2-cycle read latency: framing_rdata
// is valid when ce_d_dly (registered ce_d) is high, using addr_dly and the
// registered BRAM output.  Lets the TB inject an RX packet and observe TX.
`default_nettype none
module framing_top_sgmii
  (input wire msoc_clk, input wire [16:0] core_lsu_addr,
   input wire [63:0] core_lsu_wdata, input wire [7:0] core_lsu_be,
   input wire ce_d, we_d, framing_sel, output reg [63:0] framing_rdata,
   input wire clk_int, rst_int, sgmii_rxp, sgmii_rxn,
   output wire sgmii_txp, sgmii_txn, input wire sgmii_refclk_p, sgmii_refclk_n,
   output wire phy_reset_n, input wire phy_mdio_i, output reg phy_mdio_o,
   output reg phy_mdio_oe, output wire phy_mdc, output reg eth_irq,
   output wire [15:0] pcspma_status_o, output wire eth_clk_o,
   output wire gtrefclk_bufg_o);

  reg [4:0]  firstbuf=0, nextbuf=0, lastbuf=0;
  reg [47:0] mac=0;
  reg [10:0] tx_packet_length=0;
  reg        tx_busy=0;
  reg [7:0]  txcd=0;
  reg [7:0]  rx_mem [0:32*2048-1];
  reg [10:0] rx_len  [0:31];
  reg [7:0]  tx_mem [0:4095];
  integer    twords=0;              // count of TX triggers

  task inject_rx(input [4:0] b, input integer len); begin
     rx_len[b] = len; nextbuf = b + 1;
  end endtask

  wire avail = nextbuf != firstbuf;

  reg        ce_dly;
  reg [16:0] addr_dly;
  reg [63:0] rx_doutb, tx_doutb;
  integer rxa, txa;
  always @(posedge msoc_clk) begin
     ce_dly   <= ce_d;
     addr_dly <= core_lsu_addr;
     rxa = {core_lsu_addr[15:3], 3'b000};
     rx_doutb <= {rx_mem[rxa+7],rx_mem[rxa+6],rx_mem[rxa+5],rx_mem[rxa+4],
                  rx_mem[rxa+3],rx_mem[rxa+2],rx_mem[rxa+1],rx_mem[rxa+0]};
     txa = {core_lsu_addr[11:3], 3'b000};
     tx_doutb <= {tx_mem[txa+7],tx_mem[txa+6],tx_mem[txa+5],tx_mem[txa+4],
                  tx_mem[txa+3],tx_mem[txa+2],tx_mem[txa+1],tx_mem[txa+0]};
  end

  always @* begin
     framing_rdata = 64'h0;
     if (ce_dly) begin
        if (addr_dly[16])                                       // 0x10000+ RX
           framing_rdata = rx_doutb;
        else if (addr_dly[16:12]==5'b00001)                     // 0x1000 TX
           framing_rdata = tx_doutb;
        else if (addr_dly[16:8]==9'h00C)                        // 0xC00 RPLR[32]
           framing_rdata = rx_len[addr_dly[7:3]];
        else if (addr_dly[16:3]==(17'h00830>>3))                // 0x830 RSR
           framing_rdata = {eth_irq,avail,lastbuf,nextbuf,firstbuf};
        else if (addr_dly[16:3]==(17'h00810>>3))                // 0x810 TPLR
           framing_rdata = {tx_busy,20'b0,tx_packet_length};
     end
  end

  wire [31:0] wlo = core_lsu_wdata[31:0];
  always @(posedge msoc_clk) begin
     if (rst_int) begin firstbuf<=0; tx_busy<=0; txcd<=0; end
     else begin
        if (txcd>0) begin txcd<=txcd-8'd1; if (txcd==8'd1) tx_busy<=0; end
        if (framing_sel & we_d) begin
           if (core_lsu_addr[16]) begin
              // RX buffer write (unused)
           end else if (core_lsu_addr[16:12]==5'b00001) begin
              txa = {core_lsu_addr[11:3],3'b000};
              if (core_lsu_be[3:0]!=0) begin
                 tx_mem[txa+0]<=core_lsu_wdata[7:0];   tx_mem[txa+1]<=core_lsu_wdata[15:8];
                 tx_mem[txa+2]<=core_lsu_wdata[23:16]; tx_mem[txa+3]<=core_lsu_wdata[31:24];
              end
              if (core_lsu_be[7:4]!=0) begin
                 tx_mem[txa+4]<=core_lsu_wdata[39:32]; tx_mem[txa+5]<=core_lsu_wdata[47:40];
                 tx_mem[txa+6]<=core_lsu_wdata[55:48]; tx_mem[txa+7]<=core_lsu_wdata[63:56];
              end
           end else if ((&core_lsu_be[3:0]) & (core_lsu_addr[16:11]==6'b000001)) begin
              case (core_lsu_addr[6:3])
                0: mac[31:0]  <= wlo;
                1: mac[47:32] <= wlo[15:0];
                2: begin tx_packet_length<=wlo; tx_busy<=1; txcd<=8'd40;
                         twords<=twords+1; end
                3: tx_packet_length<=0;
                5: lastbuf  <= wlo[4:0];
                6: firstbuf <= wlo[4:0];
              endcase
           end
        end
     end
  end

  assign sgmii_txp=0; assign sgmii_txn=0; assign phy_reset_n=1; assign phy_mdc=0;
  assign pcspma_status_o=16'hFFFF; assign eth_clk_o=0; assign gtrefclk_bufg_o=0;
  initial begin phy_mdio_o=0; phy_mdio_oe=0; eth_irq=0; end
endmodule
`default_nettype wire
