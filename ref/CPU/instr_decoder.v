`timescale 1us/1ns

module instr_decoder(
    input wire [31:0] instr,
    output wire [6:0] opcode,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [6:0] funct7,

    // 五种立即数的原始格式
    output wire [11:0] imm_I,
    output wire [11:0] imm_S,
    output wire [12:1] imm_B,
    output wire [31:12] imm_U,
    output wire [20:1] imm_J
);
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    assign imm_I = instr[31:20];
    assign imm_S = {instr[31:25], instr[11:7]};
    assign imm_B = {instr[31], instr[7], instr[30:25], instr[11:8]};
    assign imm_U = instr[31:12];
    assign imm_J = {instr[31], instr[19:12], instr[20], instr[30:21]};
endmodule