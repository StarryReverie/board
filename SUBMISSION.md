# 提交物核对清单（两门课程 · 9/18 24:00 截止）

> 维护：随 pipeline/doc/tasks.md / UART/doc/tasks.md 状态更新；符号：✅ 已就绪｜🟡 素材齐、待成稿｜⬜ 待做｜🚫 依赖上板/外部。
> 依据：pipeline/doc/require（计组）与 UART/doc/require（汇编）原文；逐项建立提交链接、缺项该项 0 分。

---

## 计组课程团队提交（流水线 CPU）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 流水线 CPU 仿真实验报告（未下板成功版本） | 素材：`pipeline/doc/top_design.md`、`pipeline/doc/isa.md`、`pipeline/doc/modules/*.md`、`pipeline/doc/ref_note.md`、**`pipeline/doc/perf_analysis.md` v2.1（性能分析方案）**、**`pipeline/doc/ref_baseline_measured.md`（单周期拍数/资源/Fmax 本轮实测）**、**`pipeline/doc/perf_report.md`（性能分析完成版）**、`pipeline/doc/known_issues.md`（缺陷台账）**、**关键仿真说明 `pipeline/doc/sim_experiments.md`**；波形图/日志归档于 `pipeline/doc/sim_shots/`；性能与仿真章节已成稿** | 🟡 | 套老师模板后交付；若团队下板成功则改交"仿真与下板实验报告"版本并补板级章节 |
| 源代码 | `pipeline/src/rtl/*.v`（pipeline_top 等 14 模块）、`pipeline/src/defines/*.v`、`pipeline/src/scripts/`（run_tb/run_perf/build_asm/fix_encoding/synth_check/create_vivado_proj） | ✅ | 综合自检通过；工程 `pipeline/vivado/board.xpr`（exp1 工程目录 = pipeline/vivado/）本地生成（gitignore，不入库；入口 `pipeline/exp1_vivado.bat`） |
| 测试汇编代码和机器码 | `pipeline/src/test/*.asm`（test0/test1/test_sort/instr_cover/hazard_cover/fwd_priority/loop_heavy_8,32,128）+ `*_rom.hex`；程序级 TB `tb_prog_*.v`、性能 TB `tb_perf.v`、波形 TB `wave/wave_pipe.v`；缺陷最小复现 `accwitness.asm` | ✅ | 21/21 功能回归 + 8/8 性能档 PASS；.asm↔.hex 由 build_asm.ps1 / simple_asm.py 维护 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建（素材同上 + perf 表 A–D） | ⬜ | 汇报人/署名待提供 |
| ≤5min 下板演示视频 | — | — | **仅"下板成功"路径需要**；当前按仿真版报告走，可豁免（若中途下板成功需补拍） |
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

- 计组：T0–T36 完成（功能回归 **21/21**、性能 **8/8** 全 PASS 且恒等式全过）；**性能分析方案 `pipeline/doc/perf_analysis.md` v2.1 已落实**，单周期基线、资源/Fmax 与最终报告均已完成；**关键波形 4 项已落地**（`pipeline/doc/sim_experiments.md`、`pipeline/doc/sim_shots/`，含自动图表/日志）；冒险审计记录已归档，原 L1 线索经复核撤销（`pipeline/doc/known_issues.md`）。
- 汇编：U10–U15、U30、U31、U40、U41 完成——**实验二交付物收敛为独立 UART IP**（uart_ip_top + IP 级独立测试）；SoC 上移为整个项目的顶层 `soc/`（集成代码/固件/XDC/系统 TB/下板方案随迁）；U32 板级（XDC/固件就绪）、U33 可选 ILA——见 UART/doc/tasks.md。
- 与 origin/dev 同步 ✅。

## 变更记录

- 2026-09-14：**大三单周期基准与性能分析全部落地**——新增 `pipeline/doc/ref_baseline_measured.md`（拍数 11/20/178、资源/Fmax 同条件综合、CPI≡1.00）；`perf_analysis.md` 升级 v2.1，`perf_report.md` 完成最终性能章节；新增冒险审计记录 `pipeline/doc/known_issues.md`，原 L1 线索经复核撤销；RTL 回归 21/21 + 性能 8/8 全绿。**规模档修复并入库**：`loop_heavy_{8,32,128}` 三档，`tb_perf.v`/`run_perf.ps1` 支持三窗口与恒等式 A/B，汇总 CSV 为 `perf_data/2026-09-14_perf_summary.csv`。
- 2026-09-13：性能分析方案重写为 `pipeline/doc/perf_analysis.md` v2.0（旧 v1.0 已删除并接替同名位置）——对比基线改为**组内成员大三阶段单周期实验数据**、指标选择依据与三窗口口径写入方案；报告素材行补该方案与 `ref_note.md`（大三单周期结构梳理）；仓库总态更新为回归 20/20。
- 2026-09-13：新增计组关键波形 4 项（五级总览/前递优先级/load-use 冻结/分支冲刷）与 §7 回归·性能汇总表，归档 `pipeline/doc/sim_shots/`；回归口径 21/21（新增 `fwd_priority` 独立场景不入回归）；表 D（Fmax/资源）本机综合空转，暂留综合侧。
- 2026-09-07：结构调整——实验二交付=UART IP（UART/），SoC=项目顶层（soc/）；UART 侧构建脚本删至 build_fw/synth_check/create_vivado_proj（重建见 soc/doc/board_runbook.md）；汇编源代码行与 IP 打包行同步。
- 2026-09-06：初版核对清单。
