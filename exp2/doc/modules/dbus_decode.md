# dbus_decode 模块文档（数据侧译码——本目录交付指引）

- 代码交付位置：`../rtl/dbus_decode.v`（**本实验交付**，成员 2）；例化位置：计组 `pipeline_top` 的 MEM 段（实验二 build，`ex_mem` 与 `mem_wb` 之间）。
- **契约单源**：`../../doc/modules/dbus_decode.md`（计组侧，含端口/地址分区/时序/验收全文）+ `../../doc/isa.md` §4 + `interface.md`（本目录）。**本文件只登记交付与装配要点，不重复定义**；两者不一致以单源为准并先改契约。

## 职责（速记）
- 把一次 `lw/sw`（MEM 段）按地址路由：低区 `0x0–0xFFF` → dmem；窗口 `0x4000` → MMIO（uart_ctrl，TX/STAT/RX 槽）；其余读 0/写丢弃；
- 输出 `cs_dmem/cs_mmio/reg_off` 与 rdata mux（`cs_dmem? dmem_rdata : (cs_mmio? mmio_rdata : 0)`）；
- 纯组合、无寄存器：不改变流水级数、与 hazard 无关（计组口径）。

## 装配接口（core 穿出，interface.md §1）
- out：`cs_mmio`、`reg_off[1:0]`、`mmio_we`、`mmio_wdata[31:0]`；in：`mmio_rdata[31:0]`；
- 实验一 build 不例化（dmem 直连 mem_wb）。

## 验收（U13，随计组 T40 执行）
- 低区行为与 dmem 直连一致（回归 H1–H5 不变）；窗口槽读写位义正确（TX 触发/STAT/RX 读清位）；未映射返回 0 且不产生写。

## 变更记录
- v1.0 2026-09-04：登记（口径随计组 top_design v1.4 / isa v1.3 冻结）。
