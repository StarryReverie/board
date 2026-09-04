//=============================================================================
// tb_if_id.v — if_id 单测（doc/modules/if_id.md 验收，T30）
//   rst 清零；常规沿沿打入；en=0 保持；flush 置 NOP(0x00000013) 且 pc 更新；
//   异步复位立即清零。
//=============================================================================
`timescale 1ns/1ps
`include "defines/const_define.v"

module tb_if_id;

    reg        clk = 0;
    reg        rst = 1;
    reg        en;
    reg        flush;
    reg [31:0] inst_in;
    reg [31:0] pc_in;
    wire [31:0] inst;
    wire [31:0] pc;

    integer err = 0;
    integer n   = 0;

    if_id dut (
        .clk     (clk),
        .rst     (rst),
        .en      (en),
        .flush   (flush),
        .inst_in (inst_in),
        .pc_in   (pc_in),
        .inst    (inst),
        .pc      (pc)
    );

    always #5 clk = ~clk;

    task chk;
        input [31:0] e_inst;
        input [31:0] e_pc;
        begin
            n = n + 1;
            if (inst !== e_inst || pc !== e_pc) begin
                err = err + 1;
                $display("FAIL: %0d inst=%h pc=%h exp inst=%h pc=%h", n, inst, pc, e_inst, e_pc);
            end else begin
                $display("PASS: %0d inst=%h pc=%h", n, inst, pc);
            end
        end
    endtask

    initial begin
        en = 1; flush = 0; inst_in = 32'b0; pc_in = 32'b0;

        // 复位期间输出 0
        #2 chk(32'h0, 32'h0);
        // 释放复位，第一沿（t=5）打入
        rst = 0;
        inst_in = 32'h11223344; pc_in = 32'h00000010;
        #5 chk(32'h11223344, 32'h00000010);
        // 常规再打入
        inst_in = 32'h55667788; pc_in = 32'h00000014;
        #10 chk(32'h55667788, 32'h00000014);
        // en=0：跨两沿保持
        en = 0;
        inst_in = 32'hDEADBEEF; pc_in = 32'h000000F0;
        #10 chk(32'h55667788, 32'h00000014);
        #10 chk(32'h55667788, 32'h00000014);
        // en=1 + flush：置 NOP，pc 正常更新
        en = 1; flush = 1;
        inst_in = 32'hFFFFFFFF; pc_in = 32'h00000018;
        #10 chk(`INST_NOP, 32'h00000018);
        // flush=0 恢复正常
        flush = 0;
        inst_in = 32'h00000013; pc_in = 32'h0000001C;
        #10 chk(32'h00000013, 32'h0000001C);
        // 异步复位：沿间置 rst=1 立即清零
        rst = 1;
        #2 chk(32'h0, 32'h0);
        #10 chk(32'h0, 32'h0);   // 复位期间即使有沿仍保持 0
        // 再次释放并打入
        rst = 0;
        inst_in = 32'hABCDEF01; pc_in = 32'h00000020;
        #10 chk(32'hABCDEF01, 32'h00000020);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
