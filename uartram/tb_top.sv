`timescale 1ns/1ps
// Stubs for Xilinx primitives so we can sim top.sv directly.
module IBUFDS #(parameter DIFF_TERM="",IBUF_LOW_PWR="",IOSTANDARD="")(output O,input I,IB); assign O=I; endmodule
module BUFG(output O,input I); assign O=I; endmodule
module IBUF(output O,input I); assign O=I; endmodule
module OBUF(output O,input I); assign O=I; endmodule

module tb_top;
    reg clk=0; always #2.5 clk=~clk;     // 200 MHz
    reg rst=1; reg sin=1; wire sout; wire [7:0] led;
    top dut(.sysclk_p(clk),.sysclk_n(~clk),.rst(rst),.rx(sin),.tx(sout),.led(led));

    localparam integer BIT = 1744;       // 16*109 clk per bit (divisor 109)
    // ---- preload calc_core BRAM: LDI A; OUT; LDI B; OUT; HLT ----
    integer i;
    initial begin
        for(i=0;i<256;i=i+1) dut.core.mem[i]=8'h00;
        dut.core.mem[0]=8'h01; dut.core.mem[1]=8'h41; // LDI 'A'
        dut.core.mem[2]=8'h07;                         // OUT
        dut.core.mem[3]=8'h01; dut.core.mem[4]=8'h42; // LDI 'B'
        dut.core.mem[5]=8'h07;                         // OUT
        dut.core.mem[6]=8'h00;                         // HLT
    end

    // ---- send one UART byte on sin (8N1, LSB first) at divisor baud ----
    task send_byte(input [7:0] b); integer k; begin
        sin=0; repeat(BIT) @(posedge clk);             // start
        for(k=0;k<8;k=k+1) begin sin=b[k]; repeat(BIT) @(posedge clk); end
        sin=1; repeat(BIT) @(posedge clk);             // stop
    end endtask

    // ---- UART RX monitor on sout: decode + report bytes ----
    integer nrx=0; reg [7:0] rxb;
    initial begin : mon
        integer k;
        forever begin
            @(negedge sout);                            // start bit
            repeat(BIT/2) @(posedge clk);               // to mid start
            repeat(BIT) @(posedge clk);                 // to mid bit0
            for(k=0;k<8;k=k+1) begin rxb[k]=sout; repeat(BIT) @(posedge clk); end
            $display("  [%0t] RX byte = 0x%02x '%c'", $time, rxb, rxb);
            nrx=nrx+1;
        end
    end

    initial begin
        repeat(40) @(posedge clk); rst=0;               // release reset
        repeat(2000) @(posedge clk);                    // let APB init finish
        $display("sending X...");
        send_byte(8'h58);                               // 'X' -> execute
        repeat(80000) @(posedge clk);                   // run + drain both bytes
        $display("DONE: received %0d bytes (expect 2: A,B)", nrx);
        $finish;
    end
    initial begin #6000000 $display("TIMEOUT nrx=%0d",nrx); $finish; end
endmodule
