// opcode
`define OP_R_TYPE   7'b0110011   // 寄存器-寄存器运算
`define OP_I_TYPE   7'b0010011   // 立即数运算
`define OP_LW       7'b0000011   // 加载字
`define OP_SW       7'b0100011   // 存储字
`define OP_BEQ      7'b1100011   // 相等分支
`define OP_LUI      7'b0110111   // 加载高位立即数
`define OP_JAL      7'b1101111   // 跳转并链接

// funct3
`define F3_ADD_SUB  3'b000       // ADD/SUB/BEQ
`define F3_SLT      3'b010       // SLT
`define F3_SLTU     3'b011       // SLTU
`define F3_AND      3'b111       // AND
`define F3_OR       3'b110       // OR
`define F3_XOR      3'b100       // XOR
`define F3_SLL      3'b001       // SLL
`define F3_SRL_SRA  3'b101       // SRL/SRA
`define F3_LW_SW    3'b010       // LW/SW

// funct7
`define F7_ADD      7'b0000000   // ADD
`define F7_SUB_SRA  7'b0100000   // SUB / SRA
