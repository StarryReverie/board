# 提交物核对清单（两门课程 · 9/18 24:00 截止）

> 维护：随 doc/tasks.md / exp2/doc/tasks.md 状态更新；符号：✅ 已就绪｜🟡 素材齐、待成稿｜⬜ 待做｜🚫 依赖上板/外部。
> 依据：doc/require（计组）与 exp2/doc/require（汇编）原文；逐项建立提交链接、缺项该项 0 分。

---

## 计组课程团队提交（流水线 CPU）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 流水线 CPU 仿真实验报告（未下板成功版本） | 素材：`doc/top_design.md`（结构/冲突方案）、`doc/isa.md`、`doc/modules/*.md`（14 模块）、`doc/ref_note.md`、`doc/perf_report.md`（性能实测）；**成稿待写** | 🟡 | 套老师模板后交付；若团队下板成功则改交"仿真与下板实验报告"版本并补板级章节 |
| 源代码 | `src/rtl/*.v`（pipeline_top 等 14 模块）、`src/defines/*.v`、`src/scripts/`（run_tb/run_perf/build_asm/fix_encoding/synth_check/create_vivado_proj） | ✅ | 综合自检通过；工程 `board/vivado/board.xpr` 本地生成（gitignore，不入库） |
| 测试汇编代码和机器码 | `src/test/*.asm`（test0/test1/test_sort/instr_cover/hazard_cover）+ `*_rom.hex`；程序级 TB `tb_prog_*.v`、性能 TB `tb_perf.v` | ✅ | 20/20 回归 PASS；.asm↔.hex 由 build_asm.ps1 维护 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建（素材同上 + perf 表 A–D） | ⬜ | 汇报人/署名待提供 |
| ≤5min 下板演示视频 | — | — | **仅"下板成功"路径需要**；当前按仿真版报告走，可豁免（若中途下板成功需补拍） |
| 个人日志（10 分/人） | 待建（9/2–9/18 每日条目） | ⬜ | 格式按课程群日志模板，各成员填写 |
| 在线考试（20 分/人，个人项） | 课程系统 | — | 成员个人完成 |

## 汇编课程团队提交（UART 接口控制器 + SoC）

| 提交物 | 对应文件/素材 | 状态 | 备注 |
|---|---|---|---|
| 接口控制器设计实验报告 | 素材：`exp2/doc/top_design.md`、`interface.md`（编址方案 B/位义）、`firmware.md`、`machine_code.md`、`modules/*.md`（6 模块）、本仓 `doc/isa.md`/`top_design.md`（跨课契约）；**成稿待写（下板记录章占位）** | 🟡 | 套老师模板；含编址方式对比、仿真（8/8）与下板记录 |
| 源代码 | `exp2/src/rtl/*.v`（uart_tx/uart_rx/uart_ctrl/dbus_decode/reset_sync/soc_top）、`exp2/src/xdc/board.xdc`、`exp2/src/test/console.S + console_rom.hex + console_init.vh`、`exp2/src/scripts/`（run_tb/build_fw/synth_check/create_vivado_proj） | ✅ | 8/8 回归 PASS；带固件综合自检通过（41 s）；工程 `board/vivado/exp2.xpr` 本地生成（gitignore） |
| 可复用 IP 核（uart_tx/uart_rx/uart_ctrl 打包 + 集成说明） | 建议 `exp2/ip_pkg/`：三模块源码副本 + 集成说明 + 例化示例 | ⬜ | 报告/PPT 引用项；内容零上板依赖，随时可做 |
| 汇报 PPT×2（中期、验收） | 内容骨架待建 | ⬜ | 汇报人/署名待提供 |
| ≤5min 接口控制器下板演示视频 | 依赖 U32 下板（终端 banner/回显/复位 + 示波器波形） | 🚫 | **硬性提交物，缺项 0 分**——需上板机会/板卡资源；固件与 XDC 均已就绪 |
| 汇编实验测试（20 分，现场） | 依课程安排 | 🚫 | 现场测试，需板 |
| 个人日志（10 分/人） | 待建 | ⬜ | 同计组：课程群模板 |

## 仓库总态（2026-09-06 晚）

- 计组：T0–T33 完成（回归 20/20、性能实测 5/5 恒等式）；T34（Fmax 复测，综合侧）、T35（报告素材）待执行。
- 汇编：U10–U31 完成（回归 8/8）；U32 板级（XDC/固件就绪）、U33 可选 ILA、U41 机器码说明（已随 doc/machine_code.md 完成）——见 exp2/doc/tasks.md。
- 与 origin/dev 同步 ✅。

## 变更记录

- 2026-09-06：初版核对清单。
