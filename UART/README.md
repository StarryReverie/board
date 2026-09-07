# UART — 汇编与接口课程设计代码（实验二：UART 控制器 IP）

存放汇编与接口课程设计的**交付物——独立 UART 控制器 IP Core**（uart_ip_top 单模块：寄存器层已并入 + 内部层 uart_tx/uart_rx + 模块/IP 级测试）。**SoC 整机集成不属于实验二内容**：它是整个项目的顶层（两课共建），代码与文档在仓库根 [`../soc/`](../soc/)。设计文档在本目录 `doc/`（tasks/top_design/interface/ref_note/future_extensions/modules，仿 pipeline/doc 体系）；跨课程架构口径以 `../pipeline/doc/top_design.md`、`../pipeline/doc/isa.md`、`../pipeline/doc/tasks.md` §6 为准。

## 目录结构

```text
UART/
 ├─ doc/         IP 设计文档
 │   ├─ require                 任务书节选
 │   ├─ tasks.md                任务分解/验收/里程碑/分工（U10–U15 等）
 │   ├─ top_design.md           UART 控制器 IP 顶层设计（交付物设计）
 │   ├─ interface.md            CPU↔外设接口冻结契约（汇编侧视图，v1.2）
 │   ├─ ref_note.md             计组 core 口径 + EES-338 板卡速查
 │   ├─ future_extensions.md    暂缓扩展登记（FIFO/中断/ILA/…）
 │   └─ modules/                uart_ip_top（含寄存器层）/ uart_tx / uart_rx
 └─ src/        IP 代码（与计组 src/ 同规范；无脚本——已随 2026-09-07 结构调整删除）
     ├─ rtl/    UART 控制器 IP：uart_ip_top.v（IP 顶层，寄存器层已并入）、
     │          uart_tx.v、uart_rx.v（收发基础模块）
     └─ test/   TB：tb_uart_ip_top（IP 级独立测试）、tb_uart_ctrl（寄存器层单测，经 IP 顶层例化）、tb_uart_tx、tb_uart_rx
```

## SoC 集成（整个项目的顶层）

`soc_top`（`../soc/rtl/soc_top.v`）＝ 计组 core（`../pipeline/src/rtl/pipeline_top`，SOC_BUILD=1）＋ 本 IP（`uart_ip_top`）＋ 复位同步——core 穿出的 `cs_mmio/reg_off` 以 `addr={reg_off,2'b00}` 接入 IP。固件/XDC/系统级 TB/下板方案在 `../soc/`（`board_runbook.md` / `firmware.md` / `machine_code.md`）。

## 设计要点（定稿 v1.2）

- **独立 IP Core（实验二交付物）**：对外仅一条通用从机总线（cs/addr/we/wdata→rdata）+ 串行引脚（uart_tx_pin/uart_rx_pin），槽译码（addr[3:2]→TX/STAT/RX）IP 自含，无任何宿主 CPU 依赖；
- UART **全双工** 8N1@115200（100 MHz 分频 868，CLKS_PER_BIT 参数仿真可覆盖）；
- 寄存器位义（interface.md §3）：TX（sw 写=发送，忙丢弃）、STAT（bit0=TX_BUSY 含挂起、bit1=RX_VALID）、RX（lw 读=字节并清位）；无 FIFO、单周期无 wait；
- I/O 统一编址（方案 B）：`lw`=读（in/r）、`sw`=写（out/w），不加指令；
- 验证：4 项 TB（模块单测 ×3 + IP 级独立测试 ×1，含帧级逐位与全双工同现断言）。
