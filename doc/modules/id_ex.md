# id_ex（ID/EX 段间寄存器）模块文档

- 位置：`id_ex.v`（段间寄存器，ID→EX 边界）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 清全 0 |
| in | bubble | 1 | 1=灌气泡：本拍全 0（load-use 或分支冲刷后 ID 的指令被丢弃） |
| in | pc | 32 | ifid_pc |
| in | rs1_data / rs2_data | 32/32 | regfile 读值 |
| in | imm | 32 | decode 立即数 |
| in | rd / rs1 / rs2 | 5×3 | 字段（rs1/rs2 地址供前递比较） |
| in | alu_op | 4 | ctrl |
| in | src_a / src_b | 2/2 | ctrl |
| in | mem_read / mem_write / mem_to_reg / reg_write | 1×4 | ctrl |
| in | jump | 2 | ctrl |
| in | bne | 1 | ctrl |
| out | 同名（idex_*） | 同上 | 全部寄存输出 → execute / hazard_unit |

## 功能/时序
```
posedge clk：
  rst → 全 0；
  else if (bubble) → 全 0；      // 控制清零=气泡（数据亦 0，无害）
  else → 锁存全部输入
```
- load-use 暂停：stall 拍把 ID/EX 清零（EX 灌气泡 1 拍）；
- 分支冲刷：taken 拍也清零 ID/EX（丢弃分支后第 1 条误入 ID 的指令）。
- 无独立 `en`：气泡由清零实现；不需要"保持"语义。

## 连接
- din ← decode 输出 + regfile 读值 + if_id.pc；dout → execute、hazard_unit（load-use 判 idex.mem_read/rd、前递比较 idex.rs1/rs2、EX 取 idex_*）。
- bubble ← hazard_unit（stall | flush_branch）。

## 验收
- bubble=1 后 EX 等效 NOP（无写/读/跳转副作用）；否则沿沿打入；rst 全 0。
