# ex_mem 模块文档（EX/MEM 段间寄存器）

- `src/rtl/ex_mem.v`（EX→MEM 边界）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 清全 0 |
| in | alu_result | 32 | execute.alu_out（地址或链接值） |
| in | wdata | 32 | execute.wdata（sw 数据，已前递） |
| in | rd | 5 | 目的寄存器 |
| in | mem_read / mem_write / mem_to_reg / reg_write | 1×4 | 控制（mem_read 供前递门控） |
| out | 同名（exmem_*） | 同左 | 全部寄存输出 |

## 功能/时序
```
posedge clk：rst→全 0；else 锁存全部
```
- 分支冲刷不清本寄存器（EX 段分支/跳转照常流入，其写回/访存正常完成）；flush 后 EX 下一拍为气泡，ex_mem 值全 0，无副作用。

## 连接
- din ← execute；dout → dmem(地址/wdata/we)、mem_wb、hazard_unit（rd/reg_write/mem_read）。

## 验收
- 沿沿打入；rst 清零；wdata 为前递后的 rs2（sw 正确）。
