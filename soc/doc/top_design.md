# SoC 顶层设计（整个项目的顶层：UART 集成整机，两课共建）

- 版本：v1.1（2026-09-07：SoC 上移为项目顶层 `soc/`——实验二交付物收敛为 UART IP（`../../UART/`），本目录=SoC 集成层（rtl/xdc/test/doc）；从机改经 `uart_ip_top`（IP 顶层，自含槽译码）接入，soc_top 内把 core 穿出的 `reg_off[1:0]` 适配为 `addr[3:0]={reg_off,2'b00}`；UART 侧构建脚本随结构调整删除）。
- 总体入口：本目录文档体系（top_design/board_runbook/firmware/machine_code/modules）；课程任务清单在 `../../UART/doc/tasks.md`（SoC 集成区 U13/U14/U31–U41）；跨课程接口契约见 `../../UART/doc/interface.md`，其单源为计组 `../../pipeline/doc/isa.md` / `../../pipeline/doc/top_design.md` / `../../pipeline/doc/modules/dbus_decode.md`。本设计建立于计组交付的 CPU core（`../../pipeline/doc/top_design.md` §1–§8）与实验二交付的 UART IP（`../../UART/doc/top_design.md`）之上。
- 布局：SoC 集成代码在本目录（RTL `rtl/`、TB/固件 `test/`、约束 `xdc/`）；UART IP 在 `../../UART/src/rtl/`；CPU core 在 `../../pipeline/src/rtl/`；工程构建脚本已删（重建见 board_runbook.md §1；固件构建脚本保留 `UART/src/scripts/build_fw.ps1`，见 firmware.md §6）。

---

## 1. 系统结构（soc_top 装配总图）

```
 EES-338 板（XC7A35T-1CSG324C，100 MHz @ T5）
 ┌──────────────────────────────────────────────────────────────┐
 │ soc_top                                                       │
 │  ├─ reset_sync：rst_n(P15) ─(异步置位/同步释放)─► rst(异步高有效) │
 │  ├─ pipeline_top（计组 core，§2；dbus_decode 内置于 MEM 段）    │
 │  │    IF : pc_reg ─► imem（.vh 固化程序，上电自跑 0x0）          │
 │  │    MEM: ex_mem ─► dbus_decode ─┬─► dmem（0x0–0xFFF）        │
 │  │                                └─► MMIO 窗口 0x4000          │
 │  │       mmio 总线穿出：cs_mmio/reg_off/mmio_we/mmio_wdata ──►  │
 │  └─ uart_ip_top（UART 控制器 IP 顶层，全双工）◄───────────────┘│
 │        mmio_rdata ──►（core 内 rdata mux）                       │
 │        uart_tx ──► T4 ──► CP2102 ──► PC COM                     │
 │        uart_rx ◄── N5 ◄── CP2102 ◄── PC 键盘                     │
 └──────────────────────────────────────────────────────────────┘
```

- 平级实例：`pipeline_top`（core，含数据侧译码）、`uart_ip_top`（实验二 UART IP 顶层）、`reset_sync`；无 loader（程序固化模型）。
- 总线适配：core 穿出 `cs_mmio/reg_off[1:0]`（interface.md §1 冻结契约），soc_top 内接 IP 的 `cs/addr[3:0]`：`addr={reg_off,2'b00}`——槽译码在 IP 内部自含（TX=0x0/STAT=0x4/RX=0x8）。
- 数据流：`sw` 写 TX 槽发送；`lw` 读 STAT/RX 槽轮询/接收；UART 位时序由 uart_tx/uart_rx 状态机消化，CPU 访存每拍完成、永不等待。

## 2. 模块清单（归属 ↔ 文档）

| 归属 | 模块 | 角色 | 模块文档 |
|---|---|---|---|
| 计组交付 | `pipeline_top`（含 `imem/dmem/dbus_decode` 装配） | CPU core（§1–§8 口径）+ 数据侧译码（实验二 build） | `../../pipeline/doc/modules/pipeline_top.md`、`../../pipeline/doc/modules/dbus_decode.md` |
| 实验二交付 | `uart_ip_top`（寄存器层已并入，内例化 `uart_tx`/`uart_rx`） | UART 控制器 IP 顶层（从机总线+串行） | `../../UART/doc/modules/uart_ip_top.md`（+ uart_tx/uart_rx 各模块文档） |
| 本目录（SoC 集成） | `dbus_decode` | 数据侧译码（例化于 core MEM 段） | modules/dbus_decode.md |
| 本目录（SoC 集成） | `reset_sync` / `soc_top` | 复位同步 / 整机装配 | modules/soc_top.md |

> `dbus_decode` 代码在本目录 `rtl/dbus_decode.v`，例化位置在 core 的 MEM 段（实验二 build）；契约单源=计组文档，见 `../../UART/doc/interface.md`。

## 3. 时钟与复位

- 单时钟域 `clk`：板载 100 MHz 晶振 → **T5**；uart 波特率用 `clk_en` 分频脉冲（无第二时钟域、无异步跨域）；
- 复位链：板上按键 `rst_n`（低有效，P15；极性以 demo XDC 为准）→ `reset_sync`（两级同步器：异步置位、同步释放）→ `rst`（**异步高有效**，对齐 core 语义）→ core/uart_ip_top；
- 复位=程序从头重跑：imem 内容不变（.vh 固化）；**dmem 不复位** → 固件启动须自初始化数据区。

## 4. 引脚与板级（EES-338，XDC 定稿）

| 信号 | 原理图网络名 | FPGA PIN | 说明 |
|---|---|---|---|
| clk | SYS_CLK | T5 | 100 MHz |
| uart_tx（FPGA→CP2102） | UART_RX | T4 | CP2102 25 脚；网络名以 CP2102 视角命名，方向以 FPGA 为准 |
| uart_rx（CP2102→FPGA） | UART_TX | N5 | CP2102 26 脚 |
| rst_n | FPGA_RESET | P15 | 复位键 S8/S6 |
| LED（可选） | — | 按 demo XDC | 运行/状态指示 |

- IO 标准通常 LVCMOS33（以厂家 demo XDC 为准）；uart_rx 输入在 uart_ip_top 内打两拍防亚稳态；
- PC 侧：插入 CP2102 口后设备管理器出现 "Silicon Labs CP210x USB to UART Bridge"+COMx；终端 115200-8-N-1 无流控。

## 5. 访存总线与 MMIO 契约（摘要）

- 详细冻结契约见 `../../UART/doc/interface.md`（与计组 isa.md v1.3 / dbus_decode.md 一致），摘要：
  - core 穿出：`cs_mmio/reg_off[1:0]/mmio_we/mmio_wdata[31:0]`（→ uart_ip_top，soc_top 内适配 `addr={reg_off,2'b00}`），读回 `mmio_rdata[31:0]`（→ rdata mux）；
  - 读=组合（MEM 拍内稳定，mem_wb 末沿捕获）；写=访存段末沿（与 dmem 同步写同沿）；单周期、**无 wait**；未命中读 0/写丢弃；
  - 槽：`0x4000` TX（sw 写=发送，忙丢弃；读=0）、`0x4004` STAT（读 bit0=TX_BUSY、bit1=RX_VALID）、`0x4008` RX（读=字节并清 RX_VALID）；
  - 方向语义：`lw`=in/r、`sw`=out/w（方案 B，不加指令）。

## 6. 程序与固件模型

- imem `.vh` 固化（verify_hex.py 生成/校验），上电复位 PC=0 直接执行；换程序=重生成 .vh→综合→重烧 .bit（JTAG/SPI-Flash）；
- 固定固件 console：banner（轮询 TX_BUSY 逐字符）→ 回显循环（轮询 RX_VALID→读 RX→回发）；无 reload 命令；
- 字符串：做法一=启动时 lui+addi 构造字（字内低 8 位一字符）sw 自初始化进 dmem，发送逐字 lw 拆字符；做法二=逐字符 addi 立即数（实现二选一，固件任务定稿）。

## 7. 验收

- 仿真（U31）：行为级串口模型双向回环；banner 字节序列、回显往返、复位重跑断言 PASS；
- 下板（U32）：终端见 banner、键盘回显、复位重跑；波形/日志留档；≤5min 视频；
- 门禁：UART IP 单测与 IP 级测试（U30/U15：uart_tx/uart_rx/uart_ip_top 含寄存器层单测）全绿后进入系统级；计组 core M1–M3 全绿后联调。

## 8. 变更记录

- v1.2 2026-09-07：uart_ctrl 寄存器层并入 uart_ip_top（§2/§3/§7 称谓同步；SoC 例化接口不变）。
- v1.1 2026-09-07：SoC 上移为项目顶层 `soc/`（本文件随迁自 exp2/doc/）：实验二交付物收敛为 UART IP（`../exp2/`），从机改经 `uart_ip_top` 接入（addr 适配）；exp2 侧构建脚本删除（重建见 board_runbook.md）。
- v1.0 2026-09-04：初版（对齐计组 top_design v1.4 与 `../汇编实验设计方案.md` v1.1 定稿口径）。
