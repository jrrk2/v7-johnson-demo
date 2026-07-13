// Legacy-unisim compat: RAMB16_S9_S36 -> RAMB36E1, the same redirect the
// Vivado retarget library performs (TDP 9/36 needs a RAMB36; RAMB18E1
// true-dual-port tops out at 18 bits per port).
//
// Port A: 2K x 9  (addr[10:0] -> ADDRARDADDR[13:3], x9 ignores [2:0])
// Port B: 512 x 36 (addr[8:0]  -> ADDRBWRADDR[13:5], x36 ignores [4:0])
// Both ports sit in the lower 18Kb half (ADDR[14]=0; ADDR[15] tied 1 as
// the tools do for non-cascaded RAMB36E1).
// Symmetric 512x36 / 512x36 variant (used by dualmem64): both ports 36-bit
// wide in one RAMB36E1, the same retarget Vivado performs for RAMB16_S36_S36.
module RAMB16_S36_S36_xc7 (
    input         CLKA,
    output [31:0] DOA,
    output [3:0]  DOPA,
    input  [8:0]  ADDRA,
    input  [31:0] DIA,
    input  [3:0]  DIPA,
    input         ENA,
    input         SSRA,
    input         WEA,
    input         CLKB,
    output [31:0] DOB,
    output [3:0]  DOPB,
    input  [8:0]  ADDRB,
    input  [31:0] DIB,
    input  [3:0]  DIPB,
    input         ENB,
    input         SSRB,
    input         WEB
);
    RAMB36E1 #(
        .READ_WIDTH_A(36), .WRITE_WIDTH_A(36),
        .READ_WIDTH_B(36), .WRITE_WIDTH_B(36),
        .WRITE_MODE_A("WRITE_FIRST"), .WRITE_MODE_B("WRITE_FIRST"),
        .DOA_REG(0), .DOB_REG(0),
        .RAM_MODE("TDP"),
        .SIM_DEVICE("7SERIES")
    ) ram (
        .CLKARDCLK   (CLKA),
        .ENARDEN     (ENA),
        .REGCEAREGCE (1'b1),
        .RSTRAMARSTRAM(SSRA),
        .RSTREGARSTREG(1'b0),
        .ADDRARDADDR ({1'b1, 1'b0, ADDRA, 5'b11111}),
        .WEA         ({4{WEA}}),
        .DIADI       (DIA),
        .DIPADIP     (DIPA),
        .DOADO       (DOA),
        .DOPADOP     (DOPA),

        .CLKBWRCLK   (CLKB),
        .ENBWREN     (ENB),
        .REGCEB      (1'b1),
        .RSTRAMB     (SSRB),
        .RSTREGB     (1'b0),
        .ADDRBWRADDR ({1'b1, 1'b0, ADDRB, 5'b11111}),
        .WEBWE       ({8{WEB}}),
        .DIBDI       (DIB),
        .DIPBDIP     (DIPB),
        .DOBDO       (DOB),
        .DOPBDOP     (DOPB),

        .CASCADEINA  (1'b0),
        .CASCADEINB  (1'b0),
        .INJECTSBITERR(1'b0),
        .INJECTDBITERR(1'b0)
    );
endmodule

module RAMB16_S9_S36_xc7 (
    input         CLKA,
    output [7:0]  DOA,
    output [0:0]  DOPA,
    input  [10:0] ADDRA,
    input  [7:0]  DIA,
    input  [0:0]  DIPA,
    input         ENA,
    input         SSRA,
    input         WEA,
    input         CLKB,
    output [31:0] DOB,
    output [3:0]  DOPB,
    input  [8:0]  ADDRB,
    input  [31:0] DIB,
    input  [3:0]  DIPB,
    input         ENB,
    input         SSRB,
    input         WEB
);
    wire [31:0] doa_w;
    wire [3:0]  dopa_w;
    assign DOA  = doa_w[7:0];
    assign DOPA = dopa_w[0];

    RAMB36E1 #(
        .READ_WIDTH_A(9),  .WRITE_WIDTH_A(9),
        .READ_WIDTH_B(36), .WRITE_WIDTH_B(36),
        .WRITE_MODE_A("WRITE_FIRST"), .WRITE_MODE_B("WRITE_FIRST"),
        .DOA_REG(0), .DOB_REG(0),
        .RAM_MODE("TDP"),
        .SIM_DEVICE("7SERIES")
    ) ram (
        .CLKARDCLK   (CLKA),
        .ENARDEN     (ENA),
        .REGCEAREGCE (1'b1),
        .RSTRAMARSTRAM(SSRA),
        .RSTREGARSTREG(1'b0),
        .ADDRARDADDR ({1'b1, 1'b0, ADDRA, 3'b111}),
        .WEA         ({4{WEA}}),
        .DIADI       ({24'b0, DIA}),
        .DIPADIP     ({3'b0, DIPA}),
        .DOADO       (doa_w),
        .DOPADOP     (dopa_w),

        .CLKBWRCLK   (CLKB),
        .ENBWREN     (ENB),
        .REGCEB      (1'b1),
        .RSTRAMB     (SSRB),
        .RSTREGB     (1'b0),
        .ADDRBWRADDR ({1'b1, 1'b0, ADDRB, 5'b11111}),
        .WEBWE       ({8{WEB}}),
        .DIBDI       (DIB),
        .DIPBDIP     (DIPB),
        .DOBDO       (DOB),
        .DOPBDOP     (DOPB),

        .CASCADEINA  (1'b0),
        .CASCADEINB  (1'b0),
        .INJECTSBITERR(1'b0),
        .INJECTDBITERR(1'b0)
    );
endmodule
