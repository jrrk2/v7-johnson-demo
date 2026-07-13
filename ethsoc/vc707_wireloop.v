// Ultimate minimal open-flow test: uart_tx = uart_rx, a pure wire through
// the fabric.  No clock, no MMCM, no logic.  If the open flow can't route
// this, the FASM is small enough to diff line-by-line against golden.
module wireloop (
    input  wire uart_rx,
    output wire uart_tx
);
    assign uart_tx = uart_rx;
endmodule
