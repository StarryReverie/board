//=============================================================================
// tb_reset_sync.v — reset_sync 单测（soc_top.md 小节）
//   A. 默认配置（STABLE_CYCLES=0，旧行为）：
//      异步置位：rst_n 释放沿后 rst 立即可用；同步释放：恢复后经 2 拍才撤 rst；
//      撤除前各 posedge 保持 rst=1。
//   B. 去抖配置（STABLE_CYCLES=8，2026-09-16 新增）：
//      释放需**连续稳定 8 拍**，再经 2 拍同步 → 第 9 拍后才撤 rst；
//      松开沿抖动（多个短高脉冲，每个 < 8 拍）必须被滤掉：计数被任何一次拉低清零，
//      rst 全程保持 1 —— 这正是"按 RESET 后 banner 乱码前缀"的根因防护。
//   C. 多于 2 级同步链（STAGES=3）：覆盖释放链的 generate 分支，释放准点为第 3 拍。
//   D. **亚周期毛刺**（低 4 ns，不占任何完整拍）：输出侧必须立刻断言、并**重新计时**，
//      不能因上一轮已满足的计数而立刻释放。
//=============================================================================
`timescale 1ns/1ps

module tb_reset_sync;

    reg  clk = 0;
    reg  rst_n = 0;
    wire rst;

    // 去抖实例（A 用默认参数，B 显式开启去抖）
    reg  rst_n_d = 0;
    wire rst_d;

    // 3 级同步链实例（C：释放链 generate 分支）
    reg  rst_n_3 = 0;
    wire rst_3;

    integer err = 0;
    integer n   = 0;

    reset_sync dut (.clk(clk), .rst_n(rst_n), .rst(rst));
    reset_sync #(.STAGES(2), .STABLE_CYCLES(8)) dut_dbg (.clk(clk), .rst_n(rst_n_d), .rst(rst_d));
    reset_sync #(.STAGES(3)) dut_s3 (.clk(clk), .rst_n(rst_n_3), .rst(rst_3));

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

    initial begin
        // ============ A. 默认配置（不去抖，旧行为）============
        // 初始按下（rst_n=0）→ rst 立即 1（异步置位）
        #2 c("asserted async", rst===1'b1);

        // 释放（rst_n=1）：第 1 个沿 q1 撤、q2 仍 1；第 2 个沿 q2 撤
        rst_n = 1;
        @(posedge clk);
        #1 c("still rst after e1", rst===1'b1);
        @(posedge clk);
        #1 c("released after e2", rst===1'b0);

        // 再按一次：沿间立即生效
        rst_n = 0;
        #2 c("re-assert async", rst===1'b1);
        rst_n = 1;
        @(posedge clk);
        #1 c("hold e1", rst===1'b1);
        @(posedge clk);
        #1 c("release e2", rst===1'b0);

        // ============ B. 去抖配置（STABLE_CYCLES=8）============
        // B1. 干净释放：8 拍稳定 + 2 拍同步 → 第 9 拍撤 rst
        rst_n_d = 0;
        #2 c("dbg asserted async", rst_d===1'b1);
        rst_n_d = 1;
        repeat (8) @(posedge clk);
        #1 c("dbg hold after 8 stable cycles", rst_d===1'b1);
        @(posedge clk);                                   // 第 9 拍 = 首个可释放沿（必须正好在此撤）
        #1 c("dbg released at 9th edge (8+2)", rst_d===1'b0);

        // B2. 抖动释放：高 3 → 低 2 → 高 5 → 低 1 → 高（稳定）
        //     中间任何一次拉低都要把去抖计数清零；抖动期内 rst 必须保持 1
        rst_n_d = 0;
        repeat (4) @(posedge clk);
        #1 c("dbg re-asserted", rst_d===1'b1);

        rst_n_d = 1;  repeat (3) @(posedge clk);          // 抖动高 3 拍（< 8）
        #1 c("dbg bounce1 high: still rst", rst_d===1'b1);
        rst_n_d = 0;  repeat (2) @(posedge clk);          // 掉回低 2 拍
        #1 c("dbg bounce1 low: still rst", rst_d===1'b1);
        rst_n_d = 1;  repeat (5) @(posedge clk);          // 抖动高 5 拍（< 8）
        #1 c("dbg bounce2 high: still rst", rst_d===1'b1);
        rst_n_d = 0;  @(posedge clk);                     // 再抖 1 拍
        #1 c("dbg bounce2 low: still rst", rst_d===1'b1);

        rst_n_d = 1;                                      // 最终稳定释放
        repeat (8) @(posedge clk);
        #1 c("dbg final-8-stable: still rst", rst_d===1'b1);
        @(posedge clk);                                   // 首个可释放沿
        #1 c("dbg released after final settle", rst_d===1'b0);

        // ============ C. STAGES=3（释放链 generate 分支）============
        rst_n_3 = 0;
        #2 c("s3 asserted async", rst_3===1'b1);
        rst_n_3 = 1;
        repeat (2) @(posedge clk);
        #1 c("s3 still rst after e2", rst_3===1'b1);
        @(posedge clk);
        #1 c("s3 released after e3", rst_3===1'b0);

        // ============ D. 亚周期毛刺（低 4 ns，不占任何完整拍）============
        // 先让 dut_dbg 干净释放（已稳定 9 拍 > 8）
        rst_n_d = 0;
        repeat (4) @(posedge clk);
        rst_n_d = 1;
        repeat (9) @(posedge clk);
        #1 c("dbg released before glitch", rst_d===1'b0);

        @(posedge clk); #1;                                // 刚过一个沿，在拍中间打毛刺
        rst_n_d = 0; #4 rst_n_d = 1;                       // 低 4 ns（< 1 拍）
        #1 c("dbg glitch asserted async", rst_d===1'b1);   // 输出侧必须立刻断言
        repeat (8) @(posedge clk);
        #1 c("dbg glitch: still rst (recount)", rst_d===1'b1);
        @(posedge clk);                                   // 抖动后同样只在首个可释放沿撤
        #1 c("dbg glitch: released at 9th edge", rst_d===1'b0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
