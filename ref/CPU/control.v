`timescale 1us/1ns
`include "defines/const_define.v"
`include "defines/instr_define.v"

module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    input  wire [4:0] flags,
    output reg  [3:0] alu_op,
    output reg        alu_src,      // 0: 寄存器, 1: 立即数
    output reg  [2:0] imm_sel,      // 立即数格式编码 (IMM_I/S/B/U/J)
    output reg        imm_unsigned, // 0: 有符号扩展, 1: 无符号扩展
    output reg        reg_write,
    output reg        mem_write,
    output reg        reg_src,   // 0: ALU结果, 1: 内存数据
    output reg        pc_src        // 0: pc_pred, 1: pc_branch
);

    always @(*) begin
        // 默认值
        alu_op       = `ALU_ADD;
        alu_src      = 1'b0;
        imm_sel      = 3'b000;
        imm_unsigned = 1'b0;
        reg_write    = 1'b0;
        mem_write    = 1'b0;
        reg_src      = 1'b0;
        pc_src       = 1'b0;

        case (opcode)
            `OP_R_TYPE: begin                       // R型: ADD / SUB
                reg_write = 1'b1;
                alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
            end

            `OP_I_TYPE: begin                       // I型: ORI
                reg_write    = 1'b1;
                alu_src      = 1'b1;
                imm_sel      = `IMM_I;
                imm_unsigned = 1'b1;                // ORI使用无符号扩展
                alu_op       = `ALU_OR;
            end

            `OP_LW: begin                           // LW
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = `IMM_I;
                reg_src   = 1'b1;
            end

            `OP_SW: begin                           // SW
                alu_src   = 1'b1;
                mem_write = 1'b1;
                imm_sel   = `IMM_S;                 // S型立即数
            end

            `OP_BEQ: begin                          // BEQ
                alu_op    = `ALU_SUB;
                pc_src    = flags[`ZF];
            end

            `OP_JAL: begin                          // JAL
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = `IMM_J;
                reg_src   = 1'b0;                 // 写回PC+4
            end

            default: begin
                // 保持默认
            end
        endcase
    end

endmodule
