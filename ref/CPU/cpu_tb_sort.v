`timescale 1us/1ns

module cpu_tb_sort;

    reg clk, rst;

    // CPU 实例
    cpu_top u_cpu (
        .clk(clk),
        .rst(rst)
    );

    // 时钟: 周期 2us
    always #1 clk = ~clk;

    // ============================================================
    // 测试主流程
    // ============================================================
    initial begin
        $readmemh("D:\\MyProjects\\CO\\src\\lab2\\test\\test_sort_rom.hex", u_cpu.u_rom.mem);

        // 启动时复位
        clk = 0;
        rst = 1;

        // 保持复位 5 个周期
        #10 rst = 0;

        #380;

        // ── Display final PC ──
        $display("");
        $display("========================================");
        $display("  Bubble Sort Test End");
        $display("========================================");
        $display("PC = 0x%08h", u_cpu.pc);
        $display("");

        // ── Display key registers ──
        $display("--- Registers ---");
        $display(" t0 = 0x%08h  (expect 0x00000200)", u_cpu.u_regfile.x[5]);
        $display(" t1 = 0x%08h  (expect 0x00000004)", u_cpu.u_regfile.x[6]);
        $display(" s0 = 0x%08h  (expect 0x00000004)", u_cpu.u_regfile.x[8]);
        $display(" s1 = 0x%08h  (expect 0x00000001)", u_cpu.u_regfile.x[9]);
        $display("");

        // ── Display sorted memory results ──
        $display("--- Sort Results (RAM 0x200 ~ 0x210) ---");
        $display(" mem[0x200] = %0d  (expect %0d : %s)",
                 {u_cpu.u_ram.mem[16'h203], u_cpu.u_ram.mem[16'h202],
                  u_cpu.u_ram.mem[16'h201], u_cpu.u_ram.mem[16'h200]},
                 1, check_val(16'h200, 1) ? "PASS" : "FAIL");
        $display(" mem[0x204] = %0d  (expect %0d : %s)",
                 {u_cpu.u_ram.mem[16'h207], u_cpu.u_ram.mem[16'h206],
                  u_cpu.u_ram.mem[16'h205], u_cpu.u_ram.mem[16'h204]},
                 2, check_val(16'h204, 2) ? "PASS" : "FAIL");
        $display(" mem[0x208] = %0d  (expect %0d : %s)",
                 {u_cpu.u_ram.mem[16'h20B], u_cpu.u_ram.mem[16'h20A],
                  u_cpu.u_ram.mem[16'h209], u_cpu.u_ram.mem[16'h208]},
                 3, check_val(16'h208, 3) ? "PASS" : "FAIL");
        $display(" mem[0x20C] = %0d  (expect %0d : %s)",
                 {u_cpu.u_ram.mem[16'h20F], u_cpu.u_ram.mem[16'h20E],
                  u_cpu.u_ram.mem[16'h20D], u_cpu.u_ram.mem[16'h20C]},
                 4, check_val(16'h20C, 4) ? "PASS" : "FAIL");
        $display(" mem[0x210] = %0d  (expect %0d : %s)",
                 {u_cpu.u_ram.mem[16'h213], u_cpu.u_ram.mem[16'h212],
                  u_cpu.u_ram.mem[16'h211], u_cpu.u_ram.mem[16'h210]},
                 5, check_val(16'h210, 5) ? "PASS" : "FAIL");
        $display("");

        // ── Overall result ──
        if (check_val(16'h200, 1) && check_val(16'h204, 2) &&
            check_val(16'h208, 3) && check_val(16'h20C, 4) &&
            check_val(16'h210, 5))
            $display(">>> Overall: PASS (sort correct) <<<");
        else
            $display(">>> Overall: FAIL (sort incorrect) <<<");

        $finish;
    end

    // ── Helper function: check if 32-bit word at given address equals expected ──
    function check_val;
        input [15:0] addr;
        input [31:0] expect;
        reg   [31:0] actual;
        begin
            actual = {u_cpu.u_ram.mem[addr+3], u_cpu.u_ram.mem[addr+2],
                      u_cpu.u_ram.mem[addr+1], u_cpu.u_ram.mem[addr]};
            check_val = (actual == expect);
        end
    endfunction

    // ── 逐周期跟踪 (可选, 注释掉以简化输出) ──
    always @(posedge clk) begin
        if (!rst)
            $display("Cycle PC=%0d  instr=0x%08h  alu_out=0x%08h  flags=%b",
                     u_cpu.pc, u_cpu.instr, u_cpu.alu_out, u_cpu.flags);
    end

endmodule