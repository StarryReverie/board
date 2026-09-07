//=============================================================================
// instr_define.v — 计组实验一指令集宏（RV32I 子集，26 条冻结）
//   - 行为语义权威：doc/isa.md（v1.3）；实现口径：doc/top_design.md、doc/modules/decode.md
//   - 命名与取值沿用 ref/CPU/defines/instr_define.v（宏名对齐），本文件为
//     流水线工程的权威宏源；参考工程 ref/CPU/ 保持原样、不 include 本文件。
//   - 修改宏须先改 doc/isa.md 并登记变更记录。
//=============================================================================
`ifndef INSTR_DEFINE_V
`define INSTR_DEFINE_V

//------------------------------- opcode [6:0] -------------------------------
`define OP_R_TYPE   7'b0110011   // R 型运算（add/sub/sll/slt/sltu/xor/srl/sra/or/and）
`define OP_I_TYPE   7'b0010011   // I 型立即数运算（addi/slli/slti/sltiu/xori/srli/srai/ori/andi）
`define OP_LW       7'b0000011   // load（lw）
`define OP_SW       7'b0100011   // store（sw）
`define OP_BEQ      7'b1100011   // branch 族（beq/bne，宏名沿用参考工程）
`define OP_JALR     7'b1100111   // jalr
`define OP_LUI      7'b0110111   // lui
`define OP_JAL      7'b1101111   // jal

// 语义别名（decode 可读性；值同参考宏）
`define OP_LOAD    `OP_LW
`define OP_STORE   `OP_SW
`define OP_BRANCH  `OP_BEQ

//------------------------------- funct3 [14:12] ------------------------------
// 组名沿用参考工程；别名用于明确指令语义
`define F3_ADD_SUB  3'b000       // add/sub/addi/lw/sw/beq/jalr 的 funct3 为 000
`define F3_SLL      3'b001       // sll/slli（bne 的 funct3 亦为 001）
`define F3_SLT      3'b010       // slt/slti
`define F3_SLTU     3'b011       // sltu/sltiu
`define F3_XOR      3'b100       // xor/xori
`define F3_SRL_SRA  3'b101       // srl/srli/sra/srai
`define F3_OR       3'b110       // or/ori
`define F3_AND      3'b111       // and/andi
`define F3_BNE      3'b001       // 别名：bne
`define F3_JALR     3'b000       // 别名：jalr
`define F3_LW_SW    3'b010       // 别名：lw/sw（沿用参考）

//------------------------------- funct7 [31:25] ------------------------------
// R 型与 I 型移位共用同一定义：slli/srli 高 7 位为 0000000（F7_ADD），
// srai（R 型 sra）高 7 位为 0100000（F7_SUB_SRA）
`define F7_ADD      7'b0000000   // add/sll/slt/sltu/xor/srl/or/and + slli/srli
`define F7_SUB_SRA  7'b0100000   // sub/sra + srai

`endif // INSTR_DEFINE_V
