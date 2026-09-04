# uart_rx 模块文档（8N1 接收器）

- 位置：`rtl/uart_rx.v`。UART 接收采样 FSM：检测起始位下降沿，按 `clk_en` 节拍在位中心采样 8 数据位 + 停止位校验，输出字节与 valid 脉冲。
- 上游：板级引脚（经 soc_top ← N5，内部先打两拍防亚稳态）；下游：`uart_ctrl`（rx_data/valid）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效 |
| in | clk_en | 1 | bit 节拍脉冲（与 uart_tx 同参） |
| in | rx | 1 | 串行输入（内部打两拍后使用） |
| out | valid | 1 | 完整字节接收完成脉冲（停止位正确时 1 拍） |
| out | data | 8 | 收到的字节（LSB 先组装） |

## 功能/状态机
```
IDLE ──rx 下降沿──► START(起始位确认/半位点复检) ──► DATA(bit_index 0..7，位中心采样) ──► STOP(校验)
IDLE: 等下降沿，启动计数；DATA: 每 CLKS_PER_BIT 拍采样 rx 一次，取中点为该位值；
STOP: 采样停止位——为 1：valid=1、输出 data；为 0（帧错误）：丢弃本字节、不置 valid
完成后回 IDLE 继续等下一帧
```
- 采样时刻：起始位下降沿确认后，以位中心为采样点（计数器到 CLKS_PER_BIT/2 采样）；
- 帧错误处理：基础版丢弃不置位（无错误寄存器，报告说明）；溢出（RX_VALID 未清又收完一字节）由 uart_ctrl 层丢弃新字节。

## 连接
- ← soc_top（rx，两拍同步后）；→ uart_ctrl（valid/data）。

## 验收（U11）
- TB 按 8N1 波形驱动：起始位检测、逐位（LSB 先）正确、停止位=1 出 valid；停止位=0 帧错误丢弃；连续多字节无丢；每位宽偏移 ±少量时钟仍正确（位中心容差）。
