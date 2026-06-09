`timescale 1ns/1ps
// Sim of the timer-ISR software UART RX (calc_init.svh).  Drives rx with UART
// bytes @115200 (BIT=1357 clk @156.25MHz), checks the decoded byte on led_reg.
module IBUFDS #(parameter DIFF_TERM="",IBUF_LOW_PWR="",IOSTANDARD="")(output O,input I,IB); assign O=I; endmodule
module BUFG(output O,input I); assign O=I; endmodule
module IBUF(output O,input I); assign O=I; endmodule
module OBUF(output O,input I); assign O=I; endmodule

module tb_rx;
    reg clk=0; always #3.2 clk=~clk;            // 156.25 MHz
    reg rst=1, sin=1; wire sout; wire [7:0] led;
    top dut(.sysclk_p(clk),.sysclk_n(~clk),
            .user_clock_p(clk),.user_clock_n(~clk),
            .rst(rst),.rx(sin),.tx(sout),.led(led));

    localparam integer BIT = 1357;              // clocks per bit @115200
    task send_byte(input [7:0] b); integer k; begin
        sin=0; repeat(BIT) @(posedge clk);                       // start
        for(k=0;k<8;k=k+1) begin sin=b[k]; repeat(BIT) @(posedge clk); end // LSB first
        sin=1; repeat(BIT) @(posedge clk);                       // stop
        repeat(BIT) @(posedge clk);                              // idle gap
    end endtask

    initial begin
        repeat(40) @(posedge clk); rst=0;
        repeat(200) @(posedge clk);
        send_byte(8'h55);
        repeat(2000) @(posedge clk);
        $display("after 0x55: led=0x%02x  shreg(194)=0x%02x tk(192)=%0d nb(193)=%0d phase? rdy(195)=%0d",
                 led, dut.core.mem[194], dut.core.mem[192], dut.core.mem[193], dut.core.mem[195]);
        send_byte(8'h41);
        repeat(2000) @(posedge clk);
        $display("after 0x41: led=0x%02x  shreg=0x%02x", led, dut.core.mem[194]);
        send_byte(8'h0f);
        repeat(2000) @(posedge clk);
        $display("after 0x0f: led=0x%02x  shreg=0x%02x", led, dut.core.mem[194]);
        $finish;
    end
    initial begin #6000000 $display("TIMEOUT led=0x%02x",led); $finish; end
endmodule
