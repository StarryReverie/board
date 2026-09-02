# wb（回写组合）模块文档

- 位置：`wb.v`（WB 段纯组合选路）。经典方案 WB 无独立寄存器 → 数据在 WB 段末沿由 regfile 写口锁存。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | memwb_rd | 5 | 目的寄存器 |
| in | memwb_alu_result / memwb_rdata | 32×2 | ALU 结果 / 读存数据 |
| in | memwb_mem_to_reg | 1 | 0=ALU 结果；1=读存数据 |
| in | memwb_reg_write | 1 | 写使能（rd=0 由 regfile 内部屏蔽） |
| out | wb_rd | 5 | → regfile.waddr |
| out | wb_data | 32 | → regfile.wdata |
| out | wb_we | 1 | → regfile.we |

## 功能
```
wb_data = memwb_mem_to_reg ? memwb_rdata : memwb_alu_result
```
- 同一 `wb_data` 同时供 regfile 写口与 **MEM/WB 前递源值（wb_fwd_val）**，保证 jal/jalr 链接值、lw 值前递正确。

## 连接
- 输入 ← mem_wb 输出；输出 → regfile 写口、execute 的 wb_fwd_val。

## 验收
- mem2reg=0/1 选路对；wb_we=memwb_reg_write；rd=x0 不写（regfile 侧）。
