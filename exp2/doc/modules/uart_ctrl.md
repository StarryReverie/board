# uart_ctrl 模块文档（MMIO 从机：寄存器/位义/收发装配）

- 位置：`rtl/uart_ctrl.v`。UART IP 的**寄存器化从机封装**：接 core 穿出的 mmio 总线（interface.md §1），内部例化 `uart_tx`/`uart_rx` 与寄存器/位义逻辑。访问即普通 `lw`(in/r)/`sw`(out/w)。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效（core 语义） |
| in | cs_mmio | 1 | MMIO 窗口命中（=1 时本槽位有效） |
| in | reg_off | 2 | 00=TX 01=STAT 10=RX 11=保留 |
| in | we | 1 | 写使能（sw） |
| in | wdata | 32 | 写数据 |
| out | rdata | 32 | 组合读回（无命中/保留槽=0） |
| out | uart_tx_pin | 1 | → soc_top → T4 |
| in | uart_rx_pin | 1 | ← soc_top ← N5（内部打两拍） |

## 寄存器与位义（定稿，interface.md §3）
| reg_off | 槽 | 写（sw=out/w） | 读（lw=in/r） |
|---|---|---|---|
| 00 | TX | `wdata[7:0]`；`tx_busy=0` 时锁存并给 start（1 拍）；忙时丢弃 | 0 |
| 01 | STAT | 无操作 | `{30'b0, RX_VALID, TX_BUSY}`（bit0=TX_BUSY、bit1=RX_VALID） |
| 10 | RX | 无操作 | `{24'b0, rxd[7:0]}`；读后清 RX_VALID（访存段末沿） |

## 时序/语义（interface.md §2 硬约束）
- 写与读均在访存段一拍完成：**写=访存段末沿锁存**（触发发送/清 RX_VALID），**读=组合**（拍内稳定）；
- `TX_BUSY`：start 接受沿置 1，uart_tx done 时清 0；
- `RX_VALID`：uart_rx valid 置 1；**无 FIFO**：RX_VALID=1 期间新到字节丢弃；读 RX 槽后末沿清位；
- 单周期、无 wait、读无副作用（读 RX 清位为显式寄存器动作）。

## 连接
- mmio 总线 ← core（dbus_decode 穿出）；`uart_tx/rx` 例化于内部；串行引脚经 soc_top 引出。

## 验收（U12/U30）
- TX 空闲写→1 拍 start→busy=1→done 清 busy；忙时写丢弃；STAT 位义全对；读 RX 返回字节并清 RX_VALID；保留槽/未命中读 0、写无操作。
