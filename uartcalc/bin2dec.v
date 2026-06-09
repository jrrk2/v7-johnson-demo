// Binary -> decimal (double-dabble), DSP/RAM-free.  Converts a 32-bit unsigned
// magnitude to 10 BCD digits (40 bits) over 32 shift cycles.  Sign handling is
// done by the caller (negate + emit '-').  Max 4294967295 -> 10 digits.
module bin2dec (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] val,        // unsigned magnitude
    output reg  [39:0] bcd,        // 10 nibbles, digit9..digit0
    output reg         done
);
    reg [31:0] sh;
    reg [5:0]  cnt;
    reg        busy;

    // combinational add-3 to every BCD nibble that is >= 5
    function [39:0] add3all(input [39:0] b);
        integer k; reg [3:0] nib;
        begin
            for (k = 0; k < 10; k = k + 1) begin
                nib = b[k*4 +: 4];
                if (nib >= 5) nib = nib + 4'd3;
                add3all[k*4 +: 4] = nib;
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sh <= 32'd0; bcd <= 40'd0; cnt <= 6'd0; busy <= 1'b0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin sh <= val; bcd <= 40'd0; cnt <= 6'd0; busy <= 1'b1; end
            end else begin
                // add-3, then shift {bcd,sh} left by 1 (sh MSB -> bcd LSB)
                {bcd, sh} <= {add3all(bcd), sh} << 1;
                cnt <= cnt + 6'd1;
                if (cnt == 6'd31) begin busy <= 1'b0; done <= 1'b1; end
            end
        end
    end
endmodule
