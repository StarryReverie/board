# 课程设计任务分解与验收标准

> 工程根：`/home/voi/codes/pipeline`。本文件是唯一权威进度源，状态随执行更新。

---

## 0. 目标与口径

分解 `pipeline/doc/require` 的两门课程设计，当前聚焦**实验一：RV32I 5 级流水线 CPU**（实验二的 UART、集成、性能对比、下板在 CPU 本体定稿后追加）。

| 项 | 口径 |
|---|---|
| 指令集 | RISC-V **RV32I 子集**（`pipeline/doc/isa.md` 拟定，26 条，含运算/传送/控制三类） |
| 结构 | 5 级 `IF→ID→EX→MEM→WB`；哈佛 IMEM/DMEM 分离 |
| 段间寄存器 | 4 组独立模块 `if_id/id_ex/ex_mem/mem_wb`（统一 `en/flush` 接口） |
| 冲突处理 | 前递(EX/MEM、MEM/WB→EX) + load-use 冻结(1 气泡) + 分支 EX taken 冲刷 2 条；结构冒险靠存储分离 |
| 控制器/附加 | 硬布线；溢出判断 `flags[OF]` |
| 存储 | IMEM 指令存储运行期只读(.vh 初值装载)、预留 loader 写口(wen 恒 0)；DMEM 同步写；读均周期内组合（见 top_design §6/§9） |
| 参考 | `ref/CPU/`（大三单周期，RV32I）——继承约定见 `pipeline/doc/ref_note.md`；该工程不改动 |
| 语言/工具 | Verilog(沿用参考工程 Verilog-2001)；`riscv-none-elf-as -march=rv32i`（xPack GNU RISC-V，本机已装；与 musl-as 等价）+ `objcopy -O verilog` |
| 本机职责 | 只写 源码+文档+TB+期望值+汇编镜像；仿真/综合在下板侧(Vivado) 执行 |

---

## 1. 需求追溯（pipeline/doc/require ↔ 任务）

| require 原文要点 | 对应任务 |
|---|---|
| 特定指令集流水线处理器（级数不限），含运算/传送/控制三类；报告数据/结构/控制相关方案、测试程序、仿真 | 本 CPU（T10–T20）与 top_design.md、模块文档、T30/T31 |
| 指令条数 ≥16 | `pipeline/doc/isa.md`（T1），26 条 |
| 控制器结构三选一 | 硬布线（见 top_design.md） |
| 附加功能 ≥1 | 溢出判断 `flags[OF]`（T14，可观测出口） |
| 量化性能测试(CPI/IPC/MIPS/CPU time)并对比大三单周期 | T32–T35（方案 `pipeline/doc/perf_analysis.md` v2.1；**当前对比基线 = `ref/CPU/` 同条件复测，原始大三记录待交叉核对**，见方案 §4） |
| 汇编与接口/外设控制器/集成 | **后追加**（实验二 §6：T40–T44） |
| 提交物：源码/测试汇编+机器码/报告/PPT/视频/日志 | **后追加** |

---

## 2. 文档交付

| 任务 | 产出 | 验收标准（全过方可编码） |
|---|---|---|
| T0 | **本文件** | 每条有 依赖/产出/验收；追溯表覆盖 require；状态列可用 |
| T1 | `pipeline/doc/isa.md` RV32I 子集定稿 | 指令≥16 三类齐全；每指令位域编码表；伪指令白名单；内存映射/HALT 约定；与 RV32I 官方逐条一致；评审通过 |
| T2 | `pipeline/doc/ref_note.md` | 继承/改造清单与实际代码一致；复用文件逐一点名(带路径) |
| T3 | `pipeline/doc/top_design.md` 顶层设计 | 5 段图+4 寄存器边界/字段+模块总览+连接表+时钟复位+存储+冲突策略；无未决信号；**接口变更必须先改本文件** |
| T4 | `pipeline/doc/modules/*.md`（每 RTL 文件一份） | 职责/端口/连接/时序/验收；与 top_design 一致 |

---

## 3. 模块编码任务（每模块：先文档→再编码→再单测 TB）

> 仓库布局：代码统一于 `pipeline/src/`（RTL `*.v` 于 `pipeline/src/rtl/`；宏 `pipeline/src/defines/`；汇编/TB `pipeline/src/test/`；工具 `pipeline/src/scripts/`）；文档 `pipeline/doc/`；汇编实验 `UART/`（UART IP 交付）独立；SoC 集成顶层 `soc/`（两课共建）；参考工程 `ref/CPU/` 不动。`[组合]`=纯组合；`[寄存器]`=时序段间寄存器。

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
| T19 | `hazard_unit.v`（冲突处理） | T3,T14 | `fwdA/fwdB`、`pc_freeze`、`ifid_en`、ID/EX 气泡、`flush_branch` | 前递源：EX/MEM 优先于 MEM/WB；load-use→冻结 PC+IF/ID 且 ID/EX 灌气泡(恰 1)；分支 taken→清 IF/ID+ID/EX(恰 2)。历史 L1 线索已撤销，审计记录见 `pipeline/doc/known_issues.md` |
| T20 | `pipeline_top.v` 顶层装配 | T10–T19 | 交替例化组合段与寄存器 + HALT 观测口 | 端口与 top_design 连接表一致；无悬空/多重驱动；可综合；Vivado 综合通过(下板侧) |

---

## 4. 测试任务

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| T30 | 模块单测 TB（组合真值表 / 寄存器 en·flush / hazard 场景），每模块一份 | `pipeline/src/test/tb_*.v` + 期望值注释 | 下板侧 Vivado 运行：各 TB `$display` 全 PASS |
| T31 | 整机回归：迁移 `ref/CPU/test/test0·test1·sort`（注释预期已核验）+ 新增覆盖指令清单全部指令与 hazard 的程序 | `pipeline/src/test/*.asm → *.hex`（HALT 自循环收尾）+ `tb_pipeline_top.v` | 运行 N 周期后：寄存器堆与 dmem 终值与注释期望逐一相等；TB 逐项断言 PASS |
| T32 | 性能 TB：`pipeline/src/test/tb_perf.v`（**8 档** `PERF_*` 编译开关 = 5 主档 + 3 规模档；`PERF_MAXCYC` 看门狗；EX 段 retire/HALT 检测 + `L/T` 停顿计数 + 恒等式断言 + 主档正确性断言；依赖 T31 全绿） | `tb_perf.v` | 恒等式 `C == IC+(F−1)+L+2T` **8 档全 PASS**；主档复用 tb_prog_* 正确性断言，规模档只断言控制流收敛并标记为性能证据（方案 §5） |
| T33 | `pipeline/src/scripts/run_perf.ps1`：逐档编译运行 → 解析 CSV → 汇总 `pipeline/src/scripts/out/perf_summary.csv`（依赖 T32） | run_perf.ps1 + CSV | 一键 **8 档**（5 主档 + 3 规模档）；CSV 含恒等式结果列；打印 `== PERF ALL PASS ==`（实测 8/8 PASS） |
| T34 | 单周期基线：① 单周期**拍数实测**（`ref/CPU` 只读副本，TB 数 PC 变化次数）；② 资源/Fmax 两阶段综合（副本入 `build/`，ref 零改动；依赖 T33） | `pipeline/doc/ref_baseline_measured.md` + 报告表 4/5 | ✅ 拍数 11/20/178；单周期/流水线资源、WNS、Fmax 均已按同器件同约束出数 |
| T35 | 报告性能章节：三窗口、停顿分解、规模收敛、单周期对比、资源/Fmax 与系统层结论（依赖 T34） | `pipeline/doc/perf_report.md` | ✅ `perf_report.md` v2.1 完成；数字均可回溯至 CSV/综合报告，结论注明不可实现的 LUT 约束与规模档功能证据范围 |
| T36 | 关键仿真波形（4 项）：五级运行总览 / 数据前递与前递优先级 / load-use 冻结 1 拍 / 分支预测不跳+冲刷 2 拍；说明见 `pipeline/doc/sim_experiments.md` | `test/wave/wave_pipe.v` + `test/fwd_priority.asm` + `scripts/{run_wave,wave_png,report_png}.ps1` + `doc/sim_shots/auto/` | 4 图 + 同名日志 + 汇总表；TB 内嵌验收断言全 PASS；回归口径不变 **21/21** |
| T37 | 实验一**独立上板**（不接 UART）：板级顶层 + 复位同步 + 验收程序 + 固化脚本 + 独立工程 + 引脚约束 + 运行手册（见 `doc/board_runbook.md`） | `rtl/exp1_board_top.v`、`rtl/exp1_reset_sync.v`、`test/exp1_board_demo.asm(+_rom.hex/_init.vh)`、`scripts/hex_to_vh.ps1`、`scripts/create_exp1_board_proj.tcl`、`xdc/board_exp1.xdc`、`doc/board_runbook.md` | 板级顶层回归 `tb_exp1_board_top`（22 项断言）+ 上板程序回归 `tb_prog_board_demo`（34 项断言）全 PASS；回归口径 **23/23**；综合 **0 error / 0 critical warning**，post-route **11,338 LUT（17.88%）/ 3,808 FF / 0 BRAM / 34 IOB**；**实板验收通过（2026-09-14）**：数码管 `0000000F` + LED1–LED6 全亮 + LED7 灭 + 复位可重复，见 `doc/board_runbook.md` §10。**时序如实记录：post-route WNS −1.239 ns（Fmax≈89 MHz），100 MHz 未收敛——违例端点全部在核心组合读存储链（ID/EX），板级包装零贡献**，且实测未妨碍功能运行（§3.3/§10.2） |

> 状态（2026-09-14）：**T32/T33 已按 v2.1 升级并重出数据**——`tb_perf.v` 支持 8 档（5 主档 + 3 规模档 `loop_heavy_{8,32,128}`，含 `PERF_MAXCYC` 看门狗），`run_perf.ps1` 同步支持 8 档，**8/8 全 PASS 且恒等式全过**；汇总数据 `pipeline/doc/perf_data/2026-09-14_perf_summary.csv`（含 `C_total`/`C_steady`/`C_fixed` 与恒等式残差）。
> **T34 拍数部分已完成**：`pipeline/doc/ref_baseline_measured.md` —— 单周期实测 11/20/178 拍，与流水线 `IC` 精确满足 `C_单周期 = IC + 1`，**CPI ≡ 1.00 得证**；资源/Fmax 走两阶段综合（`build/run_both_synth.ps1`）。
> **冒险审计记录** `pipeline/doc/known_issues.md`：原 L1 线索已复核并撤销，`accwitness.asm` 保留为真实指令流审计样例；RTL 功能回归维持 21/21。
> **T35 已完成**：最终性能章节见 `pipeline/doc/perf_report.md`；旧版 `perf_report_skeleton.md` 已删除。
> **T36 已完成**：关键波形 4 项、自动图表与日志均已归档；回归口径维持 21/21。
> **T37 已完成并在实板验收通过（2026-09-14）**：实验一独立上板全套落地，回归 **23/23**（新增 `tb_exp1_board_top`、`tb_prog_board_demo`）。
>   `pipeline_top` 追加 `dbg_*` **只读观测口**（纯连线、零逻辑改动，21 项既有回归与 8 档性能逐值不变）；
>   停机判据用 `dbg_halt = br_taken & (idex_jump != jalr) & (idex_imm == 0)`（"零偏移跳到自身"）——
>   **不能用"PC 连续不变"**：本流水线未采取预测 + taken 冲刷 2 条，自循环时 PC 呈周期 3 的
>   `{halt, halt+4, halt+8}` 循环。
>   **实板结果**：数码管 `0000000F`、LED1–LED6 全亮、LED7 灭、按住 `RESET` 只剩 LED0 心跳且松手立刻恢复
>   → 四项判据全中，**post-route WNS −1.239 ns 未妨碍功能运行**（实测证据）。
>   另记板级坑：**按键丝印与 FPGA 引脚不一致**——丝印 `RESET(P9)` 实际接 **P15**（用户 IO，我们的 `rst_n`），
>   而 `PROG` 才是 **P9/`PROGRAM_B`**（误按会擦配置、板子会从 Flash 加载别的设计）。
>   完整记录（bit SHA256 / 资源时序 / 现象 / 引脚实测依据）见 `pipeline/doc/board_runbook.md` **§10**；
>   烧录/验收/拍摄步骤见同文件 §4–§6，故障定位见 §7。

汇编镜像脚本（本机可跑，T31 已落地，属工具而非仿真器）：
- `pipeline/src/scripts/build_asm.ps1`：`riscv-none-elf-as -march=rv32i -mabi=ilp32` → `objcopy -O verilog` → 字节式 `pipeline/src/test/<名>_rom.hex`；产物与参考工程（musl 工具链）逐字节一致；
- `verify_hex.py`（规划）：解码 `.hex` 与 `objdump -d` 对照，防工具链越界指令（当前以 build_asm 的 .lst 反汇编清单核对，见 `pipeline/src/scripts/out/asm/`）。

---

## 5. 里程碑与门禁

| 里程碑 | 内容 | 门禁（未过不进下一步） |
|---|---|---|
| M1 | 文档定稿(T0–T4) | isa.md 与 top_design.md 评审通过；模块文档齐全 |
| M2 | 模块编码(T10–T20) | 每模块代码通过静态核对；pipeline_top 无悬空/无多重驱动 |
| M3 | 测试(T30–T31) | 整机回归程序全部 PASS（下板侧跑） |
| M4 | 性能测量(T32–T35) | 恒等式 **8/8 PASS**；功能回归全绿；`perf_data/2026-09-14_perf_summary.csv` 齐；对比数据注明来源（单周期基准 = `ref_baseline_measured.md` 本轮实测） |
| M5 | 实验一独立上板(T37) | ✅ **已达成**：板级/程序回归 **23/23** 全绿；`hex_to_vh` 回读校验一致；独立工程综合 0 error、资源在器件内（11,338 LUT / 3,808 FF / 0 BRAM）；**实板四项判据全中**（数码管 `0000000F` + LED1–LED6 全亮 + LED7 灭 + 复位可重复）；**时序如实记录**（post-route WNS −1.239 ns，违例全在核心存储链，实测未妨碍运行），见 runbook §3.3/§10 |

> M2/M3 的实际 PASS 依赖 Vivado 侧运行；本机完成源码、TB、期望值与镜像后，交付下板侧验证。

---

## 6. 实验二任务（UART 集成：全双工从机 + 程序固化 console）

> 架构口径见 top_design §9（数据侧统一编址 MMIO 译码 + 全双工 uart_ip_top（UART IP 顶层，实验二交付）+ **程序固化单程序模型**：程序 .vh 固化、上电自跑；loader 在线重载已搁置）。SoC 集成代码与系统 TB 在 `soc/`（项目顶层）。启动门禁：**M1–M3（实验一）全绿后**。验收路径：EES-338 板下板（Vivado 侧综合/上板）。编号 T40 起。

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| T40 | 数据侧总线译码：`dbus_decode.v`（MEM 段按地址选 {数据 RAM, MMIO 窗口}；映射定稿见 top_design §9.2 / isa.md §4：TX/STAT/RX 槽） | `dbus_decode.v` + `pipeline/doc/modules/dbus_decode.md` | 低区命中 dmem、窗口命中 uart 槽（TX 写触发/STAT 位义/RX 读清位）；字访问正确；不新增气泡，回归 H1–H5 不变 |
| T41 | UART 全双工从机封装（复用基础任务 IP）：`uart_tx` + `uart_rx`（位中心采样） + TX/STAT/RX 字槽 + 忙写丢弃 / RX 读清位 | `uart_ip_top.v`（IP 顶层，寄存器层已并入）+ 单测 TB（含 IP 级独立测试） | 收发逐位与字读回正确；TX_BUSY/RX_VALID 位义符合 top_design §9.4；波特率可配（分频参数仿真可覆盖） |
| T42 | 固件/驱动（**固定程序**，.vh 固化）：`.equ` 内存映射头、putc/getc、console 主循环（banner + 回显） | `pipeline/src/test/*.asm → *.hex/.vh` + verify | 上电自运行打印 banner；键盘回显往返正确（无 reload 命令） |
| T43 | 系统级 TB：行为级 UART 模型（双向收发）+ 整机跑固定固件 | `soc/test/tb_soc_*.v` | banner 字节与注释期望相等；回显往返断言 PASS；复位重跑一致 |
| T44 | 下板：soc_top 例化 + 复位同步 + XDC（T5 晶振 / P15 复位键 / T4 uart_tx / N5 uart_rx）+ 综合/时序 | 约束 + 工程 | 终端 115200-8-N-1 见 banner、键盘回显正常；≤5 min 演示视频 |

> ~~原 T42（loader 在线重载）~~：固化单程序模型下取消；imem 写口保留预留（恒 0）。若未来恢复，先回写 top_design §9 与 tasks.md（触发条件见 `pipeline/doc/future_extensions.md` §1/§2）。

---

## 7. 开放项与默认假设

| 开放项 | 默认假设/缓解 |
|---|---|
| 板卡器件/Vivado | EES-338 实物 xc7a100tcsg324-1（手册误标 35T，实测）；本机 Vivado 2019.2 可跑仿真与缩容下板 build（4KB×2 存储需缩容，见 const_define.v 头注） |
| rv32i 汇编 | riscv-none-elf-as 已验(`-march=rv32i -mabi=ilp32`，as 2.45；与 musl-as 等价)；objcopy `-O verilog` 输出字节式 hex |
| IMEM 综合初始化 | 用 `.vh`(initial 字面量) 装载；`.hex` 仅供仿真；两路一致性由脚本校验 |
| 大三单周期数据 | `ref/CPU/` 保留作报告/性能对比引用，本阶段不动 |
| HALT 停机约定 | 程序末尾自循环(`beq x0,x0,-`)，TB 检测 PC 不动即结束并比对结果 |
| 未来可拓展设想（`pipeline/doc/future_extensions.md`：取指侧 boot ROM 分区、monitor 固件模型、imem 扩容、MMIO 从机扩充等） | 均**暂缓实现**；各条标注改动量与触发条件，实现前须先回写 top_design/tasks 正文 |

---

## 8. 变更记录

- 2026-09-15：**PR #11 review 整改**——① **上板自检加固**：`test/exp1_board_demo.asm` 阶段5 由"只核对 x18/x7 两个里程碑"改为**逐项累积 24 项核对**的失配标志（覆盖 ALU 全类、`lui`+`srli`、sw→lw 往返与两处 load-use 前递、循环计数与累加和、三种移位、有/无符号比较；大立即数用移位折成小常数比较），任一核对项错则签名 ≠ 0x0F；配 **变异测试**（`build/tb_mut.v` + `build/run_mut.bat`，build 侧不入库）把 22 条覆盖指令逐条改坏 → **22/22 全部检出、0 漏检**；② 修正 `doc/board_runbook.md` §3.3 的 post-route 资源口径（**11,338 LUT / 3,808 FF**，与 §10.1 指纹所指 bit 一致；原 11,356/3,812 属旧构建数字）；③ §8 上方 2026-09-14 条目中的停机判据写法改为**已实现口径** `br_taken & (idex_jump != 2'b11) & (idex_imm == 0)`；④ `scripts/run_tb.ps1` 环境大小写重复项改为**确定性归一**（规范名 = 全大写变体，取值 = 大小写不敏感查找的 OS 有效值，冲突时告警）——实测本机 `NO_PROXY`/`no_proxy` 取值确实不一致，旧实现"保留先出现者"不确定；⑤ `SUBMISSION.md` 交付版本行改为"下板成功版本"（依 `doc/require`）；⑥ 加固固件重建出的新 bit 指纹/资源/时序见 runbook §10.4。回归仍 **23/23**、性能 8/8（A/B=1/1）。
- 2026-09-14：**T37 实验一独立上板落地**（见 `doc/board_runbook.md`）——新增板级顶层 `rtl/exp1_board_top.v`（复位同步 + CPU + 事件监视器 + 8 LED 状态 + 8 位数码管扫描）、`rtl/exp1_reset_sync.v`、上板验收程序 `test/exp1_board_demo.asm(+_rom.hex)`（自检后写签名 `dmem[0]=0x0F`）、固化脚本 `scripts/hex_to_vh.ps1`（含回读逐字节校验）、独立工程脚本 `scripts/create_exp1_board_proj.tcl`（`pipeline/vivado/board_exp1.xpr`，`IMEM_INIT_VH IMEM_BYTES=512 DMEM_BYTES=256`）、引脚约束 `xdc/board_exp1.xdc`（依 EES-338 手册 §6.3/§6.4：LED K2/J2/J3/H4/J4/G3/G4/F6、段选两组、位选 LED_BIT1..8）、运行手册 `doc/board_runbook.md`。
  `pipeline_top` 追加 `dbg_*` **只读观测口**（纯连线，零逻辑改动）；新增回归 `tb_prog_board_demo`（34 项）+ `tb_exp1_board_top`（22 项）→ 回归口径 **21/21 → 23/23**。
  **两处关键结论**（写入 runbook §2.2/§2.3）：① 停机判据必须用 `br_taken & (idex_jump != 2'b11) & (idex_imm == 0)`（与 `br_target==idex_pc` 语义等价，但把 32 位加法器/比较器移出观测路径，避免恶化时序），**不能用"PC 连续不变"**（未采取预测 + taken 冲刷 2 条 ⇒ 自循环 PC 呈周期 3 的 `{halt,halt+4,halt+8}` 循环）；② XDC 不支持 `foreach`（Vivado `Designutils 20-1307`），IOSTANDARD 必须逐条显式书写。
  另修：`scripts/run_tb.ps1` 增加进程环境大小写重复项去重（本机 `NO_PROXY`/`no_proxy` 会让 `Start-Process` 抛异常，历史上一律绕用 `build/run_cases.ps1`），现仓库原生 runner 可直接跑全量回归。
- 2026-09-13：新增关键波形仿真（4 项：五级总览/前递优先级/load-use 冻结/分支冲刷）——`test/wave/wave_pipe.v`（逐拍采样出 CSV+VCD）+ `scripts/run_wave.ps1`（仿真）+ `scripts/wave_png.ps1`（System.Drawing 渲染 PNG）+ `scripts/report_png.ps1`（回归/性能汇总表）；产物归档 `doc/sim_shots/`；回归仍 **21/21**（新增 `fwd_priority.asm` 独立场景不入回归）。T34 表 D 本机综合收尾/报告空转，已回滚，留待综合侧。
- 2026-09-07：实验二交付物收敛为独立 UART IP（uart_ip_top，exp2/）——SoC 上移为项目顶层 `soc/`（soc_top/reset_sync/dbus_decode 随迁）；§3 布局说明、§6 T41/T43 行同步（core 侧 RTL 零改动）。
- 2026-09-13：**性能分析方案重写为 `doc/perf_analysis.md` v2.0**（取代 v1.0 并删除旧文）——指标选择依据、三窗口口径 + 恒等式 A/B 自检、负载收敛为 4 主档 + 1 规模档、**对比基线改为组内成员大三阶段单周期实验数据**（不再复测 `ref/CPU` 副本）、报告新增"大三单周期 CPU 结构与工作原理简介"；§1 追溯表行与上一条状态同步。
- 2026-09-06：T32/T33 落地——`test/tb_perf.v`（5 档 PERF_* + 恒等式/正确性断言）、`scripts/run_perf.ps1`（汇总 `out/perf_summary.csv`）；5 档实测全绿，报告成稿 `doc/perf_report.md`（T34/T35 待执行，Fmax 复测在综合侧）。
- 2026-09-06：新增性能分析任务 T32–T35 与 M4（方案 `doc/perf_analysis.md`，追溯表行"量化性能测试"由"后追加"转正）；全仓编码排查结论：文本均纯 UTF-8（乱码为 GBK 环境显示假象，见 ref_note §4）；新增编码校验工具 `src/scripts/fix_encoding.ps1`。
- 2026-09-04：实验二任务块按定稿改版（§6，T40–T44）：UART 全双工（T41）、固定固件 console（T42）、系统 TB（T43）、下板（T44）；取消 loader 在线重载（原 T42、原 T45 重载演示），imem 写口保留预留。
- 2026-09-04：新增 `doc/future_extensions.md`（未来可拓展设想登记，§7 开放项挂接）。
- 2026-09-04：登记实验二任务块（§6，T40–T45；架构 top_design §9）；指令存储命名 `imem_rom`→`imem`。
- 2026-09-04：行文精简，任务与验收口径不变。
- 2026-09-02 v0.1：初版任务分解与验收标准（覆盖实验一 CPU）。
