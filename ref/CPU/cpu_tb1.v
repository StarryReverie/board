`timescale 1us/1ns

module cpu_tb1;

    reg clk, rst;

    // CPU 实例
    cpu_top u_cpu (
        .clk(clk),
        .rst(rst)
    );

    // 时钟: 周期 2us
    always #1 clk = ~clk;

    // 初始条件
    initial begin
        $readmemh("D:\\MyProjects\\CO\\src\\lab2\\test\\test1_rom.hex", u_cpu.u_rom.mem);

        // 启动时复位
        clk = 0;
        rst = 1;

        // 保持复位 5 个周期
        #10 rst = 0;

        // 运行足够周期完成测试程序 (22条指令 ≈ 25+ 周期)
        #60;

        // 显示最终 PC
        $display("=== Simulation End ===");
        $display("PC = 0x%08h", u_cpu.pc);

        // 显示关键寄存器
        $display("--- Registers ---");
        $display(" t0 = 0x%08h  (expect 0x00000001)", u_cpu.u_regfile.x[5]);
        $display(" t1 = 0x%08h  (expect 0x00000002)", u_cpu.u_regfile.x[6]);
        $display(" t2 = 0x%08h  (expect 0x00000003)", u_cpu.u_regfile.x[7]);
        $display(" tp = 0x%08h  (expect 0x00000001)", u_cpu.u_regfile.x[4]);
        $display(" s0 = 0x%08h  (expect 0x00000003)", u_cpu.u_regfile.x[8]);
        $display(" s1 = 0x%08h  (expect 0x00000004)", u_cpu.u_regfile.x[9]);
        $display(" a0 = 0x%08h  (expect 0x00000100)", u_cpu.u_regfile.x[10]);
        $display(" a1 = 0x%08h  (expect 0x00000002)", u_cpu.u_regfile.x[11]);
        // a2 测试已移除 — ORI 零扩展在 RARS 中不适用
        $display(" a3 = 0x%08h  (expect 0x00000002)", u_cpu.u_regfile.x[13]);
        $display(" a4 = 0x%08h  (expect 0x00000000)", u_cpu.u_regfile.x[14]);
        $display(" a5 = 0x%08h  (expect 0x000000FF)", u_cpu.u_regfile.x[15]);
        $display(" a6 = 0x%08h  (expect 0x00000100)", u_cpu.u_regfile.x[16]);
        $display(" a7 = 0x%08h  (expect 0x000000FE)", u_cpu.u_regfile.x[17]);

        // 显示内存
        $display("--- Memory ---");
        $display(" mem[0x100] = 0x%08h  (expect 0x00000003)",
                 {u_cpu.u_ram.mem[16'h103], u_cpu.u_ram.mem[16'h102],
                  u_cpu.u_ram.mem[16'h101], u_cpu.u_ram.mem[16'h100]});
        $display(" mem[0x104] = 0x%08h  (expect 0x00000002)",
                 {u_cpu.u_ram.mem[16'h107], u_cpu.u_ram.mem[16'h106],
                  u_cpu.u_ram.mem[16'h105], u_cpu.u_ram.mem[16'h104]});
        $display(" mem[0x108] = 0x%08h  (expect 0x000000FE)",
                 {u_cpu.u_ram.mem[16'h10B], u_cpu.u_ram.mem[16'h10A],
                  u_cpu.u_ram.mem[16'h109], u_cpu.u_ram.mem[16'h108]});

        $finish;
    end

    // 逐周期跟踪
    always @(posedge clk) begin
        if (!rst)
            $display("Cycle PC=%0d  instr=0x%08h  alu_out=0x%08h  flags=%b",
                     u_cpu.pc, u_cpu.instr, u_cpu.alu_out, u_cpu.flags);
    end

endmodule
