//=============================================================================
// tb_execute.v — execute 单测（doc/modules/execute.md 验收，T30）
//   前递 0/1/2 选路；src_a/b 选源（rs1/imm/pc/0/4）；ALU op 结果；
//   beq/bne 判决与目标；jal/jalr 恒 taken 与链接值；jalr 清 bit0；wdata=rs2_fwd。
//=============================================================================
`timescale 1ns/1ps
`include "defines/const_define.v"

module tb_execute;

    reg  [31:0] rs1_data, rs2_data;
    reg  [31:0] ex_fwd_val, wb_fwd_val;
    reg  [1:0]  fwd_a_sel, fwd_b_sel;
    reg  [31:0] idex_pc, imm;
    reg  [3:0]  alu_op;
    reg  [1:0]  src_a, src_b;
    reg  [1:0]  jump;
    reg         bne;
    wire [31:0] alu_out;
    wire [31:0] wdata;
    wire        zero, of, br_taken;
    wire [31:0] br_target;

    integer err = 0;
    integer n   = 0;

    execute dut (
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data),
        .ex_fwd_val (ex_fwd_val),
        .wb_fwd_val (wb_fwd_val),
        .fwd_a_sel  (fwd_a_sel),
        .fwd_b_sel  (fwd_b_sel),
        .idex_pc    (idex_pc),
        .imm        (imm),
        .alu_op     (alu_op),
        .src_a      (src_a),
        .src_b      (src_b),
        .jump       (jump),
        .bne        (bne),
        .alu_out    (alu_out),
        .wdata      (wdata),
        .zero       (zero),
        .of         (of),
        .br_taken   (br_taken),
        .br_target  (br_target)
    );

    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin
                err = err + 1;
                $display("FAIL: %0d %0s (out=%h wd=%h bt=%b tgt=%h)", n, name, alu_out, wdata, br_taken, br_target);
            end else begin
                $display("PASS: %0d %0s", n, name);
            end
        end
    endtask

    initial begin
        rs1_data=0; rs2_data=0; ex_fwd_val=0; wb_fwd_val=0;
        fwd_a_sel=0; fwd_b_sel=0; idex_pc=0; imm=0;
        alu_op=`ALU_ADD; src_a=0; src_b=0; jump=0; bne=0;

        // 1) 无前递：rs1+rs2
        rs1_data=32'd5; rs2_data=32'd3;
        #1 c("add reg+reg", alu_out==32'd8 && wdata==32'd3 && br_taken==0);
        // 2) src_b=imm
        src_b=2'b01; imm=32'd16;
        #1 c("addi imm", alu_out==32'd21);
        // 3) lui：src_a=0,src_b=imm,OR
        src_a=2'b10; src_b=2'b01; alu_op=`ALU_OR; imm=32'h12345000;
        #1 c("lui passthru", alu_out==32'h12345000);
        // 4) jal：pc+4 链接 & 目标 pc+imm
        src_a=2'b01; src_b=2'b10; alu_op=`ALU_ADD; idex_pc=32'h00000100; imm=32'd8; jump=2'b10;
        #1 c("jal link", alu_out==32'h00000104);
        #1 c("jal taken/tgt", br_taken==1 && br_target==32'h00000108);
        // 5) jalr：目标 rs1_fwd+imm 清 bit0（前递 A 源=EX/MEM）
        jump=2'b11; fwd_a_sel=2'b01; ex_fwd_val=32'h00000100; rs1_data=32'hDEAD0000; imm=32'd3;
        #1 c("jalr tgt", br_taken==1 && br_target==32'h00000102 && alu_out==32'h00000104);
        // 6) beq：相等 → taken，目标 pc+imm
        jump=2'b01; bne=0; fwd_a_sel=0; fwd_b_sel=0; src_a=0; src_b=0;
        alu_op=`ALU_SUB; rs1_data=32'd7; rs2_data=32'd7; idex_pc=32'h40; imm=32'h10;
        #1 c("beq equal taken", br_taken==1 && zero==1 && br_target==32'h00000050);
        rs2_data=32'd8;
        #1 c("beq neq not taken", br_taken==0 && zero==0);
        // 7) bne：反转
        bne=1; rs2_data=32'd8;
        #1 c("bne neq taken", br_taken==1);
        rs2_data=32'd7;
        #1 c("bne eq not taken", br_taken==0);
        // 8) wdata 前递（sw 存数源）：B 源=EX/MEM
        jump=2'b00; fwd_b_sel=2'b01; ex_fwd_val=32'h00ABCDEF; rs2_data=32'hFFFF0000;
        #1 c("wdata fwdB", wdata==32'h00ABCDEF);
        // 9) MEM/WB 前递源（sel=2）
        fwd_a_sel=2'b10; wb_fwd_val=32'h0F0F0F0F; rs1_data=32'h12345678; src_a=0;
        alu_op=`ALU_ADD; src_b=2'b00; rs2_data=0; fwd_b_sel=0;
        #1 c("fwd MEM/WB", alu_out==32'h0F0F0F0F);
        // 10) OF 出口（正+正溢出）
        fwd_a_sel=0; fwd_b_sel=0; alu_op=`ALU_ADD; rs1_data=32'h7FFFFFFF; rs2_data=1;
        #1 c("of flag", of==1);
        rs1_data=32'd1; rs2_data=32'd2;
        #1 c("of clear", of==0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
