# uart_tx 模块文档（8N1 发送器）

- 位置：`rtl/uart_tx.v`。UART 发送 FSM，把 1 字节转成 8N1 串行帧逐位移出；波特率由 `clk_en` 分频脉冲节拍（每拍=1 bit 时间）。
- 上游：`uart_ctrl`（start/data）；下游：板级引脚（经 soc_top → T4）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效 |
| in | clk_en | 1 | bit 节拍脉冲（=CLKS_PER_BIT 个 clk 一个，115200@100MHz=868） |
| in | start | 1 | 启动发送（须在空闲时给 1 拍） |
| in | data | 8 | 待发字节 |
| out | busy | 1 | 1=发送中（start 接受沿置位，停止位完清除） |
| out | done | 1 | 发送完成脉冲（1 拍） |
| out | tx | 1 | 串行输出：空闲/停止=1、起始=0、数据 LSB 先 |

## 功能/状态机
```
IDLE ──start && !busy──► START ──1 bit──► DATA ──bit_index 0..7──► STOP ──1 bit──► IDLE(done 1 拍)
IDLE : tx=1;  START: tx=0;  DATA: tx=data[bit_index];  STOP: tx=1
busy = (state != IDLE)
```
- 接受规则：仅 `start && !busy` 时锁存 data 并进入 START；busy 期间 start 忽略（不覆盖）；
- 参数：`CLKS_PER_BIT`（或 CLK_FREQ_HZ/BAUD_RATE 换算），仿真经 soc_top 参数覆盖加速。

## 连接
- ← uart_ctrl（start/data）；→ uart_ctrl（busy/done）、soc_top（tx）。

## 验收（U10）
- 复位 TX=1、busy=0；帧=1 起始+8 数据(LSB 先)+1 停止；每位宽=CLKS_PER_BIT；done 恰 1 拍；忙时 start 忽略；连发两字符间恢复空闲。
