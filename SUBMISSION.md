# 提交物核对清单（两门课程 · 9/18 24:00 截止）

> 维护：随 pipeline/doc/tasks.md / UART/doc/tasks.md 状态更新；符号：✅ 已就绪｜🟡 素材齐、待成稿｜⬜ 待做｜🚫 依赖上板/外部。
> 依据：pipeline/doc/require（计组）与 UART/doc/require（汇编）原文；逐项建立提交链接、缺项该项 0 分。

---

## 计组课程团队提交（流水线 CPU）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 流水线 CPU 仿真实验报告（未下板成功版本） | 素材：`pipeline/doc/top_design.md`（结构/冲突方案）、`pipeline/doc/isa.md`、`pipeline/doc/modules/*.md`（14 模块）、`pipeline/doc/ref_note.md`、`pipeline/doc/perf_report.md`（性能实测）；**成稿待写** | 🟡 | 套老师模板后交付；若团队下板成功则改交"仿真与下板实验报告"版本并补板级章节 |
| 源代码 | `pipeline/src/rtl/*.v`（pipeline_top 等 14 模块）、`pipeline/src/defines/*.v`、`pipeline/src/scripts/`（run_tb/run_perf/build_asm/fix_encoding/synth_check/create_vivado_proj） | ✅ | 综合自检通过；工程 `pipeline/vivado/board.xpr`（exp1 工程目录 = pipeline/vivado/）本地生成（gitignore，不入库；入口 `pipeline/exp1_vivado.bat`） |
| 测试汇编代码和机器码 | `pipeline/src/test/*.asm`（test0/test1/test_sort/instr_cover/hazard_cover）+ `*_rom.hex`；程序级 TB `tb_prog_*.v`、性能 TB `tb_perf.v` | ✅ | 20/20 回归 PASS；.asm↔.hex 由 build_asm.ps1 维护 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建（素材同上 + perf 表 A–D） | ⬜ | 汇报人/署名待提供 |
| ≤5min 下板演示视频 | — | — | **仅"下板成功"路径需要**；当前按仿真版报告走，可豁免（若中途下板成功需补拍） |
| 个人日志（10 分/人） | 待建（9/2–9/18 每日条目） | ⬜ | 格式按课程群日志模板，各成员填写 |
| 在线考试（20 分/人，个人项） | 课程系统 | — | 成员个人完成 |

## 汇编课程团队提交（UART 接口控制器 + SoC）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 接口控制器设计实验报告 | 素材：`UART/doc/top_design.md`（IP 顶层设计）、`UART/doc/interface.md`（编址方案 B/位义）、`soc/doc/firmware.md`、`soc/doc/machine_code.md`、`UART/doc/modules/*.md` 与 `soc/doc/modules/*.md`（IP 4 模块 + soc 2 模块）、本仓 `pipeline/doc/isa.md`/`pipeline/doc/top_design.md`（跨课契约）；**成稿待写（下板记录章占位）** | 🟡 | 套老师模板；含编址方式对比、仿真（IP 4/4 + SoC 5/5）与下板记录 |
| 源代码 | `UART/src/`（**UART IP 交付物**：rtl=uart_ip_top（寄存器层已并入）/uart_tx/uart_rx + test=4 项 TB）+ `soc/`（**SoC 集成**：rtl=soc_top/reset_sync/dbus_decode + xdc/board.xdc + test=固件 console.*/系统 TB×5） | ✅ | 回归 TB 齐备（构建脚本保留 `UART/src/scripts/build_fw.ps1`/`synth_check.tcl`/`create_vivado_proj.tcl`，其余已删——2026-09-07 结构调整；仿真在 Vivado GUI/xsim 直跑，下板重建步骤见 `soc/doc/board_runbook.md`） |
| 可复用 IP 核（uart_ip_top/uart_tx/uart_rx 打包 + 集成说明） | 建议 `UART/ip_pkg/`：三模块源码副本 + 集成说明 + 例化示例（soc_top 即现成例化） | ⬜ | 报告/PPT 引用项；内容零上板依赖，随时可做 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建 | ⬜ | 汇报人/署名待提供 |
| ≤5min 接口控制器下板演示视频 | 依赖 U32 下板（终端 banner/回显/复位 + 示波器波形） | 🚫 | **硬性提交物，缺项 0 分**——需上板机会/板卡资源；固件与 XDC 均已就绪（soc/） |
| 汇编实验测试（20 分，现场） | 依课程安排 | 🚫 | 现场测试，需板 |
| 个人日志（10 分/人） | 待建 | ⬜ | 同计组：课程群模板 |

## 仓库总态（2026-09-07）

- 计组：T0–T33 完成（回归 20/20、性能实测 5/5 恒等式）；T34（Fmax 复测，综合侧）、T35（报告素材）待执行。
- 汇编：U10–U15、U30、U31、U40、U41 完成——**实验二交付物收敛为独立 UART IP**（uart_ip_top + IP 级独立测试）；SoC 上移为整个项目的顶层 `soc/`（集成代码/固件/XDC/系统 TB/下板方案随迁）；U32 板级（XDC/固件就绪）、U33 可选 ILA——见 UART/doc/tasks.md。
- 与 origin/dev 同步 ✅。

## 变更记录

- 2026-09-07：结构调整——实验二交付=UART IP（UART/），SoC=项目顶层（soc/）；UART 侧构建脚本删至 build_fw/synth_check/create_vivado_proj（重建见 soc/doc/board_runbook.md）；汇编源代码行与 IP 打包行同步。
- 2026-09-06：初版核对清单。
