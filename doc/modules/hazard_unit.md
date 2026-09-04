# hazard_unit 模块文档（冲突处理单元，组合）

- `rtl/hazard_unit.v`。术语对照：数据相关→前递/暂停；控制相关→冲刷（top_design）；结构相关→存储分离。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | rs1_id / rs2_id | 5×2 | 当前 ID 指令读源（if_id 字段，经 decode） |
| in | idex_mem_read | 1 | EX 段指令是否为 load |
| in | idex_rd | 5 | EX 段目的寄存器 |
| in | idex_rs1 / idex_rs2 | 5×2 | EX 段指令读源（前递比较） |
| in | exmem_rd / exmem_reg_write / exmem_mem_read | 5/1/1 | MEM 段 |
| in | memwb_rd / memwb_reg_write | 5/1 | WB 段 |
| out | fwd_a_sel / fwd_b_sel | 2×2 | 0=reg 1=EX/MEM 2=MEM/WB |
| out | stall | 1 | load-use 暂停（pc 冻结 + IF/ID 冻结 + ID/EX 气泡） |

> 分支冲刷 `flush_branch` 由 execute 的 `br_taken` 直接给出（top 层取用），本单元不重复产生。

## 判定逻辑
- **前递（A/B 同规则，EX/MEM 优先）**：
  ```
  for 源 x ∈ {idex_rs1(→A), idex_rs2(→B)}:
    if (exmem_reg_write && exmem_rd!=0 && !exmem_mem_read && exmem_rd==x)  sel=1
    else if (memwb_reg_write && memwb_rd!=0 && memwb_rd==x)                sel=2
    else                                                                   sel=0
  ```
  EX/MEM 为 load（mem_read=1）时不前递（数据未就绪；依赖该 load 的消费者必已触发 load-use，不会到达 EX）。
- **load-use 暂停**：
  ```
  load_use = idex_mem_read && idex_rd!=0 &&
             (idex_rd==rs1_id || idex_rd==rs2_id)
  stall = load_use
  ```
  stall=1 → pc_reg.en=0、if_id.en=0、id_ex.bubble=1（恰 1 气泡）。
- 优先级：flush_branch 与 stall 不会同拍同时为 1（EX 段单指令不可能既是 load 又是分支），top 端 `id_ex.bubble = stall | br_taken`、`if_id.flush = br_taken`。

## 为什么恰 1 气泡 / 恰 2 冲刷
见 top_design §3/§4 时序推导：load 数据在 MEM/WB 就绪于其 WB 拍，消费者 EX 拍前递；分支 taken 清 IF/ID+ID/EX 两条。

## 连接
- 输入 ← if_id/decode(rs1_id/rs2_id)、id_ex、ex_mem、mem_wb 输出；输出 → execute 前递 mux、pc_reg/if_id/id_ex 控制。

## 验收
- H2 两前递路径选源正确（EX/MEM 优先）；H3 load-use 恰 1 气泡；H4 分支 taken 刷 2 条；H5 整程序与期望一致（旁路+前递+暂停+冲刷组合正确）。
