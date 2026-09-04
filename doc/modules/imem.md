# imem 模块文档（指令存储：取指读口 + loader 写口）

- `imem.v`。参考 `ref/CPU/rom.v` 字节数组结构；按 top_design §6/§9 实现为**带初值、可被 loader 覆盖**的指令存储：读口供取指（组合读），写口仅供 loader 换程序（同步写）。运行期 `imem_wen=0`，行为等同只读 ROM。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 写时钟（loader 口） |
| in | addr | 32 | 取指字节地址（=pc，4 对齐） |
| out | inst | 32 | 该地址指令（组合读） |
| in | imem_wen | 1 | loader 写使能（实验一恒 0） |
| in | imem_waddr | 32 | loader 写字节地址（4 对齐） |
| in | imem_wdata | 32 | loader 写数据（整字，小端落 4 字节） |

## 存储与初始化
- 字节数组 `reg [7:0] mem [0:IMEM_BYTES-1]`（默认 4096 字节=1024 字）；小端重组 `inst = {mem[addr+3],mem[addr+2],mem[addr+1],mem[addr]}`。
- 内容装载：仿真=TB `$readmemh("xxx.hex")`；综合=`initial` 逐字节字面量（`imem_init.vh` include，由 `verify_hex.py` 生成/校验与 `.hex` 一致）。两路一致性=验收项。带初值 → 上电不接 loader 也能直接运行。

## 时序
- 读：组合（周期内 `addr` 稳定则 `inst` 稳定），供取指。
- 写：`posedge clk` 且 `imem_wen=1` 时，`{mem[imem_waddr+3],…,mem[imem_waddr]}` = `imem_wdata`（小端，4 对齐整字）。写窗口仅限 CPU 复位（取指冻结）、loader 独占（top_design §9.3）；**不得边取指边写**（会取到半截程序）。
- 访问越界返回 0（无定义但无害，测试程序应避免）。

## 连接
- 读口：addr ← pc_reg.pc；inst → if_id.inst_in。
- 写口：imem_wen/imem_waddr/imem_wdata ← pipeline_top 预留输入（实验一接 0；实验二接 loader）。

## 验收
- 运行期（`imem_wen=0`）逐字读回与镜像一致；小端重组正确（首条与 objdump 反解一致）。
- 载入语义（实验二 TB）：`imem_wen=1` 逐字写满后再读回，等于写入内容；`imem_wen=0` 期间读不受写影响。
