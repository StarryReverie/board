# imem_rom（指令存储器 ROM）模块文档

- 位置：`imem_rom.v`（取指组合，只读）。
- 参考 `ref/CPU/rom.v` 字节数组结构；新增：可综合初始化装载（`.vh`）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | addr | 32 | 取指字节地址（=pc，4 对齐） |
| out | inst | 32 | 该地址指令 |

## 存储与初始化
- 字节数组 `reg [7:0] mem [0:IMEM_BYTES-1]`（默认 4096 字节=1024 字）；小端重组 `inst = {mem[addr+3],mem[addr+2],mem[addr+1],mem[addr]}`。
- 内容：
  - 仿真：TB `$readmemh("xxx.hex", ...)`；
  - 综合：`initial` 逐字节字面量装载，由 `rom_init.vh` include（`verify_hex.py` 生成/校验，保证与 `.hex` 一致）；
  - 两路一致性=验收项。

## 时序
- 只读组合（周期内 `addr` 稳定则 `inst` 稳定）；写同步不适用。综合为分布式 ROM；测试集 <1KB 规模下时序余量充足（见 top_design §6）。
- 访问越界（addr 超出容量）→ 返回 0，属未定义但无害（测试程序应避免）。

## 验收
- 逐字读回与镜像一致；小端重组正确（首条与 objdump 反解一致）。
