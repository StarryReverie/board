# 实验一关键仿真实验说明（写入报告版）

> 配套文档：`pipeline/doc/top_design.md` §1/§4/§5（五级划分、哈佛、前递/冻结/冲刷口径）、`pipeline/doc/perf_report.md`（性能实测）、`pipeline/doc/modules/*.md`（模块契约）。
> 产物目录：脚本自动生成 → `pipeline/doc/sim_shots/auto/`（PNG + 同名日志 + 汇总表，供展示/核对）；`pipeline/doc/sim_shots/` 预留给**人工截图**归档。
> **口径（重要）**：**回归测试不计入仿真实验**。全量回归（21/21）只在报告 §7 用"一行 + 一张汇总表"交代正确性总账，不占仿真条目。
> 下面 4 项**每项验证一个明确的设计决策**，仿真要能证明"这个设计是对的"。
> **证据要求**：① 仿真 PASS 输出（可复现命令）② PNG（按"📸 截图要点"）③ 完整日志同前缀归档。

---

## 1. 四项仿真 ↔ 设计点 ↔ 报告位置

| # | 仿真实验 | 验证的**设计点** | 报告位置 | 产物 |
|---|---|---|---|---|
| **1** | **五级流水线运行总览**（连续 8–10 拍，同拍可见 5 条指令） | 五级划分 + 段间寄存器 + 哈佛结构（取指与访存不冲突） | §5.1 数据通路**图示** | `auto/1_pipe_overview_<日期>.png/.log` |
| **2** | **数据前递与前递优先级**（背靠背 RAW：`addi x1→addi x2,x1→add x3,x2,x1`；另加同址连写双命中） | 前递通路有效 + **EX/MEM 优先于 MEM/WB** | §5.3 流水线冒险（数据相关） | `auto/2_fwd_priority_<日期>.png/.log`（2a 两条通路 + 2b 双命中优先级） |
| **3** | **load-use 冻结 1 拍**（`lw x4 → addi x5,x4,1`） | "load-use 只冻结 1 拍"的正确性与代价 | §5.3（数据相关） | `auto/3_loaduse_stall_<日期>.png/.log` |
| **4** | **分支预测不跳 + 冲刷 2 拍**（`beq` taken） | 控制相关策略：默认不跳、真跳冲刷 IF/ID+ID/EX | §5.3（控制相关） | `auto/4_branch_flush_<日期>.png/.log` |

---

## 2. 实现（已落地，RTL 零改动）

- **波形 TB**：`pipeline/src/test/wave/wave_pipe.v`，置于 `test/wave/` 子目录且不以 `tb_` 开头 → **与 `run_tb.ps1` 的 21 项回归隔离**（回归口径不变）。一个 TB 顺序跑三段程序，逐拍（posedge 后 `#1`）采样：
  - `cover` = `instr_cover_rom.hex`（项 1）
  - `hazard` = `hazard_cover_rom.hex`（项 2 场景 1 / 项 3 场景 2 / 项 4 场景 4）
  - `priority` = `fwd_priority_rom.hex`（项 2 双命中优先级；**独立场景，不改 hazard_cover**，避免其 IC=16 作废 `perf_report.md` 表 A/B/C）
- **采样信号**（全部经 `u_cpu` 层次引用，顶层 wire / execute 内部前递值）：`pc`、`ifid_inst`、`idex_pc/rd/alu_op/rs1_data`、`alu_a/alu_b/alu_out`、`exmem_alu_result`、`memwb_rd/rdata`、`wb_we/rd/data`、`stall`、`br_taken`、`br_target`、`fwd_a_sel/fwd_b_sel`；另由 TB 影子寄存器给出 IF/ID/EX/MEM/WB 各级指令字供标注。
- **VCD**：本机 xsim 2019.2 `$dumpvars` 只写初值，故 TB 侧逐拍 `$fwrite` **直接写 VCD** + CSV；VCD/CSV 落在 `pipeline/src/scripts/out/wave/`（可复现、不入库）。
- **PNG**：`pipeline/src/scripts/wave_png.ps1` 用 .NET `System.Drawing` 由 CSV 渲染（本机无 GTKWave/matplotlib）；带时间标尺（1 格 = 1 周期 = 10 ns）、游标、指令反汇编标签、高亮拍。
- **一键复现**：
  ```powershell
  powershell -File pipeline/src/scripts/run_wave.ps1      # 仿真 + 渲染 4 图
  powershell -File pipeline/src/scripts/report_png.ps1    # 回归/性能汇总表
  ```
- **TB 内嵌验收断言**：项 1 = `instr_cover` 终值（26 断言）；项 2/3/4 = `hazard_cover` 终值（12 断言）；项 2b = `fwd_priority` 终值（4 断言）；末行 `=== ALL PASS ===`。

---

## 3. 逐项做法、验收与 📸 截图要点

### 1 · 五级流水线运行总览
- **做法**：装载 `instr_cover_rom.hex`，连续采样 8–10 拍导出波形。
- **验收**：末态寄存器/存储器与 TB 期望值一致（打印 PASS）。
- **📸 必须入镜**：① 时间轴取**连续 8–10 个周期**，从 `pc` 对齐处开始；② **同一拍里 5 条不同指令分别处于 IF/ID/EX/MEM/WB**（五级各占一行，必要时加指令标签）；③ **信号名 + 时间标尺 + 游标时刻**齐全；④ 图内标注程序名与时钟（100 MHz 名义）。

### 2 · 数据前递与前递优先级
- **做法**：跑 `hazard_cover` 场景 1（连续 RAW），记录 `fwd_a_sel`/`fwd_b_sel`、`idex_rs1_data`、`exmem_alu_result`、`wb_data` 与 ALU 输入/结果；另跑 `fwd_priority` 同址连写场景。
- **验收**：第 2、3 条指令取到前一条结果（`x2=2`、`x3=3`）；**两级同时可前递时选中 EX/MEM**（`fwd_a_sel=01`，`alu_a` 取较新值 2 而非 MEM/WB 的 1，`x12=2`）。
- **📸 必须入镜**：① `fwd_a_sel`/`fwd_b_sel` 的**取值**（标注 `2'b01`=EX/MEM、`2'b10`=MEM/WB）；② 被前递的两级结果与 ALU 输入**同拍对齐**；③ 标注"生产者 → 消费者"指令对；④ 用一个游标**卡住"选择 EX/MEM"那一拍**。

### 3 · load-use 冻结 1 拍
- **做法**：跑 `hazard_cover` 场景 2，记录 `stall`、`pc`、`if_id`、`id_ex` 控制位。
- **验收**：`stall` **恰好高 1 拍**；该拍 `pc` 不变、`if_id` 不更新、`id_ex` 为气泡；下一拍恢复；`x5=4`。
- **📸 必须入镜**：① `stall` 高电平**只占 1 个周期**（用游标量出宽度）；② 冻结拍内 `pc` 不变、`if_id` 不更新；③ 下一拍 `pc` 重新推进；④ 标注"`lw x4` → `addi x5,x4,1`"与"数据在 MEM 后才可用，冻结 1 拍后 MEM/WB 前递即供数"。

### 4 · 分支预测不跳 + 冲刷 2 拍
- **做法**：跑 `hazard_cover` 场景 4（`beq x6,x4` taken），记录 `br_taken`、`br_target`、`pc`、`if_id`、`id_ex` 控制位。
- **验收**：`br_taken=1` 下一拍 `if_id`=`0x00000013`(NOP)、`id_ex` 控制位清 0；`pc` 跳到 `br_target`；被冲刷的 `addi x9,x0,99` 未提交（末态 `x9=7`）。
- **📸 必须入镜**：① 冲刷拍的两处动作：**IF/ID 置 NOP + ID/EX 清气泡**；② `pc` 跳变到 `br_target`；③ **游标量出共损失 2 拍**；④ 标注被冲刷的两条错误路径指令。

---

## 4. 报告里怎么安置回归测试（不算仿真实验）

| 位置 | 写法 |
|---|---|
| §7 仿真测试用例、结果及分析 | 开头一句话 + 一张表：**21/21（14 模块单测 + 6 程序级 + 1 性能）**，表内只列**用例名与断言数**，不展开；附运行命令 `powershell -File pipeline/src/scripts/run_tb.ps1` 与日期。汇总表：`pipeline/doc/sim_shots/auto/reg_summary_<日期>.png/.md`（断言数自动统计，本次运行合计 250；含性能 5 档合计 `tb_perf=74`） |
| §7 功能性测试 | 指向上面的汇总表 + 本文 4 项关键仿真 |
| §7 性能测试 | CPI/IPC/MIPS/CPU time 5 档 + 恒等式 `C = IC + (F−1) + L + 2T`（5/5，见 `perf_report.md` 表 A/C）+ **单周期资源/Fmax 对比**（`pipeline/doc/perf_report.md` 表 D 待补） |
| §7 下板测试 | 如实写"未下板" + 准备清单（工程/脚本/固件/XDC 就绪）+ 兜底路径（课程允许仿真验收） |

性能汇总表：`pipeline/doc/sim_shots/auto/perf_table_<日期>.png/.md`（5 档实测，恒等式 5/5）。

> 人工截图：报告正文所用波形截图请存 `pipeline/doc/sim_shots/`（脚本生成的 `auto/` 版可作**展示/取景参照**，不作为最终截图）。

---

## 5. 降级为备问（不入报告正文）

- `flags[OF]` 溢出判断的仿真波形（附加功能，被问到再给）；
- dmem 未对齐访问 / 写掩码组合边界；
- 复位注入（运行中复位后重跑一致）；
- `SOC_BUILD=0` 上电自检（MMIO 悬空不误写）。

---

## 6. 复现命令与产物清单

| 步骤 | 命令 | 产物 |
|---|---|---|
| 回归 21/21 | `powershell -File pipeline/src/scripts/run_tb.ps1` | `sim_shots/auto/reg_summary_<日期>.log` |
| 性能 5 档 | `powershell -File pipeline/src/scripts/run_perf.ps1` | `sim_shots/auto/perf_run_<日期>.log` |
| 波形（仿真+渲染） | `powershell -File pipeline/src/scripts/run_wave.ps1` | `sim_shots/auto/1..4_*.png/.log`；`out/wave/*.csv/.vcd` |
| 报告素材 | `powershell -File pipeline/src/scripts/report_png.ps1` | `sim_shots/auto/{reg_summary,perf_table}_*.png/.md` |

新增文件：`pipeline/src/test/wave/wave_pipe.v`、`pipeline/src/test/fwd_priority.asm`(+`_rom.hex`)、`pipeline/src/scripts/{run_wave,wave_png,report_png}.ps1`。

---

## 变更记录

- 2026-09-13：初版——由实验一仿真清单（原 `plan.md`）持久化；4 项波形与汇总表落地，表 D（Fmax/资源）因本机 Vivado 2019.2 综合收尾/报告空转，留待综合侧。
