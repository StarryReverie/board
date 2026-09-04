# pipeline_top 模块文档（顶层装配）

- `pipeline_top.v`：例化并互联全部模块；端口对齐参考 `ref/CPU/cpu_top.v`（仅 clk/rst）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 单时钟 |
| in | rst | 1 | 异步高有效复位 |
| in | imem_wen | 1 | IMEM loader 写使能（预留，实验一恒 0；top_design §9.3） |
| in | imem_waddr | 32 | IMEM loader 写地址（预留，实验一恒 0） |
| in | imem_wdata | 32 | IMEM loader 写数据（预留，实验一恒 0） |

## 内部例化与互联（信号名=各模块端口）
```
pc_reg   (clk,rst, en=~stall, pc_src=br_taken, pc_branch=br_target) → pc
imem     (addr=pc, wen/waddr/wdata=imem_wen/imem_waddr/imem_wdata) → inst
if_id    (en=~stall, flush=br_taken, inst_in=inst, pc_in=pc) → ifid_inst, ifid_pc
decode   (inst=ifid_inst) → rd/rs1/rs2/imm + ctrl{alu_op,src_a,src_b,mem_read,mem_write,mem_to_reg,reg_write,jump,bne}
regfile  (raddr1=rs1, raddr2=rs2, 写口=wb) → rdata1/2
id_ex    (bubble=stall|br_taken, pc=ifid_pc, rs1_data=rdata1, rs2_data=rdata2, imm/rd/rs1/rs2 + ctrl)
         → idex_*（pc/rs1/rs2/rd/imm/data + ctrl）
execute  (rs1/rs2_data=idex_*, fwd 输入来自 ex_mem.alu_result 与 wb.wb_data 及 fwd_sel,
          idex_pc/imm, alu_op/src_a/src_b/jump/bne)
         → alu_out, wdata, zero, br_taken, br_target
ex_mem   (alu_result=alu_out, wdata, rd=idex_rd, ctrl=idex_*M/WB)
         → exmem_*（rd/reg_write/mem_read/mem_write/mem_to_reg/alu_result/wdata）
dmem     (addr=exmem_alu_result, wdata=exmem_wdata, we=exmem_mem_write) → rdata
mem_wb   (rdata, alu_result=exmem_alu_result, rd=exmem_rd, mem_to_reg/reg_write=exmem_*)
         → memwb_*
wb       (memwb_*) → wb_rd/wb_data/wb_we → regfile 写口；wb_data 亦作 execute.wb_fwd_val
hazard_unit(rs1_id=decode.rs1, rs2_id=decode.rs2, idex_*, exmem_*, memwb_*)
         → fwd_a_sel/fwd_b_sel/stall
```
- 控制信号打包：各 ctrl 位按需以离散 wire 互联（top_design §2 字段），或按 1 条 ctrl 总线打包后逐位拆；采用总线时在 top_design 附录登记打包位序。
- HALT 观测：测试经层次引用读 regfile/dmem/idex_pc；溢出 `of` 可经层次引用观察。

## IMEM 装载与重载
- `imem` 内含 `include "imem_init.vh"`（综合字面量装载）与 TB `$readmemh`（仿真）；两路内容由 `verify_hex.py` 校验一致。
- 重载（实验二 loader）：经 `imem_wen/imem_waddr/imem_wdata` 在 CPU 复位期写满 `imem`，本实验接 0（top_design §9.3）。

## 验收（T20）
- 端口/互联与 top_design §5 一致；无悬空/多重驱动；Vivado 综合通过；H1–H5 见 top_design §8。
