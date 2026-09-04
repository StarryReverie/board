# RV32I 流水线 CPU 指令集子集

- 版本：v1.2（2026-09-04 行文精简）。参照 RISC-V RV32I 官方编码；宏沿用 `ref/CPU/defines/`。供汇编器、校验脚本、TB 与报告引用。
- 文档分工：本文件只定义指令集**范围与行为**；实现口径（译码表、ALU op、EX 判决、冲突策略）见 `top_design.md` 与 `modules/*.md`，不一致以本文件语义为准并先修实现文档。

---

## 1. 指令清单（26 条，≥16，三类齐全）

> 公共语义：x0 恒 0 且写无效；32 位字运算，结果回卷。

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

I 型运算 `opcode=0010011`（9 条；imm 扩展见 §2，移位仅用 `shamt=inst[24:20]`，高位为 funct7）：

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

> 未纳入本轮：`auipc` 与字节/半字访存（lb/lbu/lh/lhu/sb/sh）不实现；需要时再扩展（同步更新本文件）。

### 1.3 控制类（4 条）

| 指令 | opcode | funct3 | 行为 |
|---|---|---|---|
| beq | 1100011 | 000 | rs1==rs2 → pc=pc+sext(imm_B)；否则 pc=pc+4 |
| bne | 1100011 | 001 | rs1≠rs2 → pc=pc+sext(imm_B)；否则 pc=pc+4 |
| jal | 1101111 | — | rd=pc+4；pc=pc+sext(imm_J) |
| jalr | 1100111 | 000 | rd=pc+4；pc=(rs1+sext(imm_I)) & ~1 |

> 表中 `pc`=本条指令自身地址；B/J 为相对 PC 的字节偏移（编码见 §2）。

---

## 2. 编码速查（字段位段，位 0 为最低）

- opcode=instr[6:0]；rd=instr[11:7]；funct3=instr[14:12]；rs1=instr[19:15]；rs2=instr[24:20]；funct7=instr[31:25]。
- 立即数原始字段（与 RV32I 官方一致；B/J 位序打乱）：
  - imm_I = instr[31:20]
  - imm_S = {instr[31:25], instr[11:7]}
  - imm_B = {instr[31], instr[7], instr[30:25], instr[11:8]}
  - imm_U = instr[31:12]
  - imm_J = {instr[31], instr[19:12], instr[20], instr[30:21]}
- 立即数语义：非移位立即数一律**符号扩展**到 32 位；移位仅取 `shamt=inst[24:20]`（0..31）；B/J 偏移为字节偏移（imm 最低位补 0，目标 2 字节对齐）。

---

## 3. 伪指令白名单（展开后必须是上表指令）

| 伪指令 | 展开 | 备注 |
|---|---|---|
| nop | addi x0,x0,0 | =32'h00000013 |
| j label | jal x0,label | |
| ret | jalr x0,0(ra) | |
| li rd,imm | (小)addi/(大)lui+addi | 由汇编器展开 |
| mv rd,rs | addi rd,rs,0 | |

> 测试汇编不得出现表外指令；`verify_hex.py` 用 objdump 反查，越界即构建失败。

---

## 4. 存储器与停机约定（程序可见）

- **IMEM**（指令）：字节地址 `0x0000_0000` 起，容量 `IMEM_WORDS`（默认 1024×32bit=4KB），只读，PC 每次 +4。
- **DMEM**（数据）：字节地址 `0x0000_0000` 起，容量 `DMEM_WORDS`（默认 1024×32bit=4KB），可读写。IMEM/DMEM 为**相互独立的地址空间**（哈佛），同为 0 起互不冲突。
- 对齐：lw/sw 的 EA 须 4 字节对齐（测试保证；未对齐无定义）。字节序：**小端**，字={mem[ba+3],mem[ba+2],mem[ba+1],mem[ba]}。
- 无异常/自陷：指令清单外的编码无定义行为（decode 按 NOP 处理），不产生 trap。
- HALT：无停机指令；程序末尾以自循环 `halt: beq x0,x0,halt` 收尾（TB 判 PC 连续不变即停机并比对终值）。无 MMIO 槽（实验二再加）。

---

## 5. 指令数统计（对 require 达标）

运算类 19（R10+I9）、传送类 3（lui/lw/sw）、控制类 4（beq/bne/jal/jalr）⇒ 共 26 ≥ 16；三类齐全。✔

---

## 6. 变更记录

- v1.2 2026-09-04：行文精简。
- v1.1 2026-09-02：评审修订（收敛"范围+行为"口径、修 sltiu 语义与条数表头）。
- v1.0 2026-09-02：初拟 26 条子集。
