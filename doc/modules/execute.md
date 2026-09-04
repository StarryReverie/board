# execute 模块文档（执行组合：前递 mux + ALU + 目标加法 + 分支判决）

- `execute.v`（纯组合，内例化 `alu.v`）。

## 端口
| 方向 | 名称 | 位宽 | 说明 |
|---|---|---|---|
| in | rs1_data / rs2_data | 32×2 | ID/EX 存的寄存器读值 |
| in | ex_fwd_val | 32 | EX/MEM 前递值（alu_result） |
| in | wb_fwd_val | 32 | MEM/WB 前递值（wb_data，已含 mem2reg/jal 链接） |
| in | fwd_a_sel / fwd_b_sel | 2×2 | 0=reg 1=EX/MEM 2=MEM/WB |
| in | idex_pc / imm | 32×2 | 分支/链接用 pc、imm |
| in | alu_op | 4 | 见 decode |
| in | src_a / src_b | 2×2 | 0=rs_fwd 1=pc/imm 2=0/4 |
| in | jump | 2 | 0/1/2/3（无/分支/jal/jalr） |
| in | bne | 1 | bne 分支比较取反 |
| out | alu_out | 32 | → EX/MEM（含 jal/jalr 链接 pc+4、lw/sw 地址） |
| out | wdata | 32 | 存数据源 rs2_fwd（→ EX/MEM.wdata） |
| out | zero / of | 1/1 | ALU 零标志 / 溢出标志 |
| out | br_taken | 1 | 本拍分支/跳转是否成立 |
| out | br_target | 32 | PC 更新目标 |

## 功能
```
rs1_fwd = sel(fwd_a_sel){ rs1_data, ex_fwd_val, wb_fwd_val }
rs2_fwd = sel(fwd_b_sel){ rs2_data, ex_fwd_val, wb_fwd_val }
alu_a = (src_a==0)? rs1_fwd : (src_a==1)? idex_pc : 0
alu_b = (src_b==0)? rs2_fwd : (src_b==1)? imm    : 4
alu 算 alu_out/zero/of
adder_a = (jump==3)? rs1_fwd : idex_pc            // jalr 目标=rs1+imm；其余=pc+imm
tgt_raw = adder_a + imm
br_target = (jump==3) ? {tgt_raw[31:1],1'b0} : tgt_raw   // jalr 清 bit0
cond_taken = (jump==1)? (bne? ~zero : zero) : (jump==2||jump==3)
br_taken = (jump==0)? 1'b0 : cond_taken
```
- wdata = rs2_fwd（sw 用）；分支/跳转用 `zero` 由 alu SUB 给出。

## 连接
- 前递选择 ← hazard_unit；alu/branch ← id_ex；输出 → ex_mem、pc_reg(pc_src/br_target)、hazard_unit(flush 判 br_taken)。

## 验收
- 真值表与 op；beq/bne/jal/jalr 判决与目标对；前递 0/1/2 选路对；lui 直通 imm；jal/jalr alu_out=pc+4。
