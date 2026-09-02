# if_id（IF/ID 段间寄存器）模块文档

- 位置：`if_id.v`（段间寄存器，位于 IF→ID 边界）。
- 由 hazard_unit 统一控制 `en/flush`。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | rst 异步高有效，清零 |
| in | en | 1 | 0=保持（load-use 冻结）；1=按需更新 |
| in | flush | 1 | 1=置 NOP（分支冲刷） |
| in | inst_in | 32 | 取指段指令 |
| in | pc_in | 32 | 该指令地址 |
| out | inst | 32 | → 译码 |
| out | pc | 32 | → 译码/ID/EX（作 idex_pc） |

## 功能/时序
```
posedge clk：rst→{inst,pc}<=0；
else if(en) begin pc<=pc_in;
                  inst <= flush ? 32'h0000_0013   // NOP (addi x0,x0,0)
                               : inst_in;
             end
```
- en=0（load-use）时整拍保持，当前译码指令原样留到下一拍重译。
- flush（分支 taken）本拍丢弃错误指令（置 NOP）；`en` 在 flush 时必为 1。

## 连接
- en ← hazard.stall 取反；flush ← hazard.flush_branch（=EX br_taken）。
- inst/pc → decode 与后续 id_ex（pc 供 idex_pc）。

## 验收
- en=0 保持内容；flush 后 inst=0x00000013、pc 正常更新；rst 清零；常规沿沿打入。
