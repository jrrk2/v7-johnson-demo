// Replicates uartram's OUTPUT half exactly (no calc_core): a generator pushes
// 'A' then (7 cycles later) 'B' into byte_fifo every ~2ms; the SAME APB-master
// drain logic as uartram (write outf_dout to THR on THRE & !empty, then pop)
// sends them.  Host should see "ABABAB..." if the fifo+drain path is reliable.
module top (input wire sysclk_p, sysclk_n, rst, output wire tx, output wire [7:0] led);
    wire clk_raw, clk, rst_buf, tx_int;
    IBUFDS #(.DIFF_TERM("TRUE"),.IBUF_LOW_PWR("FALSE"),.IOSTANDARD("LVDS")) ib(.I(sysclk_p),.IB(sysclk_n),.O(clk_raw));
    BUFG bg(.I(clk_raw),.O(clk));
    IBUF ir(.I(rst),.O(rst_buf));
    reg psel,penable,pwrite; reg [2:0] paddr; reg [7:0] pwdata; wire [31:0] prdata;
    apb_uart uart(.CLK(clk),.RSTN(~rst_buf),.PSEL(psel),.PENABLE(penable),.PWRITE(pwrite),
        .PADDR(paddr),.PWDATA({24'b0,pwdata}),.PRDATA(prdata),.PREADY(),.PSLVERR(),
        .INT(),.OUT1N(),.OUT2N(),.RTSN(),.DTRN(),.CTSN(1'b1),.DSRN(1'b1),.DCDN(1'b1),.RIN(1'b1),
        .SIN(1'b1),.SOUT(tx_int));
    // ---- output fifo + generator (mimics calc_core's two pushes 7 cyc apart) ----
    wire outf_empty, outf_full; wire [7:0] outf_dout;
    reg gen_wr; reg [7:0] gen_din; reg outf_rd;
    byte_fifo outfifo(.clk(clk),.rst(rst_buf),.wr(gen_wr),.din(gen_din),.full(outf_full),
        .rd(outf_rd),.dout(outf_dout),.empty(outf_empty));
    reg [21:0] gtmr; reg [3:0] gst;
    always @(posedge clk or posedge rst_buf)
      if(rst_buf) begin gtmr<=0; gst<=0; gen_wr<=0; gen_din<=0; end
      else begin
        gen_wr<=0; gtmr<=gtmr+22'd1;
        case(gst)
          0: if(gtmr==22'd0) begin gen_din<=8'h41; gen_wr<=1; gst<=1; end // push 'A'
          1: if(gtmr==22'd7) begin gen_din<=8'h42; gen_wr<=1; gst<=2; end // push 'B' 7 cyc later
          2: if(gtmr==22'h3FFFFF) begin gtmr<=0; gst<=0; end              // ~21ms, repeat
          default: gst<=0;
        endcase
      end
    // ---- APB master: identical drain logic to uartram ----
    localparam S_LCR1=0,S_DLL=1,S_DLM=2,S_LCR2=3,S_FCR=4,S_LSR=5,S_THR=7;
    reg [2:0] st; reg ph;
    always @* begin
        psel=1; penable=ph; pwrite=0; paddr=3'b101; pwdata=8'h00;
        case(st)
          S_LCR1: begin pwrite=1;paddr=3'b011;pwdata=8'h83; end
          S_DLL:  begin pwrite=1;paddr=3'b000;pwdata=8'd109; end
          S_DLM:  begin pwrite=1;paddr=3'b001;pwdata=8'd0; end
          S_LCR2: begin pwrite=1;paddr=3'b011;pwdata=8'h03; end
          S_FCR:  begin pwrite=1;paddr=3'b010;pwdata=8'h07; end
          S_LSR:  begin pwrite=0;paddr=3'b101; end
          S_THR:  begin pwrite=1;paddr=3'b000;pwdata=outf_dout; end
        endcase
    end
    always @(posedge clk or posedge rst_buf)
      if(rst_buf) begin st<=S_LCR1; ph<=0; outf_rd<=0; end
      else begin outf_rd<=0;
        if(ph==0) ph<=1;
        else begin ph<=0;
          case(st)
            S_LCR1:st<=S_DLL; S_DLL:st<=S_DLM; S_DLM:st<=S_LCR2; S_LCR2:st<=S_FCR; S_FCR:st<=S_LSR;
            S_LSR: if(prdata[5] && !outf_empty) st<=S_THR; else st<=S_LSR;
            S_THR: begin outf_rd<=1; st<=S_LSR; end
            default: st<=S_LSR;
          endcase
        end
      end
    assign led=outf_dout;
    OBUF ot(.I(tx_int),.O(tx));
endmodule
