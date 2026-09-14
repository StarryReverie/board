# 大三单周期 CPU 基准实测（实验一性能对比基线）

> **用途**：为实验一性能分析提供"大三单周期 CPU"侧的**实测**数据。
> 上位文档：`pipeline/doc/perf_analysis.md` §4、性能报告 `pipeline/doc/perf_report.md` §3.2 / §4。
> 记录日期：2026-09-14。**本文件所有数字均为本轮实测，不含估算或折算。**

---

## 1. 测量对象与出处

| 项 | 内容 |
|---|---|
| 被测设计 | 组内成员**大三阶段课程设计**的单周期 CPU（仓库内只读副本 `ref/CPU/`） |
| 顶层 | `ref/CPU/cpu_top.v`，对外**仅 `clk` / `rst`** |
| 数据出处 | 仓库内 `ref/CPU/`（22 个受版本控制文件）+ 本轮 xsim 实测 |
| **只读约束** | 全程**未修改** `ref/` 任何文件；测量 TB、综合副本全部落在 gitignored 的 `build/` |

### 1.1 该 CPU 的指令集（决定可比范围）

`ref/CPU/control.v` 的主译码只支持：`R 型（ADD/SUB）`、`ORI`、`LW`、`SW`、`BEQ`、`JAL`。

因此**同源可比的程序只有 `test0` / `test1` / `sort` 三档**（本仓库 `pipeline/src/test/` 下同名 `.asm`，
逐字节核对确认镜像同源）；流水线的 `instr_cover` / `hazard_cover` / `loop_heavy` 使用了该 CPU 不支持的指令
（`bne`、移位、比较、`lui` 等），**不参与单周期对比**，报告中必须如此说明。

---

## 2. 拍数实测（xsim 行为仿真）

### 2.1 测量方法

- TB：`build/ref_sim/tb_ref_perf.v`，运行器 `build/ref_sim/run_ref_perf.ps1`；每档独立编译运行（`xvlog -d REF_*`）。
- 计数口径：**PC 变化次数 + 1**。
  - 单周期设计**每拍执行 1 条指令**，每条已执行指令都会使 PC 变为下一个地址；
  - 程序末尾为 `beq x0,x0,0` 自旋，该指令执行后 PC 不再变化 → 故 `+1` 即这条停机指令；
  - 该判据**不依赖停机检测的时序**（早期版本用"PC 连续 N 拍不变"判停，会引入 N−1 拍常数偏差，已废弃）。
- 时钟周期沿用参考 TB 的 2 µs（与拍数无关，仅保证时序一致）。
- 每档同时核对终值（寄存器堆 / RAM），与 `ref/CPU` 自带 TB 的期望逐项一致。

### 2.2 结果

| 程序 | 单周期 `C_total`（拍） | 停机地址 | 流水线 `IC`（同源镜像） | 关系 |
|---|---|---|---|---|
| test0 | **11** | 0x24 | 10 | `IC + 1` |
| test1 | **20** | 0x4C | 19 | `IC + 1` |
| sort | **178** | 0x8C | 177 | `IC + 1` |

**三条独立结论**：

1. **单周期 `CPI ≡ 1.00`**：表中的 `C_total` 是 PC 变化计数加终止自旋的测量窗口，不能直接用
   `11/10` 解释 CPI；按单周期“每条已执行指令一拍”的定义，CPI 恒为 1.00。这里的 `+1` 是
   停机用的自旋指令本身，而非流水线的填充/停顿开销。
2. **两条测量链路交叉验证**：单周期侧（PC 变化计数）与流水线侧（EX 槽计数）对同一镜像给出
   `C_单周期 = IC_流水线 + 1`，两者**完全一致**，说明两套 TB 的计数口径都可信。
3. **流水线的 CPI 溢价来源清晰**：流水线在同源程序上需要 `C_steady`= 9 / 21 / 244 拍，
   以剔除停机自旋后的 `IC_useful=9/18/176` 计，`CPI_steady` = 1.000 / 1.167 / 1.386；稳态窗口相对有效指令数多出的部分严格为
   **load-use 冻结（`L`）+ 非终止分支冲刷（`2(T-1)`）**，即 `C_steady - IC_useful = L + 2(T-1)`，与 `perf_report.md` §2.3 的拆解一致。

### 2.3 复现命令

```powershell
powershell -File build/ref_sim/run_ref_perf.ps1
# 产物：build/ref_sim/out/ref_{test0,test1,sort}/ref_*.out.txt（含 REF_SUMMARY / REF_REG / REF_MEM）
```

---

## 3. 资源与时序（综合）

| 项 | 内容 |
|---|---|
| 综合脚本 | `build/ref_synth/synth_ref_stage1.tcl`（综合落 DCP）+ `synth_ref_stage2.tcl`（读 DCP 出报告） |
| 运行器 | `build/run_both_synth.ps1`（一次跑完单周期 + 流水线两个设计的两阶段综合） |
| 源 | `build/ref_synth/src/`（`ref/CPU` 的副本，仅 `rom.v` 加 `$readmemh` 初值、`pc_reg.v` 加上电初值、`cpu_top.v` 加 1 位观测输出） |
| 器件/约束 | `xc7a100tcsg324-1`、100 MHz（10 ns）——与流水线侧同口径 |
| 工具 | Vivado 2019.2，`synth_design -flatten_hierarchy none` |

### 3.1 实测结果（2026-09-14）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 综合单元数 | **215,770 cells** | `get_cells -hier` |
| **Slice LUTs** | **141,854**（占器件 **223.74%**） | `report_utilization`；器件可用 63,400 |
| Slice Registers (FF) | **33,768**（26.63%） | 器件可用 126,800 |
| **Block RAM** | **0**（0%） | **4 KB ROM 与 4 KB RAM 均未映射成 BRAM** |
| DSP | 0 | — |
| 时钟约束 | 100 MHz（10 ns） | `create_clock -period 10.000` |
| **WNS** | **−2.950 ns** | 综合后估计（`report_timing`） |
| **Fmax（估）** | **≈ 77.2 MHz** | `1000 / (10 + 2.950)` |
| **关键路径** | 12.846 ns（logic 5.170 + route 7.676），23 级逻辑 | 起点 `u_pc/pc_reg[1]/C` → 终点 `u_rom/instr[...]`；**落在 ROM 组合读译码上** |

**两条客观结论（报告可直接引用）**：

1. **该单周期设计的存储实现严重不适合 FPGA**：`ram`/`rom` 在综合日志中分别报
   `Trying to implement RAM 'mem_reg' in registers` 与
   `ROM "imm_sel" won't be mapped to RAM because it is too sparse`，
   最终 **Block RAM = 0**，4 KB+4 KB 存储全部落成 LUT 逻辑 → LUT 用量达器件的 **223.74%**（放不下）。
2. **关键路径不在 ALU 而在 ROM 组合读**：路径起点为 PC 寄存器，终点为 `u_rom/instr[...]` 的
   组合读译码（12.846 ns，23 级逻辑）→ 单周期结构的频率瓶颈正是"取指组合读 + 整条通路串联"，
   这与 §2 的 `CPI ≡ 1` 形成教科书式的对照（用频率换 CPI）。

> ⚠️ **使用限制**：LUT 绝对数（141,854）**主要由"存储未映射成 BRAM"贡献，不能当作"逻辑规模"直接与
> 流水线侧比较**。报告中必须同时给出 Block RAM = 0 这一条件，并把结论限定为
> "该单周期实现的存储映射方式导致资源不可实现"；若要比较**纯逻辑**规模，需另做一版
> 把 ROM/RAM 显式映射为 BRAM 的变体（改变存储读时序，属另一实验，本轮未做）。

### 3.2 为什么必须给副本打三处"综合可见性"补丁

`ref/CPU` 的 `rom` / `ram` / `regfile` 在仿真期**全部由 TB 用 `$readmemh` 装载**，RTL 内既无存储初值，
`pc_reg` 也没有非复位的初值来源。综合器据此判定：

- `pc` 恒为 0（复位值）→ ROM 地址恒定 → 取指内容恒定 → **整条取指/译码/执行/访存通路被判为死逻辑**；
- 实测后果：`synth_design` 报 0 errors，但报告输出
  **`Slice LUTs = 0`、`Slice Registers = 0`、`Block RAM = 0`、`No timing paths found`** —— 空设计。

因此副本上只加三处**不改变任何组合/时序逻辑结构**的改动：

1. `rom.v`：`initial $readmemh("test_sort_rom.hex", mem);` —— 让 ROM 有内容，取指通路不被判死逻辑；
2. `pc_reg.v`：`initial pc = 32'b0;` —— PC 有上电初值（仿真期由 `rst` 给出，综合期无来源）；
3. `cpu_top.v`：新增 **1 位观测输出 `dbg_pc0`**（`assign dbg_pc0 = pc[0];`）——
   `cpu_top` 对外**只有输入**（`clk`/`rst`，且 `rst` 在本测量中无扇出），综合器会删除"不驱动任何输出"的
   全部逻辑；引出 1 位即可保留整条指令通路。**1 位对资源/关键路径的影响可忽略**。

这三处只让综合器"看得见"本就存在的存储与寄存器，**不新增/删除任何逻辑**，
故资源与关键路径与仿真所用设计一致。报告中引用本节数据时须一并注明该条件（属"测量条件"，非设计改动）。

### 3.3 已知工具坑（记录备查）

| 现象 | 原因 / 规避 |
|---|---|
| `report_utilization` 在 `synth_design` 之后同进程内调用会输出**空设计** | Vivado 2019.2 的 `synth_design` 会派生 helper 进程（日志 `Helper process launched with PID …`），此时父进程设计尚未回填 → **必须分两个 vivado 进程**（阶段1 落 DCP、阶段2 `open_checkpoint` 后出报告） |
| 顶层"只有输入、无可观测输出"时综合出空设计 | 综合器删除不驱动任何输出的逻辑锥；**加 1 位观测输出**即可（本文件 §3.2 第 3 条）。流水线侧同理：`pipeline_top` 在 `SOC_BUILD=0` 下四个 mmio 输出全为常量，故用 `build/pipe_synth/pipe_synth_top.v` 作综合顶层 |
| `read_verilog -define` 报 `'-define' is only supported when is_compile_unit_mode is enabled` | `create_project`（project 模式）下不支持；**去掉 `create_project`**，用内存式流程（与单周期侧一致） |
| 偶发 `couldn't read file "…/scripts/rt/…/unimacro_*.tcl"` 或 `"…/.Xil/…/cpu_top.tcl": No error` | 本机 Vivado 安装/工程目录读取偶发失败（文件确实存在、有读权限）；**加 3 次重试**即可 |
| 综合收尾阶段偶发 CPU 空转不退出 | 仓库既有文档（`pipeline/src/scripts/synth_check.tcl` 头注）已记录同一现象；以日志出现 `Synthesis finished` 且无 ERROR 为通过判据 |
| C 盘剩余空间偏小可能加剧上述偶发读失败 | 综合前把 `TEMP`/`TMP` 指到工程所在盘（脚本内已设） |
