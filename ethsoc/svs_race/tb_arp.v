`timescale 1ns/1ps
// Lockstep race: RTL arp_ctrl vs SVS netlist under identical (random) bus
// responses. Any divergence in outputs = synthesis bug.
module tb_arp;
    reg clk = 0; always #4 clk = ~clk;
    reg rst_n = 0;
    reg [31:0] lfsr = 32'hcafebabe;
    always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
    reg [63:0] rdata;
    always @(posedge clk) rdata <= {lfsr, lfsr[15:0], lfsr[31:16]};

    wire [16:0] r_addr, s_addr; wire [63:0] r_wd, s_wd; wire [7:0] r_be, s_be;
    wire r_ce, s_ce, r_we, s_we, r_sel, s_sel, r_led, s_led;
    wire [15:0] r_rc, s_rc; wire [3:0] r_db, s_db;

    arp_ctrl #(.FPGA_MAC(48'h02_00_00_4B_41_31), .FPGA_IP(32'hC0_A8_01_64)) ref_a (
        .clk(clk), .rst_n(rst_n),
        .core_lsu_addr(r_addr), .core_lsu_wdata(r_wd), .core_lsu_be(r_be),
        .ce_d(r_ce), .we_d(r_we), .framing_sel(r_sel), .framing_rdata(rdata),
        .led_arp(r_led), .reply_count(r_rc), .dbg_state(r_db));
    arp_svs dut_a (
        .clk(clk), .rst_n(rst_n),
        .core_lsu_addr(s_addr), .core_lsu_wdata(s_wd), .core_lsu_be(s_be),
        .ce_d(s_ce), .we_d(s_we), .framing_sel(s_sel), .framing_rdata(rdata),
        .led_arp(s_led), .reply_count(s_rc), .dbg_state(s_db));

    integer errors = 0;
    task chk(input [127:0] tag, input [127:0] a, input [127:0] b);
        if (rst_n && a !== b && (^a) !== 1'bx) begin
            if (errors < 12)
                $display("DIFF %0s t=%0t ref=%h svs=%h", tag, $time, a, b);
            errors = errors + 1;
        end
    endtask
    always @(posedge clk) begin
        chk("addr", r_addr, s_addr);
        chk("wd", r_wd, s_wd);
        chk("be", r_be, s_be);
        chk("ce", r_ce, s_ce);
        chk("we", r_we, s_we);
        chk("sel", r_sel, s_sel);
        chk("led", r_led, s_led);
        chk("rc", r_rc, s_rc);
        chk("dbg", r_db, s_db);
    end
    initial begin
        repeat (20) @(posedge clk);
        rst_n <= 1;
        repeat (8000) @(posedge clk);
        if (errors == 0) $display("ARPSIM PASS");
        else $display("ARPSIM FAIL errors=%0d", errors);
        $finish;
    end
endmodule
