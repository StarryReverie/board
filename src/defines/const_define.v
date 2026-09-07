//=============================================================================
// const_define.v — 计组实验一常量宏
//   - ALU 操作码 / 标志位位号 / 立即数格式沿用 ref/CPU/defines/const_define.v
//   - 新增：存储规模（IMEM_WORDS/DMEM_WORDS）、NOP 指令编码
//   - 修改须先改 doc/top_design.md §2/§6 与 doc/isa.md 并登记变更记录
//=============================================================================
`ifndef CONST_DEFINE_V
`define CONST_DEFINE_V

//------------------------------- ALU 操作码 [3:0] ----------------------------
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

//------------------------------- 标志位位号（flags[4:0]） ---------------------
// flags = {ZF,SF,CF,OF,PF}（alu 输出，33 位进位结果产生 CF/OF）
`define ZF 4      // 零标志
`define SF 3      // 符号标志
`define CF 2      // 进位/借位
`define OF 1      // 溢出（附加功能"溢出判断"）
`define PF 0      // 奇偶标志

//------------------------------- 立即数格式选择 ------------------------------
`define IMM_I  3'b001    // I 型
`define IMM_S  3'b010    // S 型
`define IMM_B  3'b011    // B 型
`define IMM_U  3'b100    // U 型
`define IMM_J  3'b101    // J 型

//------------------------------- 存储规模（top_design §6） --------------------
// 容量可参数化：仿真/契约默认 1024 字=4KB×2；**下板 build 缩容为
// IMEM 128 字=512B、DMEM 64 字=256B**（组合读寄存器阵列：4KB×2=65k FF
// > XC7A35T/100T 容量且时序引擎卡死；1KB×2 需 35.5k LUT > 20.8k 超限；
// 512B/256B 实测 LUT/FF 均收敛，2026-09-07 上板通过，见 exp2/doc/tasks.md）。
// 覆盖方式：综合时 verilog_define 须**成对**提供 IMEM_WORDS/DMEM_WORDS/IMEM_BYTES/
// DMEM_BYTES（须成对给全；默认 1024 字 4KB 不变）。
`ifndef IMEM_WORDS
`define IMEM_WORDS 1024   // 指令存储字数（×32bit，默认 4KB）
`endif
`ifndef DMEM_WORDS
`define DMEM_WORDS 1024   // 数据存储字数（×32bit，默认 4KB）
`endif
`ifndef IMEM_BYTES
`define IMEM_BYTES (1024*4)   // 须与 IMEM_WORDS 成对覆盖（xvlog 宏体内不递归展开，无法由 WORDS 派生）
`endif
`ifndef DMEM_BYTES
`define DMEM_BYTES (1024*4)   // 须与 DMEM_WORDS 成对覆盖
`endif

//------------------------------- 杂项 ----------------------------------------
`define INST_NOP 32'h00000013  // nop = addi x0,x0,0（if_id 冲刷 / 气泡填充值）

`endif // CONST_DEFINE_V
