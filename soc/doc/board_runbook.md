# 下板实验方案（其他设备执行）—— EES-338 + UART SoC console

- 版本：v1.2（2026-09-07：SoC 上移为项目顶层 `soc/`——路径同步；**固件构建脚本保留**（`UART/src/scripts/build_fw.ps1`，见 firmware.md §6）；**烧录/取证脚本已随结构调整删除**，§1 给出无脚本手动工程步骤，需要时可从 git 历史恢复原脚本（exp2/src/scripts/ 曾含 create_vivado_proj/board_runs/program_devices/uart_check））。
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

## 1. 获取仓库与手动建工程（~5 分钟，脚本已删）

```powershell
git clone https://github.com/StarryReverie/board.git
cd board
```

无脚本步骤（原 create_vivado_proj.tcl/board_runs.tcl 的等效操作；也可从 git 历史恢复原脚本）：

1. 新建工程：`create_project soc soc/vivado -part xc7a35tcsg324-1`（或 GUI 建工程，目录 `soc/vivado/`）；
2. 读入 RTL（原位引用）：`soc/rtl/*.v` + `UART/src/rtl/*.v`（UART IP）+ `pipeline/src/rtl/*.v`（计组 core）；top = `soc_top`；
3. include 目录设 `soc/`、`UART/src/`、`pipeline/src/`（计组 `` `include "defines/*.v"`` 解析）+ 固件 ROM 目录；
4. 固件固化：若需重生成，先 `powershell -File UART/src/scripts/build_fw.ps1`（`soc/test/console.S` → `console_rom.hex` + 补零到 512 B 的 `console_init.vh`，见 firmware.md §6）；然后把 `soc/test/console_init.vh` 复制为固件目录下 `imem_init.vh`（imem.v 硬编码 include 名），并设 `verilog_define IMEM_INIT_VH`；
5. 加约束 `soc/xdc/board.xdc`（T5 clk 100MHz / T4 uart_tx / N5 uart_rx / P15 rst_n）；
6. synth → impl → write_bitstream（约 5–15 分钟）。

- 产物：`board/soc/vivado/soc.runs/impl_1/soc_top.bit`。
- 无网络时：把仓库目录整体拷贝到目标机（`soc/`、`UART/src/rtl/`、`pipeline/src/rtl/` 即可，`vivado/` 可省）。
- 说明：仓库已内置 console 固件（`console_init.vh` → 综合期固化 IMEM），XDC 已按手册核定（T5=100MHz / T4=FPGA TX / N5=FPGA RX / P15=复位）。

## 2. 烧录（~1 分钟）

**GUI 方式**：Vivado → Open Hardware Manager → Open target（自动连 localhost）→ Program Device → 选 `soc_top.bit` → Program。板载 D24（配置成功灯）应点亮。

**批处理方式（脚本已删）**：GUI Hardware Manager 操作，或用 Vivado Tcl Console 逐条执行 `open_hw_manager → connect_hw_server → open_hw_target → current_hw_device [lindex [get_hw_devices] 0] → set_property PROGRAM.FILE <bit> [current_hw_device] → program_hw_devices [current_hw_device]`。（找不到板时 `get_hw_devices` 为空——检查 USB-JTAG 线与驱动。）

## 3. 复位极性首测（第 0 步，必须先做）

P15 极性手册未明示，设计默认"**低有效：松键=运行，按下=复位**"。

- 上电松键：应见 banner（若极性相反则 CPU 一直处于复位，无输出）。
- **fallback**：若实测为"按下才运行/上电卡死"，把 `soc/rtl/soc_top.v` 顶部参数 `RST_ACTIVE_LOW` 默认值 1 改 0 → 重跑 §1 步骤 → 重烧。（或经工程 `generic` 属性 `RST_ACTIVE_LOW=0` 覆盖，等价。）

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

## 6. 演示视频拍摄方案（≤5 分钟）

本节用于 U32 实验二 SoC 下板视频，须与实验一独立上板视频分开拍摄、命名和归档。建议成片 2–4 分钟，最长不得超过 5 分钟；画面需同时包含真实开发板和 PC 串口终端，避免只录屏或只拍板卡。

### 6.1 拍摄目标与画面要求

- 证明 `soc_top` 已由实验一 `pipeline_top`、UART IP 和复位同步模块组成，并在 EES-338 上运行。
- 证明 UART 使用 T4（FPGA TX）/N5（FPGA RX），终端参数为 **115200-8-N-1**，终端 Local Echo 关闭。
- 连续记录三个验收点：完整 banner、键盘回显、按 P15 复位后 banner 再次出现；复位重跑至少展示两次。
- 开始录制前关闭无关窗口和通知，终端字体放大到可辨认，保留时间戳或在开头口述日期、板卡和工程名称。

### 6.2 拍前准备

1. 按 §1 建工程并生成 `soc_top.bit`，确认 Hardware Manager 已识别目标器件 `xc7a100tcsg324-1`。
2. 接好 USB-JTAG 与 USB-UART 两根线，确认开发板供电灯 D18、配置灯 D24 状态正常；不要把 `PROG`（P9/PROGRAM_B）当作复位键。
3. 打开串口终端，选择实际 COM 号，设置 115200 baud、8 data bits、No parity、1 stop bit、无流控，并关闭 Local Echo。
4. 先短按 P15 验证低有效复位；等待 banner 完整显示后再开始输入，避免首字符与启动输出重叠。
5. 准备短字符串 `AB` 和连续字符串 `HELLO-RV32I`，便于在镜头中清楚展示逐字回显。

### 6.3 分镜脚本

| 镜头 | 建议时长 | 动作 | 画面必须出现 | 口播要点 |
|---|---:|---|---|---|
| 1 | 10 s | 展示整板、两根 USB 线和复位键位置 | EES-338、JTAG/UART 线、P15 | “这是实验二 UART SoC 实物连接。” |
| 2 | 15 s | 切到 Vivado 工程与 Hardware Manager | 工程顶层 `soc_top`、已生成 bit、目标器件 | “CPU 采用实验一流水线，外设为 UART IP，统一编址 MMIO。” |
| 3 | 10 s | 展示终端串口设置 | 115200-8-N-1、Local Echo 关闭 | “终端按约定参数工作，回显只来自 FPGA。” |
| 4 | 20 s | 松开 P15，等待启动 | 完整 `EES-338 RV32I UART OK` 和 CRLF | “上电或复位释放后，固件先发送启动 banner。” |
| 5 | 20 s | 输入 `AB`，逐字停顿 | 键入字符与终端回显一一对应 | “CPU 轮询 RX_VALID，收到字符后通过 TX 原样发送。” |
| 6 | 20 s | 输入 `HELLO-RV32I` 或快速连续字符 | 连续回显，无乱码、无双写 | “连续收发保持正确，TX_BUSY 时软件等待，不丢字符。” |
| 7 | 15 s | 按住 P15 | 按键动作和输出停止/复位状态 | “按下 P15 触发低有效复位，处理器回到初始状态。” |
| 8 | 20 s | 松开 P15，等待再次启动 | 第二次完整 banner | “释放复位后程序重新运行，banner 再次完整出现。” |
| 9 | 25 s | 再重复一次复位—启动 | 第三次 banner 或终端日志中的两次记录 | “重复复位结果一致，验证复位同步与固件重启。” |
| 10 | 10 s | 收尾定格 | 开发板、终端日志、文件名/日期 | “实验二三项验收均通过，视频与日志按方案归档。” |

### 6.4 三项验收必须拍到的细节

1. **Banner**：文本须完整可读，不能被窗口滚动或鼠标遮挡；至少出现两次。
2. **回显**：建议先慢速输入 `AB`，再输入较长字符串；每个字符只出现一次，不能用剪辑拼接代替连续收发。
3. **复位重跑**：镜头中明确拍到手指按下、松开 P15 的动作及其前后终端变化；两次复位之间不要重新烧录 bit。

### 6.5 异常情况处理

| 现象 | 处理 |
|---|---|
| 无输出 | 检查 COM、USB-UART 线、bit 是否正确；重新松开 P15 并等待 2 s。 |
| 乱码 | 核对 115200-8-N-1、无流控，并确认没有把 JTAG 口当 UART 口。 |
| 字符双写 | 关闭 Local Echo 后重新录制；双写镜头不作为有效证据。 |
| 首字符丢失 | 等完整 banner 出现后再输入；必要时重新复位，不剪掉启动过程。 |
| 按键无效或卡死 | 确认按的是 P15（低有效），不要按 P9/PROG；检查复位同步与电源。 |
| Banner 不完整 | 停止录制，重新烧录并复位；保留失败日志但提交最终完整视频。 |

### 6.6 视频文件与证据归档

建议将以下文件放入 `soc/doc/board_evidence/`；若仓库策略忽略大视频，可将 MP4 存课程网盘，并在 README 登记链接。

```text
soc/doc/board_evidence/
├─ uart_soc_demo_YYYYMMDD.mp4
├─ uart_soc_terminal_YYYYMMDD.log
├─ uart_soc_board_record_YYYYMMDD.md
└─ README.md
```

记录文件至少包含：拍摄日期、板卡器件、Vivado 版本、bit 文件名与 SHA256、COM 号、串口参数、banner/回显/复位三项结果、视频文件名或外链。

## 7. 常见问题速查（新增异地项，其余见 ../../UART/doc/tasks.md §3.1）

| 现象 | 处理 |
|---|---|
| `get_hw_devices` 为空 / Hardware Manager 找不到板 | USB-JTAG 线未接或驱动（CP210x/FTDI）未装；换口重插；检查 D18 电源灯 |
| 终端无输出 | COM 号错 / 波特率错 / 未复位极性错误（§3 fallback） |
| 输出乱码 | 波特率不一致（必须 115200）或 USB-UART 与 JTAG 两线插反 |
| 发几个字符后停 | 终端开启了本地回显造成"双写"观感≠故障；确认 CPU 回显为唯一来源（关终端本地回显再验） |
| 首字符丢 | 上电瞬间 PC 复位释放即发 banner，属正常时序；重跑验证一致性即可 |
| 本机（原开发机）Vivado 2019.2 综合后器件加载空转 | 已知限制：换本方案任一步骤到健康主机执行即可（工程已全打包） |

## 8. 回传物与收尾

1. `soc_top.bit` 拷回开发机（本机 JTAG 与 COM8 可用时也可继续编程/验收）；
2. 证据文件（终端日志/记录/波形/视频）归入仓库外存档或 `soc/doc/board_evidence/`；
3. 在 `../../UART/doc/tasks.md` U32 状态栏更新：bit 产出（机器/日期）、终端验收三项、视频链接；
4. 若极性或引脚实测与约定不符 → 先改契约文档（`soc/xdc/board.xdc` 头注 / `../../UART/doc/interface.md`）再改实现，禁止单侧改。

## 9. 变更记录

- v1.2 2026-09-07：固件构建脚本保留口径（`UART/src/scripts/build_fw.ps1`）；§1.4 补脚本调用与 .vh 补零（`-PadBytes 512`）→ `imem_init.vh` 复制步骤。
- v1.3 2026-09-15：新增 §6 实验二 SoC 演示视频拍摄方案（拍前准备、10 镜头脚本、三项验收细节、异常处理与证据归档），并明确与实验一视频分开提交。
- v1.1 2026-09-07：随 SoC 上移 `soc/`（本文件随迁）：全部路径改 `soc/` 与 `../exp2/`；构建/烧录/取证脚本已删——§1 改无脚本手动工程步骤、§2 批处理改 Tcl Console 逐条、§4.4 取证改手动等价。
- v1.0 2026-09-06：初版（异地设备完整执行方案）。
