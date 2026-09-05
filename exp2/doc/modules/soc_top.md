# soc_top / reset_sync 模块文档（整机装配与复位同步）

- 位置：`src/rtl/soc_top.v`（最顶层）、`rtl/reset_sync.v`。soc_top 例化计组 core（pipeline_top，实验二 build）＋ uart_ctrl ＋ reset_sync，引出板级引脚。程序固化模型：无 loader。
- 上游：无（顶层）；下游：板级（XDC）。

## soc_top 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 板载 100 MHz（XDC → T5） |
| in | rst_n | 1 | 板上复位键（低有效；XDC → P15，极性以 demo XDC 为准） |
| out | uart_tx_pin | 1 | UART 发送（XDC → T4） |
| in | uart_rx_pin | 1 | UART 接收（XDC → N5） |
| out | led（可选） | 1..n | 运行/状态指示（按 demo XDC） |

## reset_sync（内部实例）
- 两级同步器：`rst_n`（低有效）→ 异步置位、同步释放 → `rst`（**异步高有效**，对齐 core/uart_ctrl 语义）；
- 复位=程序从头重跑：imem 内容不变（.vh 固化）；dmem 不清 → 固件自初始化数据区。

## 内部例化
```
pipeline_top（计组 core，实验二 build：MEM 段含 dbus_decode）
   ├─ cs_mmio/reg_off/mmio_we/mmio_wdata ──► uart_ctrl
   └─ mmio_rdata ◄── uart_ctrl（组合读回）
uart_ctrl ── uart_tx_pin / ◄── uart_rx_pin
```

## 时钟
- 单时钟域 `clk`（100 MHz）；波特率 clk_en 分频（uart_ctrl 内）；uart_rx 输入打两拍防亚稳态。

## 验收（U14/U32）
- 例化/互联与 top_design.md §1/§2 一致；无悬空/多重驱动；Vivado 综合/实现/时序通过；上板：终端见 banner、键盘回显、复位重跑。
