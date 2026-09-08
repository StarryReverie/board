# uart_ip_top 模块文档（UART 控制器 IP 顶层——实验二交付物）

- 位置：`src/rtl/uart_ip_top.v`。实验二**最终成果**：独立可复用的 UART 控制器 IP Core 顶层。寄存器层（clk_en 分频 + TX 挂起/缓冲 + RX 字节/有效位 + 槽位义，原独立 `uart_ctrl` 模块已并入本文件）与 `uart_tx`/`uart_rx` 收发引擎一体例化于此；对外只暴露**一条通用从机总线 + 串行引脚**，无任何宿主 CPU 依赖。
- 设计：`doc/top_design.md`（IP 顶层设计）；寄存器位义/时序契约：`doc/interface.md` §3（与计组 isa.md §4 一致）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效 |
| in | cs | 1 | 窗口命中（由**系统侧**译码提供；=0 时读 0、写丢弃） |
| in | addr | 4 | 窗口内字节偏移（**IP 自含译码**）：0x0=TX 0x4=STAT 0x8=RX 0xC=保留 |
| in | we | 1 | 写使能（sw=out/w） |
| in | wdata | 32 | 写数据（低 8 位有效） |
| out | rdata | 32 | 组合读回（cs=0/保留槽=0） |
| out | uart_tx_pin | 1 | UART 发送（8N1，空闲高） |
| in | uart_rx_pin | 1 | UART 接收（内部打两拍防亚稳态） |

## 寄存器映射译码（IP 自含）
- `reg_off = addr[3:2]`：00=TX 01=STAT 10=RX 11=保留（未命中读 0、写丢弃）；
- 窗口基址（0x0000_4000）与 dmem 低区选路是**系统级**契约（dbus_decode，soc 集成层），不在 IP 内——IP 只按 cs+addr 工作，可挂接任何提供 cs/addr/we/wdata 的总线。

## 寄存器与位义（定稿，interface.md §3）
| reg_off | 槽 | 写（sw=out/w） | 读（lw=in/r） |
|---|---|---|---|
| 00 | TX | `wdata[7:0]`；完全空闲（无挂起、非移位忙）时锁存并置 pend（遇 bit_tick 启动发送）；挂起/忙期间写丢弃 | 0 |
| 01 | STAT | 无操作 | `{30'b0, RX_VALID, TX_BUSY}`（bit0=TX_BUSY=挂起或移位中、bit1=RX_VALID） |
| 10 | RX | 无操作 | `{24'b0, rxd[7:0]}`；读后清 RX_VALID（访存段末沿） |

## 时序/语义（interface.md §2 硬约束）
- 读=组合（拍内稳定）、写=末沿锁存、单周期无 wait、读无副作用（读 RX 清位为显式寄存器动作）；
- `TX_BUSY`（STAT bit0）= **挂起待发或移位中**：写接受沿置 1（pend），uart_tx done 后清 0；写接受仅限完全空闲，挂起/移位期写丢弃——软件"busy=0 才写"轮询无丢字窗口；
- `RX_VALID`：uart_rx valid 置 1；**无 FIFO**：RX_VALID=1 期间新到字节丢弃；读 RX 槽后末沿清位；
- 全双工：uart_tx 与 uart_rx 两路独立，收发可同帧并行；收发共用同一 clk_en 分频节拍。

## 连接
- SoC 集成：`soc/rtl/soc_top.v` 例化本模块——core 穿出的 `cs_mmio/reg_off[1:0]` 经 `{reg_off,2'b00}` 适配为 `addr[3:0]`；
- 独立使用：任何总线主机按上表端口直连即可（集成说明见 SUBMISSION.md IP 打包项）。

## 验收（U12/U15）
- `src/test/tb_uart_ctrl.v`（U12 寄存器层单测，经本 IP 顶层例化）：默认槽读 0；写 TX 触发发送（STAT.TX_BUSY 翻转）；忙时写丢弃；RX 收字节（STAT.RX_VALID）→ 读槽取字节 → 读后清位；未读期间新字节丢弃（保留首字节）；写 STAT/RX 无操作。
- `src/test/tb_uart_ip_top.v`（U15 IP 级独立测试，CLKS_PER_BIT=4，无 CPU 依赖）：默认态读 0/cs=0 读 0/空闲高；TX 帧逐位（start=0、LSB 先、stop=1）；STAT 位义（busy 含挂起）；忙写丢弃无第二帧；RX 收字节/读清位；溢出丢弃保留首字节；写 STAT/RX 无操作；全双工 TX_BUSY 与 RX_VALID 同现且两路结果正确。

## 变更记录
- v1.1 2026-09-07：结构合并——原独立 `uart_ctrl` 寄存器层并入本模块（分频/TX 挂起/RX 寄存器/组合读一体例化），删除 `src/rtl/uart_ctrl.v` 与 modules/uart_ctrl.md；端口/时序/位义零改动（功能不变）；tb_uart_ctrl.v 改经本 IP 顶层例化（检查点不变），tb_uart_ip_top.v 层次路径随深度减一层调整（dut.u_ctrl.*→dut.*）。
- v1.0 2026-09-07：初版（实验二交付物收敛为独立 UART IP：新增本顶层；uart_ctrl/uart_tx/uart_rx 为零改动内部层；SoC 上移为项目顶层 soc/）。
