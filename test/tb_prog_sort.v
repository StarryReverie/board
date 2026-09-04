//=============================================================================
// tb_prog_sort.v — T31 程序回归：test_sort_rom.hex（冒泡排序）
//   数据 [4,2,5,1,3] @0x200 → 排序 [1,2,3,4,5]
//   期望：mem[0x200..0x210] = 1..5；t0(x5)=0x200 t1(x6)=4 s0(x8)=4 s1(x9)=1
//=============================================================================
`timescale 1ns/1ps

module tb_prog_sort;

    reg        clk = 0;
    reg        rst = 1;
    reg        imem_wen;
    reg [31:0] imem_waddr, imem_wdata;
    wire       cs_mmio;
    wire [1:0] reg_off;
    wire       mmio_we;
    wire [31:0] mmio_wdata;

    integer err = 0;
    integer n   = 0;
    integer i;

    pipeline_top u_cpu (
        .clk (clk), .rst (rst),
        .imem_wen(imem_wen), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .cs_mmio(cs_mmio), .reg_off(reg_off), .mmio_we(mmio_we),
        .mmio_wdata(mmio_wdata), .mmio_rdata(32'b0)
    );

    always #5 clk = ~clk;

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin err = err + 1; $display("FAIL: %0d %0s", n, name); end
            else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // mem 字读取（0x200+i*4）
    function [31:0] mw;
        input [11:0] wa;
        begin
            mw = {u_cpu.u_dmem.mem[wa+3], u_cpu.u_dmem.mem[wa+2],
                  u_cpu.u_dmem.mem[wa+1], u_cpu.u_dmem.mem[wa]};
        end
    endfunction

    initial begin
        for (i = 0; i < 4096; i = i + 1) u_cpu.u_imem.mem[i] = 8'h00;
        $readmemh("test_sort_rom.hex", u_cpu.u_imem.mem);
        imem_wen = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (3000) @(posedge clk);
        #1;

        c("mem[0x200]=1", mw(12'h200) === 32'd1);
        c("mem[0x204]=2", mw(12'h204) === 32'd2);
        c("mem[0x208]=3", mw(12'h208) === 32'd3);
        c("mem[0x20C]=4", mw(12'h20C) === 32'd4);
        c("mem[0x210]=5", mw(12'h210) === 32'd5);
        c("t0=0x200", u_cpu.u_regfile.x[5] === 32'h200);
        c("t1=4",    u_cpu.u_regfile.x[6] === 32'd4);
        c("s0=4",    u_cpu.u_regfile.x[8] === 32'd4);
        c("s1=1",    u_cpu.u_regfile.x[9] === 32'd1);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
