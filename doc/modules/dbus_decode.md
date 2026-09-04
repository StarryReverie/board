# dbus_decode 模块文档（数据侧总线译码：DMEM/MMIO 选路，组合）

- `dbus_decode.v`（MEM 段纯组合）。**实验二启用**（top_design §9.2、tasks.md §6 T40）；实验一核内 dmem 直连、不例化。职责：把一次 `lw/sw`（MEM 段）按地址路由到数据 RAM 或 MMIO 外设，并选出回写数据（rdata mux）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | addr | 32 | 访存字节地址（=exmem_alu_result，4 对齐） |
| in | we | 1 | 写使能（=exmem_mem_write） |
| in | dmem_rdata | 32 | 数据 RAM 组合读回 |
| in | mmio_rdata | 32 | 命中外设读回（实验二接 uart_ctrl 读口） |
| out | cs_dmem | 1 | 命中数据 RAM 低区；RAM 写使能=`we & cs_dmem` |
| out | cs_mmio | 1 | 命中 MMIO 窗口；写选通=`we & cs_mmio` |
| out | reg_off | 2 | MMIO 槽内寄存器偏移（TX/STAT/RX…，组合） |
| out | rdata | 32 | 回写数据 → mem_wb（`cs_dmem? dmem_rdata : (cs_mmio? mmio_rdata : 0)`） |

## 地址分区（**定稿 v1.4**，与 isa.md §4 / top_design §9.2 一致）
| 地址 | 目标 | 判定 |
|---|---|---|
| `0x0000_0000`–`0x0000_0FFF`（`addr < DMEM_BYTES`，默认 4096） | cs_dmem | 数据 RAM |
| `0x0000_4000` + 0x0 | cs_mmio · TX 槽 | `reg_off=00`；写=待发字节（低 8 位），读=0 |
| `0x0000_4000` + 0x4 | cs_mmio · STAT 槽 | `reg_off=01`；读 bit0=TX_BUSY、bit1=RX_VALID，写无操作 |
| `0x0000_4000` + 0x8 | cs_mmio · RX 槽 | `reg_off=10`；读=收到字节（低 8 位，读后清 RX_VALID），写无操作 |
| 其余 | 无操作 | `rdata=0`、写丢弃（程序不应访问；无定义但无害） |

- **编址口径：统一编址（方案 B 定稿）**——`lw`=外设读（in/r）、`sw`=外设写（out/w），读写方向由指令天然区分，**无专用 in/out 指令**；`reg_off[1:0]` 仅对 `cs_mmio` 有效（00=TX、01=STAT、10=RX、11=保留）。

## 时序/语义
- 纯组合、无寄存器：读在 MEM 周期内稳定（沿前供 mem_wb 锁存），写与 dmem 同步写同一沿 → 插入后**流水级数与冒险策略不变**（top_design §9.2）。
- 与 hazard 无关：load-use/前递按 rd 判定，不关心命中 RAM 还是外设。

## 连接（实验二例化于 pipeline_top）
- 输入 ← ex_mem（alu_result→addr、mem_write→we）；dmem_rdata ← dmem；mmio_rdata ← uart_ctrl 读口。
- 输出 → rdata → mem_wb；`we & cs_dmem` → dmem.we；`we & cs_mmio` + reg_off → uart_ctrl 写口。

## 验收
- 低区行为与"dmem 直连"完全一致（实验一回归 H1–H5 不变）。
- 窗口按上表命中 TX/STAT/RX 槽：写 TX 触发发送（忙时丢弃语义在 uart_ctrl 侧）、STAT/RX 读回位义正确、RX 读后清 RX_VALID；未映射地址返回 0 且不产生写。
