//=============================================================================
// tb_decode.v — decode 单测（doc/modules/decode.md 26 行真值表验收，T30）
//   覆盖：R 型 10 条 op 映射、I 型（含移位 shamt/符号扩展）、lw/sw、
//   beq/bne、jal/jalr、lui、未知编码全 0、非法组合不产生写。
//=============================================================================
`timescale 1ns/1ps
`include "defines/instr_define.v"
`include "defines/const_define.v"

module tb_decode;

    reg  [31:0] inst;
    wire [4:0]  rd, rs1, rs2;
    wire [31:0] imm;
    wire [3:0]  alu_op;
    wire [1:0]  src_a, src_b;
    wire        mem_read, mem_write, mem_to_reg, reg_write;
    wire [1:0]  jump;
    wire        bne;

    integer err = 0;
    integer n   = 0;

    decode dut (
        .inst       (inst),
        .rd         (rd),
        .rs1        (rs1),
        .rs2        (rs2),
        .imm        (imm),
        .alu_op     (alu_op),
        .src_a      (src_a),
        .src_b      (src_b),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .reg_write  (reg_write),
        .jump       (jump),
        .bne        (bne)
    );

    // 逐项断言：满足则 PASS 否则 FAIL 计数
    task c;
        input [255:0] name;
        input         ok;
        begin
            n = n + 1;
            if (!ok) begin
                err = err + 1;
                $display("FAIL: %0d %0s", n, name);
            end else begin
                $display("PASS: %0d %0s", n, name);
            end
        end
    endtask

    task put;
        input [31:0] v;
        begin
            inst = v;
            #1;
        end
    endtask

    initial begin
        // ---------------- R 型 ----------------
        // add x2,x1,x3 = {f7=0, rs2=3, rs1=1, f3=0, rd=2, op=R}
        put({`F7_ADD, 5'd3, 5'd1, `F3_ADD_SUB, 5'd2, `OP_R_TYPE});
        c("add rd/rs", rd==5'd2 && rs1==5'd1 && rs2==5'd3);
        c("add alu_op", alu_op==`ALU_ADD);
        c("add ctrl", reg_write==1 && mem_read==0 && mem_write==0 && mem_to_reg==0 && jump==0 && bne==0);
        c("add src", src_a==2'b00 && src_b==2'b00);
        c("add imm=0", imm==32'h0);

        put({`F7_SUB_SRA, 5'd6, 5'd5, `F3_ADD_SUB, 5'd4, `OP_R_TYPE});
        c("sub alu_op", alu_op==`ALU_SUB && reg_write==1);
        put({`F7_SUB_SRA, 5'd6, 5'd5, `F3_SRL_SRA, 5'd4, `OP_R_TYPE});   // sra
        c("sra alu_op", alu_op==`ALU_SRA && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_SRL_SRA, 5'd4, `OP_R_TYPE});       // srl
        c("srl alu_op", alu_op==`ALU_SRL && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_SLL, 5'd4, `OP_R_TYPE});           // sll
        c("sll alu_op", alu_op==`ALU_SLL && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_SLT, 5'd4, `OP_R_TYPE});           // slt
        c("slt alu_op", alu_op==`ALU_SLT && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_SLTU, 5'd4, `OP_R_TYPE});          // sltu
        c("sltu alu_op", alu_op==`ALU_SLTU && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_XOR, 5'd4, `OP_R_TYPE});           // xor
        c("xor alu_op", alu_op==`ALU_XOR && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_OR, 5'd4, `OP_R_TYPE});            // or
        c("or alu_op", alu_op==`ALU_OR && reg_write==1);
        put({`F7_ADD, 5'd6, 5'd5, `F3_AND, 5'd4, `OP_R_TYPE});           // and
        c("and alu_op", alu_op==`ALU_AND && reg_write==1);

        // 非法 R 组合（funct7=SUB 配 f3=SLL）：不写
        put({`F7_SUB_SRA, 5'd6, 5'd5, `F3_SLL, 5'd4, `OP_R_TYPE});
        c("invalid R -> nop", reg_write==0 && mem_read==0 && mem_write==0 && jump==0);

        // ---------------- I 型 ----------------
        // addi x9,x0,-1
        put({12'hFFF, 5'd0, 3'b000, 5'd9, `OP_I_TYPE});
        c("addi imm sext=-1", imm==32'hFFFFFFFF);
        c("addi ctrl", reg_write==1 && alu_op==`ALU_ADD && src_b==2'b01 && src_a==2'b00 && jump==0);
        // slli x9,x1,5
        put({`F7_ADD, 5'd5, 5'd1, 3'b001, 5'd9, `OP_I_TYPE});
        c("slli imm=shamt5", imm==32'd5);
        c("slli alu", alu_op==`ALU_SLL && reg_write==1);
        // srli / srai
        put({`F7_ADD, 5'd7, 5'd1, 3'b101, 5'd9, `OP_I_TYPE});
        c("srli", alu_op==`ALU_SRL && imm==32'd7 && reg_write==1);
        put({`F7_SUB_SRA, 5'd7, 5'd1, 3'b101, 5'd9, `OP_I_TYPE});
        c("srai", alu_op==`ALU_SRA && imm==32'd7 && reg_write==1);
        // slti / sltiu / xori / ori / andi（符号扩展抽查）
        put({12'h801, 5'd1, 3'b010, 5'd9, `OP_I_TYPE});    // imm=-2047
        c("slti", alu_op==`ALU_SLT && reg_write==1 && imm==32'hFFFFF801);
        put({12'h001, 5'd1, 3'b011, 5'd9, `OP_I_TYPE});
        c("sltiu", alu_op==`ALU_SLTU && reg_write==1);
        put({12'h00F, 5'd1, 3'b100, 5'd9, `OP_I_TYPE});
        c("xori", alu_op==`ALU_XOR && reg_write==1);
        put({12'h00F, 5'd1, 3'b110, 5'd9, `OP_I_TYPE});
        c("ori", alu_op==`ALU_OR && reg_write==1);
        put({12'h00F, 5'd1, 3'b111, 5'd9, `OP_I_TYPE});
        c("andi", alu_op==`ALU_AND && reg_write==1);
        // 非法移位 funct7：不写
        put({7'b0000001, 5'd5, 5'd1, 3'b001, 5'd9, `OP_I_TYPE});
        c("invalid shift -> nop", reg_write==0);

        // ---------------- lw / sw ----------------
        // lw x10, 8(x11)
        put({12'h008, 5'd11, `F3_LW_SW, 5'd10, `OP_LW});
        c("lw ctrl", mem_read==1 && mem_to_reg==1 && reg_write==1 && mem_write==0);
        c("lw imm/src", imm==32'd8 && alu_op==`ALU_ADD && src_b==2'b01 && src_a==2'b00);
        c("lw fields", rd==5'd10 && rs1==5'd11);
        // sw x12, -4(x13)：S 型编码 imm=-4 → inst[31:25]=1111111, inst[11:7]=11100
        put({7'b1111111, 5'd12, 5'd13, `F3_LW_SW, 5'b11100, `OP_SW});
        c("sw ctrl", mem_write==1 && reg_write==0 && mem_read==0 && mem_to_reg==0);
        c("sw imm=-4", imm==32'hFFFFFFFC && rs2==5'd12 && rs1==5'd13);

        // ---------------- beq / bne ----------------
        // beq x1,x2,+8：imm=8 → imm[12]=0,imm[10:5]=0,imm[4:1]=4,imm[11]=0
        put({1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b0100, 1'b0, `OP_BEQ});
        c("beq ctrl", jump==2'b01 && bne==0 && reg_write==0 && alu_op==`ALU_SUB);
        c("beq imm", imm==32'd8);
        // bne x1,x2,-8
        put({1'b1, 6'b111111, 5'd2, 5'd1, 3'b001, 4'b1100, 1'b1, `OP_BEQ});
        c("bne ctrl", jump==2'b01 && bne==1 && imm==32'hFFFFFFF8);

        // ---------------- jal / jalr / lui ----------------
        // jal x1, 0
        put({1'b0, 10'b0000000000, 1'b0, 10'b0000000000, 1'b0, 5'd1, `OP_JAL});
        c("jal ctrl", jump==2'b10 && reg_write==1 && src_a==2'b01 && src_b==2'b10 && alu_op==`ALU_ADD);
        // jalr x2, 0(x3)
        put({12'h000, 5'd3, 3'b000, 5'd2, `OP_JALR});
        c("jalr ctrl", jump==2'b11 && reg_write==1 && rd==5'd2 && rs1==5'd3);
        // lui x6, 0x12345
        put({20'h12345, 5'd6, `OP_LUI});
        c("lui ctrl", reg_write==1 && alu_op==`ALU_OR && src_a==2'b10 && src_b==2'b01);
        c("lui imm", imm==32'h12345000);

        // ---------------- 未知/非法 ----------------
        put(32'hFFFFFFFF);
        c("unknown -> all-zero", reg_write==0 && mem_read==0 && mem_write==0 && mem_to_reg==0 && jump==0 && bne==0 && imm==32'h0);
        put({12'h000, 5'd3, 3'b111, 5'd2, `OP_LW});       // lw 非法 funct3
        c("lw bad f3", reg_write==0 && mem_read==0);
        put({12'h000, 5'd3, 3'b001, 5'd2, `OP_JALR});     // jalr 非法 funct3
        c("jalr bad f3", jump==0 && reg_write==0);

        if (err == 0) $display("=== ALL PASS ===");
        else          $display("=== FAIL === (%0d/%0d)", err, n);
        $finish;
    end

endmodule
