# board — 计算机组成原理 + 汇编与接口 课程设计

## 目录结构

```text
board/
 ├─ src/                 计组代码（本仓主干，统一代码目录）
 │   ├─ rtl/             流水线 CPU core RTL（14 模块，含 pipeline_top）
 │   ├─ defines/         指令/常量宏
 │   ├─ test/            TB + 汇编测试程序（.asm/.hex）
 │   └─ scripts/         run_tb.ps1（批量仿真）、build_asm.ps1（汇编→hex）、synth_check.tcl（综合自检）
 ├─ doc/                 计组设计文档（isa/top_design/tasks/modules/future_extensions）
 ├─ exp2/                汇编与接口课程（UART SoC，独立子工程）
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

# Vivado 综合自检（include 目录 = src/）
vivado -mode batch -source src/scripts/synth_check.tcl
```

> 说明：RTL 内 `` `include "defines/*.v"`` 以 **src/ 为 include 目录**解析；Vivado
> 工程中把 include_dirs 指向 `src/` 即可直接读入 `src/rtl/` 全部源码。
