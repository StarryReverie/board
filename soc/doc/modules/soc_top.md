# soc_top / reset_sync 模块文档（整机装配与复位同步）

- 位置：`rtl/soc_top.v`（整个项目的顶层，本目录）、`rtl/reset_sync.v`。soc_top 例化计组 core（pipeline_top，实验二 build）＋ uart_ip_top（实验二 UART IP 顶层）＋ reset_sync，引出板级引脚。程序固化模型：无 loader。
- 上游：无（顶层）；下游：板级（XDC，`xdc/board.xdc`）。

## soc_top 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 板载 100 MHz（XDC → T5） |
| in | rst_n | 1 | 板上复位键（低有效；XDC → P15，极性以 demo XDC 为准） |
| out | uart_tx_pin | 1 | UART 发送（XDC → T4） |
| in | uart_rx_pin | 1 | UART 接收（XDC → N5） |
| out | led（可选） | 1..n | 运行/状态指示（按 demo XDC） |

## reset_sync（内部实例）
- 参数：`STAGES`（同步链级数，默认 2）、`STABLE_CYCLES`（**释放去抖**拍数，默认 0 = 不去抖）；
  `soc_top` 经 `RESET_STABLE_CYCLES` 传入 **20 ms @100 MHz**（= 2,000,000 拍）；
- 两级同步器：`rst_n`（低有效）→ **异步置位、同步释放** → `rst`（**异步高有效**，对齐 core/uart_ip_top 语义）；
- **释放去抖（2026-09-16 新增）**：机械按键松开瞬间抖动（0.1–5 ms）会让 core 在抖动窗口内反复置位/释放
  → 正在发送的 UART 帧被中途截断（`uart_tx` 的 `tx` 为组合输出）+ 分频节拍被清零错位
  → 终端出现"按 RESET 后 banner 前面一段乱码"。去抖要求 `rst_n` **连续稳定 20 ms** 才允许释放，
  **按下始终立即生效**；任何一次拉低都立即清零去抖计数。
  验证：`tb_reset_sync`（去抖单测：抖动被滤除）+ `tb_soc_console` **P5**（抖动式松开 → banner 逐字节干净）；
- **释放路径全同步化（v1.4，PR #13 review）**：异步级只有 1 个 `meta_q`（直接挂在 `rst_n` 上的唯一触发器，
  其释放沿的亚稳只被同步逻辑采样、在第 2 级被"消费"）；去抖计数器与释放链均为**纯同步**逻辑，
  不再把异步释放沿接进计数器的复位脚（否则 recovery/removal 可能让计数被采成非零值、提前满足
  `stable_ok`、吃掉去抖时长）。`rst` 输出 = 异步置位（`!rst_n`）+ 同步释放（`release_ok`）；
  **释放时序与 v1.3 逐拍一致**：`STABLE_CYCLES=0` → STAGES 拍释放；去抖 N → N+STAGES−1 拍释放。
  该结构在 `soc/rtl/reset_sync.v` 与 `pipeline/src/rtl/exp1_reset_sync.v` 中保持同构。
- 复位=程序从头重跑：imem 内容不变（.vh 固化）；dmem 不清 → 固件自初始化数据区。

## 内部例化
```
pipeline_top（计组 core，实验二 build：MEM 段含 dbus_decode）
   ├─ cs_mmio/reg_off[1:0]/mmio_we/mmio_wdata ──► uart_ip_top（cs/addr[3:0]/we/wdata）
   │     总线适配：addr = {reg_off, 2'b00}（槽译码在 IP 内部自含）
   └─ mmio_rdata ◄── uart_ip_top（组合读回）
uart_ip_top ── uart_tx_pin / ◄── uart_rx_pin
```

## 时钟
- 单时钟域 `clk`（100 MHz）；波特率 clk_en 分频（uart_ip_top 寄存器层内）；uart_rx 输入打两拍防亚稳态。

## 验收（U14/U32，任务见 ../../../UART/doc/tasks.md）
- 例化/互联与 top_design.md §1/§2 一致；无悬空/多重驱动；Vivado 综合/实现/时序通过；上板：终端见 banner、键盘回显、复位重跑。

## 变更记录
- v1.4 2026-09-16：`reset_sync` **释放路径全同步化**（异步级仅 `meta_q`，去抖计数与释放链纯同步；释放时序与 v1.3 逐拍一致，`tb_reset_sync` 原断言不改仍 PASS）；见"reset_sync 内部实例"小节。
- v1.3 2026-09-16：`reset_sync` 增加**释放去抖**（`STABLE_CYCLES`，soc_top 默认 20 ms）；修复"按 RESET 后 banner 乱码前缀"；配套 `tb_reset_sync` 去抖单测与 `tb_soc_console` P5。
- v1.2 2026-09-07：uart_ctrl 寄存器层并入 uart_ip_top（复位/分频称谓同步；例化接口不变）。
- v1.1 2026-09-07：随 SoC 上移 `soc/`（本文件随迁）：位置改 `rtl/`；从机改 `uart_ip_top`（addr 适配）；XDC 位置 `xdc/`。
- v1.0 2026-09-04：初版。
