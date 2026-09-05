//=============================================================================
// tb_reset_sync.v — reset_sync 单测（soc_top.md 小节）
//   异步置位：rst_n 释放沿后 rst 立即可用；同步释放：恢复后经 2 拍才撤 rst；
//   撤除前各 posedge 保持 rst=1。
//=============================================================================
`timescale 1ns/1ps

module tb_reset_sync;

    reg  clk = 0;
    reg  rst_n = 0;
    wire rst;

    integer err = 0;
    integer n   = 0;

    reset_sync dut (.clk(clk), .rst_n(rst_n), .rst(rst));

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

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
