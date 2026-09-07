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
- 两级同步器：`rst_n`（低有效）→ 异步置位、同步释放 → `rst`（**异步高有效**，对齐 core/uart_ip_top 语义）；
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

## 验收（U14/U32，任务见 ../exp2/doc/tasks.md）
- 例化/互联与 top_design.md §1/§2 一致；无悬空/多重驱动；Vivado 综合/实现/时序通过；上板：终端见 banner、键盘回显、复位重跑。

## 变更记录
- v1.2 2026-09-07：uart_ctrl 寄存器层并入 uart_ip_top（复位/分频称谓同步；例化接口不变）。
- v1.1 2026-09-07：随 SoC 上移 `soc/`（本文件随迁）：位置改 `rtl/`；从机改 `uart_ip_top`（addr 适配）；XDC 位置 `xdc/`。
- v1.0 2026-09-04：初版。
