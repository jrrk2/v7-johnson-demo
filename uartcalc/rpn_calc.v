// RPN calculator core: parses ASCII over a byte-in interface, maintains a
// 2-deep signed 32-bit stack, supports + - * (RPN), and prints the top of
// stack as signed decimal on '='.  Input chars are echoed.  DSP/RAM-free
// (sequential multiply + double-dabble).
//
//   tokens: digits 0-9 build a number; space/CR/LF push it; + - * operate;
//           '=' prints TOS as "<value>\r\n".
//
// Byte interfaces (1-cycle pulses):
//   rx_valid/rx_data : a received byte (from the UART receiver)
//   tx_stb/tx_byte   : request to send a byte; accepted when tx_rdy=1
module rpn_calc (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [7:0]  tx_byte,
    output reg         tx_stb,
    input  wire        tx_rdy,
    output wire [3:0]  led
);
    // ---- stack ----
    reg signed [31:0] tos, nos;
    reg [1:0] depth;
    reg [31:0] acc;
    reg        have_num;

    // ---- arithmetic units ----
    reg         mul_start;
    reg  [31:0] mul_a, mul_b;
    wire [31:0] mul_p;  wire mul_done;
    mult_seq u_mul(.clk(clk),.rst(rst),.start(mul_start),.a(mul_a),.b(mul_b),.p(mul_p),.done(mul_done));

    reg         cvt_start;
    reg  [31:0] cvt_val;
    wire [39:0] cvt_bcd; wire cvt_done;
    bin2dec u_cvt(.clk(clk),.rst(rst),.start(cvt_start),.val(cvt_val),.bcd(cvt_bcd),.done(cvt_done));

    // ---- main FSM ----
    localparam S_RUN=0, S_PUSH=1, S_APPLY=2, S_MULWAIT=3,
               S_CVT=4, S_CVTWAIT=5, S_EMIT=6, S_ECHO=7;
    reg [3:0] st;
    reg [7:0] ch;          // current char being handled
    reg [2:0] op;          // pending op: 1=+ 2=- 3=*
    reg [7:0] echo_ch;     // char to echo
    reg       want_emit;   // after handling, print result?

    // emit state
    reg        neg;
    reg [39:0] bcd_r;
    reg [3:0]  digidx;     // 9..0 walking nibbles
    reg        started;    // leading-zero suppression seen a nonzero
    reg [1:0]  emitphase;  // 0=sign 1=digits 2=cr 3=lf

    wire is_digit = (rx_data >= "0") && (rx_data <= "9");

    function [31:0] times10(input [31:0] x); times10 = (x<<3) + (x<<1); endfunction

    assign led = depth==0 ? 4'b0001 : (depth==1 ? 4'b0011 : 4'b0111);

    task do_push(input [31:0] v); begin
        nos <= tos; tos <= v; if (depth!=2'd2) depth <= depth + 2'd1;
    end endtask

    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tos<=0; nos<=0; depth<=0; acc<=0; have_num<=0;
            st<=S_RUN; mul_start<=0; cvt_start<=0; tx_stb<=0;
            op<=0; want_emit<=0; neg<=0; bcd_r<=0; digidx<=0; started<=0; emitphase<=0;
        end else begin
            mul_start<=0; cvt_start<=0; tx_stb<=0;
            case (st)
            S_RUN: begin
                if (rx_valid) begin
                    ch <= rx_data; echo_ch <= rx_data; want_emit <= 1'b0;
                    if (is_digit) begin
                        acc <= times10(acc) + (rx_data - "0"); have_num <= 1'b1;
                        st <= S_ECHO;
                    end else if (rx_data=="+" || rx_data=="-" || rx_data=="*") begin
                        op <= (rx_data=="+")?3'd1:(rx_data=="-")?3'd2:3'd3;
                        st <= S_PUSH;     // flush pending number first
                    end else if (rx_data=="=") begin
                        op <= 0; want_emit <= 1'b1; st <= S_PUSH;
                    end else begin
                        // space / CR / LF / other -> just flush pending number
                        op <= 0; want_emit <= 1'b0; st <= S_PUSH;
                    end
                end
            end
            S_PUSH: begin   // push the pending number if any, then dispatch
                if (have_num) begin do_push(acc); acc<=0; have_num<=0; end
                st <= S_APPLY;
            end
            S_APPLY: begin
                if (op==3'd1)      begin tos <= nos + tos; if(depth!=0) depth<=depth-1; st<=S_ECHO; end
                else if (op==3'd2) begin tos <= nos - tos; if(depth!=0) depth<=depth-1; st<=S_ECHO; end
                else if (op==3'd3) begin mul_a<=nos; mul_b<=tos; mul_start<=1'b1; st<=S_MULWAIT; end
                else st <= S_ECHO;   // '=' (want_emit) echoes first, then S_ECHO starts conversion
            end
            S_MULWAIT: begin
                if (mul_done) begin tos <= mul_p; if(depth!=0) depth<=depth-1; st<=S_ECHO; end
            end
            S_CVT: st <= S_CVTWAIT;
            S_CVTWAIT: if (cvt_done) begin
                bcd_r <= cvt_bcd; digidx <= 4'd9; started<=1'b0; emitphase<=2'd0;
                st <= S_EMIT;
            end
            S_EMIT: begin
                if (tx_rdy && !tx_stb) begin
                    case (emitphase)
                    2'd0: begin
                        if (neg) begin tx_byte<="-"; tx_stb<=1'b1; end
                        emitphase<=2'd1;
                    end
                    2'd1: begin
                        // walk nibbles MS..LS by shifting the top nibble out each
                        // cycle (no variable part-select -> no MUXF7); suppress
                        // leading zeros.  digidx counts the 10 nibbles 9..0.
                        if (bcd_r[39:36]!=4'd0 || started || digidx==4'd0) begin
                            tx_byte <= "0" + bcd_r[39:36]; tx_stb<=1'b1; started<=1'b1;
                        end
                        bcd_r <= bcd_r << 4;
                        if (digidx==4'd0) emitphase<=2'd2; else digidx<=digidx-4'd1;
                    end
                    2'd2: begin tx_byte<=8'h0d; tx_stb<=1'b1; emitphase<=2'd3; end
                    2'd3: begin tx_byte<=8'h0a; tx_stb<=1'b1; st<=S_RUN; end
                    endcase
                end
            end
            S_ECHO: begin
                if (tx_rdy && !tx_stb) begin
                    tx_byte <= echo_ch; tx_stb <= 1'b1;
                    if (want_emit) begin
                        // after echoing '=', start the result conversion
                        neg <= tos[31];
                        cvt_val <= tos[31] ? (~tos + 1'b1) : tos;
                        cvt_start <= 1'b1; st <= S_CVT;
                    end else st <= S_RUN;
                end
            end
            default: st <= S_RUN;
            endcase
        end
    end
endmodule
