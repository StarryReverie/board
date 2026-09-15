# 提交物核对清单（两门课程 · 9/18 24:00 截止）

> 维护：随 pipeline/doc/tasks.md / UART/doc/tasks.md 状态更新；符号：✅ 已就绪｜🟡 素材齐、待成稿｜⬜ 待做｜🚫 依赖上板/外部。
> 依据：pipeline/doc/require（计组）与 UART/doc/require（汇编）原文；逐项建立提交链接、缺项该项 0 分。

---

## 计组课程团队提交（流水线 CPU）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| **流水线 CPU 仿真与下板实验报告（下板成功版本）** | 素材：`pipeline/doc/top_design.md`、`pipeline/doc/isa.md`、`pipeline/doc/modules/*.md`、`pipeline/doc/ref_note.md`、**`pipeline/doc/perf_analysis.md` v2.1（性能分析方案）**、**`pipeline/doc/ref_baseline_measured.md`（单周期拍数/资源/Fmax 本轮实测）**、**`pipeline/doc/perf_report.md`（性能分析完成版）**、`pipeline/doc/known_issues.md`（缺陷台账）、**关键仿真说明 `pipeline/doc/sim_experiments.md`**、**板级章节素材 `pipeline/doc/board_runbook.md`（§2 板级结构与 LED 语义／§5 验收流程与自检判据／§6 拍摄脚本／§10 实测验收记录与 bit 指纹）**；波形图/日志归档于 `pipeline/doc/sim_shots/`；性能与仿真章节已成稿，板级章节可直接据 runbook 成稿 | 🟡 | 依据 `pipeline/doc/require`：团队已下板成功（2026-09-14 实板 PASS，见 runbook §10），故**按"下板成功版本"交付**（不再保留"未下板"版本与条件切换）；套老师模板后交付 |
| 源代码 | `pipeline/src/rtl/*.v`（pipeline_top 等 14 模块 **+ 上板 `exp1_board_top`/`exp1_reset_sync`**）、`pipeline/src/defines/*.v`、`pipeline/src/scripts/`（run_tb/run_perf/build_asm/fix_encoding/synth_check/create_vivado_proj/**hex_to_vh/create_exp1_board_proj**）、**引脚约束 `pipeline/xdc/board_exp1.xdc`** | ✅ | 综合自检通过；仿真工程 `pipeline/vivado/board.xpr`、**上板工程 `pipeline/vivado/board_exp1.xpr`**（本地生成、gitignore 不入库；入口 `pipeline/exp1_vivado.bat`） |
| 测试汇编代码和机器码 | `pipeline/src/test/*.asm`（test0/test1/test_sort/instr_cover/hazard_cover/fwd_priority/loop_heavy_8,32,128/**exp1_board_demo**）+ `*_rom.hex`（+ 上板固化镜像 `exp1_board_demo_init.vh`）；程序级 TB `tb_prog_*.v`、性能 TB `tb_perf.v`、波形 TB `wave/wave_pipe.v`、**板级 TB `tb_exp1_board_top.v`**；缺陷最小复现 `accwitness.asm` | ✅ | **23/23** 功能回归 + 8/8 性能档 PASS；.asm↔.hex 由 build_asm.ps1 / simple_asm.py 维护；.hex↔.vh 由 hex_to_vh.ps1 维护（含回读校验） |
| **实验一独立上板（CPU core，不接 UART）** | `pipeline/doc/board_runbook.md`（综合/烧录/验收/拍摄/故障定位全套 + **§10 实测验收记录 / §10.4 自检加固后重建 bit**） | ✅ **构建 A 已上板验收通过（2026-09-14）**；🟡 **构建 B（自检加固）待实板复测（约 3 分钟，步骤见 §10.4）** | 构建 A 判据全中：数码管 **`0000000F`**、**LED1–LED6 全亮 / LED7 灭**、按住 `RESET` 时只剩 LED0 心跳且松手立刻恢复（复位可重复）。构建 A bit SHA256 `4C3FAC64…EB97`（post-route **11,338 LUT / 3,808 FF / 0 BRAM / 34 IOB**，WNS −1.239 ns）；**构建 B**（PR #11 review 整改：自检由 2 个里程碑 → **逐项 24 项核对** + **变异测试 22/22 检出**）bit SHA256 `4EC61A42…D214`，post-route **12,088 LUT / 3,833 FF / 0 BRAM / 34 IOB**，WNS −1.468 ns。**时序如实记录：两次构建的 100 MHz 约束均未收敛（263 / 240 个违例端点），实测最差 200 条路径终点全部在 `u_cpu/`（核心组合读存储链），板级包装零贡献**，但**实测未妨碍功能运行**。另记板级坑：按键丝印与 FPGA 引脚不一致（丝印 `RESET(P9)` 实际接 **P15**；`PROG` 才是 **P9/PROGRAM_B**，误按会擦配置） |
| 汇报 PPT×2（中期、验收） | 内容骨架待建（素材同上 + perf 表 A–D） | ⬜ | 汇报人/署名待提供 |
| ≤5min 下板演示视频 | 实验一上板视频：拍摄脚本见 `pipeline/doc/board_runbook.md` §6（7 个镜头）；实验二 SoC 视频单独拍、单独归档 | ⬜ **待拍** | **实验一已下板成功 ⇒ 需补拍**（原"可豁免"的前提已不成立）。**拍摄前先烧 §10.4 的构建 B bit（自检加固固件）并完成复测**，这样视频里的 `0000000F` 才等于"24 项核对全对"。两段视频分别写入对应报告；实验一视频不需要串口终端 |
| 个人日志（10 分/人） | 待建（9/2–9/18 每日条目） | ⬜ | 格式按课程群日志模板，各成员填写 |
| 在线考试（20 分/人，个人项） | 课程系统 | — | 成员个人完成 |

## 汇编课程团队提交（UART 接口控制器 + SoC）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 接口控制器设计实验报告 | **设计部分新稿：`UART/doc/report_design.md`（v1.0，含新增 §5.8 与计组交叉章节，可直接替换 docx 前五章相应正文）**；素材：`UART/doc/top_design.md`（IP 顶层设计）、`UART/doc/interface.md`（编址方案 B/位义）、`soc/doc/firmware.md`、`soc/doc/machine_code.md`、`UART/doc/modules/*.md` 与 `soc/doc/modules/*.md`、本仓 `pipeline/doc/isa.md`/`pipeline/doc/top_design.md`（跨课契约）；下板记录章待补 | 🟡 | 套老师模板；含编址方式对比、三层验证（core 21 / IP 3 / SoC 5）与下板记录 |
| 源代码 | `UART/src/`（**UART IP 交付物**：rtl=uart_ip_top（寄存器层已并入）/uart_tx/uart_rx + test=3 项 TB：tb_uart_tx/tb_uart_rx/tb_uart_ip_top（寄存器层检查并入 IP 级 TB））+ `soc/`（**SoC 集成**：rtl=soc_top/reset_sync/dbus_decode + xdc/board.xdc + test=固件 console.*/系统 TB×5） | ✅ | 回归 TB 齐备（构建脚本保留 `UART/src/scripts/build_fw.ps1`/`synth_check.tcl`/`create_vivado_proj.tcl`，其余已删——2026-09-07 结构调整；仿真在 Vivado GUI/xsim 直跑，下板重建步骤见 `soc/doc/board_runbook.md`） |
| 可复用 IP 核（uart_ip_top/uart_tx/uart_rx 打包 + 集成说明） | 建议 `UART/ip_pkg/`：三模块源码副本 + 集成说明 + 例化示例（soc_top 即现成例化） | ⬜ | 报告/PPT 引用项；内容零上板依赖，随时可做 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建 | ⬜ | 汇报人/署名待提供 |
| ≤5min 接口控制器下板演示视频 | 依赖 U32 下板（终端 banner/回显/复位 + 示波器波形） | 🚫 | **硬性提交物，缺项 0 分**——需上板机会/板卡资源；固件与 XDC 均已就绪（soc/） |
| 汇编实验测试（20 分，现场） | 依课程安排 | 🚫 | 现场测试，需板 |
| 个人日志（10 分/人） | 待建 | ⬜ | 同计组：课程群模板 |

## 仓库总态（2026-09-14）

- 计组：T0–T37 完成（功能回归 **23/23**、性能 **8/8** 全 PASS 且恒等式全过）；**性能分析方案 `pipeline/doc/perf_analysis.md` v2.1 已落实**，单周期基线、资源/Fmax 与最终报告均已完成；**关键波形 4 项已落地**（`pipeline/doc/sim_experiments.md`、`pipeline/doc/sim_shots/`，含自动图表/日志）；冒险审计记录已归档，原 L1 线索经复核撤销（`pipeline/doc/known_issues.md`）；**实验一独立上板（T37）已在 EES-338 实板验收通过（2026-09-14）**——数码管 `0000000F`、LED1–LED6 全亮、LED7 灭、复位可重复，记录见 `pipeline/doc/board_runbook.md` §10；板级/上板程序回归全 PASS。
- 汇编：U10–U15、U30、U31、U40、U41 完成——**实验二交付物收敛为独立 UART IP**（uart_ip_top + IP 级独立测试）；SoC 上移为整个项目的顶层 `soc/`（集成代码/固件/XDC/系统 TB/下板方案随迁）；U32 板级（XDC/固件就绪）、U33 可选 ILA——见 UART/doc/tasks.md。
- 与 origin/dev 同步 ✅。

## 变更记录

- 2026-09-14：**实验一独立上板实板验收通过**——EES-338 上烧录 `exp1_board_top.bit`（SHA256 `4C3FAC64…EB97`，11,338 LUT / 3,808 FF / 0 BRAM，post-route WNS −1.239 ns）后四项判据全中：数码管 **`0000000F`**、**LED1–LED6 全亮**、**LED7 灭**、按住 `RESET` 只剩 LED0 心跳且松手立刻恢复（复位可重复）。记录与证据见 `pipeline/doc/board_runbook.md` **§10 实测验收记录**（含 **§10.3 板上按键与 FPGA 引脚实测：丝印 `RESET(P9)` 实际接 P15 用户 IO，`PROG` 才是 P9/`PROGRAM_B`，误按会擦配置**——首测即踩到，已写入 §7 故障定位）；`SUBMISSION.md` 上板行 🟡→✅、演示视频行由"可豁免"改为"待拍"。
- 2026-09-14：**实验一独立上板（T37）落地**——按 `pipeline/doc/board_runbook.md` 新增板级顶层 `pipeline/src/rtl/exp1_board_top.v`（复位同步 + CPU + 事件监视器 + 8 LED + 8 位数码管扫描）与 `exp1_reset_sync.v`；`pipeline_top` 追加 `dbg_*` 只读观测口（纯连线、零逻辑改动）；上板验收程序 `exp1_board_demo.asm`（自检后写签名 `dmem[0]=0x0F`）与其 `.hex`/`_init.vh`；固化脚本 `hex_to_vh.ps1`；独立工程脚本 `create_exp1_board_proj.tcl`；引脚约束 `pipeline/xdc/board_exp1.xdc`（依 EES-338 手册 §6.3/§6.4）；运行手册 `pipeline/doc/board_runbook.md`。新增回归 `tb_prog_board_demo`(34 项) 与 `tb_exp1_board_top`(22 项) → 回归口径 **21/21 → 23/23**。顺带修复 `run_tb.ps1` 在本机的环境变量大小写重复导致 `Start-Process` 抛异常的问题（现仓库原生 runner 可直接跑全量）。
- 2026-09-14：**大三单周期基准与性能分析全部落地**——新增 `pipeline/doc/ref_baseline_measured.md`（拍数 11/20/178、资源/Fmax 同条件综合、CPI≡1.00）；`perf_analysis.md` 升级 v2.1，`perf_report.md` 完成最终性能章节；新增冒险审计记录 `pipeline/doc/known_issues.md`，原 L1 线索经复核撤销；RTL 回归 21/21 + 性能 8/8 全绿。**规模档修复并入库**：`loop_heavy_{8,32,128}` 三档，`tb_perf.v`/`run_perf.ps1` 支持三窗口与恒等式 A/B，汇总 CSV 为 `perf_data/2026-09-14_perf_summary.csv`。
- 2026-09-13：性能分析方案重写为 `pipeline/doc/perf_analysis.md` v2.0（旧 v1.0 已删除并接替同名位置）——对比基线改为**组内成员大三阶段单周期实验数据**、指标选择依据与三窗口口径写入方案；报告素材行补该方案与 `ref_note.md`（大三单周期结构梳理）；仓库总态更新为回归 20/20。
- 2026-09-13：新增计组关键波形 4 项（五级总览/前递优先级/load-use 冻结/分支冲刷）与 §7 回归·性能汇总表，归档 `pipeline/doc/sim_shots/`；回归口径 21/21（新增 `fwd_priority` 独立场景不入回归）；表 D（Fmax/资源）本机综合空转，暂留综合侧。
- 2026-09-07：结构调整——实验二交付=UART IP（UART/），SoC=项目顶层（soc/）；UART 侧构建脚本删至 build_fw/synth_check/create_vivado_proj（重建见 soc/doc/board_runbook.md）；汇编源代码行与 IP 打包行同步。
- 2026-09-06：初版核对清单。
