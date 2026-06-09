`timescale 1ns/1ps
// Sim of the timer-ISR software UART TX (calc_init.svh).  Drives user_clock at
// 156.25 MHz, lets AUTOSTART run the program, decodes tx, peeks at timer/ISR state.
module IBUFDS #(parameter DIFF_TERM="",IBUF_LOW_PWR="",IOSTANDARD="")(output O,input I,IB); assign O=I; endmodule
module BUFG(output O,input I); assign O=I; endmodule
module IBUF(output O,input I); assign O=I; endmodule
module OBUF(output O,input I); assign O=I; endmodule

module tb_tx;
    reg clk=0; always #3.2 clk=~clk;            // 156.25 MHz (6.4 ns period)
    reg rst=1, sin=1; wire sout; wire [7:0] led;
    top dut(.sysclk_p(clk),.sysclk_n(~clk),
            .user_clock_p(clk),.user_clock_n(~clk),
            .rst(rst),.rx(sin),.tx(sout),.led(led));

    localparam integer BIT = 1357;              // clocks per bit (timer reload)
    integer nrx=0, k; reg [7:0] rxb;
    // decode tx (sout) as UART
    initial begin : mon
        forever begin
            @(negedge sout);
            repeat(BIT/2) @(posedge clk);
            repeat(BIT)   @(posedge clk);
            for(k=0;k<8;k=k+1) begin rxb[k]=sout; repeat(BIT) @(posedge clk); end
            $display("  [%0t] TX byte = 0x%02x", $time, rxb);
            nrx=nrx+1; if (nrx>=5) begin $display("GOT %0d bytes",nrx); $finish; end
        end
    end
    // peek at timer/interrupt state early on
    initial begin
        repeat(40) @(posedge clk); rst=0;
        // sample some internal state after setup
        repeat(3000) @(posedge clk);
        $display("[%0t] tmr_en=%b ie=%b tmr_term=%0d tmr=%0d tmr_if=%b in_isr=%b phase=%0d tx_bit=%b pc=%0d",
                 $time, dut.core.tmr_en, dut.core.ie, dut.core.tmr_term, dut.core.tmr,
                 dut.core.tmr_if, dut.core.in_isr, dut.core.mem[192], dut.core.tx_bit, dut.core.pc);
        #4000000 $display("TIMEOUT nrx=%0d (tmr_en=%b ie=%b tmr=%0d)",nrx,dut.core.tmr_en,dut.core.ie,dut.core.tmr); $finish;
    end
endmodule
