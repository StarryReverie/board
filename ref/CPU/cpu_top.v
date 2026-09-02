`timescale 1us/1ns
`include "defines/instr_define.v"
`include "defines/const_define.v"

module cpu_top (
    input  wire       clk,
    input  wire       rst
);
    // PC
    wire [31:0] pc, pc_next;
    wire        pc_src;
    wire [31:0] branch_target;

    // 指令通路
    wire [31:0] instr;

    // 译码
    wire [6:0]  opcode;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [11:0] imm_I, imm_S;
    wire [12:1] imm_B;
    wire [31:12] imm_U;
    wire [20:1] imm_J;

    // 寄存器文件
    wire [31:0] rdata1, rdata2, reg_wdata;
    wire        reg_write;

    // 控制
    wire [3:0]  alu_op;
    wire        alu_src;
    wire [2:0]  imm_sel;
    wire        imm_unsigned, mem_write, reg_src;

    // ALU
    wire [31:0] alu_out;
    wire [4:0]  flags;

    // 数据存储器
    wire [31:0] mem_out;

    // 立即数扩展 — 5种格式 × 2种扩展 (有符号/无符号)
    wire [31:0] imm_i_sext = {{20{imm_I[11]}}, imm_I};         // I型有符号
    wire [31:0] imm_i_zext = {20'b0, imm_I};                   // I型无符号
    wire [31:0] imm_s_sext = {{20{imm_S[11]}}, imm_S};         // S型有符号
    wire [31:0] imm_s_zext = {20'b0, imm_S};                   // S型无符号
    wire [31:0] imm_b_sext = {{19{imm_B[12]}}, imm_B, 1'b0};   // B型有符号
    wire [31:0] imm_b_zext = {19'b0, imm_B, 1'b0};             // B型无符号
    wire [31:0] imm_u_sext = {{12{imm_U[31]}}, imm_U[31:12]};  // U型有符号
    wire [31:0] imm_u_zext = {12'b0, imm_U[31:12]};            // U型无符号
    wire [31:0] imm_j_sext = {{11{imm_J[20]}}, imm_J[20:1], 1'b0};  // J型有符号
    wire [31:0] imm_j_zext = {11'b0, imm_J[20:1], 1'b0};            // J型无符号

    // ALU B MUX
    wire [31:0] alu_b = !alu_src ? rdata2 :
                        (imm_sel == `IMM_I) ? (imm_unsigned ? imm_i_zext : imm_i_sext) :
                        (imm_sel == `IMM_S) ? (imm_unsigned ? imm_s_zext : imm_s_sext) :
                        (imm_sel == `IMM_B) ? (imm_unsigned ? imm_b_zext : imm_b_sext) :
                        (imm_sel == `IMM_U) ? (imm_unsigned ? imm_u_zext : imm_u_sext) :
                        (imm_sel == `IMM_J) ? (imm_unsigned ? imm_j_zext : imm_j_sext) :
                        32'b0;

    // 写回数据 MUX
    assign reg_wdata = reg_src ? mem_out : alu_out;

    // 分支目标计算
    // 需单独一个加法器，alu需要能同时进行
    assign branch_target = pc + imm_b_sext;


    // 模块实例
    pc_reg u_pc (
        .clk        (clk),
        .rst        (rst),
        .pc_src     (pc_src),
        .pc_branch  (branch_target),
        .pc         (pc)
    );

    rom u_rom (
        .addr       (pc),
        .instr      (instr)
    );

    instr_decoder u_decoder (
        .instr      (instr),
        .opcode     (opcode),
        .rd         (rd),
        .funct3     (funct3),
        .rs1        (rs1),
        .rs2        (rs2),
        .funct7     (funct7),
        .imm_I      (imm_I),
        .imm_S      (imm_S),
        .imm_B      (imm_B),
        .imm_U      (imm_U),
        .imm_J      (imm_J)
    );

    regfile u_regfile (
        .clk        (clk),
        .rst        (rst),
        .raddr1     (rs1),
        .raddr2     (rs2),
        .waddr      (rd),
        .wdata      (reg_wdata),
        .we         (reg_write),
        .rdata1     (rdata1),
        .rdata2     (rdata2)
    );

    control u_control (
        .opcode       (opcode),
        .funct3       (funct3),
        .funct7       (funct7),
        .flags        (flags),
        .alu_op       (alu_op),
        .alu_src      (alu_src),
        .imm_sel      (imm_sel),
        .imm_unsigned (imm_unsigned),
        .reg_write    (reg_write),
        .mem_write    (mem_write),
        .reg_src      (reg_src),
        .pc_src       (pc_src)
    );

    alu u_alu (
        .alu_a      (rdata1),
        .alu_b      (alu_b),
        .alu_op     (alu_op),
        .alu_out    (alu_out),
        .flags      (flags)
    );

    ram u_ram (
        .clk        (clk),
        .addr       (alu_out),
        .wdata      (rdata2),
        .wmask      (4'b1111),
        .we         (mem_write),
        .rdata      (mem_out)
    );

endmodule
