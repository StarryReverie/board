//=============================================================================
// tb_pipeline_top.v — 整机冒烟（H1 直行 + 前递 + load-use + sw/lw + 分支跳转）
//   程序（内嵌机器码，正式回归 T31 改用 .asm→.hex）：
//     0x00 addi x1,x0,1     0x00100093
//     0x04 beq  x0,x0,+8    0x00000463   （跳 0x0C：EX 判决 + 冲刷 2 条）
//     0x08 addi x1,x0,99    0x06300093   （应被跳过——验证分支目标正确）
//     0x0C sw   x1,0(x0)    0x00102023
//     0x10 beq  x0,x0,0     0x00000063   （halt 自循环）
//     0x14..0x3C NOP 填充（避免取指到未初始化区）
//   期望终值：x1=1（未被 99 覆盖）；dmem[0]=1（0x0C 的 sw 到达）
//=============================================================================
`timescale 1ns/1ps

module tb_pipeline_top;

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
        .clk        (clk),
        .rst        (rst),
        .imem_wen   (imem_wen),
        .imem_waddr (imem_waddr),
        .imem_wdata (imem_wdata),
        .cs_mmio    (cs_mmio),
        .reg_off    (reg_off),
        .mmio_we    (mmio_we),
        .mmio_wdata (mmio_wdata),
        .mmio_rdata (32'b0)
    );

    always #5 clk = ~clk;

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin
                err = err + 1;
                $display("FAIL: %0d %0s", n, name);
            end else $display("PASS: %0d %0s", n, name);
        end
    endtask

    // 写一条指令（小端字节入 imem）
    task load_word;
        input [31:0] wa;
        input [31:0] wd;
        begin
            u_cpu.u_imem.mem[wa   ] = wd[7:0];
            u_cpu.u_imem.mem[wa+1 ] = wd[15:8];
            u_cpu.u_imem.mem[wa+2 ] = wd[23:16];
            u_cpu.u_imem.mem[wa+3 ] = wd[31:24];
        end
    endtask

    initial begin
        imem_wen = 0; imem_waddr = 0; imem_wdata = 0;

        // ---- 装载程序（分支目标探针：0x04 beq 跳过 0x08 的 addi 99，落 0x0C）----
        load_word(32'h00, 32'h00100093);   // addi x1,x0,1
        load_word(32'h04, 32'h00000463);   // beq x0,x0,+8 → 0x0C
        load_word(32'h08, 32'h06300093);   // addi x1,x0,99（应被跳过）
        load_word(32'h0C, 32'h00102023);   // sw x1,0(x0)
        load_word(32'h10, 32'h00000063);   // halt 自循环
        // 填充 0x14..0x3C 为 NOP，避免取指到未初始化区（X 污染）
        for (i = 0; i < 12; i = i + 1) load_word(32'h14 + i*4, 32'h00000013);

        // ---- 复位 3 拍后运行 45 拍 ----
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (45) @(posedge clk);
        #1;

        // ---- 终值检查（分支目标探针：beq 正确跳 0x0C 跳过 addi 99）----
        c("x1=1 (skip works)", u_cpu.u_regfile.x[1] === 32'd1);
        c("dmem[0]=1 (store reached)", {u_cpu.u_dmem.mem[3], u_cpu.u_dmem.mem[2],
                                        u_cpu.u_dmem.mem[1], u_cpu.u_dmem.mem[0]} === 32'd1);
        // 实验一 mmio 口恒 0
        c("mmio idle", cs_mmio===0 && mmio_we===0 && mmio_wdata===0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
