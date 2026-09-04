# decode 模块文档（译码组合：主译码 + 立即数扩展 + load-use 检测）

- `src/rtl/decode.v`（译码段纯组合）。参考 `ref/CPU/instr_decoder.v`（拆字段）与 `ref/CPU/control.v`（译码）；改造：按 isa.md 指令清单 26 条全译码、控制信号成组输出。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | inst | 32 | IF/ID 输出的当前指令 |
| out | rd / rs1 / rs2 | 5/5/5 | 字段拆解（rs1/rs2 供 regfile 读与 hazard） |
| out | imm | 32 | 按格式完成的符号扩展立即数 |
| out | alu_op | 4 | ALU op（`ALU_*`） |
| out | src_a / src_b | 2/2 | ALU A/B 源选择（top_design §2） |
| out | mem_read / mem_write | 1/1 | MEM 控制 |
| out | mem_to_reg / reg_write | 1/1 | WB 控制 |
| out | jump | 2 | 0=无 1=分支 2=jal 3=jalr |
| out | bne | 1 | 1=bne（配合 jump=1） |

## 译码真值表（26 条）
| 指令 | alu_op | src_a | src_b | mem_r | mem_w | mem2reg | reg_w | jump | bne |
|---|---|---|---|---|---|---|---|---|---|
| add | ADD | rs1 | rs2 | 0 | 0 | 0 | 1 | 0 | 0 |
| sub | SUB | rs1 | rs2 | 0 | 0 | 0 | 1 | 0 | 0 |
| sll/srl/sra | SLL/SRL/SRA | rs1 | rs2 | 0 | 0 | 0 | 1 | 0 | 0 |
| slt/sltu | SLT/SLTU | rs1 | rs2 | 0 | 0 | 0 | 1 | 0 | 0 |
| xor/or/and | XOR/OR/AND | rs1 | rs2 | 0 | 0 | 0 | 1 | 0 | 0 |
| addi | ADD | rs1 | imm | 0 | 0 | 0 | 1 | 0 | 0 |
| slti/sltiu | SLT/SLTU | rs1 | imm | 0 | 0 | 0 | 1 | 0 | 0 |
| xori/ori/andi | XOR/OR/AND | rs1 | imm | 0 | 0 | 0 | 1 | 0 | 0 |
| slli/srli/srai | SLL/SRL/SRA | rs1 | imm(=shamt zext) | 0 | 0 | 0 | 1 | 0 | 0 |
| lw | ADD | rs1 | imm | 1 | 0 | 1 | 1 | 0 | 0 |
| sw | ADD | rs1 | imm | 0 | 1 | x | 0 | 0 | 0 |
| lui | OR | 0 | imm | 0 | 0 | 0 | 1 | 0 | 0 |
| beq | SUB | rs1 | rs2 | 0 | 0 | 0 | 0 | 1 | 0 |
| bne | SUB | rs1 | rs2 | 0 | 0 | 0 | 0 | 1 | 1 |
| jal | ADD | pc | 4 | 0 | 0 | 0 | 1 | 2 | 0 |
| jalr | ADD | pc | 4 | 0 | 0 | 0 | 1 | 3 | 0 |

（“x”=无关，默认 0。默认值=全 0：NOP/无效指令退化为气泡。）

## 立即数（isa.md §2）
- I 型(除移位)：`{{20{inst[31]}},inst[31:20]}`；移位 imm=`{27'b0,inst[24:20]}`（shamt）。
- S 型：`{{20{inst[31]}}, inst[31:25], inst[11:7]}`；B 型：`{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}`。
- U 型(lui)：`{inst[31:12], 12'b0}`；J 型(jal)：`{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}`。

## 连接
- inst ← if_id.inst；输出 → regfile(rs1/rs2 地址)、id_ex 的 ctrl/imm/rd 字段；rs1/rs2 送 hazard_unit 作 load-use/前递判据（判定与冻结见 hazard/id_ex 文档）。

## 验收
- 26 条指令 ctrl 与上表一致；imm 五型符号扩展边界（± 全 1/全 0）正确；未知 opcode 输出全 0。
