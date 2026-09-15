# 实验一独立上板 Runbook（exp1_board_top）

> 本文是实验一独立上板的完整操作手册与验收记录。
> 范围：**只跑实验一 CPU core**——不接 UART、不例化 `soc/` 任何模块、不使用实验二固件。
> 器件/工具：`xc7a100tcsg324-1`（EES-338）／Vivado 2019.2。
> 交付边界：本流程证明 core 的 FPGA 独立运行能力，**不**证明 UART IP、MMIO 译码或实验二 SoC。

---

## 1. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `pipeline/src/rtl/exp1_board_top.v` | 板级顶层：复位同步 + CPU + 事件监视器 + LED/数码管显示 |
| `pipeline/src/rtl/exp1_reset_sync.v` | 板上按键（低有效）→ core 复位（异步高有效、同步释放） |
| `pipeline/src/rtl/pipeline_top.v` | CPU core（`SOC_BUILD=0`）；新增 `dbg_*` **只读观测口**供板级使用 |
| `pipeline/src/test/exp1_board_demo.asm` | 上板验收程序（自检 + 写验收签名 `dmem[0]=0x0F` + HALT） |
| `pipeline/src/test/exp1_board_demo_rom.hex` | 上述程序的仿真镜像（`simple_asm.py` 产出） |
| `pipeline/src/test/exp1_board_demo_init.vh` | 上述程序的**综合固化镜像**（`hex_to_vh.ps1` 产出；入库归档，同 `soc/test/console_init.vh` 约定） |
| `pipeline/src/test/tb_prog_board_demo.v` | 上板程序的仿真回归（34 项断言） |
| `pipeline/src/test/tb_exp1_board_top.v` | 板级顶层回归（22 项断言，含 LED 语义与显示译码） |
| `pipeline/src/scripts/hex_to_vh.ps1` | `.hex` → `<名>_init.vh`（综合固化，含回读逐字节校验） |
| `pipeline/src/scripts/create_exp1_board_proj.tcl` | 生成独立上板工程 `pipeline/vivado/board_exp1.xpr` |
| `pipeline/xdc/board_exp1.xdc` | 时钟/复位/LED/数码管引脚约束（依 EES-338 手册 §6.3/§6.4） |

---

## 2. 板级结构与端口

```
exp1_board_top
 ├─ exp1_reset_sync #(STAGES=2)      rst_n(P15,低有效) → rst(异步高有效/同步释放)
 ├─ pipeline_top #(SOC_BUILD=0)      程序经 imem 的 `include "imem_init.vh"` 综合固化
 ├─ 事件与结果监视器                  dbg_pc / dbg_stall / dbg_br_taken / dbg_halt /
 │                                    dbg_store_valid/addr/data → 锁存板级状态
 └─ LED + 数码管                      led[7:0]、seg0[7:0]、seg1[7:0]、an[7:0]
```

| 端口 | 引脚 | 说明 |
|---|---|---|
| `clk` | T5 | 100 MHz 晶振（`create_clock -period 10.000`） |
| `rst_n` | P15 | `FPGA_RESET` 按键，**低有效**（带上拉） |
| `led[7:0]` | K2 J2 J3 H4 J4 G3 G4 F6 | 高电平点亮 |
| `seg0[7:0]` | B4 A4 A3 B1 A1 B3 B2 D5 | 段选组0 `{DP,G,F,E,D,C,B,A}`，高有效 |
| `seg1[7:0]` | D4 E3 D3 F4 F3 E2 D2 H2 | 段选组1 `{DP,G,F,E,D,C,B,A}`，高有效 |
| `an[7:0]` | G2 C2 C1 H1 G1 F1 E1 G6 | 位选 `LED_BIT1..8`，高有效 one-hot |

### 2.1 LED 语义

| LED | 含义 | 来源 |
|---|---|---|
| LED0 | 时钟心跳（约 0.5 s 翻转） | 自由运行计数器（**无复位**，上电即翻 → 证明时钟/供电/烧录） |
| LED1 | 复位释放完成 | `reset_done` |
| LED2 | CPU 已开始执行 | `cpu_started`（PC 出现过非 0） |
| LED3 | 检测到 load-use 停顿 | `stall_seen`（锁存 `dbg_stall`） |
| LED4 | 检测到分支重定向 | `br_seen`（锁存 `dbg_br_taken`） |
| LED5 | 检测到 dmem 写入 | `store_seen`（锁存 `dbg_store_valid`） |
| LED6 | **PASS** | `sig_written && sig_data==0x0F && halt_seen` |
| LED7 | FAIL / 超时 | `timeout_r && ~pass_r`（默认 1500 ms 窗口） |

### 2.2 停机判据（重要，易踩坑）

本流水线是"**未采取预测 + taken 冲刷 2 条**"，因此 `beq x0,x0,self` 自循环时
**PC 不是常量**，而是周期为 3 的 `{halt, halt+4, halt+8}` 循环——每轮都会多取 2 条
错路指令再被重定向回来。

> 所以 **"PC 连续若干拍不变"不能作为停机判据**（会永远不成立）。
> 正确判据是语义判据：分支 taken 且**偏移为 0**（即"跳到自己"）。
> 等价性：branch/jal 的目标加法器 A 操作数就是 `idex_pc`（见 `execute.v`），
> 故 `br_target == idex_pc ⟺ idex_imm == 0`（当 `jump != jalr`）。
> `dbg_halt` 因此实现为 `br_taken & (idex_jump != 2'b11) & (idex_imm == 32'b0)`：
> **语义等价，但把 32 位加法器/比较器从观测路径上拿掉**（直接比 `br_target==idex_pc`
> 会让它成为全设计最差路径，实测 post-synthesis WNS 恶化约 0.15 ns）。
> 该判据由 `pipeline_top` 直接给出，板级只需锁存；`jalr` 零偏移自环不覆盖
> （isa §4 的停机约定是 `beq x0,x0,self`）。

错路取到的指令是 imem 补零区（`0x00000000`），译码为全零控制字 → 不写回、不访存，
因此自循环期间寄存器堆/dmem 保持不变（已由 `tb_prog_demo` / `tb_prog_board_demo`
在 400 拍 HALT 后采样终值 PASS 证实）。

### 2.3 数码管显示

- 显示内容 = **锁存到的 `dmem[0]` 写数据**（未写入前为 0）；
- PASS 后读作 **`0000000F`**（DN0 组低四位即 `000F`）；
- 扫描：8 位 one-hot，默认每位 `2^14 ≈ 164 µs`@100 MHz，整帧 `≈1.31 ms`（≈763 Hz）；
- 两组段选输出**同一图案**（任一时刻只有一位被选中），因此即使实物上
  "组0/组1 ↔ LED_BIT1..4 / 5..8" 的对应关系与推断相反，**显示内容仍然正确**；
- 位选与段选都是**高电平有效**（手册 §6.4：共阴极 + 三极管驱动，FPGA 给正向信号）。

---

## 3. 构建步骤（命令行）

```powershell
# ① 汇编上板程序 → .hex
uv run --no-project --python 3.13.13 pipeline/src/scripts/simple_asm.py pipeline/src/test/exp1_board_demo.asm

# ② 校验 + 生成综合固化镜像（默认补零到 512 B = 下板 IMEM_BYTES）
#    产物：pipeline/src/test/exp1_board_demo_init.vh（入库归档）
powershell -File pipeline/src/scripts/hex_to_vh.ps1 -Hex pipeline/src/test/exp1_board_demo_rom.hex -PadBytes 512

# ③ 生成独立上板工程（缺 ② 会直接报错退出；工程侧自动复制为 imem_init.vh）
vivado -mode batch -source pipeline/src/scripts/create_exp1_board_proj.tcl
```

得到 `pipeline/vivado/board_exp1.xpr`，工程口径：

```text
part          : xc7a100tcsg324-1
top           : exp1_board_top
sources       : pipeline/src/rtl/*.v（原位引用）
constraints   : pipeline/xdc/board_exp1.xdc
verilog_define: IMEM_INIT_VH  IMEM_WORDS=128  DMEM_WORDS=64  IMEM_BYTES=512  DMEM_BYTES=256
include_dirs  : pipeline/src, pipeline/vivado/board_exp1_build（内含 imem_init.vh）
```

> **为什么 `imem_init.vh` 放在工程构建目录**：`imem.v` 里 `include` 的文件名是固定的
> `imem_init.vh`，而本仓库 `soc/` 上板流程同样是把 `<名>_init.vh` 复制成 `imem_init.vh`
> 再进 include 路径（见 `build/board_build_cur.tcl`）。**切勿**把固化镜像放在
> `pipeline/src/scripts/out/` 下——`run_tb.ps1`/`run_perf.ps1` 每次运行都会清空重建 `out/`，
> 下一次跑回归就会把它删掉，随后综合报 `cannot open include file imem_init.vh`。

### 3.1 GUI 方式（推荐给学生用）

1. `vivado` → Open Project → `pipeline/vivado/board_exp1.xpr`；
2. **Run Synthesis** → 期望 `synth_design completed`、0 error、0 critical warning；
3. 看 Timing Summary（见 §3.3：**当前核在 100 MHz 约束下 WNS 为负**，这是已知结论，
   不阻塞烧录，但要按 §3.3 的口径理解与记录）；
4. **Run Implementation** → **Generate Bitstream**；
5. 确认资源在器件内（见 §3.3 表：LUT 17.9%、FF 3.0%、BRAM 0、IOB 34）。

### 3.2 `.hex` 与 `.vh` 必须同源

| 用途 | 文件 | 装载方式 |
|---|---|---|
| 仿真 | `exp1_board_demo_rom.hex` | TB `$readmemh` |
| 综合/上板 | `exp1_board_demo_init.vh` →（工程侧复制为）`imem_init.vh` | `imem.v` 内 `ifdef IMEM_INIT_VH` 的 `initial` 字面量 |

两者由 ② 同步生成，`hex_to_vh.ps1` 会**回读 `.vh` 与 `.hex` 逐字节比对**；
若只改 `.asm` 而忘了重跑 ②③，板上跑的仍是旧程序——**这是最常见的"改了没生效"原因**。

### 3.3 实测资源与时序（本机 Vivado 2019.2，`xc7a100tcsg324-1`）

同一 RTL、同一约束、同一器件，**两个固件版本各构建一次**。固件内容不同会改变 imem 的
LUT 初值，进而影响 LUT 打包与布线，因此 LUT/FF 与 WNS **都随固件而变**——引用这些数字时
必须连同 bit 指纹一起引用（分别见 §10.1 与 §10.4）：

| 构建 | 固件 | post-synth LUT / FF | **post-route LUT / FF** | BRAM / IOB | **post-route WNS** | 等价 Fmax |
|---|---|---|---|---|---|---|
| **A（2026-09-14）** | 42 条指令 / 168 B | 11,412（18.00%）/ 3,816（3.01%） | **11,338（17.88%）/ 3,808（3.00%）** | 0 / 34 | **−1.239 ns** | ≈ 89.0 MHz |
| **C（2026-09-15）** | 123 条指令 / 492 B（自检加固，见 §5.1/§10.4） | 12,349（19.48%）/ 3,859（3.04%） | **12,165（19.19%）/ 3,838（3.03%）** | 0 / 34 | **−1.430 ns** | ≈ 87.5 MHz |

`create_clock -period 10.000`（100 MHz）约束下两次构建**都没有收敛**，实现状态均为
`route_design Complete, Failed Timing!`：C 构建 268 个违例端点、TNS ≈ −301 ns
（A 构建为 240 个、TNS ≈ −199 ns）。C 相对 A 的 LUT +827 / FF +30 属预期方向
（imem 以 LUT 初值实现，固件变长后零区减少、可被常量折叠的逻辑变少），
但**未做"同 RTL 换固件"的对照综合，故不作为定量结论**。

**这不阻塞烧录**（`write_bitstream` 可正常产出，见 §10.4），但必须如实理解：

1. **违例全部落在核心内部，板级包装零贡献**：C 构建用
   `report_timing -delay_type max -max_paths 200` 实测，最差 200 条路径**全部**以
   `u_cpu/…` 为终点（`u_id_ex` 138 条、`u_pc_reg` 42 条、`u_if_id` 20 条），
   **没有一条**落在板级逻辑（`br_seen`/`halt_seen`/`q_*`/`sig_*`/`to_cnt`/`heart`/数码管扫描）上；
   A 构建的同类统计为"最差 30 条全部落在 `u_cpu/u_id_ex/*`"。
   —— 板级监视器已把 `dbg_*` 先打一拍再比较；未打拍时最差路径确实落在板级
   （`exmem_rd → br_seen/CE`，WNS −1.442），打拍后回落到核心自身的最差路径。
2. **瓶颈是核心既有的组合读存储链**：`PC → imem（512 B 组合读 LUTRAM）→ 译码 → 寄存器堆组合读 → ID/EX`；
   C 构建实测的最差路径为 `u_cpu/u_id_ex/idex_rs2_reg[*] → u_cpu/u_id_ex/idex_pc_reg[28]`
   （ID/EX 段内部：操作数/前递选择 → PC 副本寄存器，仍是同一条组合链的下游段）。
   这与 `pipeline/doc/perf_report.md` 的既有结论一致（"关键路径仍受组合存储和译码逻辑影响"、
   "优化优先级应为……将 ROM/RAM 改为可推断 BRAM 后重新综合"）。
   `pipeline/doc/ref_baseline_measured.md` §3.2 也记录了同一现象的成因（无初值存储需补丁、
   存储未映射 BRAM → LUT 化）。
3. **实践先例**：实验二 SoC 使用**同一 core + 同一 512 B/256 B 存储口径 + 同一 100 MHz 约束**构建，
   已实际烧录并在板上跑通（UART banner/回显/复位重跑）。
   即该静态时序缺口在本板实测中**没有妨碍功能运行**。
4. **若上板后结果不稳定（LED 抖动 / PASS 时有时无）**，按以下优先级处理：
   - ① 先复核 §5 接线与复位极性（更常见的原因）；
   - ② 把 CPU 改成"整机时钟使能"（每 2 拍推进一次 ⇒ 等效 50 MHz）——需给 `pipeline_top`
     增加全局 CE，属核心 RTL 改动，须同步文档并重跑 23 项回归，并**用正确的
     `create_generated_clock`（周期 20 ns）约束派生时钟**，不能只是把 `sys_clk` 周期改大；
   - ③ 把 imem/dmem 改为可推断 BRAM（同步读）——收益最大但改变流水线取指/访存时序，
     属结构性改动，须先改 `top_design.md`。
   **不要**通过放宽 `create_clock` 周期来"消除"违例（板上晶振就是 100 MHz，改约束只会掩盖问题）。
   本工程因此**原样保留 10.000 ns 约束**，同时在 `xdc/board_exp1.xdc` 与本文件记录
   已知缺口、成因归属与上面的修复路径。

> 记录口径：报告/答辩中引用本节时必须写明"**post-route WNS −1.239 ns（构建 A，Fmax≈89 MHz）
> / −1.430 ns（构建 C，Fmax≈87.5 MHz），两次构建的 100 MHz 约束均未收敛；违例全部位于核心
> 组合读存储链，板级包装无贡献**"，并且**标明是哪一个构建/哪一个 bit 的数字**，
> 不得写成"100 MHz 时序满足"。

---

## 4. 烧录

1. 连接 JTAG（板载 D24 为配置成功灯）；
2. Vivado → Open Hardware Manager → Open target（自动连 localhost）；
3. Program Device → 选 `board_exp1.bit` → Program；
4. D24 应点亮。

---

## 5. 上板验收流程

| # | 操作 | 期望 |
|---|---|---|
| 0 | 按键识别（**已实测**，见 §10.3） | 按 **`RESET`** 那颗（丝印 `RESET(P9)`，实际接 FPGA **P15**）；**不要按 `PROG`**（`PROGRAM_B`，会擦配置） |
| 1 | 上电/烧录后 | **LED0 心跳**约 0.5 s 翻转（证明时钟/供电/烧录正常） |
| 2 | 松开复位键 | **LED1** 亮（复位释放完成）；**LED2** 亮（CPU 已取指执行） |
| 3 | 程序跑完 | **LED3/LED4/LED5** 亮（load-use 停顿 / 分支重定向 / dmem 写入均被观测） |
| 4 | 看数码管 | 稳定显示 **`0000000F`**（DN0 组低四位 = `000F`） |
| 5 | 看 PASS | **LED1–LED6 全亮**、**LED7 灭** |
| 6 | 按住 `RESET` 再松开，≥3 次 | 按住时只剩 LED0 心跳、LED1–LED6 灭；松手立刻恢复 → **稳定复现** |

> 复位极性（§5 首测项）已实测确认：`P15` **低有效**、按下复位，与 XDC 的"低有效 + `PULLUP`"假设一致，无需反相。

### 5.1 为什么 PASS 是可信的

验收签名不是"无条件写 15"，而是**逐项自检通过后**才写。加固后的自检链（构建 C）：

```asm
addi x31, x0, 0        # x31 = 失配计数（sltu 归一 + add 累加路径）
addi x30, x0, 0        # x30 = 独立 OR 路径的失配标志
# 每个核对项（共 22 项）重复：
addi x28, x0, <期望值>
<xor|sub> x29, xR, x28 # 比较：xor 与 sub 交替（两种机制各占一半，互为备份）
sltu x29, x0, x29      # 归一成 0/1
add  x31, x31, x29     # 累加（**不用 or**，理由见下）
# x9 / x26 两项（取值由 ALU_SLTU 产生）另走一条不经 sltu 的路径：
<xor|sub> x29, xR, x28
or   x30, x30, x29
# 生成签名（多机制叠加）：
addi x27, x0, 15
add  x31, x31, x30     # 并入 OR 路径标志（用 add 合并，用 or 会被 ALU_OR 故障清零）
sltu x5,  x0, x31      # 有错 → 1
sub  x6,  x0, x5       # 无错 → 0；有错 → 0xFFFFFFFF
xor  x7,  x6, x27      # 无错 → 0x0F；有错 → 0xFFFFFFF0
srl  x8,  x27, x31     # 无错 → 15；有错 → 15>>计数 < 15
and  x8,  x7, x8       # 无错 → 0x0F；有错 → 0
sw   x8,  0(x0)        # ★ 只有全部核对项正确才写出 0x0F
```

**核对范围（22 项）**：阶段1 的 7 项 ALU 结果（`add/sub/and/or/xor/slt/sltu`）、
`lui`+`srli` 的 3 项折半核对（x10/x11 用左右移折成小常数，规避 `addi` 12 位立即数
放不下的问题）、阶段2 的 4 项访存与 load-use 前递结果（x13/x14/x15/x16）、
阶段3 的循环累加和（x18）、阶段4 的 7 项移位与有/无符号比较
（x19/x20/x21/x23/x24/x25/x26）。
受下板 imem 512 B 限制未单列：`x17`（循环计数——已由 x18 与"必须停机"覆盖）、
`x10` 低 12 位（已由 `x10>>20` 与 x11 两项部分覆盖）。

**为什么不用 `or` 累加**：若 `ALU_OR` 本身故障（恒 0），`or x31,x31,x29` 会把所有
失配项一并吞掉、x31 恒 0 → 板上**假 PASS**。改为 `sltu` 归一 + `add` 累加后，
`ALU_OR` 故障会由"x6 == 30"这一项算出失配并计入。

**灵敏度已两层实测**：

1. **指令级变异**（`build/tb_mut.v`，build 侧临时验证、不入库）：把 23 条与"正确运行
   签名"相关的指令逐条改成 NOP（`sltu` 一条改成交换操作数）→ **23/23 全部使签名 ≠ 0x0F、
   0 漏检**。含边界情形：循环计数不递减（死循环）→ 根本不写签名；签名常数/第二条
   机制/写口被改 → 写出非 `0x0F` 的值。
   注：只在"有错"场景才起作用的签名尾指令（如 `add x31,x31,x30`）被改掉时，**正确运行**
   的签名不变，属**等价变异**，故不计入本层；这类"自检机制自身的鲁棒性"由第 2 层覆盖。
2. **ALU 级故障变异**（`build/alu_fault_<op>.v` + `build/tb_mut_alu.v`）：把 ALU 的单个
   opcode 强制返回 0，分别跑旧固件（`or` 累加）与新固件，实测矩阵：

   | ALU 单点故障 | 旧固件（`or` 累加） | **新固件（本版）** |
   |---|---|---|
   | `ALU_OR` → 0 | **写出 0x0F（假 PASS）** | **检出：签名 = 0x00** |
   | `ALU_SUB` → 0 | **写出 0x0F（假 PASS）** | **检出：签名 = 0x01** |
   | `ALU_SLTU` → 0 | **写出 0x0F（假 PASS）** | **检出：签名 = 0x07** |
   | `ALU_XOR` → 0 | 检出 | 检出（0x00） |
   | `ALU_ADD` → 0 | 检出 | 检出（0x00） |

   **5/5 全部检出**。加固前有 3 个 opcode 的单点故障能造成假 PASS；其中 `ALU_SUB`、
   `ALU_SLTU` 两个洞是**在修第一个洞的过程中被这个矩阵当场暴露**的（分别来自"签名尾
   用了 `sub`"与"归一只用 `sltu`"），对应修法：签名尾并联一条与 sltu/sub/xor 无关的
   `srl x8, 15, x31`；让 `sltu` 产生的两项走独立 OR 路径；合并时用 `add` 而不是 `or`
   （用 `or` 的反例也被矩阵复现过：ALU_OR 故障会把已累计的计数清零）。

任一核对项错误 → 写入 0 或非 `0x0F` → 板上不出现 PASS（若此时程序仍能进入 HALT，
则 PASS 不亮且 LED7 也不亮，属"跑完但结果错"；若程序卡住则超时 → LED7 亮）。

> 残留边界（如实记录）：本自检是"用被测 CPU 自检自身"，上述保证仅覆盖**单 opcode
> 故障**模型。**两个及以上 opcode 同时故障**（例如 `ALU_OR` 与 `ALU_SLTU` 同时恒 0）
> 仍可能漏检；要做到单故障全覆盖需为每项并联两条独立累积路径（每项 5 条指令），
> 当前 512 B 下板 imem 放不下（22 项 × 5 > 128 字），需先扩 imem 或改用
> "回读 dmem 校验和"等外部机制。
>
> 另：数值自检无法识别"故障结果恰好等于期望值"的情形（例如某条指令被删掉，而它写的
> 目的寄存器本来就该是 0）；这类情形由 `tb_prog_board_demo.v` 的结构化断言覆盖。

---

## 6. 视频拍摄（2～3 分钟）

### 6.1 拍前准备

| 检查 | 要求 |
|---|---|
| 终态先确认 | **LED1–LED6 全亮、LED7 灭、数码管一个 `F` + 七个 `0`**；不对就先重新 `Program Device`（§4） |
| **不要按 `PROG`** | 它是 `PROGRAM_B`（FPGA 引脚 P9），一按就擦配置、板子随后从 Flash 加载别的设计（全灭 → 别的 LED 图案），视频里无法解释；详见 §10.3 |
| 固定与机位 | 板子与相机都固定（支架/书堆）；**斜 30–45°** 拍以避开数码管高光；先全景（含 JTAG 线与 D24）再数码管近景 |
| 光线 | 稍暗的环境光让 LED 更醒目；避免强光直射数码管 |
| 走线 | 别让 USB/JTAG 线挡住 LED 或数码管 |
| 可选 | 画面角落放写有「实验一 独立上板 / 姓名 / 学号 / 日期」的纸 |

> **LED 物理排列**（便于镜头前指点）：绿 4 颗 = `LED0–LED3`，黄 4 颗 = `LED4–LED7`；
> 引脚 `K2 / J2 / J3 / H4 / J4 / G3 / G4 / F6`。
> **注意：程序约 1.5 µs 就跑完（静态 123 条指令、动态 135 条 ≈ 145 拍 @100 MHz），所有状态灯几乎同时亮，不存在"依次点亮"**——只能拍"终态 + 复位重跑"。

### 6.2 分镜脚本

| # | 时间 | 手上动作 | 画面 | 口播要点 |
|---|---|---|---|---|
| 1 | 0:00–0:15 | — | 板子全景 + JTAG + D24 + 上电状态 | "EES-338，实验一独立上板：不接 UART，只有 CPU 核 + 8 个 LED + 8 位数码管" |
| 2 | 0:15–0:40 | 切屏幕 | Hardware Manager 的 `Program Device` 对话框（bit 路径 `…/impl_1/exp1_board_top.bit`）；`board_exp1.xpr` 顶层 = `exp1_board_top` | "板上就是这个 bit：顶层 `exp1_board_top` = `exp1_reset_sync` + 流水线核 + 事件监视器" |
| 3 | 0:40–1:05 | 手指依次点 | LED0 心跳 → **LED1–LED6 全亮** → LED7 灭 → 推近数码管 **`0000000F`** | "LED0 是 0.5 s 心跳；LED1 复位完成 / LED2 已取指 / LED3 load-use 停顿 / LED4 分支重定向 / LED5 dmem 写入 / LED6 **PASS**；数码管是验收签名" |
| 4 | 1:05–1:40 | **按住 `RESET` 3–5 s 再松开**，重复 2 次 | ① 按住：**只剩 LED0 还在闪**、LED1–LED6 全灭；② 数码管**塌成一位 `0`**（其余位熄灭）；③ 松手：**立刻**恢复 8 位 `0000000F` + LED1–LED6 全亮 | "复位把 CPU 拉回 PC=0、监视器全部清零——**心跳没停**，说明心跳不属于复位；数码管只剩一位 `0`，因为扫描计数被清零且签名还没写。松手立即重跑、结果完全一致 = **可重复**" |
| 5 | 1:40–2:05 | — | 近景轮流对准数码管与 LED | "`0x0F` 不是无条件写的：程序先**逐项核对 22 项**中间结果（ALU 全类、`lui`+`srli`、`sw→lw` 往返与两处 load-use 前递、循环累加和、三种移位、有/无符号比较），全部相符才写。所以这一位 `F` 等于这 22 项在实板全对（口径见 §5.1）" |
| 6 | 2:05–2:25 | 切屏幕 | `run_tb.ps1` 的 **23/23 ALL PASS** 日志；综合/实现资源与时序报告 | "上板前 23 项回归全绿；上板口径 512 B/256 B，**构建 C** 的 12,165 LUT / 3,838 FF / 0 BRAM（见 §10.4）" |
| 7 | 2:25–2:40 | — | 板子全景收尾 | "本设计不接 UART；`PROG` 是擦配置的，别按；掉电后 JTAG 配置丢失、需重新烧录" |

时长超了就先砍镜头 6 的口播，或把镜头 1/2 合并。

### 6.3 两个必须拍到的细节

1. **按住 `RESET`**：只有 LED0 心跳在动、其余全灭，且**数码管从 8 位塌成 1 位 `0`**
   → 同时证明三件事：复位生效、**心跳自由运行**（不属于复位）、**数码管是真扫描出来的**（不是固定显示）；
2. **松手瞬间全部恢复**：8 位 `0000000F` + LED1–LED6 全亮，重复 ≥3 次一致
   → 程序 ≈1.5 µs 跑完，这是"可重复运行"的唯一直接证据。

### 6.4 怎么体现"这是我做的"（三档，按需选）

| 档 | 成本 | 做法 |
|---|---|---|
| ① 必做 | 0 | 口播 + 字幕写清本人负责部分（板级顶层 / 复位同步 / 事件监视器 / 验收程序 / 固化脚本 / 引脚约束）；展示 `board_exp1.xpr`（top=`exp1_board_top`）、`board_exp1.xdc`、`run_tb.ps1` 的 23/23 全绿 |
| ② 推荐 | 0 | 展示 `Program Device` 对话框里的 bit 路径 + 综合/实现日志中本人的模块名（`exp1_board_top`、`exp1_reset_sync`）——把"板上现象"与"本人 RTL"绑定 |
| ③ 加分（可选） | 重出 bit 10–15 min | 把验收签名改成一个别的值（如 `0x5A`）重烧，镜头里演示**数码管 `0000000F` → `0000005A`** —— 最硬的"确为本设计在跑"证据（出厂 demo 不可能显示该值） |

### 6.5 归档

- 文件名建议 `实验一独立上板_<YYYYMMDD>.mp4`，**与实验二视频分开归档**；
- 本视频**不需要串口终端**（实验一不含 UART）；实验二 SoC 视频单独拍摄、单独写入实验二报告；
- 拍完在本节末尾登记：`文件名 / 日期 / 时长`（对应 §9 归档清单与 §10 验收记录）。

---

## 7. 故障定位

| 现象 | 优先检查 |
|---|---|
| **所有 LED 忽然全灭（含心跳 LED0）** | **误按了 `PROG`**：它是 `PROGRAM_B`（FPGA 引脚 **P9**，bank 0 专用配置脚），一按就**擦除配置**；板子随后会从 SPI Flash 重新加载别的设计（典型表现：部分 LED 恒亮 + 数码管显示 `0000000...`），此时的现象**与实验一无关**。处理：重新 Program 本 bit 即可（见 §10.3） |
| LED0 心跳不亮 | 时钟 T5、供电、`.bit` 是否烧录成功、D24 |
| 心跳正常但 LED1 不亮 | `P15` 复位极性、`exp1_reset_sync` 是否被综合掉、按键是否卡住（**别用 PROG 键测复位**） |
| LED2 不亮 | `imem_init.vh` 是否生成并进 include 路径、`IMEM_INIT_VH` 宏是否生效 |
| 数码管全灭 | 位选/段选极性、`SEG_EN=1`、`SCAN_DIV_BITS` 是否被误改 |
| 数码管乱码/错位 | 段序 `{DP,G,F,E,D,C,B,A}` 与实物是否一致（改 `exp1_board_top` 的 `seg_act` 位序）；另：本设计只保证"**一个 `F` + 七个 `0`**"，F 在最左或最右取决于模块排列 |
| 结果不是 `0000000F` | CPU 逻辑问题：看仿真回归（`tb_prog_board_demo` / `tb_exp1_board_top`）是否全绿 |
| 复位后不能重复运行 | 监视器是否被 `rst` 清零（本设计已清）；dmem 无复位初值，靠程序自初始化 |
| LED7 亮（超时） | 程序未进入 HALT 或签名未写入 → 先跑仿真回归定位 |
| 综合资源超限 | 确认 `IMEM_BYTES=512`/`DMEM_BYTES=256` 生效，勿回落到默认 4 KB |

---

## 8. 仿真自检（上板前必做）

```powershell
# 全量功能回归（含上板程序与板级顶层）
powershell -File pipeline/src/scripts/run_tb.ps1
# 备用（若本机 Start-Process 仍受环境变量大小写重复影响）：
powershell -File build/run_cases.ps1 -Kind tb
```

当前口径 **23/23 PASS**（14 模块 TB + `tb_perf` + 7 程序级 TB + 板级 `tb_exp1_board_top`）。
其中与上板判据一一对应的两项：

| 用例 | 对应上板现象 |
|---|---|
| `tb_prog_board_demo`（34 项断言） | 上板程序的全部中间结果与 `dmem[0]=0x0F` |
| `tb_exp1_board_top`（22 项断言） | LED 语义（心跳/复位/取指/停顿/重定向/写存/PASS）+ 数码管译码 `0000000F` |
| 其余 core 回归 | CPU 本体（含 8 档性能恒等式）无回归 |

---

## 9. 归档证据

- `pipeline/vivado/board_exp1.xpr`（工程，本地生成、不入库）与 `pipeline/xdc/board_exp1.xdc`；
- 综合/实现/时序日志（资源与 `WNS`）；
- `exp1_board_demo.asm` / `_rom.hex` / `imem_init.vh`；
- `.bit` 及生成日期；
- 上板验收记录（见 §10）；
- 实验一独立上板视频（拍摄脚本见 §6，文件名/日期/时长在 §6.5 登记）。

---

## 10. 实测验收记录（2026-09-14，EES-338 实板）

### 10.1 本次 bit 的指纹与构建口径

| 项 | 值 |
|---|---|
| bit | `pipeline/vivado/board_exp1.runs/impl_1/exp1_board_top.bit`（3,825,899 B） |
| 生成时间 | 2026-09-14 21:29:05 |
| **SHA256** | `4C3FAC647DDE3C5FF2DE32A276D01D0A3FEABF38254E95167DDFCEA59695EB97` |
| 资源（post-route） | **11,338 LUT（17.88%）/ 3,808 FF（3.00%）/ 0 BRAM / 34 IOB** |
| 时序（post-route） | WNS **−1.239 ns**（≈89 MHz），100 MHz 约束未收敛（见 §3.3） |
| 固件口径 | `IMEM_INIT_VH` + `IMEM_BYTES=512` / `DMEM_BYTES=256`，程序 `exp1_board_demo` |
| 烧录方式 | JTAG `Program Device`（**掉电即失**，需重烧；未写 SPI Flash） |

### 10.2 验收结果（**通过**）

| 判据 | 实测 | 结论 |
|---|---|---|
| 数码管（验收签名） | **`0000000F`** | ✅ 签名被正确写入并被监视器捕获 |
| LED1–LED6 | **全亮** | ✅ 复位释放 / 已取指 / load-use 停顿 / 分支重定向 / dmem 写入 / **PASS** 全部成立 |
| LED7 | **灭** | ✅ 无超时、无 FAIL |
| 复位可重复 | 按住 `RESET` → 只有 LED0 心跳、LED1–LED6 全灭；**松手立刻恢复**（多次一致） | ✅ 复位同步器与监视器清零行为正确 |

**`0000000F` 对构建 A 能证明什么（严格口径）**：该值只在程序**自检通过后**才写。
构建 A 的自检只核对**两个里程碑**——`bne` 循环累加和 = 15、阶段1 `xor x3,x4` = 20
（任一项不符则写 0），因此它只证明：

- ① `IMEM_INIT_VH` 固化生效、CPU 确实执行了这段程序（否则不会有任何写入）；
- ② 这两个里程碑及其依赖链正确：`add`/`addi`（循环累加与计数）、`bne` + **分支冲刷**、
  阶段1 的 `xor`；
- ③ 自检链尾与写口本身工作（把累积器 0 映射成 `0x0F` 并写入 dmem[0]）；
- ④ 板级监视器正确判出"签名 == 0x0F"与"HALT 自循环"；
- ⑤ 另由 LED3/LED4/LED5 观测到 **load-use 停顿 / 分支重定向 / dmem 写入**"发生过"
  （这三盏灯只证明事件出现，**不证明结果正确**）。

**不能**由构建 A 的签名推出：`lw`、load-use **前递结果**、`lui`、三种移位、
`slt`/`sltu` 的**结果**正确——这些项当时未被核对，它们出错时签名仍可能是 `0x0F`
（PR #11 review 指出）。该覆盖缺口已由构建 C 的加固自检关闭，见 §5.1 与 §10.4。

> 附带结论：**post-route WNS −1.239 ns 的静态时序缺口没有妨碍本板功能运行**——这是实测证据，
> 与 `pipeline/doc/perf_report.md` 的既有判断一致（缺口集中在核心组合读存储链，板级包装零贡献）。

### 10.3 板上按键与 FPGA 引脚（实测，**与板子丝印不一致，勿凭丝印判断**）

| 板子丝印 | 实测功能 | 实际 FPGA 引脚 |
|---|---|---|
| `RESET(P9)` | 设计复位（**用户 IO**，低有效、按下复位） | **P15** ← `board_exp1.xdc` 的 `rst_n`，与手册 §6.1"复位引脚 `FPGA_RESET` → P15"一致 |
| `PROG` | **擦除 FPGA 配置**（`PROGRAM_B`，逻辑读不到） | **P9**（bank 0 专用配置脚） |

**依据（两条独立证据）**：

1. **器件侧**：`link_design -part xc7a100tcsg324-1` + `get_package_pins` 实测
   `P9 → PIN_FUNC=PROGRAM_B_0, BANK=0`、`P15 → PIN_FUNC=IO_L13P_T2_MRCC_14, BANK=14`；
2. **行为侧**：按住"能复位"的那颗键时 **LED0 心跳持续**（说明配置未被擦除，它是用户 IO）；
   而按 `PROG` 会让**所有 LED（含心跳）全灭**（配置被擦，FPGA 停止运行）。

**踩坑记录（值得写入报告"问题及解决方法"）**：首测时按方案文字找了"复位键"，误按到 `PROG`，
配置被擦除、板子从 SPI Flash 重新加载了别的设计（现象：4 个 LED 恒亮 + 数码管全 0），
一度被误判为"实验一设计异常"。**教训：板级按键必须用"丝印文字 + 功能实测"双重确认**——
不要只信丝印括号里的引脚号，也不要只信手册正文；判据是"按下时心跳是否继续"
（心跳继续 = 用户 IO 复位；心跳熄灭 = `PROGRAM_B` 擦配置）。

### 10.4 2026-09-15 重建 bit（自检加固，**待实板复测**）

**为什么要重建**：PR #11 review 指出上板固件的自检只核对 2 个里程碑——`lw`、load-use 前递、
`lui`、移位、有符号比较出错时签名仍可能是 `0x0F`，于是 PASS 推不出这些功能正确。
本轮按两批 review 意见把阶段5 重写为：

- **逐项核对 22 项**（覆盖 ALU 全类、`lui`+`srli`、`sw→lw` 往返与两处 load-use 前递、
  循环累加和、三种移位、有/无符号比较），比较用 `xor`/`sub` 交替；
- **独立累积机制**：`sltu` 归一 + **`add` 累加**（不再用 `or`——`ALU_OR` 故障会吞掉全部失配）；
  `sltu` 产生的 x9/x26 两项另走一条不经 `sltu` 的 OR 路径；
- **多机制签名生成**：`sltu`→`sub`→`xor` 之外再并联与它们无关的 `srl x8, 15, x31`，
  合并用 `add`。原理与边界见 §5.1。

**灵敏度两层实测**（细节与矩阵见 §5.1）：指令级变异 **23/23 全部检出、0 漏检**；
ALU 级故障变异 **5/5 单 opcode 故障全部检出**（加固前有 3 个 opcode 可造成假 PASS）。

| 项 | 值 |
|---|---|
| 固件 | `exp1_board_demo.asm` → `_rom.hex`（**123 条指令 / 492 B**）→ `exp1_board_demo_init.vh`（补零 512 B） |
| 固件指纹 | `exp1_board_demo_init.vh` SHA256 `276F732396C633CAB2E560B1B0F2C2BAE6B8747687A38D1223018B0148760E8B` |
| bit | `pipeline/vivado/board_exp1.runs/impl_1/exp1_board_top.bit`（3,825,899 B，2026-09-15 14:35:19） |
| **SHA256** | `EB8A5870039AC33C56315AA02BA0AE5CFE533D6B328E5DAFF0A060C30BF39F77` |
| 资源（post-route） | **12,165 LUT（19.19%）/ 3,838 FF（3.03%）/ 0 BRAM / 34 IOB**（post-synth 12,349 / 3,859） |
| 时序（post-route） | WNS **−1.430 ns**（≈87.5 MHz），268 个违例端点、TNS ≈ −301 ns；**违例全部在 `u_cpu/…`**（见 §3.3） |
| 构建方式 | 工程模式 `reset_run synth_1` → `launch_runs synth_1` → `reset_run impl_1` → `launch_runs impl_1`，再 `open_run impl_1` + `write_bitstream`（0 error） |
| 仿真口径 | `run_tb.ps1` **23/23 PASS**；`tb_prog_board_demo` 34 项断言含全部里程碑；`tb_exp1_board_top` 判据同 §10.2 |
| 固件运行口径 | 静态 123 条 / 动态 135 条指令、到停机 **145 拍 ≈ 1.45 µs** @100 MHz（恒等式 135+2 气泡+8 冲刷 = 145） |
| 历史 bit | 构建 A：`build/exp1_board_top_OLD_4C3FAC64.bit`（= §10.1 的 SHA，**已实板验收**）；构建 B：`build/exp1_board_top_B_4EC61A42.bit`（仅仿真验证，未上板） |

**复测步骤（约 3 分钟，判据与 §10.2 完全相同）**：

1. Vivado → Open Hardware Manager → Program Device，bit 路径取上表；
2. 期望：LED0 心跳 ✓、**LED1–LED6 全亮**、**LED7 灭**、数码管 **`0000000F`**；
3. 按住 `RESET` 3–5 s 再松开，重复 ≥3 次：按住时只剩 LED0 心跳、LED1–LED6 全灭、
   数码管塌成一位 `0`；松手立刻恢复；
4. 全部命中后，把本节标题改为"**验收通过**"并补记日期与操作人。
   **未复测前，本工程"已上板验收通过"的结论只对构建 A 有效**（§10.2 保留为
   2026-09-14 对构建 A 的实测记录，不改写历史）。

> 复测的额外意义：加固后"板上出现 `0000000F`"⇒ **22 项核对全部正确**（含 `lw`、
> load-use 前递、`lui`、三种移位与有/无符号比较），且**单 opcode 故障不会假 PASS**，
> 比构建 A 的结论强得多；报告里应同时给出"指令级变异 23/23 + ALU 级故障 5/5"作为
> 该判据的灵敏度证据。
