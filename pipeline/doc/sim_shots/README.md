# sim_shots — 实验一仿真截图与自动图表归档

实验一（RV32I 五级流水线 CPU）四项关键仿真的**人工截图**与**脚本自动图表**归档，
对应 `pipeline/doc/sim_experiments.md`。实验二归档见 `soc/doc/sim_shots/exp2/`。

## 目录内容

| 路径 | 内容 | 入库 |
|---|---|---|
| `exp1/*.png` | 人工截图（按 `sim_experiments.md` 的"截图要点"截取） | 是 |
| `exp1/auto/*.png` `exp1/auto/*.log` `exp1/auto/*.md` | 脚本自动生成的展示/参照图、同名日志与汇总表 | 是 |

## 人工截图（`exp1/`）

- `前递优先级.png`、`数据前递.png`、`load-use.png`、`分支预测.png`、`五级流水线运行总览.png`

## 自动图表（`exp1/auto/`）

由 `pipeline/src/scripts/run_wave.ps1`、`wave_png.ps1`、`report_png.ps1` 生成，
作**展示/取景参照**，不作为最终截图。含 `1_pipe_overview`、`2_fwd_priority`、`3_loaduse_stall`、
`4_branch_flush` 四项波形与 `reg_summary`、`perf_table` 两张汇总表（各带同名 `.log` / `.md`）。
