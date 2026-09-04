//=============================================================================
// tb_alu.v — alu 单测（doc/modules/alu.md 验收口径，T30）
//   组合真值表 + 边界：逐 op；add 正+正溢出 OF=1；sub 相等 zero=1；
//   移位取低 5 位；flags{CF,SF,ZF,PF} 抽查。
//   约定：每项 PASS/FAIL 打印；结尾 === ALL PASS === / === FAIL ===
//=============================================================================
`timescale 1ns/1ps
`include "defines/const_define.v"

module tb_alu;

    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] out;
    wire [4:0]  flags;
    wire        zero;

    integer err = 0;
    integer n   = 0;

    alu dut (
        .alu_a  (a),
        .alu_b  (b),
        .alu_op (op),
        .alu_out(out),
        .flags  (flags),
        .zero   (zero)
    );

    // exp 期望；ez/ec/ef/... 期望标志（1=x 不查）
    task chk;
        input [31:0] exp_out;
        input        exp_zero;
        input        exp_cf;   // 1=x
        input        exp_of;   // 1=x
        input        exp_sf;   // 1=x
        input        exp_zf;   // 1=x
        begin
            n = n + 1;
            if (out !== exp_out) begin
                err = err + 1;
                $display("FAIL: %0d op=%h a=%h b=%h out=%h exp=%h", n, op, a, b, out, exp_out);
            end else begin
                if ((zero !== exp_zero) ||
                    (exp_cf !== 1'bx && flags[`CF] !== exp_cf) ||
                    (exp_of !== 1'bx && flags[`OF] !== exp_of) ||
                    (exp_sf !== 1'bx && flags[`SF] !== exp_sf) ||
                    (exp_zf !== 1'bx && flags[`ZF] !== exp_zf)) begin
                    err = err + 1;
                    $display("FAIL: %0d flags mismatch op=%h a=%h b=%h zero=%b flags=%b", n, op, a, b, zero, flags);
                end else begin
                    $display("PASS: %0d op=%h -> out=%h", n, op, out);
                end
            end
        end
    endtask

    initial begin
        // ---- ADD ----
        op = `ALU_ADD;
        a = 32'h00000001; b = 32'h00000002; #1 chk(32'h00000003, 0, 1'bx, 1'bx, 1'bx, 1'bx);
        // 正+正溢出：OF=1、结果符号翻转
        a = 32'h7FFFFFFF; b = 32'h00000001; #1 chk(32'h80000000, 0, 1'bx, 1'b1, 1'b1, 1'bx);
        // 进位：CF=1（0xFFFFFFFF+1）
        a = 32'hFFFFFFFF; b = 32'h00000001; #1 chk(32'h00000000, 1, 1'b1, 1'bx, 1'b0, 1'b1);
        // ---- SUB ----
        op = `ALU_SUB;
        a = 32'h00000005; b = 32'h00000005; #1 chk(32'h00000000, 1, 1'bx, 1'bx, 1'b0, 1'b1); // 相等 zero=1
        a = 32'h00000000; b = 32'h00000001; #1 chk(32'hFFFFFFFF, 0, 1'b1, 1'bx, 1'b1, 1'bx); // 借位 CF=1
        a = 32'h80000000; b = 32'h00000001; #1 chk(32'h7FFFFFFF, 0, 1'bx, 1'b1, 1'b0, 1'bx); // 溢出 OF=1
        // ---- SLT（有符号）/ SLTU ----
        op = `ALU_SLT;
        a = 32'hFFFFFFFF; b = 32'h00000000; #1 chk(32'h00000001, 0, 1'bx, 1'bx, 1'bx, 1'bx); // -1 < 0
        a = 32'h00000000; b = 32'hFFFFFFFF; #1 chk(32'h00000000, 1, 1'bx, 1'bx, 1'bx, 1'bx); // 0 < -1 为假 → 0
        op = `ALU_SLTU;
        a = 32'h00000001; b = 32'hFFFFFFFF; #1 chk(32'h00000001, 0, 1'bx, 1'bx, 1'bx, 1'bx); // 无符号 1<2^32-1
        a = 32'hFFFFFFFF; b = 32'h00000001; #1 chk(32'h00000000, 1, 1'bx, 1'bx, 1'bx, 1'bx);
        // ---- 逻辑 ----
        op = `ALU_AND; a = 32'hF0F0F0F0; b = 32'h0F0F0F0F; #1 chk(32'h00000000, 1, 1'bx, 1'bx, 1'bx, 1'b1);
        op = `ALU_OR;  a = 32'hF0F0F0F0; b = 32'h0F0F0F0F; #1 chk(32'hFFFFFFFF, 0, 1'bx, 1'bx, 1'b1, 1'bx);
        op = `ALU_XOR; a = 32'hFFFF0000; b = 32'hFF00FF00; #1 chk(32'h00FFFF00, 0, 1'bx, 1'bx, 1'bx, 1'bx);
        // ---- 移位（取 alu_b[4:0]）----
        op = `ALU_SLL; a = 32'h00000001; b = 32'h0000001F; #1 chk(32'h80000000, 0, 1'bx, 1'bx, 1'b1, 1'bx); // 1<<31
        op = `ALU_SRL; a = 32'h80000000; b = 32'h00000001; #1 chk(32'h40000000, 0, 1'bx, 1'bx, 1'bx, 1'bx); // 逻辑右移
        op = `ALU_SRA; a = 32'h80000000; b = 32'h00000001; #1 chk(32'hC0000000, 0, 1'bx, 1'bx, 1'b1, 1'bx); // 算术右移（符号扩展）
        // ---- 奇偶标志 PF（偶=1，低 8 位）----
        op = `ALU_OR; a = 32'h00000003; b = 32'h0; #1 chk(32'h00000003, 0, 1'bx, 1'bx, 1'bx, 1'bx);
        if (flags[`PF] !== 1'b1) begin err = err + 1; $display("FAIL: PF even=1 expected"); end
        else $display("PASS: PF even parity (0x03 -> 1)");
        a = 32'h00000001; b = 32'h0; #1
        if (flags[`PF] !== 1'b0) begin err = err + 1; $display("FAIL: PF odd=0 expected"); end
        else $display("PASS: PF odd parity (0x01 -> 0)");

        // ---- 未知 op 归 0 ----
        op = 4'hF; a = 32'hDEADBEEF; b = 32'h00000001; #1 chk(32'h00000000, 1, 1'bx, 1'bx, 1'b0, 1'b1);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
