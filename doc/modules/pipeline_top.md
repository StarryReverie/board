# pipeline_top 模块文档（顶层装配）

- `pipeline_top.v`：例化并互联全部模块；端口对齐参考 `ref/CPU/cpu_top.v`（仅 clk/rst，另加实验二预留/扩展口）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | clk | 1 | 单时钟 |
| in | rst | 1 | 异步高有效复位 |
| in | imem_wen | 1 | imem 写使能（**预留，恒 0**——固化单程序模型不启用；top_design §9.3） |
| in | imem_waddr | 32 | imem 写地址（预留，恒 0） |
| in | imem_wdata | 32 | imem 写数据（预留，恒 0） |
| out | cs_mmio | 1 | MMIO 片选（dbus_decode 命中窗口；实验一不例化，悬空） |
| out | reg_off | 2 | MMIO 槽偏移（dbus_decode 拆 TX/STAT/RX；实验一悬空） |
| out | mmio_we | 1 | MMIO 写使能（=`we & cs_mmio`；实验一悬空） |
| out | mmio_wdata | 32 | MMIO 写数据（=exmem_wdata；实验一悬空） |
| in | mmio_rdata | 32 | MMIO 读回（← uart_ctrl；实验一接 0） |

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
dbus_decode（实验二例化，MEM 段）：(addr=exmem_alu_result, we=exmem_mem_write,
         dmem_rdata=dmem.rdata, mmio_rdata=mmio_rdata) → rdata→mem_wb、
         cs_dmem→dmem.we、mmio 总线(cs_mmio/reg_off/mmio_we/mmio_wdata)穿出；
         实验一不例化：dmem.rdata 直连 mem_wb.rdata（top_design §0.1）
mem_wb   (rdata, alu_result=exmem_alu_result, rd=exmem_rd, mem_to_reg/reg_write=exmem_*)
         → memwb_*
wb       (memwb_*) → wb_rd/wb_data/wb_we → regfile 写口；wb_data 亦作 execute.wb_fwd_val
hazard_unit(rs1_id=decode.rs1, rs2_id=decode.rs2, idex_*, exmem_*, memwb_*)
         → fwd_a_sel/fwd_b_sel/stall
```
- 控制信号打包：各 ctrl 位按需以离散 wire 互联（top_design §2 字段），或按 1 条 ctrl 总线打包后逐位拆；采用总线时在 top_design 附录登记打包位序。
- HALT 观测：测试经层次引用读 regfile/dmem/idex_pc；溢出 `of` 可经层次引用观察。

## IMEM 装载（固化单程序模型）
- `imem` 内含 `include "imem_init.vh"`（综合字面量装载 = 固化程序，上电自跑）与 TB `$readmemh`（仿真）；两路内容由 `verify_hex.py` 校验一致。
- `imem_wen/waddr/wdata` 为**预留写口（恒 0）**：固化模型不做运行期重载；换程序 = 重新生成 .vh → 重新综合 → 重烧 .bit（top_design §9.3）。若未来恢复 loader 再启用本口（先回写 top_design/tasks）。

## 验收（T20）
- 端口/互联与 top_design §5/§9.5 一致（实验一：dbus_decode 不例化、mmio 端口悬空/接 0，H1–H5 口径不变）；无悬空/多重驱动；Vivado 综合通过；H1–H5 见 top_design §8。
