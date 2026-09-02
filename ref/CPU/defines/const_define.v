// ALU 操作码
`define ALU_ADD  4'b0000
`define ALU_SUB  4'b0001
`define ALU_SLT  4'b0010
`define ALU_AND  4'b0011
`define ALU_OR   4'b0100
`define ALU_XOR  4'b0101
`define ALU_SLL  4'b0110
`define ALU_SRL  4'b0111
`define ALU_SRA  4'b1000
`define ALU_SLTU 4'b1001

// 标志位
`define ZF 4
`define SF 3
`define CF 2
`define OF 1
`define PF 0

// imm_sel
`define IMM_I  3'b001    // I型
`define IMM_S  3'b010    // S型
`define IMM_B  3'b011    // B型
`define IMM_U  3'b100    // U型
`define IMM_J  3'b101    // J型