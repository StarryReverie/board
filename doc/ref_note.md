# 单周期 CPU 参考梳理（设计继承清单）

> 参考工程：`ref/CPU/`（大三课程设计，RV32I，独立 git，**保持原样不改**）——流水线设计思想参考 + 报告"单周期"章节与性能对比数据源（已通读核验 2026-09-02）。

---

## 1. 工程结构速览

```
ref/CPU/
 ├─ cpu_top.v          顶层：仅 clk/rst；PC/rom/decoder/regfile/control/alu/ram 互联
 ├─ pc_reg.v           PC：pc_pred=pc+4；pc_next=pc_src?pc_branch:pc_pred；复位 0
 ├─ rom.v              指令存储 reg[7:0] mem[0:4095]，组合读，字={mem[a+3..a]}
 ├─ instr_decoder.v    拆 opcode/rd/funct3/rs1/rs2/funct7 + 五型立即数原始字段
 ├─ regfile.v          reg x[31:1]，x0 恒 0，waddr=0 不写，异步读/边缘写
 ├─ control.v          主译码（硬布线）：opcode 一级 case 出控制
 ├─ alu.v              33 位进位 result，flags{CF,ZF,SF,PF,OF}（含 OF 溢出判定）
 ├─ ram.v              数据存储 reg[7:0] mem[0:4095]，wmask 字节写，组合读/边缘写
 ├─ defines/           instr_define.v（OP_*/F3_*/F7_*）、const_define.v（ALU_*/flags/IMM_*）
 ├─ utils/rars1_6.jar  RARS（汇编/仿真参照）
 └─ test/              test0/test1/test_sort.asm + rom.hex + makefile + 结果
```

## 2. 继承项（流水线沿用其思想/宏/模块）

| 类别 | 参考点（文件） | 说明 |
|---|---|---|
| 宏 | `defines/instr_define.v` | `OP_R_TYPE/I_TYPE/LW/SW/BEQ/LUI/JAL`、`F3_*`、`F7_ADD/SUB_SRA` |
| 宏 | `defines/const_define.v` | `ALU_*`(10 op)、`ZF/SF/CF/OF/PF`、`IMM_I/S/B/U/J` |
| ALU | `alu.v` | 33 位进位、flags；`OF` 满足"附加功能-溢出判断"；**计划近乎原样复用** |
| 寄存器堆 | `regfile.v` | x[31:1]、x0=0、waddr=0 不写 |
| 分支目标 | `cpu_top.v` L70 | 专用加法器 `branch_target=pc+imm_b_sext`（注释：需单独加法器） |
| 立即数拆法 | `instr_decoder.v` | imm_I/S/B/U/J 原始字段位序重组（B/J 含位序打乱），沿用 |
| imm 扩展思路 | `cpu_top.v` | `imm_sel`+有/无符号多路选（流水线改为 ID 段产 imm 直送 ID/EX） |
| PC 思想 | `pc_reg.v` | `pc_pred/pc_next/pc_src/pc_branch` 命名与组合思路，流水线加 stall/flush |
| 指令集 | makefile | RV32I：`riscv64-linux-musl-as -march=rv32i -mabi=ilp32` |
| 镜像格式 | makefile → test*.hex | `objcopy -O verilog` 输出 `@00000000`+空格分隔字节，`$readmemh` 按字节装 mem（小端） |
| 回归样例 | `test/test0·test1·test_sort.asm` | ORI/ADD/SUB/SW/LW/BEQ + 注释预期 → 迁移为流水线 T31 回归 |
| 存储 | `rom.v/ram.v` | 字节数组 + wmask（sw 全字、预留字节写），小端重组 |

## 3. 必须改造项（单周期 → 流水线差异，记入 top_design）

| 差异 | 单周期做法 | 流水线做法 | 理由 |
|---|---|---|---|
| 控制信号 | control 组合直达各单元 | 随 4 组段间寄存器打拍，flush/bubble 清零 | 各段独立判段信号 |
| 分支 | 集中 `pc_src`，BEQ 用 flags[ZF] | EX 判决 + taken 冲刷 2 条(清 IF/ID+ID/EX) | 流水线需重取 |
| 数据冒险 | 无（每指令一拍读写完成） | 前递(EX/MEM、MEM/WB→EX) + load-use 冻结 | 新增冲突处理 |
| 访存 | rom/ram **组合读** | IMEM/DMEM **同步读** | 大数组组合读不可综合为 BRAM/下板不稳 |
| IMEM 装载 | 仅 TB `$readmemh` | `.vh`(initial 字面量) 供综合 | 综合 ROM 初始化需字面量 |
| 立即数 | 顶层 imm 多路选 | ID 段产 imm 后随 ID/EX 走 | 简化 EX |
| ori 扩展 | 零扩展(与规范不符) | 按规范**符号扩展** | 正确性；参考测试全为正小立即数，迁移不受影响 |

## 4. 参考数据的"不越界"原则

- 流水线是**新设计**；`ref/CPU/` 的代码/数据仅作参考与对比源，任何可能被误读为"流水线实现"的脚手架均需标注；性能对比引用大三数据时须注明来源（实验一定稿后追加）。

## 5. 变更记录

- 2026-09-04：行文精简（清单与结论不变）。
- 2026-09-02 v1.0：初版梳理。
