# pipeline_top 模块文档（顶层装配）

- `pipeline/src/rtl/pipeline_top.v`：例化并互联全部模块；端口对齐参考 `ref/CPU/cpu_top.v`（仅 clk/rst，另加实验二预留/扩展口）。

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
| in | mmio_rdata | 32 | MMIO 读回（← uart_ip_top，实验二 UART IP 顶层；实验一接 0） |
| out | dbg_pc | 32 | 板级观测：IF 段 PC（= `pc`） |
| out | dbg_stall | 1 | 板级观测：load-use 冻结中（= `stall`） |
| out | dbg_br_taken | 1 | 板级观测：分支/跳转重定向（= `br_taken`） |
| out | dbg_halt | 1 | 板级观测：**停机自循环**（`br_taken & (idex_jump != jalr) & (idex_imm == 0)`，isa §4） |
| out | dbg_store_valid | 1 | 板级观测：MEM 段实际写 dmem（= `dmem_we_int`） |
| out | dbg_store_addr | 32 | 板级观测：写地址（= `exmem_alu_result`） |
| out | dbg_store_data | 32 | 板级观测：写数据（= `exmem_wdata`） |
| out | dbg_wb_we | 1 | 板级观测：WB 段写回使能（= `wb_we`） |
| out | dbg_wb_rd | 5 | 板级观测：WB 段写回目的寄存器（= `wb_rd`） |
| out | dbg_wb_data | 32 | 板级观测：WB 段写回数据（= `wb_data`） |

### dbg_* 观测口的用途与约束（T36 新增）

- **用途**：实验一独立上板（`exp1_board_top`）需要把 CPU 内部事件变成 LED/数码管可见状态。
  板级包装**不得使用不可综合的层次引用**（`u_cpu.xxx`），因此把已有内部信号引出为端口。
- **纯观测、零逻辑改动**：全部是连续赋值读已有 wire，不新增/不改变任何逻辑，
  既有 21 项功能回归与 8 档性能实测**逐值不变**。
- **为什么必须加**：实验一构建（`SOC_BUILD=0`）下四个 mmio 输出恒为常量
  （`cs_mmio=0/reg_off=0/mmio_we=0/mmio_wdata=0`），综合器会判定"无任何可观测输出"
  而把取指/译码/执行/访存整条通路删空（实测：`synth_design` 0 error 但 DCP 内
  `0 cells / 0 LUT / 无时序路径`）。
- **停机判据的坑**：本流水线为"未采取预测 + taken 冲刷 2 条"，`beq x0,x0,self`
  自循环时 **PC 不是常量**，而是周期 3 的 `{halt, halt+4, halt+8}` 循环；
  故 `dbg_halt` 用**语义判据**而非"PC 连续不变"。
- **停机判据为什么写成"零偏移"而不是"`br_target == idex_pc`"**：两者对 branch/jal 完全等价
  （目标加法器的 A 操作数就是 `idex_pc`，见 `execute.v`），但直接比较会把
  `idex_pc/imm → 32 位加法器 → 32 位比较器 → 观测触发器` 变成全设计最差路径
  （实测 post-synthesis WNS 因此恶化约 0.15 ns）；用 `idex_imm == 0` 只需对寄存器输出做
  或归一，路径长度基本为 0。jalr 自环不覆盖（isa §4 的停机约定是 `beq x0,x0,self`）。
  详见 `pipeline/doc/board_runbook.md` §2.2。


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
- T36（实验一独立上板）追加：`dbg_*` 观测口为纯连线，21 项功能回归 + 8 档性能实测逐值不变；
  板级顶层回归 `tb_exp1_board_top`（22 项断言）与上板程序回归 `tb_prog_board_demo`（34 项断言）全 PASS。
