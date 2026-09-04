//=============================================================================
// tb_imem.v — imem 单测（doc/modules/imem.md 验收，T30）
//   逐字读回与预置内容一致（小端重组：{mem[a+3..a]}）；loader 写口（预留）
//   写入后读回一致；wen=0 期间读不受写影响；越界返回 0。
//   注：综合装载 .vh 路径在脚本生成后另行校验（verify_hex.py）。
//=============================================================================
`timescale 1ns/1ps

module tb_imem;

    reg        clk = 0;
    reg [31:0] addr;
    wire [31:0] inst;
    reg        imem_wen;
    reg [31:0] imem_waddr;
    reg [31:0] imem_wdata;

    integer err = 0;
    integer n   = 0;

    imem dut (
        .clk        (clk),
        .addr       (addr),
        .inst       (inst),
        .imem_wen   (imem_wen),
        .imem_waddr (imem_waddr),
        .imem_wdata (imem_wdata)
    );

    always #5 clk = ~clk;

    task chk;
        input [31:0] exp;
        begin
            n = n + 1;
            if (inst !== exp) begin
                err = err + 1;
                $display("FAIL: %0d addr=%h inst=%h exp=%h", n, addr, inst, exp);
            end else begin
                $display("PASS: %0d addr=%h inst=%h", n, addr, inst);
            end
        end
    endtask

    initial begin
        imem_wen = 0; imem_waddr = 32'h0; imem_wdata = 32'h0;

        // ---- 预置字节（模拟 .hex 装载后的小端布局）----
        // 地址 0：0x00000013（nop）→ 字节 13 00 00 00
        dut.mem[0] = 8'h13; dut.mem[1] = 8'h00; dut.mem[2] = 8'h00; dut.mem[3] = 8'h00;
        // 地址 4：0x11223344 → 字节 44 33 22 11
        dut.mem[4] = 8'h44; dut.mem[5] = 8'h33; dut.mem[6] = 8'h22; dut.mem[7] = 8'h11;
        // 地址 8：0xDEADBEEF → 字节 EF BE AD DE
        dut.mem[8] = 8'hEF; dut.mem[9] = 8'hBE; dut.mem[10] = 8'hAD; dut.mem[11] = 8'hDE;

        // ---- 组合读（小端重组）----
        addr = 32'h00000000; #1 chk(32'h00000013);
        addr = 32'h00000004; #1 chk(32'h11223344);
        addr = 32'h00000008; #1 chk(32'hDEADBEEF);

        // ---- 越界返回 0 ----
        addr = 32'h00001000; #1 chk(32'h00000000);
        addr = 32'hFFFFFFF0; #1 chk(32'h00000000);

        // ---- loader 写口（预留）：4 对齐整字写入 ----
        imem_wen = 1; imem_waddr = 32'h00000010; imem_wdata = 32'hCAFEBABE;
        @(posedge clk);
        imem_wen = 0;
        addr = 32'h00000010; #1 chk(32'hCAFEBABE);
        if (dut.mem[16] !== 8'hBE || dut.mem[19] !== 8'hCA) begin
            err = err + 1;
            $display("FAIL: loader 写口小端落字节错误 mem[16]=%h mem[19]=%h", dut.mem[16], dut.mem[19]);
        end else begin
            $display("PASS: loader 写口小端字节落位 mem[16]=BE mem[19]=CA");
        end

        // ---- wen=0 期间读不受写影响 ----
        imem_wdata = 32'h11111111;
        @(posedge clk);
        #1 chk(32'hCAFEBABE);

        // ---- 复位无影响（无复位端口；写路径与读无关已验）----
        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
