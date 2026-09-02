# 课程设计任务分解与验收标准

> 工程根：`/home/voi/codes/pipeline`
> 状态列随执行更新。本文件是所有任务的唯一权威进度源（最终状态以 git 提交与清单为准）。
> 上一版本：`v0.1`（2026-09-02）

---

## 0. 目标与口径

分解对象 = `doc/require` 中两门课程设计，当前阶段聚焦**实验一：RV32I 5 级流水线 CPU**（实验二 UART、集成、性能对比、下板在 CPU 冻结后追加）。

| 项 | 口径 |
|---|---|
| 指令集 | RISC-V **RV32I 子集**（冻结于 `doc/isa.md`，≥16 条、含运算/传送/控制三类） |
| 结构 | 5 级 `IF→ID→EX→MEM→WB`；哈佛 IMEM/DMEM 分离 |
| 寄存器组织 | 经典 **4 组段间寄存器** `if_id/id_ex/ex_mem/mem_wb`（独立模块，统一 `en/flush` 接口） |
| 冲突处理 | 前递(EX/MEM、MEM/WB→EX)+load-use 冻结(1 气泡)+分支 EX 判决 taken 冲刷 2 条；结构冒险靠存储分离 |
| 控制器 | 硬布线；附加功能默认溢出判断(`flags[OF]`) |
| 存储 | IMEM 只读（.vh 综合装载）；DMEM 同步写；两者读为周期内组合读（小型，语义见 top_design §6） |
| 设计参考 | `ref/CPU/`（大三单周期，RV32I）——继承约定见 `doc/ref_note.md`；该工程不改动 |
| 语言/工具 | Verilog(参考工程为 Verilog-2001，沿用)；汇编用 `riscv64-linux-musl-as -march=rv32i` + `objcopy -O verilog` |
| 本机职责 | 只写 源码+文档+TB+期望值+汇编镜像；**仿真/综合在下板侧(Vivado)执行**，本机不搭仿真器 |

---

## 1. 需求追溯（doc/require ↔ 任务）

| require 原文要点 | 对应任务 |
|---|---|
| 团队任务：特定指令集流水线处理器，级数不限，含运算/传送/控制三类，报告给数据/结构/控制相关方案、测试程序、仿真 | 本 CPU（T10–T20）与 top_design.md、模块文档、T30/T31 |
| 指令条数≥16，选 RISC-V…子集 | `doc/isa.md`（T1） |
| 控制器结构三选一 | 硬布线（top_design.md 冻结） |
| 附加功能至少选 1 | 溢出判断 `flags[OF]`（T14 执行段，可观测出口） |
| 量化性能测试(CPI/IPC/MIPS/CPU time)并对比大三单周期 | **后追加**（引用 `ref/CPU/` 数据） |
| 汇编与接口/外设控制器/集成 | **后追加**（实验二） |
| 提交物：源码/测试汇编+机器码/报告/PPT/视频/日志 | **后追加** |

---

## 2. 文档交付（本文件所指"先生成文档"部分）

| 任务 | 产出 | 验收标准（全部通过方可进入编码） |
|---|---|---|
| T0 | **本文件** `doc/tasks.md` | 每条有 依赖/产出/验收；追溯表覆盖 require；状态列可用 |
| T1 | `doc/isa.md` RV32I 子集冻结 | 指令≥16 三类齐全；每指令位域编码表；伪指令白名单；内存映射/HALT 约定；与 RV32I 官方逐条一致；评审通过 |
| T2 | `doc/ref_note.md` 单周期参考梳理 | 继承/改造清单与实际代码一致；复用文件逐一点名(带路径) |
| T3 | `doc/top_design.md` 顶层设计 | 5 段图+4 寄存器边界/字段+模块总览+连接表+时钟复位+存储+冲突策略；无未决信号；**接口冻结后改接口必须先改本文档** |
| T4 | `doc/modules/*.md` 每模块一份 | 每个 RTL 文件对应一份(职责/端口/连接/时序/验收)；与 top_design 一致 |

---

## 3. 模块编码任务（每模块：先文档→再编码→再单测 TB）

> 仓库根布局：RTL `*.v` 于根目录；`defines/` 宏；`test/` 汇编/TB；`doc/` 文档；参考工程 `ref/CPU/` 不动。`[组合]`=纯组合；`[寄存器]`=时序段间寄存器。

| 任务 | 模块/文件 | 依赖 | 产出 | 验收标准（可测） |
|---|---|---|---|---|
| T10 | 取指组合：`pc_reg.v` + `imem_rom.v` | T1,T3 | PC 目标 mux + 同步读 ROM | 复位 PC=0；`pc_freeze` 保持；`branch_taken` 取 `branch_target`；inst 逐字=镜像(`.hex` 字节小端重组) |
| T11 | `if_id.v` `[寄存器]` | T3 | IF/ID：`{inst,pc}` | `en=0` 保持；`flush` 置 NOP(`0x13`)且 pc 可任意；其余沿沿打入 |
| T12 | 译码组合：`regfile.v`+主译码+imm+load-use 检测 | T1,T3 | 读 rs1/rs2、Ctrl_EX/M/WB、imm、`load_use` | ctrl 真值表与 isa.md 一致；imm 五型扩展正确；load-use 判据：`id_ex.rd==rs1\|rs2 && id_ex.memread && rd≠0`→1；x0 恒 0、写 x0 无效 |
| T13 | `id_ex.v` `[寄存器]` | T3 | ID/EX：`{pc,rs1,rs2,imm,inst(func),Ctrl}` | flush/气泡时 EX/M/WB 控制位清零成 NOP；否则沿沿打入 |
| T14 | 执行组合：前递 mux+`alu.v`+分支判决/目标加法 | T3 | ALU 结果/OF/zero、`br_taken`、`br_target` | ALU 逐 op 真值表；`add` 正+正溢出 `OF=1`；beq(相等)/bne 判对；jal 恒跳、jalr=rs1+imm；分支目标=`pc_ex+imm`(专用加法器) |
| T15 | `ex_mem.v` `[寄存器]` | T3 | EX/MEM：`{alu_result,wdata,rd,Ctrl_M,Ctrl_WB}` | wdata=前递后 rs2；常规打入 |
| T16 | 访存组合：`dmem_ram.v` | T3 | 同步写 RAM(sw/lw, wmask)，读周期内组合有效 | 同一地址 `sw` 后紧邻 `lw`(下拍读) 值一致；读写同拍行为按文档定义 |
| T17 | `mem_wb.v` `[寄存器]` | T3 | MEM/WB：`{rdata,alu_result,rd,Ctrl_WB}` | 常规打入 |
| T18 | 回写组合 `wb` | T3 | `MemtoReg` 选路→regfile 写口 | MemtoReg=1 取 rdata，=0 取 alu_result；rd=x0 不写；WB 末沿直写 |
| T19 | `hazard_unit.v`（冲突处理） | T3,T14 | `fwdA/fwdB`、`pc_freeze`、`ifid_en`、ID/EX 气泡、`flush_branch` | 前递源：EX/MEM 优先于 MEM/WB；load-use→冻结 PC+IF/ID 且 ID/EX 灌气泡(恰 1)；分支 taken→清 IF/ID+ID/EX(恰 2) |
| T20 | `pipeline_top.v` 顶层装配 | T10–T19 | 交替例化组合段与寄存器 + HALT 观测口 | 端口与 top_design 连接表一致；无悬空/多重驱动；可综合(SV/Verilog-2001 合法)；Vivado 综合通过(下板侧) |

---

## 4. 测试任务

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| T30 | 模块单测 TB（组合真值表 / 寄存器 en·flush / hazard 场景），每模块一份 | `test/tb_*.v` + 期望值注释 | 下板侧 Vivado 运行：各 TB `$display` 全 PASS |
| T31 | 整机回归：迁移 `ref/CPU/test/test0·test1·sort`（注释预期已核验）+ 新增覆盖全部冻结指令与 hazard 的程序 | `test/*.asm → *.hex`（HALT 自循环收尾）+ `tb_pipeline_top.v` | 运行 N 周期后：寄存器堆与 dmem 终值与注释期望逐一相等；TB 逐项断言 PASS |

汇编镜像脚本（本机可跑，T31 前置，属工具而非仿真器）：
- `make -C test`：`as -march=rv32i` → `objcopy -O verilog` → 字节式 `.hex`；
- 校验脚本 `verify_hex.py`：解码 `.hex` 首条/末条与 `objdump -d` 对照，防工具链越界指令（见 `doc/ref_note.md`）。

---

## 5. 里程碑与门禁

| 里程碑 | 内容 | 门禁（未过不进下一步） |
|---|---|---|
| M1 | 文档冻结(T0–T4) | isa.md 与 top_design.md 评审通过；模块文档齐全 |
| M2 | 模块编码(T10–T20) | 每模块代码通过静态核对；pipeline_top 无悬空/无多重驱动 |
| M3 | 测试(T30–T31) | 整机回归程序全部 PASS（下板侧跑） |

> M2/M3 的实际 PASS 依赖 Vivado 侧运行；本机完成源码、TB、期望值与镜像后，交付下板侧验证。

---

## 6. 开放项与默认假设

| 开放项 | 默认假设/缓解 |
|---|---|
| 精工板型号/器件/Vivado 版本（本机无 Vivado） | 代码保持可综合、无厂商原语；综合在装有 Vivado 的机器进行 |
| rv32i 汇编 | musl-as 已验(`-march=rv32i -mabi=ilp32`)；objcopy `-O verilog` 输出字节式 hex |
| IMEM 综合初始化 | 用 `.vh`(initial 字面量)装载；`.hex` 仅供仿真；两路一致性由脚本校验 |
| 大三单周期数据 | `ref/CPU/` 保留作报告/性能对比引用，本阶段不动 |
| HALT 停机约定 | 程序末尾自循环(`beq x0,x0,-`)，TB 检测 PC 不动即结束并比对结果 |

---

## 7. 变更记录

- 2026-09-02 v0.1：初版任务分解与验收标准（覆盖实验一 CPU）。
