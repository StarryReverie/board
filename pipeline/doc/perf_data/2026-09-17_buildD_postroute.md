# 构建 D（实现策略优化后）时序与资源实测 · 2026-09-17

> 用途：性能分析报告的"时序资源层"证据（下板构建口径）。
> 口径：**post-route（含布线后物理优化）+ 下板存储缩容 IMEM 512 B / DMEM 256 B**。
> 与性能报告 §4 的 **post-synthesis、4 KB/1 KB×2** 口径**不可直接比较**（综合阶段 vs 布线后、容量不同）。

## 1. 构建条件

| 项 | 值 |
|---|---|
| RTL | 当前分支（含复位释放去抖加固），**未因本次优化改动 RTL** |
| 固件 | 123 条指令 / 492 B（与构建 C 相同，见 `board_runbook.md` §10.4） |
| 器件 / 工具 | `xc7a100tcsg324-1` / Vivado 2019.2 |
| 约束 | `create_clock -period 10.000`（`sys_clk` = **100 MHz**，10.000 ns） |
| 存储口径 | `IMEM_BYTES=512` / `DMEM_BYTES=256`（`verilog_define`，与下板一致） |
| 实现策略 | `STRATEGY Performance_Explore`；`PHYS_OPT_DESIGN = AggressiveExplore`；`POST_ROUTE_PHYS_OPT_DESIGN = AggressiveExplore` |
| 优化性质 | **仅实现策略**（综合/布局布线/物理优化），不涉及 RTL 或约束改动 |

## 2. 结果

| 指标 | 值 |
|---|---|
| **WNS** | **−1.347 ns**（未收敛；`Timing constraints are not met`） |
| **TNS** | **−273.660 ns** |
| 违例端点（setup） | **268 / 8948** |
| 保持时间 WHS / THS | +0.076 ns / 0.000（**0 个违例**） |
| 脉宽 WPWS | 4.500 ns（0 个违例） |
| **等价 Fmax** | `1000 / (10 + 1.347)` ≈ **88.13 MHz** |
| 资源（post-route） | **Slice LUT 12,171（19.20%）/ Slice Register 3,864（3.05%）/ Block RAM 0 / Bonded IOB 34** |
| 布线前（routed，未做布线后物理优化） | WNS −1.646 ns（物理优化阶段自身改善 **0.299 ns**） |

**最差路径（post-route phys_opt）**

| 项 | 值 |
|---|---|
| 起点 | `u_cpu/u_ex_mem/exmem_mem_read_reg/C` |
| 终点 | `u_cpu/u_id_ex/idex_rs2_reg[0]/D` |
| 数据路径 | 10.978 ns（logic 3.439 ns / **route 7.539 ns**） |
| 逻辑级数 | 18（`CARRY4=7`、LUT6=6、LUT5=1、LUT4=2、LUT2=2） |

同榜次差路径：`…exmem_mem_read_reg` → `u_id_ex/idex_pc_reg[4]/D`（11.347 ns，logic 3.439 / route 7.908，18 级）、→ `u_pc_reg/pc_reg[22]/D`（11.277 ns，logic 2.082 / route 9.195，12 级）。起点全部为 EX/MEM 的 `mem_read` 控制位，终点集中在 ID/EX 寄存器组与 PC。

## 3. 证据与复现

| 证据 | 位置 / 值 |
|---|---|
| bit（3,825,899 B，2026-09-17 19:34:27） | `pipeline/vivado/board_exp1.runs/impl_1/exp1_board_top.bit` |
| bit SHA256 | `D866924E0CA88FC70B8EDD6CD344F9198B6D7CA48A8C7DCD42FA61A8480AD93F` |
| 布线后检查点 | `pipeline/vivado/board_exp1.runs/impl_1/exp1_board_top_postroute_physopt.dcp` |
| 本文件数字的重出方式（只读检查点） | `open_checkpoint <上述 dcp>` → `report_timing_summary -max_paths 20` + `report_utilization` + `report_timing -max_paths 10 -input_pins` |
| 记录出处 | `pipeline/doc/board_runbook.md` §3.3 与 §10.5（构建 D） |

复现命令（本机）：

```powershell
# 1) 重建工程（含实现策略设置）：见 pipeline/src/scripts/create_exp1_board_proj.tcl
# 2) 实现 + 出 bit：launch_runs impl_1 -to_step write_bitstream
# 3) 只读重出时序/资源报告：
vivado -mode batch -nojournal -nolog -source build/perfD_reports.tcl
```

## 4. 结论与使用限制

1. 实现策略优化把下板口径的 WNS 从构建 C 的 −1.430 ns 改善到 **−1.347 ns**（等价 Fmax 87.5 → **88.13 MHz**），但 **100 MHz 仍未收敛**，不能宣称时序满足。
2. 本构建资源足以放进器件（LUT 19.20%、Block RAM 0），因此这是**布局布线质量**的改善，而非结构改动。
3. **不可与单周期基线的 77.22 MHz（post-synthesis，4 KB）直接比较**：流程阶段与存储容量口径都不同。若要据此更新"时间加速比"，需要对单周期基线做**同器件/同工具/同约束/同流程/同容量**的实现运行，本轮未做。
