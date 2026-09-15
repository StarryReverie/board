# 下板实验方案（其他设备执行）—— EES-338 + UART SoC console

- 版本：v1.4（2026-09-15：§1 改为**一条命令建工程**——新增 `soc/scripts/create_soc_proj.tcl`（由 UART 侧旧脚本迁移统一，落点 `soc/vivado/soc.xpr`）；**修正 §1 的器件型号**为实测 `xc7a100tcsg324-1`（原文误写 `xc7a35tcsg324-1`，与实物不符会导致 bit 烧不进板）；固件构建脚本保留 `UART/src/scripts/build_fw.ps1`，烧录/取证脚本仍为手动步骤或从 git 历史恢复）。
- 目标：在**任意一台装好 Vivado 的机器**上独立完成 U32 下板：出 bit → 烧录 → 终端验收（banner/回显/复位重跑）→ 证据采集。
- 验收判据与分层流程以 `../../UART/doc/tasks.md` §3（U32/U30）为准；本文只讲"怎么在别的设备跑通"，假设仓库完整（固件 .vh 已生成，无需 RISC-V 工具链）。

---

## 0. 设备与前置清单

| 项 | 要求 |
|---|---|
| Vivado 主机 | 任意 Windows/Linux + **Vivado 2019.2 或更新**（Artix-7 WebPACK 免费版即可）；若在"本机"执行请先读已知限制（下 §7） |
| EES-338 | 一块；USB 线 ×2：**Type-C USB-UART**（CP2102，兼供电）与 **Type-C/方口 USB-JTAG**（依板型，两接口功能不同） |
| 串口终端 | Tera Term / SSCOM（演示视频用）；自动化取证脚本已删（§4.4） |
| 示波器 | （证据可选）测 FPGA uart_tx 引脚（T4）波形 |

## 1. 获取仓库与建工程（一条命令，~1 分钟）

```powershell
git clone https://github.com/StarryReverie/board.git
cd board

# 建工程：soc/vivado/soc.xpr（sources/sim/constrs/include/defines 全部口径已设好）
vivado -mode batch -source soc/scripts/create_soc_proj.tcl
```

脚本 `soc/scripts/create_soc_proj.tcl` 按下列口径建好工程（**只建工程，不综合**）：

| 项 | 值 |
|---|---|
| part | **`xc7a100tcsg324-1`** —— EES-338 实物 idcode 实测为 XC7A100T；**用户手册误标 35T，务必用实测值**，否则生成的 bit 烧不进实物 |
| sources_1 | `UART/src/rtl/*.v` + `pipeline/src/rtl/*.v` + `soc/rtl/*.v`（原位引用），top = `soc_top` |
| sim_1 | `UART/src/test/tb_*.v` + `soc/test/tb_*.v`，默认 top = `tb_soc_full`（不参与综合） |
| include | `UART/src`、`pipeline/src`（计组 `` `include "defines/*.v"`` 由此解析）、`soc/vivado/soc_build`（固件 ROM） |
| define | `IMEM_INIT_VH IMEM_WORDS=128 DMEM_WORDS=64 IMEM_BYTES=512 DMEM_BYTES=256`（下板缩容 512 B/256 B） |
| constrs_1 | `soc/xdc/board.xdc`（T5 clk 100 MHz / T4 uart_tx / N5 uart_rx / P15 rst_n） |

工程建好后在 GUI 里 `Run Synthesis` → `Run Implementation` → `Generate Bitstream`（约 5–15 分钟），
产物 `board/soc/vivado/soc.runs/impl_1/soc_top.bit`。

<details>
<summary>手动建工程（等价步骤，脚本不可用时备用）</summary>

1. 新建工程：`create_project soc soc/vivado -part xc7a100tcsg324-1`（**不是 35T**）；
2. 读入 RTL（原位引用）：`soc/rtl/*.v` + `UART/src/rtl/*.v`（UART IP）+ `pipeline/src/rtl/*.v`（计组 core）；top = `soc_top`；
3. include 目录设 `UART/src`、`pipeline/src`、`soc/vivado/soc_build`；
4. 固件固化：把 `soc/test/console_init.vh` 复制为 `soc/vivado/soc_build/imem_init.vh`（`imem.v` 硬编码 include 名），
   并设 `verilog_define` 为上表那一串；要重生成固件先跑 `powershell -File UART/src/scripts/build_fw.ps1`
   （`soc/test/console.S` → `console_rom.hex` + 补零到 512 B 的 `console_init.vh`，见 firmware.md §6）再复制；
5. 加约束 `soc/xdc/board.xdc`（T5 clk 100MHz / T4 uart_tx / N5 uart_rx / P15 rst_n）；
6. synth → impl → write_bitstream（约 5–15 分钟）。

</details>

- 无网络时：把仓库目录整体拷贝到目标机（`soc/`、`UART/src/rtl/`、`pipeline/src/rtl/` 即可，`vivado/` 可省）。
- 说明：仓库已内置 console 固件（`console_init.vh` → 综合期固化 IMEM），XDC 已按手册核定（T5=100MHz / T4=FPGA TX / N5=FPGA RX / P15=复位）。
- 变更：2026-09-15 起本节由"手动 6 步"改为"一条命令"——脚本从 `UART/src/scripts/create_vivado_proj.tcl`
  迁移为 `soc/scripts/create_soc_proj.tcl`，工程落点由 `UART/vivado/exp2.xpr` 统一为 `soc/vivado/soc.xpr`（口径不变）。

## 2. 烧录（~1 分钟）

**GUI 方式**：Vivado → Open Hardware Manager → Open target（自动连 localhost）→ Program Device → 选 `soc_top.bit` → Program。板载 D24（配置成功灯）应点亮。

**批处理方式（脚本已删）**：GUI Hardware Manager 操作，或用 Vivado Tcl Console 逐条执行 `open_hw_manager → connect_hw_server → open_hw_target → current_hw_device [lindex [get_hw_devices] 0] → set_property PROGRAM.FILE <bit> [current_hw_device] → program_hw_devices [current_hw_device]`。（找不到板时 `get_hw_devices` 为空——检查 USB-JTAG 线与驱动。）

## 3. 复位极性首测（第 0 步）

**已实测确认（2026-09-14，实验一独立上板，同一块 EES-338）**：P15 **低有效**——松键=运行、按下=复位，
与本设计默认一致，**无需反相**；同时实测两条板级坑：**丝印 `RESET(P9)` 的复位键实际接 FPGA P15**
（丝印括号里的引脚号不可信），而 **`PROG` 才是 P9 = `PROGRAM_B`，一按就擦配置**（板子随后从 SPI Flash
加载别的设计，现象是全灭/异常图案）——**切勿按 PROG**。

- 上电松键：应见 banner（若极性相反则 CPU 一直处于复位，无输出）。
- **fallback（一般不再需要）**：若在别的板子上实测为"按下才运行/上电卡死"，把 `soc/rtl/soc_top.v`
  顶部参数 `RST_ACTIVE_LOW` 默认值 1 改 0 → 重跑 §1 步骤 → 重烧。（或经工程 `generic` 属性
  `RST_ACTIVE_LOW=0` 覆盖，等价。）

## 4. 终端验收（分三小步）

串口设置：**115200-8-N-1**；COM 号在设备管理器查 "CP210x USB to UART / USB Serial Port"（本机曾见 COM8，异地以实测为准，注意别选到别的 COM）。

1. **Banner**：上电/复位后终端应收到（精确文本）：
   ```
   EES-338 RV32I UART OK
   ```
   （即 23 字节 `45 45 53 2D 33 33 38 20 52 56 33 32 49 20 55 41 52 54 20 4F 4B 0D 0A`）
2. **回显**：键盘逐字输入，每个字符应即时回显（getc→putc 轮询往返）；连续快速输入不掉字（TX_BUSY 含挂起语义保证）。
3. **复位重跑**：按 P15（或 FPGA 复位键）→ banner 重新完整出现；重复 ≥2 次一致。
4. **自动化取证（脚本已删）**：原 uart_check.ps1（自动收 banner 比对 23 字节、发 `AB` 验证回显、写证据日志）已随结构调整删除，可从 git 历史恢复；手动等价=终端日志存档 + 肉眼比对 §4.1 字节序列。

## 5. 证据采集清单（提交物 U32 需要）

| 证据 | 要求 | 备注 |
|---|---|---|
| 终端日志 | Tera Term/SSCOM 存档：banner + 回显 + 复位重跑全过程 | 存 `soc/doc/board_evidence/` 建议 |
| 下板记录 | 按 `../../UART/doc/tasks.md` §3.1 分层记录（裸 UART 先行→SoC 整机） | 模板字段：日期/机器/COM/现象/结论 |
| 示波器波形（可选但加分） | TX 帧：空闲高、起始低、位宽 ≈8.68 µs、10 位帧 ≈86.8 µs | 测 T4 或 CP2102 侧 |
| ≤5 min 演示视频 | 全程：上电 banner→键盘回显→复位重跑 | 需真实板卡画面 |

## 6. 常见问题速查（新增异地项，其余见 ../../UART/doc/tasks.md §3.1）

| 现象 | 处理 |
|---|---|
| `get_hw_devices` 为空 / Hardware Manager 找不到板 | USB-JTAG 线未接或驱动（CP210x/FTDI）未装；换口重插；检查 D18 电源灯 |
| 终端无输出 | COM 号错 / 波特率错 / 未复位极性错误（§3 fallback） |
| 输出乱码 | 波特率不一致（必须 115200）或 USB-UART 与 JTAG 两线插反 |
| 发几个字符后停 | 终端开启了本地回显造成"双写"观感≠故障；确认 CPU 回显为唯一来源（关终端本地回显再验） |
| 首字符丢 | 上电瞬间 PC 复位释放即发 banner，属正常时序；重跑验证一致性即可 |
| 本机（原开发机）Vivado 2019.2 综合后器件加载空转 | 已知限制：换本方案任一步骤到健康主机执行即可（工程已全打包） |

## 7. 回传物与收尾

1. `soc_top.bit` 拷回开发机（本机 JTAG 与 COM8 可用时也可继续编程/验收）；
2. 证据文件（终端日志/记录/波形/视频）归入仓库外存档或 `soc/doc/board_evidence/`；
3. 在 `../../UART/doc/tasks.md` U32 状态栏更新：bit 产出（机器/日期）、终端验收三项、视频链接；
4. 若极性或引脚实测与约定不符 → 先改契约文档（`soc/xdc/board.xdc` 头注 / `../../UART/doc/interface.md`）再改实现，禁止单侧改。

## 8. 变更记录

- v1.4 2026-09-15：§1 改为**一条命令建工程**——新增 `soc/scripts/create_soc_proj.tcl`（由 `UART/src/scripts/create_vivado_proj.tcl` 迁移而来；落点统一 `soc/vivado/soc.xpr`，固件副本改放工程内 `soc/vivado/soc_build/imem_init.vh`）；**修正 §1 器件型号**为实测 `xc7a100tcsg324-1`（原写 `xc7a35tcsg324-1`，与实物不符会导致 bit 烧不进板）。
- v1.2 2026-09-07：固件构建脚本保留口径（`UART/src/scripts/build_fw.ps1`）；§1.4 补脚本调用与 .vh 补零（`-PadBytes 512`）→ `imem_init.vh` 复制步骤。
- v1.1 2026-09-07：随 SoC 上移 `soc/`（本文件随迁）：全部路径改 `soc/` 与 `../exp2/`；构建/烧录/取证脚本已删——§1 改无脚本手动工程步骤、§2 批处理改 Tcl Console 逐条、§4.4 取证改手动等价。
- v1.0 2026-09-06：初版（异地设备完整执行方案）。
