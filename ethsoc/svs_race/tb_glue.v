`timescale 1ns/1ps
// RTL vs SVS race: rx_axis_packer, tx_axis_unpacker, async_fifo_wr, async_fifo_rd.
// Deterministic LFSR stimulus; outputs compared every cycle per pair.
module tb_glue;
    reg clk = 0; always #4 clk = ~clk;
    reg rst = 1;
    reg [31:0] lfsr = 32'hdeadbeef;
    always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

    integer errors = 0;
    task chk(input [127:0] tag, input [127:0] a, input [127:0] b);
        if (!rst && a !== b && (^a) !== 1'bx) begin
            if (errors < 12)
                $display("DIFF %0s t=%0t ref=%h svs=%h", tag, $time, a, b);
            errors = errors + 1;
        end
    endtask

    // ---------------- rx_axis_packer pair ----------------
    reg  [7:0] p_tdata; reg p_tvalid, p_tlast, p_full;
    always @(posedge clk) begin
        p_tdata <= lfsr[7:0]; p_tvalid <= lfsr[8]; p_tlast <= lfsr[9] & lfsr[10] & lfsr[11];
        p_full <= lfsr[12] & lfsr[13];
    end
    wire r_wren, s_wren, r_ovf, s_ovf; wire [71:0] r_wdata, s_wdata;
    rx_axis_packer rp (.clk(clk), .rst(rst), .rx_axis_tdata(p_tdata),
        .rx_axis_tvalid(p_tvalid), .rx_axis_tlast(p_tlast),
        .wr_en(r_wren), .wr_data(r_wdata), .wr_full(p_full), .overflow(r_ovf));
    rx_axis_packer_svs sp (.clk(clk), .rst(rst), .rx_axis_tdata(p_tdata),
        .rx_axis_tvalid(p_tvalid), .rx_axis_tlast(p_tlast),
        .wr_en(s_wren), .wr_data(s_wdata), .wr_full(p_full), .overflow(s_ovf));
    always @(posedge clk) begin
        chk("pack.en", r_wren, s_wren);
        if (r_wren) chk("pack.data", r_wdata, s_wdata);
        chk("pack.ovf", r_ovf, s_ovf);
    end

    // ---------------- tx_axis_unpacker pair ----------------
    reg [71:0] u_rdata; reg u_empty, u_tready;
    always @(posedge clk) begin
        u_rdata <= {lfsr, lfsr[15:0], lfsr[23:0]}; u_empty <= lfsr[3] & lfsr[17];
        u_tready <= |lfsr[5:4];
    end
    wire r_rden, s_rden, r_utv, s_utv, r_utl, s_utl, r_utu, s_utu;
    wire [7:0] r_utd, s_utd;
    tx_axis_unpacker ru (.clk(clk), .rst(rst), .rd_data(u_rdata), .rd_empty(u_empty),
        .rd_en(r_rden), .tx_axis_tdata(r_utd), .tx_axis_tvalid(r_utv),
        .tx_axis_tready(u_tready), .tx_axis_tlast(r_utl), .tx_axis_tuser(r_utu));
    tx_axis_unpacker_svs su (.clk(clk), .rst(rst), .rd_data(u_rdata), .rd_empty(u_empty),
        .rd_en(s_rden), .tx_axis_tdata(s_utd), .tx_axis_tvalid(s_utv),
        .tx_axis_tready(u_tready), .tx_axis_tlast(s_utl), .tx_axis_tuser(s_utu));
    always @(posedge clk) begin
        chk("unpk.rden", r_rden, s_rden);
        chk("unpk.tv", r_utv, s_utv);
        if (r_utv) begin
            chk("unpk.td", r_utd, s_utd);
            chk("unpk.tl", r_utl, s_utl);
            chk("unpk.tu", r_utu, s_utu);
        end
    end

    // ---------------- async_fifo_wr pair ----------------
    reg fw_en; reg [71:0] fw_data; reg [5:0] fw_rdgray; reg [4:0] fw_rdaddr;
    always @(posedge clk) begin
        fw_en <= lfsr[6]; fw_data <= {lfsr, lfsr[7:0], lfsr[31:0]};
        // gray-ish wandering pointer (not protocol-exact; same on both sides)
        fw_rdgray <= lfsr[27:22]; fw_rdaddr <= lfsr[20:16];
    end
    wire r_full, s_full; wire [5:0] r_wg, s_wg; wire [71:0] r_rd, s_rd;
    async_fifo_wr #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) rfw (
        .wr_clk(clk), .wr_rst(rst), .wr_en(fw_en), .wr_data(fw_data),
        .wr_full(r_full), .wr_gray(r_wg), .rd_gray(fw_rdgray),
        .rd_addr(fw_rdaddr), .rd_data(r_rd));
    async_fifo_wr__DW72_AW5_svs sfw (
        .wr_clk(clk), .wr_rst(rst), .wr_en(fw_en), .wr_data(fw_data),
        .wr_full(s_full), .wr_gray(s_wg), .rd_gray(fw_rdgray),
        .rd_addr(fw_rdaddr), .rd_data(s_rd));
    always @(posedge clk) begin
        chk("fwr.full", r_full, s_full);
        chk("fwr.gray", r_wg, s_wg);
        chk("fwr.rd", r_rd, s_rd);
    end

    // ---------------- async_fifo_rd pair ----------------
    reg fr_en; reg [5:0] fr_wrgray; reg [71:0] fr_mem;
    always @(posedge clk) begin
        fr_en <= lfsr[14]; fr_wrgray <= lfsr[9:4];
        fr_mem <= {lfsr[15:0], lfsr, lfsr[23:0]};
    end
    wire r_empty, s_empty; wire [5:0] r_rg, s_rg; wire [4:0] r_ra, s_ra;
    wire [71:0] r_rdd, s_rdd;
    async_fifo_rd #(.DATA_WIDTH(72), .ADDR_WIDTH(5)) rfr (
        .rd_clk(clk), .rd_rst(rst), .rd_en(fr_en), .rd_data(r_rdd),
        .rd_empty(r_empty), .rd_gray(r_rg), .wr_gray(fr_wrgray),
        .rd_addr(r_ra), .rd_data_mem(fr_mem));
    async_fifo_rd__DW72_AW5_svs sfr (
        .rd_clk(clk), .rd_rst(rst), .rd_en(fr_en), .rd_data(s_rdd),
        .rd_empty(s_empty), .rd_gray(s_rg), .wr_gray(fr_wrgray),
        .rd_addr(s_ra), .rd_data_mem(fr_mem));
    always @(posedge clk) begin
        chk("frd.empty", r_empty, s_empty);
        chk("frd.gray", r_rg, s_rg);
        chk("frd.addr", r_ra, s_ra);
        chk("frd.data", r_rdd, s_rdd);
    end

    initial begin
        repeat (20) @(posedge clk);
        rst <= 0;
        repeat (4000) @(posedge clk);
        if (errors == 0) $display("GLUESIM PASS");
        else $display("GLUESIM FAIL errors=%0d", errors);
        $finish;
    end
endmodule
