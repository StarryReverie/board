# mem_wb 模块文档（MEM/WB 段间寄存器）

- `src/rtl/mem_wb.v`（MEM→WB 边界）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 清全 0 |
| in | rdata | 32 | dmem 读回（lw 数据） |
| in | alu_result | 32 | exmem_alu_result |
| in | rd | 5 | 目的寄存器 |
| in | mem_to_reg / reg_write | 1×2 | WB 控制 |
| out | 同名（memwb_*） | 同左 | 全部寄存输出 |

## 功能/时序
```
posedge clk：rst→全 0；else 锁存全部
```

## 连接
- din ← ex_mem + dmem.rdata；dout → wb（mem2reg 选路）、hazard_unit（memwb.rd/reg_write 作 MEM/WB 前递源与 regfile 旁路参考）。

## 验收
- 沿沿打入；rst 清零；lw 数据经本寄存器进入 WB 写回与前递。
