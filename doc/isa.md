# RV32I 流水线 CPU 指令集子集（冻结契约）

- 版本：v1.1（2026-09-02 评审修订），冻结前可评审，冻结后改指令先改本文件。
- 参照：RISC-V RV32I 官方编码；宏命名沿用 `ref/CPU/defines/`（`instr_define.v`、`const_define.v`）。
- 本子集供**流水线 CPU** 与后续工具/校验脚本共用。

> **文档分工**：本文件只定义指令集的**范围与行为**（每条指令的编码、语义、存储器/停机约定），供汇编器、`verify_hex.py`、TB 与报告引用。
> **实现口径**（译码真值表、ALU op 映射、EX 段判决/目标加法器、前递/冻结/冲刷）见 `doc/top_design.md` 与 `doc/modules/*.md`；
> 两者如不一致，以本文件的语义为准，并先修正实现文档。

---

## 1. 冻结指令清单（26 条，≥16，三类齐全）

> 公共语义：寄存器号 0..31，`x0` 恒 0 且写入无效（丢弃）；运算在 32 位字上进行，结果截断回卷（不产生异常/自陷）。

### 1.1 运算类（R 型 + I 型立即数）
R 型 `opcode=0110011`（10 条）：

| 指令 | funct7 | funct3 | 行为 |
|---|---|---|---|
| add | 0000000 | 000 | rd=rs1+rs2 |
| sub | 0100000 | 000 | rd=rs1-rs2 |
| sll | 0000000 | 001 | rd=rs1<<shamt，shamt=rs2[4:0] |
| slt | 0000000 | 010 | rd=(rs1<rs2)，有符号比较 |
| sltu | 0000000 | 011 | rd=(rs1<rs2)，无符号比较 |
| xor | 0000000 | 100 | rd=rs1^rs2 |
| srl | 0000000 | 101 | rd=rs1>>shamt，逻辑右移 |
| sra | 0100000 | 101 | rd=rs1>>shamt，算术右移 |
| or | 0000000 | 110 | rd=rs1\|rs2 |
| and | 0000000 | 111 | rd=rs1&rs2 |

I 型运算 `opcode=0010011`（9 条；非移位立即数符号扩展到 32 位；移位仅用 `shamt=inst[24:20]`，`inst[31:25]` 为 funct7）：

| 指令 | funct3 | funct7/特判 | 行为 |
|---|---|---|---|
| addi | 000 | — | rd=rs1+sext(imm_I) |
| slli | 001 | funct7=0000000 | rd=rs1<<shamt |
| slti | 010 | — | rd=(rs1<sext(imm_I))，有符号比较 |
| sltiu | 011 | — | rd=(rs1<sext(imm_I))，无符号比较（立即数仍先符号扩展，再整体按无符号比） |
| xori | 100 | — | rd=rs1^sext(imm_I) |
| srli | 101 | funct7=0000000 | rd=rs1>>shamt，逻辑右移 |
| srai | 101 | funct7=0100000 | rd=rs1>>shamt，算术右移 |
| ori | 110 | — | rd=rs1\|sext(imm_I) |
| andi | 111 | — | rd=rs1&sext(imm_I) |

### 1.2 传送/访存类（3 条）
| 指令 | opcode | funct3 | 行为 |
|---|---|---|---|
| lui | 0110111 | — | rd={inst[31:12],12'b0}（20 位立即数装入高 20 位） |
| lw | 0000011 | 010 | EA=rs1+sext(imm_I)（4 对齐）；rd=DMEM[EA]（小端取 32 位） |
| sw | 0100011 | 010 | EA=rs1+sext(imm_S)（4 对齐）；DMEM[EA]=rs2 |

> 未冻结：`auipc` 与字节/半字访存（lb/lbu/lh/lhu/sb/sh）本轮不实现；实验二需要时再扩展并回改本文件。

### 1.3 控制类（4 条）
| 指令 | opcode | funct3 | 行为 |
|---|---|---|---|
| beq | 1100011 | 000 | rs1==rs2 → pc=pc+sext(imm_B)；否则 pc=pc+4 |
| bne | 1100011 | 001 | rs1≠rs2 → pc=pc+sext(imm_B)；否则 pc=pc+4 |
| jal | 1101111 | — | rd=pc+4；pc=pc+sext(imm_J) |
| jalr | 1100111 | 000 | rd=pc+4；pc=(rs1+sext(imm_I)) & ~1 |

> 语义约定：表中 `pc` 均指**本条指令自身的地址**；B/J 目标为相对 PC 的字节偏移（编码见 §2），仍落在同一 32 位地址空间。bne 与 beq 由 funct3 区分。

---

## 2. 编码速查（字段位段，位 0 为最低）
- opcode=instr[6:0]；rd=instr[11:7]；funct3=instr[14:12]；rs1=instr[19:15]；rs2=instr[24:20]；funct7=instr[31:25]。
- 立即数原始字段（与 RV32I 官方一致；B/J 位序打乱）：
  - imm_I = instr[31:20]
  - imm_S = {instr[31:25], instr[11:7]}
  - imm_B = {instr[31], instr[7], instr[30:25], instr[11:8]}
  - imm_U = instr[31:12]
  - imm_J = {instr[31], instr[19:12], instr[20], instr[30:21]}
- 立即数语义：非移位立即数一律**符号扩展**到 32 位；移位仅取 `shamt=inst[24:20]`（0..31）；B/J 偏移值为字节偏移（imm 最低位补 0，目标 2 字节对齐）。

---

## 3. 伪指令白名单（测试程序可用，展开后必须是上表指令）
| 伪指令 | 展开 | 备注 |
|---|---|---|
| nop | addi x0,x0,0 | =32'h00000013 |
| j label | jal x0,label | |
| ret | jalr x0,0(ra) | |
| li rd,imm | (小)addi/(大)lui+addi | 由汇编器展开，`verify_hex.py` 校验终产物仅含上表指令 |
| mv rd,rs | addi rd,rs,0 | |

> 测试汇编不得出现上表以外的指令。`verify_hex.py` 用 objdump 反查，越界即构建失败。

---

## 4. 存储器与停机约定（程序可见）
- **IMEM**（指令）：字节地址 `0x0000_0000` 起；容量 `IMEM_WORDS`（默认 1024×32bit=4KB）；只读。PC 每次 +4。
- **DMEM**（数据）：字节地址 `0x0000_0000` 起；容量 `DMEM_WORDS`（默认 1024×32bit=4KB）；可读写。IMEM/DMEM 为**相互独立的地址空间**（哈佛），同为 0 起互不冲突。
- 对齐：lw/sw 的 EA 必须 4 字节对齐（测试保证；未对齐行为无定义）。
- 字节序：**小端**，字={mem[ba+3],mem[ba+2],mem[ba+1],mem[ba]}。
- 无异常/自陷：未冻结的指令编码无定义行为（按 NOP 处理，见 decode 默认值），本机不产生 trap。
- HALT：无停机指令；程序末尾以自循环 `halt: beq x0,x0,halt` 收尾（TB 判 PC 连续不变即停机并比对终值）。无 MMIO 槽（实验二再加）。

---

## 5. 指令数统计（对 require 达标）
运算类 19（R10+I9）、传送类 3（lui/lw/sw）、控制类 4（beq/bne/jal/jalr）⇒ 共 26 ≥ 16；三类齐全。✔

---

## 6. 变更记录
- v1.1 2026-09-02：评审修订，收敛为纯"范围+行为"口径——删除实现级注记（原 1.1 的 ALU op 宏映射、1.3 的 EX 判决/目标加法器说明、2 的"专用加法器"句；这些已由 top_design/decode/execute/ref_note 表述）；ori 零扩展迁移注记移归 `ref_note.md` §3；修正 1.2 表头条数、明确 sltiu 无符号比较语义。
- v1.0 2026-09-02：冻结 26 条子集。
