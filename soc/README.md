# soc — 整个项目的顶层（SoC 集成，两课共建）

本目录是把**计组实验一**（RV32I 5 级流水线 CPU core，`../pipeline/src/`）与**汇编实验二**（UART 控制器 IP，`../UART/`）集成为自定义计算机系统的**项目级顶层**——不属于任何单一课程的交付物，是两门课设的共建集成层。

## 目录结构

```text
soc/
 ├─ rtl/    SoC 集成 RTL：soc_top.v（最顶层）、reset_sync.v（复位同步）、
 │          dbus_decode.v（数据侧译码，例化于 core MEM 段）
 ├─ xdc/    EES-338 板级约束 board.xdc（T5 clk / T4 uart_tx / N5 uart_rx / P15 rst_n）
 ├─ test/   固件 console.S → console_rom.hex / console_init.vh（程序固化镜像）
 │          与系统级 TB：tb_soc_console / tb_soc_full / tb_pipe_soc /
 │          tb_reset_sync / tb_dbus_decode
 └─ doc/    SoC 顶层设计、下板方案（board_runbook）、固件与机器码说明、模块文档
```

依赖（引用不复制）：CPU core `../pipeline/src/rtl/`（pipeline_top 等）、UART IP `../UART/src/rtl/`（uart_ip_top）。

## 装配

`soc_top` = `reset_sync`（rst_n → 异步高有效 rst）+ `pipeline_top #(.SOC_BUILD(1))`（core，MEM 段含 dbus_decode）+ `uart_ip_top`（UART IP 顶层）。core 穿出的 mmio 总线（cs_mmio/reg_off）在 soc_top 内适配为 IP 的 cs/addr（`addr={reg_off,2'b00}`）。

## 文档入口

- 顶层设计：[doc/top_design.md](doc/top_design.md)
- 下板方案（出 bit/烧录/终端验收/取证）：[doc/board_runbook.md](doc/board_runbook.md)
- 固件软件：[doc/firmware.md](doc/firmware.md) ｜ 机器码说明：[doc/machine_code.md](doc/machine_code.md)
- 接口冻结契约（汇编侧视图）：[../UART/doc/interface.md](../UART/doc/interface.md)
- 课程任务（U13/U14/U31–U41）：[../UART/doc/tasks.md](../UART/doc/tasks.md)

> 2026-09-07：构建/烧录/取证脚本已随结构调整删除（原在 exp2/src/scripts/，git 历史可恢复）；无脚本建工程步骤见 board_runbook.md §1。
