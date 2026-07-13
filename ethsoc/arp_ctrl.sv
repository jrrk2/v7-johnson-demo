// arp_ctrl.sv — standalone Ethernet ARP responder.
//
// State machine extracted from cva6 heavyhash/mine_ctrl.sv: same framing_top
// bus interface (RX/TX BRAM + MAC registers), same poll->read->build->send->
// advance skeleton, but the HeavyHash mining payload is replaced with an ARP
// request matcher + ARP reply generator.  No CPU, no register file.
//
// Answers ARP "who-has FPGA_IP" broadcasts with an ARP reply carrying FPGA_MAC,
// so the board becomes pingable / visible in the host ARP table.  Minimal
// exercise of the full framing_top RX+TX datapath.
//
// framing_top register map (same as vc707_ethloop's framing_top_sgmii):
//   0x00800 mac_address[31:0]        0x00808 mac_address[47:32]+flags
//   0x00810 tx trigger (wr) / tx_busy bit31 (rd)   0x00828 lastbuf
//   0x00830 rx status (rd: avail bit15, buf[4:0]) / advance (wr firstbuf+1)
//   0x00C00 + buf*8  rx_length[buf]  (fcs_err bit11, len[10:0])
//   0x10000 | buf<<11 | word<<3      RX BRAM (64-bit LE words)
//   0x01000 | txbuf<<11 | word<<3    TX BRAM (double-buffered)
//
// BRAM byte order: frame byte N -> word N/8, bits [(N%8)*8 +: 8].
// Bus: registered outputs -> 2-cycle read latency (assert ce_d, wait, capture).

`default_nettype none

module arp_ctrl #(
    parameter logic [47:0] FPGA_MAC = 48'h02_00_00_4B_41_31,
    parameter logic [31:0] FPGA_IP  = 32'hC0_A8_01_64   // 192.168.1.100
) (
    input  wire         clk,
    input  wire         rst_n,

    // framing_top bus (directly replaces CPU LSU)
    output logic [16:0] core_lsu_addr,
    output logic [63:0] core_lsu_wdata,
    output logic [7:0]  core_lsu_be,
    output logic        ce_d,
    output logic        we_d,
    output logic        framing_sel,
    input  wire  [63:0] framing_rdata,

    // status
    output logic        led_arp,          // toggles on each reply sent
    output logic [15:0] reply_count,      // ARP replies sent
    output logic [3:0]  dbg_state
);
    // ----------------------------------------------------------------
    localparam [15:0] ETH_ARP  = 16'h0806;
    localparam [15:0] ARP_REQ  = 16'h0001;
    localparam [15:0] ARP_REPL = 16'h0002;

    typedef enum logic [3:0] {
      S_INIT, S_IDLE, S_POLL_WAIT, S_POLL_DONE,
      S_LEN_WAIT, S_LEN_DONE, S_FRAME_WAIT, S_FRAME_PROC,
      S_TX_WR, S_TX_WAIT, S_TX_WAIT_DONE, S_TX_GO, S_ADV_BUF, S_DONE
    } state_t;
    state_t state;

    logic [1:0]  init_step;
    logic [7:0]  wcnt;
    logic [4:0]  cur_buf;
    logic        tx_buf;

    // captured ARP request fields
    logic [47:0] sender_mac;    // = eth src / ARP sha
    logic [31:0] sender_ip;     // ARP spa
    logic [31:0] target_ip;     // ARP tpa (must == FPGA_IP)
    logic [15:0] etype, oper;
    logic [63:0] saved_w0;
    logic        is_arp_req;

    // ---- address helpers ----
    function automatic logic [16:0] rx_addr(logic [4:0] b, logic [7:0] w);
      rx_addr = {1'b1, b, w, 3'b000};
    endfunction
    function automatic logic [16:0] len_addr(logic [4:0] b);
      len_addr = {9'b0_0000_1100, b, 3'b000};
    endfunction

    // ---- TX word generator (ARP reply, LE byte order into 64-bit words) ----
    // reply: dst=sender_mac src=FPGA_MAC etype=0806 htype=1 ptype=0800 hlen=6
    //        plen=4 oper=2 sha=FPGA_MAC spa=FPGA_IP tha=sender_mac tpa=sender_ip
    logic [63:0] tx_word;
    always_comb begin
      tx_word = '0;
      case (wcnt)
        8'd0: // bytes 0-7: dst[0:5]=sender_mac, src[0:1]=FPGA_MAC[0:1]
          tx_word = {FPGA_MAC[39:32], FPGA_MAC[47:40],
                     sender_mac[7:0],  sender_mac[15:8], sender_mac[23:16],
                     sender_mac[31:24],sender_mac[39:32],sender_mac[47:40]};
        8'd1: // bytes 8-15: src[2:5]=FPGA_MAC[2:5], etype=0806, htype=0001
          tx_word = {8'h01, 8'h00, 8'h06, 8'h08,
                     FPGA_MAC[7:0], FPGA_MAC[15:8], FPGA_MAC[23:16], FPGA_MAC[31:24]};
        8'd2: // bytes 16-23: ptype=0800, hlen=6, plen=4, oper=0002, sha[0:1]
          tx_word = {FPGA_MAC[39:32], FPGA_MAC[47:40],
                     8'h02, 8'h00, 8'h04, 8'h06, 8'h00, 8'h08};
        8'd3: // bytes 24-31: sha[2:5]=FPGA_MAC[2:5], spa[0:3]=FPGA_IP
          tx_word = {FPGA_IP[7:0], FPGA_IP[15:8], FPGA_IP[23:16], FPGA_IP[31:24],
                     FPGA_MAC[7:0], FPGA_MAC[15:8], FPGA_MAC[23:16], FPGA_MAC[31:24]};
        8'd4: // bytes 32-39: tha[0:5]=sender_mac, tpa[0:1]=sender_ip[0:1]
          tx_word = {sender_ip[23:16], sender_ip[31:24],
                     sender_mac[7:0],  sender_mac[15:8], sender_mac[23:16],
                     sender_mac[31:24],sender_mac[39:32],sender_mac[47:40]};
        8'd5: // bytes 40-47: tpa[2:3]=sender_ip[2:3], pad
          tx_word = {48'd0, sender_ip[7:0], sender_ip[15:8]};
        default: tx_word = '0;
      endcase
    end
    localparam [7:0] ARP_TX_BYTES = 8'd42;   // 14 eth + 28 arp (MAC pads to 60)
    localparam [7:0] ARP_TX_WORDS = 8'd6;    // words 0-5

    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        state <= S_INIT; init_step <= 0;
        ce_d <= 0; we_d <= 0; framing_sel <= 1'b1;
        core_lsu_addr <= '0; core_lsu_wdata <= '0; core_lsu_be <= 8'hFF;
        wcnt <= 0; cur_buf <= 0; tx_buf <= 0;
        sender_mac <= '0; sender_ip <= '0; target_ip <= '0;
        etype <= '0; oper <= '0; saved_w0 <= '0; is_arp_req <= 0;
        led_arp <= 0; reply_count <= 0;
      end else begin
        case (state)
          // ---- init: MAC, promiscuous, lastbuf ----
          S_INIT: begin
            ce_d <= 1'b1; we_d <= 1'b1;
            case (init_step)
              2'd0: begin core_lsu_addr <= 17'h00800;
                          core_lsu_wdata <= {32'd0, FPGA_MAC[31:0]};
                          init_step <= 2'd1; end
              2'd1: begin core_lsu_addr <= 17'h00808;
                          core_lsu_wdata <= {40'd0, 1'b0, 1'b1, 4'b0, 1'b0, 1'b0, FPGA_MAC[47:32]};
                          init_step <= 2'd2; end
              2'd2: begin core_lsu_addr <= 17'h00828;
                          core_lsu_wdata <= {59'd0, 5'd31};
                          init_step <= 2'd3; end
              default: begin ce_d <= 0; we_d <= 0; state <= S_IDLE; end
            endcase
          end

          // ---- poll for an RX frame ----
          S_IDLE: begin
            ce_d <= 1'b1; we_d <= 1'b0;
            core_lsu_addr <= 17'h00830;
            state <= S_POLL_WAIT;
          end
          S_POLL_WAIT: state <= S_POLL_DONE;
          S_POLL_DONE: begin
            if (framing_rdata[15]) begin
              cur_buf <= framing_rdata[4:0];
              ce_d <= 1'b1; we_d <= 1'b0;
              core_lsu_addr <= len_addr(framing_rdata[4:0]);
              state <= S_LEN_WAIT;
            end else state <= S_IDLE;
          end

          // ---- length + FCS ----
          S_LEN_WAIT: state <= S_LEN_DONE;
          S_LEN_DONE: begin
            if (framing_rdata[11]) begin          // bad FCS -> drop
              state <= S_ADV_BUF;
            end else begin
              wcnt <= 8'd0; is_arp_req <= 1'b0;
              ce_d <= 1'b1; we_d <= 1'b0;
              core_lsu_addr <= rx_addr(cur_buf, 8'd0);
              state <= S_FRAME_WAIT;
            end
          end

          // ---- read header words 0..5, extract ARP fields ----
          S_FRAME_WAIT: state <= S_FRAME_PROC;
          S_FRAME_PROC: begin
            case (wcnt)
              8'd0: begin  // dst[0:5], src[0:1]
                saved_w0 <= framing_rdata;
                wcnt <= 8'd1;
                ce_d <= 1'b1; we_d <= 1'b0;
                core_lsu_addr <= rx_addr(cur_buf, 8'd1);
                state <= S_FRAME_WAIT;
              end
              8'd1: begin  // src[2:5], etype, htype
                sender_mac[47:40] <= saved_w0[55:48];
                sender_mac[39:32] <= saved_w0[63:56];
                sender_mac[31:24] <= framing_rdata[7:0];
                sender_mac[23:16] <= framing_rdata[15:8];
                sender_mac[15:8]  <= framing_rdata[23:16];
                sender_mac[7:0]   <= framing_rdata[31:24];
                etype <= {framing_rdata[39:32], framing_rdata[47:40]};
                if ({framing_rdata[39:32], framing_rdata[47:40]} != ETH_ARP)
                  state <= S_ADV_BUF;                 // not ARP
                else begin
                  wcnt <= 8'd2;
                  ce_d <= 1'b1; we_d <= 1'b0;
                  core_lsu_addr <= rx_addr(cur_buf, 8'd2);
                  state <= S_FRAME_WAIT;
                end
              end
              8'd2: begin  // ptype, hlen, plen, oper, sha[0:1]
                oper <= {framing_rdata[39:32], framing_rdata[47:40]};
                if ({framing_rdata[39:32], framing_rdata[47:40]} != ARP_REQ)
                  state <= S_ADV_BUF;                 // not a request
                else begin
                  wcnt <= 8'd3;
                  ce_d <= 1'b1; we_d <= 1'b0;
                  core_lsu_addr <= rx_addr(cur_buf, 8'd3);
                  state <= S_FRAME_WAIT;
                end
              end
              8'd3: begin  // sha[2:5], spa[0:3] (sender IP)
                sender_ip <= {framing_rdata[39:32], framing_rdata[47:40],
                              framing_rdata[55:48], framing_rdata[63:56]};
                wcnt <= 8'd4;
                ce_d <= 1'b1; we_d <= 1'b0;
                core_lsu_addr <= rx_addr(cur_buf, 8'd4);
                state <= S_FRAME_WAIT;
              end
              8'd4: begin  // tha[0:5], tpa[0:1]
                target_ip[31:24] <= framing_rdata[55:48];  // byte 38
                target_ip[23:16] <= framing_rdata[63:56];  // byte 39
                wcnt <= 8'd5;
                ce_d <= 1'b1; we_d <= 1'b0;
                core_lsu_addr <= rx_addr(cur_buf, 8'd5);
                state <= S_FRAME_WAIT;
              end
              8'd5: begin  // tpa[2:3]
                // full target IP now known; decide
                if ({target_ip[31:16], framing_rdata[7:0], framing_rdata[15:8]} == FPGA_IP) begin
                  is_arp_req <= 1'b1;
                  wcnt <= 8'd0;
                  state <= S_TX_WR;                   // build + send reply
                end else
                  state <= S_ADV_BUF;
              end
              default: state <= S_ADV_BUF;
            endcase
          end

          // ---- write ARP reply words to TX BRAM (double-buffered) ----
          S_TX_WR: begin
            ce_d <= 1'b1; we_d <= 1'b1;
            core_lsu_addr <= {4'b0, 1'b1, tx_buf, 4'b0, wcnt[3:0], 3'b000};
            core_lsu_wdata <= tx_word;
            if (wcnt + 1 >= ARP_TX_WORDS) begin
              wcnt <= 8'd0; state <= S_TX_WAIT;
            end else begin
              wcnt <= wcnt + 1; state <= S_TX_WR;
            end
          end
          S_TX_WAIT: begin
            ce_d <= 1'b1; we_d <= 1'b0;
            core_lsu_addr <= 17'h00810;
            state <= S_TX_WAIT_DONE;
          end
          S_TX_WAIT_DONE: begin
            if (framing_rdata[31]) begin              // tx_busy
              ce_d <= 1'b1; we_d <= 1'b0;
              core_lsu_addr <= 17'h00810;
              state <= S_TX_WAIT;
            end else state <= S_TX_GO;
          end
          S_TX_GO: begin
            ce_d <= 1'b1; we_d <= 1'b1;
            core_lsu_addr <= 17'h00810;
            core_lsu_wdata <= {52'd0, tx_buf, 3'd0, ARP_TX_BYTES};
            tx_buf <= ~tx_buf;
            reply_count <= reply_count + 1;
            led_arp <= ~led_arp;
            state <= S_ADV_BUF;
          end

          // ---- advance RX buffer ----
          S_ADV_BUF: begin
            ce_d <= 1'b1; we_d <= 1'b1;
            core_lsu_addr <= 17'h00830;
            core_lsu_wdata <= {59'd0, cur_buf + 5'd1};
            state <= S_DONE;
          end
          S_DONE: begin
            ce_d <= 1'b0; we_d <= 1'b0;
            state <= S_IDLE;
          end
          default: state <= S_IDLE;
        endcase
      end
    end

    assign dbg_state = state;
endmodule

`default_nettype wire
