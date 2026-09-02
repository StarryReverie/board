# 流水线 CPU 顶层设计（冻结契约）

- 工程布局（仓库根）：RTL `*.v` 于根目录、`defines/` 宏、`test/` 汇编/测试、`doc/` 文档；参考工程 `ref/CPU/` 不改动。版本 v1.0（2026-09-02）；冻结后改接口必须先改本文件与对应模块文档。
- 指令集：`doc/isa.md`（26 条 RV32I 子集）。参考：`doc/ref_note.md`（单周期 `ref/CPU/`）。

---

## 1. 总体结构：5 段 × (组合逻辑 + 段间寄存器)

```
        ┌──────────────────────────────────────────────────────────────┐
        │ clk / rst(异步高有效) / (TB 经层次引用装载 IMEM)                 │
        │                                                              │
 pc_next├─►[取指组合] pc_reg → imem_rom ─(inst,pc)─► [IF/ID] ─►[译码组合]│
        │                              ▲   ▲          │                 │
        │ branch/br_target(EX)         │   │          ▼                 │
        │                          [ID/EX] ◄── decode(regfile读+ctrl+imm+load-use检测)
        │                              │              │                 │
        │   fwdA/fwdB ◄─[冲突处理 hazard_unit]        ▼                 │
        │   stall/flush ◄─────────────┘      [执行组合] execute(前递mux+alu+目标加法)
        │      │                                    │                  │
        │      ▼                                    ▼                  │
        │  [EX/MEM] ─►[访存组合] dmem ─►[MEM/WB] ─►[回写组合 wb]──► regfile 写口
        └──────────────────────────────────────────────────────────────┘
```

- 段间寄存器：**4 组独立模块** `if_id / id_ex / ex_mem / mem_wb`，在段边界例化；组合段为纯组合（`imem_rom/dmem_ram` 含同步写存储，读组合）。
- 哈佛：IMEM（指令）与 DMEM（数据）物理分离 → **结构冒险靠分离化解**（报告口径）。

## 2. 段间寄存器边界与字段（字段名即跨模块信号名）

| 寄存器 | 位置 | 字段 | 说明 |
|---|---|---|---|
| if_id | IF/ID 间 | `ifid_inst[31:0]`, `ifid_pc[31:0]` | 冻结：`en=0`；冲刷：置 NOP `0x13` |
| id_ex | ID/EX 间 | `idex_pc, idex_rs1_data, idex_rs2_data, idex_imm, idex_rs1, idex_rs2, idex_rd`；`ctrl`：`alu_op[3:0], src_a[1:0], src_b[1:0], mem_read, mem_write, mem_to_reg, reg_write, jump[1:0], bne` | 冲刷/气泡：`ctrl` 全 0（NOP） |
| ex_mem | EX/MEM 间 | `exmem_alu_result, exmem_wdata, exmem_rd`；`mem_read, mem_write, mem_to_reg, reg_write` | 常规打入 |
| mem_wb | MEM/WB 间 | `memwb_rdata, memwb_alu_result, memwb_rd`；`mem_to_reg, reg_write` | 常规打入 |

控制组说明：
- `alu_op[3:0]`：用 `const_define.v` 的 `ALU_ADD/SUB/SLT/…`。
- `src_a[1:0]`：ALU 的 A 源 `0=rs1_fwd / 1=idex_pc / 2=0`。
- `src_b[1:0]`：ALU 的 B 源 `0=rs2_fwd / 1=imm / 2=常数4`。
- `jump[1:0]`：`0`无 / `1`分支(beq/bne) / `2`jal / `3`jalr；`bne`=1 表示 bne。
- 常用组合：LUI=`src_a=0,src_b=imm,op=OR`(0|imm 直通)；jal/jalr 链接=`src_a=pc,src_b=4,op=ADD`→pc+4 写 rd。
- 译码真值表见 `modules/decode.md`；寄存器全表见各模块文档。

## 3. 取指 / 分支 / 跳转语义（EX 段判决）

| 指令类 | ALU | ALU 结果用途 | 目标 | 条件 |
|---|---|---|---|---|
| beq/bne | src_a=rs1, src_b=rs2, op=SUB | 置 `zero` | `target = pc + imm`（专用加法器，A 选 pc） | taken = `bne? !zero : zero` |
| jal | src_a=pc, src_b=4, op=ADD | 链接 `pc+4` 写 rd | `target = pc + imm`（加法器，A 选 pc） | 恒 taken |
| jalr | src_a=pc, src_b=4, op=ADD | 链接 `pc+4` 写 rd | `target = rs1_fwd + imm`（加法器，A 选 rs1_fwd） | 恒 taken |
| lui | src_a=0, src_b=imm, op=OR | imm 直通写 rd | — | — |
| 普通 ALU | src_a=rs1 | 常规 | — | — |

- 目标加法器：A=`jump==3 ? rs1_fwd : pc`，B=`imm`；`br_target = A+B`（jalr 结果 &~1）。
- **控制冒险**：not-taken 预测。taken → 下一沿 **冲刷 2 条**（IF/ID 置 NOP、ID/EX 控制清零）且 PC←br_target；not-taken 无气泡。EX 段本身正常流入 EX/MEM。
- 分支比较所需的寄存器值：由前递/寄存器堆旁路提供（见 §5），故分支仅在真正的 load-use 距离才停 1 拍。

## 4. 冲突（冒险）处理策略 —— hazard_unit

| 冲突 | 手段 | 条件（判定） | 代价 |
|---|---|---|---|
| 数据相关（RAW） | **前递** EX/MEM 与 MEM/WB → EX 的 A/B 源 | EX/MEM 或 MEM/WB 指令 `reg_write && rd≠0` 且 `rd==EX 的 rs1/rs2 地址`；**EX/MEM 为 load(`mem_read`)时不前递**（数据未就绪，靠下方 stall） | 0 |
| load-use | **冻结**：PC 与 IF/ID 停一拍，ID/EX 灌气泡 | ID 指令 rs1/rs2 命中 `idex` 中 load(`mem_read=1`) 的 `rd`（rd≠0） | 恰 1 气泡 |
| 控制相关 | 分支 EX 判决 + taken 冲刷 2 条（§3） | EX 段 taken | 恰 2 条 |
| 结构相关 | IMEM/DMEM 分离 + regfile 2 读 1 写 | 设计上消除 | 0 |

前递优先级：EX/MEM（更近）优先于 MEM/WB；两个源同时命中时取 EX/MEM。
MEM/WB 前递的值 = `mem_to_reg ? rdata : alu_result`（已含 jal 链接值）。
寄存器堆 **读旁路（write-first）**：读口命中当拍写口且 `reg_write` 时返回 `wdata`，消除"生产者恰在 WB、消费者同拍在 ID"的陈旧读。

控制输出（hazard_unit → 各段）：
- `fwd_a_sel[1:0], fwd_b_sel[1:0]`：`0=寄存器值 1=EX/MEM 2=MEM/WB`（送执行组合）。
- `stall`：load-use → `pc_reg.en=0, if_id.en=0, id_ex 气泡=1`。
- `flush_branch`：EX `br_taken`（由执行组合给出）→ `if_id 冲刷、id_ex 气泡`，同时 `pc_src=1`。
- 冻结与冲刷互斥（EX 指令不可能是 load 与分支同时成立）。

## 5. 数据通路信号总览（模块互连）

| 段 | 模块 | 输入（来源） | 输出（去向） |
|---|---|---|---|
| IF | `pc_reg` | clk/rst, en, pc_src, pc_branch(EX) | pc → imem 地址（组合输入）与 IF/ID 的 pc 位 |
| IF | `imem_rom` | 地址=pc | inst → if_id |
| ID | `if_id` | en, flush, pc, inst | ifid_pc, ifid_inst → decode |
| ID | `decode`+`regfile` | ifid_inst/ifid_pc, regfile 写回, `idex_mem_read/idex_rd`(load-use) | rs1_data/rs2_data/imm/rd/Ctrl → id_ex |
| EX | `id_ex` | decode 全部输出 + flush/气泡 | → execute、hazard_unit |
| EX | `execute`(alu+目标加法) | idex_*, fwd_a/fwd_b 源值 | alu_result/zero, wdata(rs2_fwd), br_taken/br_target → ex_mem、pc_reg、hazard_unit |
| MEM | `ex_mem` | execute 输出 | → dmem、mem_wb |
| MEM | `dmem_ram` | 地址=exmem_alu_result, wdata=exmem_wdata, we | rdata → mem_wb |
| WB | `mem_wb` | dmem rdata + ex_mem 输出 | → wb |
| WB | `wb` | memwb_* | regfile 写口（经 wb 选路） |

## 6. 存储（Verilog 口径，面向下板）

- `imem_rom`：同步写约束不适用（只读）；内容由 `.vh`（`initial` 字面量 `for` 循环装载）综合初始化；`test/*.hex` 仅供 TB `$readmemh`（两路内容由校验脚本保证一致）。字节数组小端：`{mem[a+3],mem[a+2],mem[a+1],mem[a]}`，字地址对齐。
- `dmem_ram`：同步写（wmask 字节使能，默认全字），组合读（周期内稳定）；同样字节数组小端。
- 存储规模：`IMEM_WORDS/DMEM_WORDS`（默认各 1024 字=4KB，测试集小于 1KB）。综合为分布式 ROM/RAM；如需块 BRAM 属可选优化（附读出寄存器需另计一拍，见模块文档）。
- `.vh` 与 `.hex` 一致性与"仅含冻结指令"由 `verify_hex.py` 校验（见 tasks.md T31）。

## 7. 时钟/复位
- 单时钟 `clk`；复位 `rst` **异步高有效**（对齐参考 `pc_reg.v/regfile.v` 的 `posedge rst` 写法），复位 PC=0、流水寄存器与 regfile 清零。
- 每模块单时钟、无门控；段间寄存器 `en/flush` 由 hazard_unit 统一驱动。

## 8. 验收口径（H1–H5）
- H1 直行无依赖链：CPI=1（首条启动流水外），cycle 数=手算。
- H2 前递：`add x1,..; 紧接用 x1` 无气泡，终值=golden。
- H3 load-use：`lw x2,0(x1); add x3,x2,x2` 恰 1 气泡。
- H4 分支：taken 刷 2 条 / not-taken 无气泡，cycle 与手算一致。
- H5 整程序（test0/test1/sort + 新增）与注释预期一致。

## 9. 变更记录
- v1.0 2026-09-02：初版冻结。
