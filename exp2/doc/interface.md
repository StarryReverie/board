# CPU ↔ 外设接口冻结契约（汇编实验视角）

- 版本：v1.1（2026-09-06：TX_BUSY 位义修正——STAT bit0=1 含挂起待发与移位中，对齐 uart_ctrl 实现；挂起期写亦丢弃）。
- 单源声明：本文件是汇编实验一侧的**阅读视图**；跨课程权威文本为计组 `../../doc/isa.md`（v1.3，MMIO 映射）、`../../doc/top_design.md`（v1.4，§9.2/§9.4/§9.5）、`../../doc/modules/dbus_decode.md` 与 `../../doc/modules/pipeline_top.md`。两侧不一致时以计组单源为准并先改契约，禁止单侧改接口。
- 职责归属：core 主端口/时序=计组；`dbus_decode` 代码=本实验交付（例化于 core MEM 段）；`uart_ctrl` 及其后=本实验；地址分配表=双方共管。

---

## 1. 总线信号（core ↔ 外设，实验二 build）

| 方向 | 信号 | 位宽 | 来源/去向 | 说明 |
|---|---|---|---|---|
| out | `cs_mmio` | 1 | dbus_decode 命中 MMIO 窗口 | 窗口=1 |
| out | `reg_off` | 2 | dbus_decode | 00=TX 01=STAT 10=RX 11=保留 |
| out | `mmio_we` | 1 | =`we & cs_mmio`（exmem_mem_write） | 1=sw 写槽 |
| out | `mmio_wdata` | 32 | =exmem_wdata | 写数据（低 8 位有效位义见 §3） |
| in | `mmio_rdata` | 32 | uart_ctrl → rdata mux | 组合读回，未命中应稳定为 0 |

> 实验一 build：以上端口悬空/接 0（H1–H5 不受影响）。core 内部 MEM 段数据通路：`ex_mem → dbus_decode → mem_wb`（rdata=`cs_dmem?dmem_rdata : (cs_mmio? mmio_rdata : 0)`）。

## 2. 时序规则（硬约束，从机不得违反）

1. **读**：`lw` 访存拍内从机给出**组合读数据**（沿前稳定），mem_wb 在该拍末沿捕获；从机读必须**无副作用**（读 STAT/RX 除"读 RX 清 RX_VALID"这一显式定义的寄存器动作外，不改变状态）；
2. **写**：`sw` 在**访存段末沿**锁存（与 dmem 同步写同沿）——uart_ctrl 的寄存器更新、TX 触发、RX_VALID 清除均以该沿为准；
3. **无等待**：总线固定 1 拍完成、ready 恒 1、从机不得反压/插入 wait（CPU 无总线停顿机制）；
4. **对齐/端序**：字访问 4 对齐、小端；槽内仅低 8 位有语义；
5. 与 hazard 无关：load-use/前递按 rd 判定，不关心命中 RAM 还是外设（计组口径）。

## 3. 地址映射与寄存器位义（程序可见，冻结）

| 地址 | 方向语义 | 寄存器 | 位义 |
|---|---|---|---|
| `0x0000_0000`–`0x0000_0FFF` | lw/sw | dmem | 数据 RAM 4KB（仿真/契约默认；**下板 build 缩容 256B**，见 `../../src/defines/const_define.v` 头注） |
| `0x0000_4000` | **sw = out/w** | TX | 写低 8 位=待发字节；TX_BUSY=0（完全空闲）时接受并触发发送，接受后 TX_BUSY 即置 1（含挂起）直至帧完；期间写丢弃；`lw` 读=0 |
| `0x0000_4004` | **lw = in/r** | STAT | bit0=TX_BUSY（1=发送忙：挂起待发或移位中）、bit1=RX_VALID（1=有未读字节）；写无操作 |
| `0x0000_4008` | **lw = in/r** | RX | 读低 8 位=收到字节；读后清 RX_VALID（访存段末沿）；写无操作 |
| 其余 | — | — | 读 0、写丢弃（无定义但无害） |

- I/O 编址口径（方案 B）：**统一编址、不加 in/out 指令**；读/写方向由 `lw`(in/r)/`sw`(out/w) 天然区分；
- 无 FIFO：RX_VALID=1 期间到达的新字节丢弃；TX 忙时写入丢弃；
- 软件必须**先轮询再操作**（程序查询方式）。

## 4. 复位与时钟边界

- `rst` 异步高有效（core 语义），由板上 `rst_n` 经 reset_sync（异步置位/同步释放）产生；
- 单时钟域 `clk`（100 MHz）；波特率由 `clk_en` 分频脉冲给出（uart 模块内参数化 CLKS_PER_BIT，仿真可覆盖）。

## 5. 变更记录

- v1.1 2026-09-06：TX_BUSY 位义修正（STAT bit0=1 含挂起待发与移位中；写接受仅限完全空闲，挂起期写丢弃）——修复连续 putc 在"挂起窗口"丢字隐患，同步 uart_ctrl.v / isa v1.4 / top_design v1.5。
- v1.0 2026-09-04：冻结（同步 isa v1.3 / top_design v1.4 / dbus_decode 定稿：全双工 TX/STAT/RX 槽、0x4000 窗口、方案 B）。
