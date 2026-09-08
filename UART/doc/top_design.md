# UART 控制器 IP 顶层设计（汇编实验二 · 交付物）

- 版本：v1.2（2026-09-07：**结构合并**——原 `uart_ctrl` 寄存器层并入 IP 顶层 `uart_ip_top`（单模块 UART IP，功能/契约零改动）；SoC 上移为整个项目的顶层 `../soc/`；构建脚本删除）。
- 本文件是实验二**交付物 IP 的设计文档**：`uart_ip_top`（IP 顶层，寄存器层已并入）＋ `uart_tx`/`uart_rx`（收发基础模块）。跨课程接口契约（从机总线、槽位义、时序硬约束）见 `interface.md`；模块细节见 `modules/*.md`。

---

## 1. IP 结构与封装层次

```
 uart_ip_top（IP 顶层，对外唯一接口 = 通用从机总线 + 串行引脚）
 │
 ├─ 译码：addr[3:2] → 槽（00=TX 01=STAT 10=RX 11=保留）     ← IP 自含
 │
 ├─ 寄存器层（clk_en 分频 + TX 挂起/缓冲 + RX 字节/有效 + 槽位义，原 uart_ctrl 并入）
 │
 ├─ uart_tx（8N1 发送 FSM）
 └─ uart_rx（位中心采样接收 FSM，输入打两拍）
```

- 职责：`uart_tx`/`uart_rx`=位级收发；寄存器层=分频/寄存器/位义/丢弃策略；`uart_ip_top`=寄存器映射译码 + 对外接口收敛（一体例化，单模块交付）；
- **独立性**：IP 只按 `cs/addr/we/wdata` 工作并给出 `rdata`，不感知宿主 CPU、不感知窗口基址——窗口基址与 dmem 选路是系统级契约（soc 集成层 dbus_decode），任何总线主机均可直挂本 IP。

## 2. 从机接口（IP 视角，与 interface.md §1 的适配关系）

| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | cs | 1 | 窗口命中（系统侧译码提供） |
| in | addr | 4 | 窗口内字节偏移：0x0=TX 0x4=STAT 0x8=RX（IP 自译槽） |
| in | we / wdata | 1 / 32 | 写（sw=out/w）；wdata 低 8 位有效 |
| out | rdata | 32 | 组合读回（lw=in/r）；cs=0/保留槽=0 |
| out / in | uart_tx_pin / uart_rx_pin | 1 | 8N1 串行侧 |

- 与冻结契约的适配：SoC 内 core 穿出的 `cs_mmio/reg_off[1:0]` 以 `cs=cs_mmio、addr={reg_off,2'b00}` 接入（见 `../soc/doc/top_design.md` §1）；**core 侧端口零改动**。

## 3. 寄存器映射与位义（定稿，interface.md §3）

| addr | 槽 | 写（sw=out/w） | 读（lw=in/r） |
|---|---|---|---|
| 0x0 | TX | `wdata[7:0]`；完全空闲时接受并触发发送，接受后 TX_BUSY 即 1（含挂起）直至帧完；挂起/忙时写丢弃 | 0 |
| 0x4 | STAT | 无操作 | `{30'b0, RX_VALID, TX_BUSY}`（bit0=TX_BUSY=挂起或移位中、bit1=RX_VALID） |
| 0x8 | RX | 无操作 | `{24'b0, rxd[7:0]}`；读后清 RX_VALID（末沿） |

- 无 FIFO：RX_VALID=1 期间新到字节丢弃；软件先轮询再操作（程序查询方式）。

## 4. 时钟与复位

- 单时钟域 `clk`；波特率由 clk_en 分频脉冲给出（`CLKS_PER_BIT` 参数，115200@100MHz=868，仿真可覆盖）；
- `rst` 异步高有效（对齐宿主机 core 语义）。

## 5. 验收（4 项 TB 独立回归）

| TB | 覆盖 | 口径 |
|---|---|---|
| tb_uart_tx | 8N1 帧/忙时忽略/done 脉冲 | U10 |
| tb_uart_rx | 位中心采样/停止位校验/连续字节 | U11 |
| tb_uart_ctrl | 槽位义/挂起丢弃/读清位/溢出丢弃（寄存器层单测，经 IP 顶层例化） | U12 |
| tb_uart_ip_top | **IP 级独立测试**：帧级逐位、STAT 位义、忙写丢弃、全双工同现 | U15 |

## 6. 变更记录

- v1.2 2026-09-07：结构合并——原 uart_ctrl 寄存器层并入 IP 顶层 uart_ip_top（单模块 UART IP：分频/TX 挂起/RX 寄存器/组合读一体例化，删 `src/rtl/uart_ctrl.v` 与 modules/uart_ctrl.md；端口/时序/位义零改动）；tb_uart_ctrl.v 改经 IP 顶层例化，tb_uart_ip_top.v 层次路径调整。
- v1.1 2026-09-07：实验二交付物收敛为独立 UART IP——新增 IP 顶层（uart_ip_top）与 IP 级独立测试（tb_uart_ip_top）；SoC 装配内容随迁 `../soc/doc/top_design.md`；构建脚本删除（重建见 `../soc/doc/board_runbook.md`）。
- v1.0 2026-09-04：初版（UART 集成整机口径，已随迁 soc/）。
