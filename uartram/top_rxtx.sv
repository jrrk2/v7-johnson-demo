// Minimal rx->tx passthrough, NO other logic (no CPU, no BRAM, no clock).
// Isolates the open-flow rx-input / tx-output analog path for loopback test
// and Vivado DCP static analysis.  Ports match top.xdc so the same pins/IOBs
// are used (rx=AU33 slave-site, tx=AU36).  Combinational: tx follows rx directly.
module top (
    input  wire       sysclk_p,
    input  wire       sysclk_n,
    input  wire       user_clock_p,
    input  wire       user_clock_n,
    input  wire       rst,
    input  wire       rx,
    output wire       tx,
    output wire [7:0] led
);
    wire rxb;
    IBUF ibuf_rx (.I(rx), .O(rxb));
    OBUF obuf_tx (.I(rxb), .O(tx));     // pure combinational rx -> tx
    // tie off unused outputs (keep ports for the XDC)
    OBUF o0 (.I(1'b0), .O(led[0]));  OBUF o1 (.I(1'b0), .O(led[1]));
    OBUF o2 (.I(1'b0), .O(led[2]));  OBUF o3 (.I(1'b0), .O(led[3]));
    OBUF o4 (.I(1'b0), .O(led[4]));  OBUF o5 (.I(1'b0), .O(led[5]));
    OBUF o6 (.I(1'b0), .O(led[6]));  OBUF o7 (.I(1'b0), .O(led[7]));
endmodule
