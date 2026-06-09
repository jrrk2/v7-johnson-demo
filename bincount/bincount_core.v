// Free-running binary counter — a CARRY4 smoke test.  The johnson demo is
// shift-register only and never builds a carry chain, so it can't tell us
// whether CARRY4 (and the open-flow carry/const fixes) actually work on
// silicon.  This counter's adder maps to a CARRY4 chain; the top 8 bits
// drive the LEDs so they count in binary, visibly (~12 Hz on led[0]) at the
// 200 MHz sysclk.  If the LEDs count, the carry chain is correct on hardware.
module bincount_core (
    input  wire clk,
    input  wire rst,            // active-high (CPU_RESET button)
    output wire [7:0] led
);
    reg [31:0] cnt = 32'h0;
    always @(posedge clk)
        if (rst) cnt <= 32'h0;
        else     cnt <= cnt + 32'h1;
    assign led = cnt[31:24];
endmodule
