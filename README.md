# board — 计算机组成原理 + 汇编与接口 课程设计

## 目录结构

```text
board/
 ├─ src/                 计组代码（本仓主干，统一代码目录）
 │   ├─ rtl/             流水线 CPU core RTL（14 模块，含 pipeline_top）
 │   ├─ defines/         指令/常量宏
 │   ├─ test/            TB + 汇编测试程序（.asm/.hex）
 │   └─ scripts/         run_tb.ps1（批量仿真）、run_perf.ps1（性能测量）、build_asm.ps1（汇编→hex）、fix_encoding.ps1（编码校验）、synth_check.tcl（综合自检）
 ├─ doc/                 计组设计文档（isa/top_design/tasks/modules/future_extensions/perf_analysis/perf_report）
 ├─ exp2/                汇编与接口课程（UART SoC，独立子工程）
 ├─ SUBMISSION.md        两门课提交物核对清单（9/18 24:00 截止）
 ├─ ref/CPU/             大三单周期参考工程（只读）
 └─ tools/(仓库外)        RISC-V 工具链（E:\Homework\26-27-1\tools）
```

## 快速上手（本机 Vivado 2019.2 + xPack RISC-V 工具链）

```powershell
# 仿真全部单测/回归（19 项，须在装有 Vivado 的机器）
powershell -File src/scripts/run_tb.ps1          # 全部
powershell -File src/scripts/run_tb.ps1 -Case alu # 按名过滤

# 汇编测试程序 → 机器码镜像
powershell -File src/scripts/build_asm.ps1

# 性能测量（5 档程序：CPI/IPC/停顿分解，汇总 out/perf_summary.csv）
powershell -File src/scripts/run_perf.ps1

# Vivado 综合自检（include 目录 = src/）
vivado -mode batch -source src/scripts/synth_check.tcl

# 文本编码健康校验（全仓 UTF-8；默认仅报告，-Apply 写回）
powershell -File src/scripts/fix_encoding.ps1
```

## 下板（exp2 U32：本机已可全流程出 bit+烧录；完整方案见 exp2/doc/board_runbook.md）

```powershell
git clone https://github.com/StarryReverie/board.git && cd board
vivado -mode batch -source exp2/src/scripts/create_vivado_proj.tcl   # 生成工程
vivado -mode batch -source exp2/src/scripts/board_runs.tcl           # 一键出 .bit
vivado -mode batch -source exp2/src/scripts/program_devices.tcl -tclargs <bit>  # 烧录
powershell -File exp2/src/scripts/uart_check.ps1 -Port COMx          # 终端自动验收
```

# Vivado GUI（工程已按工程风格分组，可直接打开）
```text
双击仓库根 vivado/board.xpr（exp1 工程，目录=仓库根 vivado/，即 exp1/vivado；若不存在，先执行下方重建命令）；实验二工程：双击 exp2/exp2_vivado.bat（工程 exp2/vivado/exp2.xpr）
  设计源 sources_1 : src/rtl/*.v          top = pipeline_top（综合/实现）
  仿真源 sim_1     : src/test/tb_*.v      top = tb_pipeline_top（默认）
  约束  constrs_1  : （实验一为空；实验二 XDC 放 exp2/xdc）
  include 目录     : src/（VerilogDir=$PPRDIR/../src，`include "defines/…" 由此解析）
```
重建工程（工程不入 git，本机生成即可）：
```powershell
vivado -mode batch -source src/scripts/create_vivado_proj.tcl
```

> 说明：RTL 内 `` `include "defines/*.v"`` 以 **src/ 为 include 目录**解析；Vivado
> 工程中把 include 目录指向 `src/` 即可直接读入 `src/rtl/` 全部源码。
> 程序级回归 TB（tb_prog_*）经 $readmemh 按文件名读 .hex，GUI 直跑需把
> `src/test/*.hex` 复制到 xsim 工作目录；**推荐用 run_tb.ps1 跑仿真**（自动拷贝）。
