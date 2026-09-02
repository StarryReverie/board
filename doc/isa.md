# RV32I 流水线 CPU 指令集子集（冻结契约）

- 版本：v1.0（2026-09-02），冻结前可评审，冻结后改指令先改本文件。
- 参照：RISC-V RV32I 官方编码；宏命名沿用 `ref/CPU/defines/`（`instr_define.v`、`const_define.v`）。
- 本子集供**流水线 CPU** 与后续工具/校验脚本共用。

---

## 1. 冻结指令清单（26 条，≥16，三类齐全）

### 1.1 运算类（R 型 + I 型立即数）
R 型 `opcode=0110011`（10 条）：

| 指令 | funct7 | funct3 | 说明 |
|---|---|---|---|
| add | 0000000 | 000 | rd=rs1+rs2 |
| sub | 0100000 | 000 | rd=rs1-rs2 |
| sll | 0000000 | 001 | 逻辑左移，shamt=rs2[4:0] |
| slt | 0000000 | 010 | rd=(rs1<rs2) 有符号 |
| sltu | 0000000 | 011 | rd=(rs1<rs2) 无符号 |
| xor | 0000000 | 100 | 按位异或 |
| srl | 0000000 | 101 | 逻辑右移 |
| sra | 0100000 | 101 | 算术右移 |
| or | 0000000 | 110 | 按位或 |
| and | 0000000 | 111 | 按位与 |

I 型运算 `opcode=0010011`（9 条，立即数符号扩展；移位用 `shamt=imm[4:0]`）：

| 指令 | funct3 | funct7/特判 | 说明 |
|---|---|---|---|
| addi | 000 | — | rd=rs1+sext(imm) |
| slli | 001 | funct7=0000000 | rd=rs1<<shamt |
| slti | 010 | — | rd=(rs1<sext(imm)) 有符号 |
| sltiu | 011 | — | rd=(rs1<zext 语义) 无符号比较 |
| xori | 100 | — | 按位异或 |
| srli | 101 | funct7=0000000 | 逻辑右移 |
| srai | 101 | funct7=0100000 | 算术右移 |
| ori | 110 | — | 按位或（**按 RV 规范符号扩展**；单周期参考曾零扩展，仅正小立即数时结果相同，故 test0/test1 可迁移） |
| andi | 111 | — | 按位与 |

> ALU op 宏沿用 `const_define.v`：`ALU_ADD/SUB/SLT/AND/OR/XOR/SLL/SRL/SRA/SLTU`。I 型把 `{slti,sltiu,xori,ori,andi,addi}` 译到对应 ALU op；移位译到 SLL/SRL/SRA。

### 1.2 传送/访存类（4 条）
| 指令 | opcode | funct3 | 说明 |
|---|---|---|---|
| lui | 0110111 | — | rd={imm[31:12],12'b0} |
| lw | 0000011 | 010 | rd=DMEM[rs1+sext(imm)]，字节地址 4 对齐 |
| sw | 0100011 | 010 | DMEM[rs1+sext(imm)]=rs2，4 对齐 |
| auipc | — | — | **不实现**（未冻结） |

> 传送类含 lui 与 lw/sw。字节/半字指令(lb/lbu/sb/…)本轮不实现，实验二需字节 I/O 时再扩展并回改本文件。

### 1.3 控制类（4 条）
| 指令 | opcode | funct3 | 说明 |
|---|---|---|---|
| beq | 1100011 | 000 | rs1==rs2 分支 |
| bne | 1100011 | 001 | rs1!=rs2 分支 |
| jal | 1101111 | — | rd=pc+4；pc=pc+sext(imm_J) |
| jalr | 1100111 | 000 | rd=pc+4；pc=(rs1+sext(imm_I)) & ~1 |

> 决策/目标计算放 EX：beq/bne 用 ALU_SUB→zero；jal 目标专用加法器 pc+imm；jalr 目标=ALU(rs1+imm)。控制流程口径见 `top_design.md`。

---

## 2. 编码速查（字段位段，位 0 为最低）
- opcode=instr[6:0]；rd=instr[11:7]；funct3=instr[14:12]；rs1=instr[19:15]；rs2=instr[24:20]；funct7=instr[31:25]。
- 立即数原始字段与符号扩展（同单周期 `instr_decoder.v` 拆法）：
  - imm_I = instr[31:20]
  - imm_S = {instr[31:25], instr[11:7]}
  - imm_B = {instr[31], instr[7], instr[30:25], instr[11:8]}（注意位序）
  - imm_U = instr[31:12]
  - imm_J = {instr[31], instr[19:12], instr[20], instr[30:21]}（注意位序）
- B/J 目标为**相对 PC**（PC+imm，imm 最低位补 0），分支目标专用加法器处理。

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

## 4. 存储与内存映射（流水线，哈佛）
- **IMEM**（指令）：字节地址 `0x0000_0000` 起；容量 `IMEM_WORDS`（默认 1024×32bit=4KB）；只读。PC 步进 4。
- **DMEM**（数据）：字节地址 `0x0000_0000` 起；容量 `DMEM_WORDS`（默认 1024×32bit=4KB）；可读写。与 IMEM 物理分离（**结构冒险化解**）。lw/sw 需 4 字节对齐。
- 字节序：**小端**；存储器按字节数组实现，字={mem[ba+3],mem[ba+2],mem[ba+1],mem[ba]}。
- HALT：程序末尾自循环 `halt: beq x0,x0,halt`（TB 检测 PC 连续不动视为停机并比对结果）。无 MMIO 槽（实验二再加）。

## 5. 指令数统计（对 require 达标）
运算类 19（R10+I9）、传送类 3（lui/lw/sw）、控制类 4（beq/bne/jal/jalr）⇒ 共 26 ≥ 16；三类齐全。✔

## 6. 变更记录
- v1.0 2026-09-02：冻结 26 条子集。
