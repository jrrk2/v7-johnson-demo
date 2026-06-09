// Sequential shift-add multiplier — DSP-free (open-flow safe).  Computes the
// low 32 bits of a*b, which equals (signed a * signed b) mod 2^32, so the same
// hardware works for signed operands (two's-complement low bits are identical).
// 32 cycles per multiply.  start pulses for one cycle; done pulses when p valid.
module mult_seq (
    input  wire        clk,
    input  wire        rst,        // active-high
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] p,
    output reg         done
);
    reg [31:0] acc;     // running product (low 32)
    reg [31:0] m;       // shifted multiplicand (a << i)
    reg [31:0] mp;      // remaining multiplier bits (b >> i)
    reg [5:0]  cnt;
    reg        busy;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acc <= 32'd0; m <= 32'd0; mp <= 32'd0; cnt <= 6'd0;
            busy <= 1'b0; done <= 1'b0; p <= 32'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    acc <= 32'd0; m <= a; mp <= b; cnt <= 6'd0; busy <= 1'b1;
                end
            end else begin
                if (mp[0]) acc <= acc + m;     // add current partial product
                m  <= m  << 1;                  // a << (i+1)
                mp <= mp >> 1;                  // next multiplier bit
                cnt <= cnt + 6'd1;
                if (cnt == 6'd31) begin
                    // 'acc' this cycle still excludes the bit-31 add when
                    // mp[0] was set; fold it into the published result.
                    p    <= mp[0] ? (acc + m) : acc;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
