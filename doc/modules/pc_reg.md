# pc_reg 模块文档（取指组合：PC 更新）

- `rtl/pc_reg.v`。参考 `ref/CPU/pc_reg.v`：沿用 `pc_pred/pc_next/pc_src/pc_branch` 思路，新增 `en`（暂停）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk / rst | 1 | 复位异步高有效→pc=0 |
| in | en | 1 | 0=暂停保持（load-use）；1=更新 |
| in | pc_src | 1 | 0=pc+4；1=pc_branch（EX 分支目标） |
| in | pc_branch | 32 | EX 的 br_target |
| out | pc | 32 | 当前取指地址（字节） |

## 功能/时序
```
pc_next = pc_src ? pc_branch : pc + 4;
posedge clk：rst→pc<=0；else if(en) pc<=pc_next;   // en=0 保持
```
- 分支 taken 与暂停互斥：taken 时 `en=1, pc_src=1`；load-use 暂停时 `en=0`。
- 组合输出 `pc` 供 IMEM 与 IF/ID 的 pc 字段。

## 连接
- pc → imem.addr、if_id.pc_in（与译码取址同拍）；pc_src/pc_branch ← execute/hazard（br_taken、br_target）。

## 验收
- 复位后 pc=0；en=0 一周期值不变；pc_src=1 时下沿取 pc_branch；否则 +4。
