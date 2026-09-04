# alu 模块文档（算术逻辑单元，组合）

- `rtl/alu.v`（execute 内）。**近乎原样复用 `ref/CPU/alu.v`**，仅补 `zero` 输出与常量宏（`ALU_*` 见 `const_define.v`）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | alu_a / alu_b | 32/32 | 操作数（execute 的 A/B 源选择后） |
| in | alu_op | 4 | op |
| out | alu_out | 32 | 结果低 32 位 |
| out | flags | 5 | `{ZF,SF,CF,OF,PF}`（CF=result[32]） |
| out | zero | 1 | `alu_out==0`（分支比较） |

## 功能
- 33 位进位 `result`：ADD/SUB 取 33 位结果（CF=进位/借位）；SLT/SLTU 置 0/1；逻辑/移位按 `alu_b[4:0]`。
- 溢出 `OF`：ADD=同号相加异号出；SUB=异号相减结果为减数符号时溢出 → 附加功能"溢出判断"。
- `zero=1` 当 `alu_out==32'b0`（SUB 结果相等时为 1）。

## 连接
- 输入 ← execute 的 A/B mux；输出 → execute（alu_out/zero/of 供分支与结果）。

## 验收
- 逐 op 真值表（含边界）；`add` 正+正越界 OF=1；`sub` 相等 zero=1；移位取低 5 位。
