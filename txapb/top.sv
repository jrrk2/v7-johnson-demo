// Minimal isolation: init apb_uart, then write an incrementing counter to THR
// whenever LSR.THRE is set.  No calc_core, no FIFO, no program load.  Host should
// see a clean 0,1,2,... stream if the apb_uart-via-APB TX path is reliable.
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
    reg [7:0] cnt; reg [20:0] dly;
    localparam S_LCR1=0,S_DLL=1,S_DLM=2,S_LCR2=3,S_FCR=4,S_LSR=5,S_THR=6,S_DLY=7;
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
          S_THR:  begin pwrite=1;paddr=3'b000;pwdata=cnt; end
        endcase
    end
    always @(posedge clk or posedge rst_buf)
      if(rst_buf) begin st<=S_LCR1; ph<=0; cnt<=0; end
      else begin
        if(st==S_DLY && dly!=0) dly<=dly-21'd1;
        if(ph==0) ph<=1;
        else begin ph<=0;
          case(st)
            S_LCR1:st<=S_DLL; S_DLL:st<=S_DLM; S_DLM:st<=S_LCR2; S_LCR2:st<=S_FCR; S_FCR:st<=S_LSR;
            S_LSR: if(prdata[5]) st<=S_THR; else st<=S_LSR;     // THRE -> write
            S_THR: begin cnt<=cnt+8'd1; dly<=21'd1000000; st<=S_DLY; end
            S_DLY: begin if(dly==0) st<=S_LSR; end
            default: st<=S_LSR;
          endcase
        end
      end
    assign led=cnt;
    OBUF ot(.I(tx_int),.O(tx));
endmodule
