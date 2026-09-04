# dmem 模块文档（访存存储：数据 RAM）

- `src/rtl/dmem.v`。参考 `ref/CPU/ram.v`（wmask 字节写），保留同步写、周期内组合读；与 IMEM 物理分离 → **结构冒险化解**。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 写时钟 |
| in | addr | 32 | 字节地址（=exmem_alu_result，lw/sw 4 对齐） |
| in | wdata | 32 | 写数据（=exmem_wdata） |
| in | wmask | 4 | 字节写使能（默认 `4'b1111`，支持字节扩展） |
| in | we | 1 | 写使能（=exmem_mem_write） |
| out | rdata | 32 | 读数据（组合，周期内有效） |

## 存储与时序
- 字节数组 `reg [7:0] mem[0:DMEM_BYTES-1]`（默认 4096）；小端 `rdata={mem[a+3],…,mem[a]}`。
- 写（同步）：`posedge clk if(we) for(i<4) if(wmask[i]) mem[addr+i]<=wdata[8i+:8]`。
- 读（组合）：地址来自 EX/MEM 寄存器（周期内稳定），数据在访存周期内就绪 → 访存段末沿由 MEM/WB 捕获。复位不清存储（数据由程序自初始化，同单周期）。
- 读写同拍同址语义：同步写+组合读 → 该拍读先出旧值（写未生效）⇒ lw 必须晚于 sw 一拍（依赖顺序由前递/旁路保证），测试程序遵循。

## 连接
- 地址/wdata/we ← ex_mem；rdata → mem_wb（实验二经 dbus_decode 选路，top_design §9.2）。

## 验收
- `sw` 后下一拍 `lw` 同址读回一致；wmask 字节写正确；越界行为定义（返回 0）。
