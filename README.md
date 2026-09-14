# board — 计算机组成原理 + 汇编与接口 课程设计

## 目录结构

```text
board/
 ├─ pipeline/            计组实验一（本仓主干，统一代码目录）
 │   ├─ src/rtl/          流水线 CPU core RTL（14 模块，含 pipeline_top）
 │   ├─ src/defines/      指令/常量宏
 │   ├─ src/test/         TB + 汇编测试程序（.asm/.hex）
 │   ├─ src/scripts/      run_tb.ps1（批量仿真）、run_perf.ps1（性能测量）、build_asm.ps1（汇编→hex）、fix_encoding.ps1（编码校验）、synth_check.tcl（综合自检）
 │   ├─ doc/              计组设计文档（isa/top_design/tasks/modules/future_extensions/perf_analysis 性能分析方案 v2.1/perf_report 实测数据）
 │   └─ exp1_vivado.bat   exp1 Vivado 工程入口
 ├─ UART/                汇编与接口课程（交付物：UART 控制器 IP——uart_ip_top + 内部层 + IP 级独立测试）
 ├─ soc/                 整个项目的顶层（SoC 集成，两课共建：soc_top/reset_sync/dbus_decode + 固件/XDC/系统 TB）
 ├─ SUBMISSION.md        两门课提交物核对清单（9/18 24:00 截止）
 ├─ ref/CPU/             大三单周期参考工程（只读）
 └─ tools/(仓库外)        RISC-V 工具链（E:\Homework\26-27-1\tools）
```

## 快速上手（本机 Vivado 2019.2 + xPack RISC-V 工具链）

```powershell
# 仿真全部单测/回归（19 项，须在装有 Vivado 的机器）
powershell -File pipeline/src/scripts/run_tb.ps1          # 全部
powershell -File pipeline/src/scripts/run_tb.ps1 -Case alu # 按名过滤

# 汇编测试程序 → 机器码镜像
powershell -File pipeline/src/scripts/build_asm.ps1

# 性能测量（8 档程序：CPI/IPC/停顿分解，汇总 out/perf_summary.csv）
powershell -File pipeline/src/scripts/run_perf.ps1

# Vivado 综合自检（include 目录 = pipeline/src/）
vivado -mode batch -source pipeline/src/scripts/synth_check.tcl

# 文本编码健康校验（全仓 UTF-8；默认仅报告，-Apply 写回）
powershell -File pipeline/src/scripts/fix_encoding.ps1
```

## 下板（SoC U32：本机已可全流程出 bit+烧录；完整方案见 soc/doc/board_runbook.md）

> 2026-09-07：SoC 上移为项目顶层 `soc/`；UART 侧构建/烧录/取证脚本已随结构调整删减（仅保留 build_fw.ps1/create_vivado_proj.tcl/synth_check.tcl 上游修复版）——无脚本建工程步骤见 `soc/doc/board_runbook.md` §1（工程目录 `soc/vivado/`，bit 产物 `soc/vivado/soc.runs/impl_1/soc_top.bit`），其余脚本可从 git 历史恢复。

# Vivado GUI（工程已按工程风格分组，可直接打开）
```text
双击 pipeline/vivado/board.xpr（exp1 工程，目录 = pipeline/vivado；若不存在，先执行下方重建命令）
  设计源 sources_1 : pipeline/src/rtl/*.v          top = pipeline_top（综合/实现）
  仿真源 sim_1     : pipeline/src/test/tb_*.v      top = tb_pipeline_top（默认）
  约束  constrs_1  : （实验一为空；SoC XDC 在 soc/xdc/board.xdc）
  include 目录     : pipeline/src/（VerilogDir=$PPRDIR/../src，`include "defines/…" 由此解析）
UART（UART IP）与 soc（SoC 集成）工程无脚本生成——按 soc/doc/board_runbook.md §1 手动建工程（IP 工程只需读入 UART/src/rtl/*.v，top=uart_ip_top）。
```
重建工程（工程不入 git，本机生成即可）：
```powershell
vivado -mode batch -source pipeline/src/scripts/create_vivado_proj.tcl
```

> 说明：RTL 内 `` `include "defines/*.v"`` 以 **pipeline/src/ 为 include 目录**解析；Vivado
> 工程中把 include 目录指向 `pipeline/src/` 即可直接读入 `pipeline/src/rtl/` 全部源码。
> 程序级回归 TB（tb_prog_*）经 $readmemh 按文件名读 .hex，GUI 直跑需把
> `pipeline/src/test/*.hex` 复制到 xsim 工作目录；**推荐用 run_tb.ps1 跑仿真**（自动拷贝）。
