//=============================================================================
// tb_pc_reg.v — pc_reg 单测（doc/modules/pc_reg.md 验收，T30）
//   复位后 pc=0；en=0 保持；pc_src=1 取 pc_branch；否则 +4；异步复位。
//=============================================================================
`timescale 1ns/1ps

module tb_pc_reg;

    reg        clk = 0;
    reg        rst = 1;
    reg        en;
    reg        pc_src;
    reg [31:0] pc_branch;
    wire [31:0] pc;

    integer err = 0;

    pc_reg dut (
        .clk       (clk),
        .rst       (rst),
        .en        (en),
        .pc_src    (pc_src),
        .pc_branch (pc_branch),
        .pc        (pc)
    );

    always #5 clk = ~clk;

    task expect_pc;
        input [31:0] exp;
        begin
            if (pc !== exp) begin
                err = err + 1;
                $display("FAIL: pc=%h exp=%h (t=%0t)", pc, exp, $time);
            end else begin
                $display("PASS: pc=%h (t=%0t)", pc, exp);
            end
        end
    endtask

    initial begin
        en = 1; pc_src = 0; pc_branch = 32'h00000100;

        // 复位保持：复位期间 pc=0（异步）
        #2 expect_pc(32'h00000000);
        // 释放复位（异步高有效 rst=0）
        rst = 0;
        // 第 1 个沿（t=5）：pc<=0+4
        #5 expect_pc(32'h00000004);
        // 第 2 个沿：pc<=8
        #10 expect_pc(32'h00000008);
        // pc_src=1：取 pc_branch=0x100
        pc_src = 1;
        #10 expect_pc(32'h00000100);
        // 回到顺序执行
        pc_src = 0;
        #10 expect_pc(32'h00000104);
        // en=0：冻结两拍保持 0x104
        en = 0;
        #10 expect_pc(32'h00000104);
        #10 expect_pc(32'h00000104);
        // en=1 恢复
        en = 1;
        #10 expect_pc(32'h00000108);
        // 异步复位：沿间置 rst=1，pc 应立即回 0（不等时钟沿）
        rst = 1;
        #1 expect_pc(32'h00000000);
        // 复位期间即使有沿也保持 0
        #10 expect_pc(32'h00000000);
        // 再次释放
        rst = 0;
        #10 expect_pc(32'h00000004);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d)", err);
        $finish;
    end

endmodule
