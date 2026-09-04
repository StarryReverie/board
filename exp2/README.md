# exp2 — 汇编与接口课程设计代码（实验二：UART SoC）

存放汇编与接口课程设计的全部代码与工程文件。**设计文档在本目录 `doc/`**（tasks/top_design/interface/firmware/ref_note/future_extensions/modules，仿 board/doc 体系）；根目录原 `汇编实验设计方案.md`（v1.0/v1.1）内容已全部并入 `doc/` 后删除（2026-09-04）。跨课程架构口径以 `../doc/top_design.md` v1.4、`../doc/isa.md` v1.3、`../doc/tasks.md` §6 为准。

## 建议目录结构（随实现补充）

```text
exp2/
 ├─ doc/         本课程设计文档（仿 board/doc 体系）
 │   ├─ require                  任务书节选
 │   ├─ tasks.md                 任务分解/验收/里程碑/分工（U10–U41）
 │   ├─ top_design.md            SoC 顶层设计（soc_top 装配/引脚/复位）
 │   ├─ interface.md             CPU↔外设接口冻结契约（汇编侧视图）
 │   ├─ ref_note.md              计组 core 口径 + EES-338 板卡速查
 │   ├─ future_extensions.md     暂缓扩展登记（FIFO/中断/ILA/…）
 │   └─ modules/                 uart_tx / uart_rx / uart_ctrl /
 │                               soc_top(reset_sync) / dbus_decode
 ├─ rtl/        UART IP 与 SoC 装配：uart_tx.v、uart_rx.v、uart_ctrl.v、
 │              reset_sync.v、soc_top.v、dbus_decode.v（CPU core 在计组 `rtl/`，按计组布局）
 ├─ tb/         单元与系统 TB：uart_tx_tb、uart_rx_tb、uart_ctrl_tb、tb_soc_top
 ├─ asm/        汇编固件与机器码：console(banner+回显)、*.hex/*.vh（verify_hex.py 校验）
 └─ xdc/        EES-338 约束：T5(clk 100MHz)/T4(uart_tx)/N5(uart_rx)/P15(rst_n)
```

## 设计要点（定稿 v1.1）

- UART **全双工** 8N1@115200（100 MHz 分频 868）；MMIO 窗口 `0x0000_4000`：TX/STAT/RX 字槽；
- I/O 统一编址（方案 B）：`lw`=读（in/r）、`sw`=写（out/w），不加指令；
- 程序固化单程序模型：固件 .vh 固化、上电自跑；无 loader/在线重载；
- 软件程序查询（轮询 TX_BUSY/RX_VALID）；dmem 不复位 → 数据区启动自初始化。
