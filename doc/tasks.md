# 课程设计任务分解与验收标准

> 工程根：`/home/voi/codes/pipeline`。本文件是唯一权威进度源，状态随执行更新。

---

## 0. 目标与口径

分解 `doc/require` 的两门课程设计，当前聚焦**实验一：RV32I 5 级流水线 CPU**（实验二的 UART、集成、性能对比、下板在 CPU 本体定稿后追加）。

| 项 | 口径 |
|---|---|
| 指令集 | RISC-V **RV32I 子集**（`doc/isa.md` 拟定，26 条，含运算/传送/控制三类） |
| 结构 | 5 级 `IF→ID→EX→MEM→WB`；哈佛 IMEM/DMEM 分离 |
| 段间寄存器 | 4 组独立模块 `if_id/id_ex/ex_mem/mem_wb`（统一 `en/flush` 接口） |
| 冲突处理 | 前递(EX/MEM、MEM/WB→EX) + load-use 冻结(1 气泡) + 分支 EX taken 冲刷 2 条；结构冒险靠存储分离 |
| 控制器/附加 | 硬布线；溢出判断 `flags[OF]` |
| 存储 | IMEM 指令存储运行期只读(.vh 初值装载)、预留 loader 写口(wen 恒 0)；DMEM 同步写；读均周期内组合（见 top_design §6/§9） |
| 参考 | `ref/CPU/`（大三单周期，RV32I）——继承约定见 `doc/ref_note.md`；该工程不改动 |
| 语言/工具 | Verilog(沿用参考工程 Verilog-2001)；`riscv-none-elf-as -march=rv32i`（xPack GNU RISC-V，本机已装；与 musl-as 等价）+ `objcopy -O verilog` |
| 本机职责 | 只写 源码+文档+TB+期望值+汇编镜像；仿真/综合在下板侧(Vivado) 执行 |

---

## 1. 需求追溯（doc/require ↔ 任务）

| require 原文要点 | 对应任务 |
|---|---|
| 特定指令集流水线处理器（级数不限），含运算/传送/控制三类；报告数据/结构/控制相关方案、测试程序、仿真 | 本 CPU（T10–T20）与 top_design.md、模块文档、T30/T31 |
| 指令条数 ≥16 | `doc/isa.md`（T1），26 条 |
| 控制器结构三选一 | 硬布线（见 top_design.md） |
| 附加功能 ≥1 | 溢出判断 `flags[OF]`（T14，可观测出口） |
| 量化性能测试(CPI/IPC/MIPS/CPU time)并对比大三单周期 | T32–T35（方案 `doc/perf_analysis.md`；`ref/CPU/` 基线见 T34） |
| 汇编与接口/外设控制器/集成 | **后追加**（实验二 §6：T40–T44） |
| 提交物：源码/测试汇编+机器码/报告/PPT/视频/日志 | **后追加** |

---

## 2. 文档交付

| 任务 | 产出 | 验收标准（全过方可编码） |
|---|---|---|
| T0 | **本文件** | 每条有 依赖/产出/验收；追溯表覆盖 require；状态列可用 |
| T1 | `doc/isa.md` RV32I 子集定稿 | 指令≥16 三类齐全；每指令位域编码表；伪指令白名单；内存映射/HALT 约定；与 RV32I 官方逐条一致；评审通过 |
| T2 | `doc/ref_note.md` | 继承/改造清单与实际代码一致；复用文件逐一点名(带路径) |
| T3 | `doc/top_design.md` 顶层设计 | 5 段图+4 寄存器边界/字段+模块总览+连接表+时钟复位+存储+冲突策略；无未决信号；**接口变更必须先改本文件** |
| T4 | `doc/modules/*.md`（每 RTL 文件一份） | 职责/端口/连接/时序/验收；与 top_design 一致 |

---

## 3. 模块编码任务（每模块：先文档→再编码→再单测 TB）

> 仓库布局：代码统一于 `src/`（RTL `*.v` 于 `src/rtl/`；宏 `src/defines/`；汇编/TB `src/test/`；工具 `src/scripts/`）；文档 `doc/`；汇编实验 `exp2/` 独立；参考工程 `ref/CPU/` 不动。`[组合]`=纯组合；`[寄存器]`=时序段间寄存器。

| 任务 | 模块/文件 | 依赖 | 产出 | 验收标准（可测） |
|---|---|---|---|---|
| T10 | 取指组合：`pc_reg.v` + `imem.v` | T1,T3 | PC 目标 mux + 同步读指令存储（loader 写口 `wen=0`） | 复位 PC=0；`pc_freeze` 保持；`branch_taken` 取 `branch_target`；inst 逐字=镜像(`.hex` 字节小端重组) |
| T11 | `if_id.v` `[寄存器]` | T3 | IF/ID：`{inst,pc}` | `en=0` 保持；`flush` 置 NOP(`0x13`) 且 pc 可任意；其余沿沿打入 |
| T12 | 译码组合：`regfile.v`+主译码+imm+load-use 检测 | T1,T3 | 读 rs1/rs2、Ctrl_EX/M/WB、imm、`load_use` | ctrl 真值表同 isa.md；imm 五型扩展正确；load-use 判据 `id_ex.rd==rs1\|rs2 && id_ex.memread && rd≠0`→1；x0 恒 0、写 x0 无效 |
| T13 | `id_ex.v` `[寄存器]` | T3 | ID/EX：`{pc,rs1,rs2,imm,inst(func),Ctrl}` | flush/气泡时 EX/M/WB 控制清零成 NOP；否则沿沿打入 |
| T14 | 执行组合：前递 mux+`alu.v`+分支判决/目标加法 | T3 | ALU 结果/OF/zero、`br_taken`、`br_target` | ALU 逐 op 真值表；`add` 正+正溢出 `OF=1`；beq(相等)/bne 判对；jal 恒跳、jalr=rs1+imm；分支目标=`pc_ex+imm`(专用加法器) |
| T15 | `ex_mem.v` `[寄存器]` | T3 | EX/MEM：`{alu_result,wdata,rd,Ctrl_M,Ctrl_WB}` | wdata=前递后 rs2；常规打入 |
| T16 | 访存组合：`dmem.v` | T3 | 同步写 RAM(sw/lw, wmask)，读周期内组合有效 | 同址 `sw` 后紧邻 `lw`(下拍读) 值一致；读写同拍语义按文档定义 |
| T17 | `mem_wb.v` `[寄存器]` | T3 | MEM/WB：`{rdata,alu_result,rd,Ctrl_WB}` | 常规打入 |
| T18 | 回写组合 `wb` | T3 | `MemtoReg` 选路→regfile 写口 | MemtoReg=1 取 rdata，=0 取 alu_result；rd=x0 不写；WB 末沿直写 |
| T19 | `hazard_unit.v`（冲突处理） | T3,T14 | `fwdA/fwdB`、`pc_freeze`、`ifid_en`、ID/EX 气泡、`flush_branch` | 前递源：EX/MEM 优先于 MEM/WB；load-use→冻结 PC+IF/ID 且 ID/EX 灌气泡(恰 1)；分支 taken→清 IF/ID+ID/EX(恰 2) |
| T20 | `pipeline_top.v` 顶层装配 | T10–T19 | 交替例化组合段与寄存器 + HALT 观测口 | 端口与 top_design 连接表一致；无悬空/多重驱动；可综合；Vivado 综合通过(下板侧) |

---

## 4. 测试任务

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| T30 | 模块单测 TB（组合真值表 / 寄存器 en·flush / hazard 场景），每模块一份 | `test/tb_*.v` + 期望值注释 | 下板侧 Vivado 运行：各 TB `$display` 全 PASS |
| T31 | 整机回归：迁移 `ref/CPU/test/test0·test1·sort`（注释预期已核验）+ 新增覆盖指令清单全部指令与 hazard 的程序 | `test/*.asm → *.hex`（HALT 自循环收尾）+ `tb_pipeline_top.v` | 运行 N 周期后：寄存器堆与 dmem 终值与注释期望逐一相等；TB 逐项断言 PASS |
| T32 | 性能 TB：`test/tb_perf.v`（5 档 `PERF_*` 编译开关；WB 段 retire/HALT 检测 + `L/T` 停顿计数 + 恒等式断言 + 正确性断言复用） | T31 全绿 | `tb_perf.v` | 恒等式 `C == IC+(F−1)+L+2T` 5 档全 PASS；正确性断言与 tb_prog_* 一致（方案 §5） |
| T33 | `scripts/run_perf.ps1`：逐档编译运行 → 解析 CSV → 汇总 `out/perf_summary.csv` | T32 | run_perf.ps1 + CSV | 一键 5 档；CSV 含恒等式结果列；打印 `== PERF ALL PASS ==` |
| T34 | 单周期基线：`cycles_single = IC` 理论基线表；（可选）ref 副本综合复测 Fmax/资源（副本入 `build/`，ref 零改动） | T33 | 基线表/复测数据 | 表 A/B/D 数据齐；数据来源逐项注明（方案 §6） |
| T35 | 报告性能章节素材：表 A–D + 停顿堆叠图 + 结论分析 | T34 | 报告/PPT 素材 | 覆盖 require"量化性能对比"；恒等式与停顿分解自洽（方案 §8） |

> 状态（2026-09-06）：**T32（`test/tb_perf.v`）与 T33（`scripts/run_perf.ps1`）已落地**——5 档程序实测全绿（恒等式 5/5 + 正确性断言全绿，随 run_tb 20 项回归）；实测数据与结论见 `doc/perf_report.md`。**T34/T35 待执行**（单周期 Fmax 复测在综合侧，本机时序报告环节已知空转限制）。

汇编镜像脚本（本机可跑，T31 已落地，属工具而非仿真器）：
- `scripts/build_asm.ps1`：`riscv-none-elf-as -march=rv32i -mabi=ilp32` → `objcopy -O verilog` → 字节式 `test/<名>_rom.hex`；产物与参考工程（musl 工具链）逐字节一致；
- `verify_hex.py`（规划）：解码 `.hex` 与 `objdump -d` 对照，防工具链越界指令（当前以 build_asm 的 .lst 反汇编清单核对，见 `scripts/out/asm/`）。

---

## 5. 里程碑与门禁

| 里程碑 | 内容 | 门禁（未过不进下一步） |
|---|---|---|
| M1 | 文档定稿(T0–T4) | isa.md 与 top_design.md 评审通过；模块文档齐全 |
| M2 | 模块编码(T10–T20) | 每模块代码通过静态核对；pipeline_top 无悬空/无多重驱动 |
| M3 | 测试(T30–T31) | 整机回归程序全部 PASS（下板侧跑） |
| M4 | 性能测量(T32–T35) | 恒等式 5/5 PASS；回归全绿；perf_summary.csv 齐；对比数据注明来源 |

> M2/M3 的实际 PASS 依赖 Vivado 侧运行；本机完成源码、TB、期望值与镜像后，交付下板侧验证。

---

## 6. 实验二任务（UART 集成：全双工从机 + 程序固化 console）

> 架构口径见 top_design §9（数据侧统一编址 MMIO 译码 + 全双工 uart_ctrl + **程序固化单程序模型**：程序 .vh 固化、上电自跑；loader 在线重载已搁置）。启动门禁：**M1–M3（实验一）全绿后**。验收路径：EES-338 板下板（Vivado 侧综合/上板）。编号 T40 起。

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| T40 | 数据侧总线译码：`dbus_decode.v`（MEM 段按地址选 {数据 RAM, MMIO 窗口}；映射定稿见 top_design §9.2 / isa.md §4：TX/STAT/RX 槽） | `dbus_decode.v` + `doc/modules/dbus_decode.md` | 低区命中 dmem、窗口命中 uart 槽（TX 写触发/STAT 位义/RX 读清位）；字访问正确；不新增气泡，回归 H1–H5 不变 |
| T41 | UART 全双工从机封装（复用基础任务 IP）：`uart_tx` + `uart_rx`（位中心采样） + TX/STAT/RX 字槽 + 忙写丢弃 / RX 读清位 | `uart_ctrl.v` + 单测 TB | 收发逐位与字读回正确；TX_BUSY/RX_VALID 位义符合 top_design §9.4；波特率可配（分频参数仿真可覆盖） |
| T42 | 固件/驱动（**固定程序**，.vh 固化）：`.equ` 内存映射头、putc/getc、console 主循环（banner + 回显） | `test/*.asm → *.hex/.vh` + verify | 上电自运行打印 banner；键盘回显往返正确（无 reload 命令） |
| T43 | 系统级 TB：行为级 UART 模型（双向收发）+ 整机跑固定固件 | `tb_soc_top.v` | banner 字节与注释期望相等；回显往返断言 PASS；复位重跑一致 |
| T44 | 下板：soc_top 例化 + 复位同步 + XDC（T5 晶振 / P15 复位键 / T4 uart_tx / N5 uart_rx）+ 综合/时序 | 约束 + 工程 | 终端 115200-8-N-1 见 banner、键盘回显正常；≤5 min 演示视频 |

> ~~原 T42（loader 在线重载）~~：固化单程序模型下取消；imem 写口保留预留（恒 0）。若未来恢复，先回写 top_design §9 与 tasks.md（触发条件见 `doc/future_extensions.md` §1/§2）。

---

## 7. 开放项与默认假设

| 开放项 | 默认假设/缓解 |
|---|---|
| 精工板型号/器件/Vivado 版本（本机无 Vivado） | 代码保持可综合、无厂商原语；综合在装有 Vivado 的机器进行 |
| rv32i 汇编 | riscv-none-elf-as 已验(`-march=rv32i -mabi=ilp32`，as 2.45；与 musl-as 等价)；objcopy `-O verilog` 输出字节式 hex |
| IMEM 综合初始化 | 用 `.vh`(initial 字面量) 装载；`.hex` 仅供仿真；两路一致性由脚本校验 |
| 大三单周期数据 | `ref/CPU/` 保留作报告/性能对比引用，本阶段不动 |
| HALT 停机约定 | 程序末尾自循环(`beq x0,x0,-`)，TB 检测 PC 不动即结束并比对结果 |
| 未来可拓展设想（`doc/extensions.md`：取指侧 boot ROM 分区、monitor 固件模型、imem 扩容、MMIO 从机扩充等） | 均**暂缓实现**；各条标注改动量与触发条件，实现前须先回写 top_design/tasks 正文 |

---

## 8. 变更记录

- 2026-09-06：T32/T33 落地——`test/tb_perf.v`（5 档 PERF_* + 恒等式/正确性断言）、`scripts/run_perf.ps1`（汇总 `out/perf_summary.csv`）；5 档实测全绿，报告成稿 `doc/perf_report.md`（T34/T35 待执行，Fmax 复测在综合侧）。
- 2026-09-06：新增性能分析任务 T32–T35 与 M4（方案 `doc/perf_analysis.md`，追溯表行"量化性能测试"由"后追加"转正）；全仓编码排查结论：文本均纯 UTF-8（乱码为 GBK 环境显示假象，见 ref_note §4）；新增编码校验工具 `src/scripts/fix_encoding.ps1`。
- 2026-09-04：实验二任务块按定稿改版（§6，T40–T44）：UART 全双工（T41）、固定固件 console（T42）、系统 TB（T43）、下板（T44）；取消 loader 在线重载（原 T42、原 T45 重载演示），imem 写口保留预留。
- 2026-09-04：新增 `doc/future_extensions.md`（未来可拓展设想登记，§7 开放项挂接）。
- 2026-09-04：登记实验二任务块（§6，T40–T45；架构 top_design §9）；指令存储命名 `imem_rom`→`imem`。
- 2026-09-04：行文精简，任务与验收口径不变。
- 2026-09-02 v0.1：初版任务分解与验收标准（覆盖实验一 CPU）。
