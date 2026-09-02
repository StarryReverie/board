`timescale 1us/1ns

module cpu_tb;

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
        $readmemh("D:\\MyProjects\\CO\\src\\lab2\\test\\test0_rom.hex", u_cpu.u_rom.mem);

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
    end

    // 逐周期跟踪
    always @(posedge clk) begin
        if (!rst)
            $display("Cycle PC=%0d  instr=0x%08h  alu_out=0x%08h  flags=%b",
                     u_cpu.pc, u_cpu.instr, u_cpu.alu_out, u_cpu.flags);
    end

endmodule