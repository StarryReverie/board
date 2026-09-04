# id_ex 模块文档（ID/EX 段间寄存器）

- `id_ex.v`（ID→EX 边界）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 清全 0 |
| in | bubble | 1 | 1=灌气泡：本拍全 0（load-use 或分支冲刷丢弃 ID 指令） |
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
- 无独立 `en`：气泡由清零实现，不需要"保持"语义。
- load-use：stall 拍清 ID/EX（EX 灌 1 拍气泡）；分支冲刷：taken 拍同样清零（丢弃分支后误入 ID 的第 1 条指令）。

## 连接
- din ← decode 输出 + regfile 读值 + if_id.pc；dout → execute、hazard_unit（load-use 判 mem_read/rd、前递比较 rs1/rs2）。bubble ← hazard_unit（stall | flush_branch）。

## 验收
- bubble=1 后 EX 等效 NOP（无写/读/跳转副作用）；否则沿沿打入；rst 全 0。
