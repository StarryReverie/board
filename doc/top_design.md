# 计算机系统顶层设计（实验一：流水线 CPU core · 实验二：UART 集成 SoC）

- 版本：v1.3（2026-09-04：升级为两级顶层设计；§1–§8=实验一 CPU core，§9=实验二整机 SoC）。
- 布局：RTL `*.v` 于根、`defines/` 宏、`test/` 汇编/测试、`doc/` 文档；`ref/CPU/` 不改动。指令集：`doc/isa.md`（26 条 RV32I）；参考：`doc/ref_note.md`。

---

## 0. 项目两级结构、模块清单与分工

> 本文档覆盖两门课程设计：**实验一**＝RV32I 5 级流水线 **CPU core**（`pipeline_top`，§1–§8，门禁 M1–M3，见 tasks.md §2–§5）；**实验二**＝在其上集成 UART 形成**整机 SoC**（§9，见 tasks.md §6 T40–T45）。实验一单独交付时 core 的 `dbus_decode` 与 `imem` loader 写口不启用（恒 0/不例化），§1–§8 完全成立。

### 0.1 两级结构（总图）

```
【实验一】CPU core = pipeline_top（§1–§8，交付物）
   取指 IF ──► 译码 ID ──► 执行 EX ──► 访存 MEM ──► 回写 WB ──► regfile
   段间寄存器：if_id · id_ex · ex_mem · mem_wb（各带 en/flush）；冒险：hazard_unit 前递/冻结/冲刷

   实验一存储接法 = 直连（无译码、无写口）：
     取指侧  pc ──► imem 读口 ──► inst ──► IF/ID
     访存侧  ex_mem ──► dmem ──► mem_wb        （取指/访存分体 → 哈佛，互不冲突）

【实验二】SoC 整机 = soc_top（§9）＝ 实验一 core ＋ 两处接口扩展 ＋ 外围
   ① 取指侧：imem 加 loader 写口 —— CPU 与 loader 共用 imem，但不同时（CPU 复位期才写）
     运行：   pc ──► imem(读口) ──► inst ──► IF/ID          ← core 取指
     换程序： loader ──imem_wen/waddr/wdata(写口)──► imem    ← CPU 复位/冻结，写满后撤复位
     来源：   PC ──► USB-UART ──► uart_ctrl.RX ──► loader 收字节组字

   ② 访存侧：MEM 段插 dbus_decode 选路 —— CPU 不再直连 dmem/uart
     ex_mem(addr/wdata/we) ──► dbus_decode ──┬─ 低区 cs_dmem ──► dmem 数据 RAM
                                             └─ MMIO cs_mmio ──► uart_ctrl（TX/STAT/RX 字槽）
     读回：  mem_wb ◄── rdata ◄── dbus_decode（dmem/uart 二选一 mux）
     外发：  uart_ctrl ── uart_tx/uart_rx ──► USB-UART ──► PC

   复位（§9.5）：板载复位键 ──► reset_sync ──► rst(异步高有效) ──► core / loader（单时钟域 clk）
```

- **实验一（core）**：上图的"CPU core"即 `pipeline_top`＝5 段哈佛流水，交付可综合 CPU core，H1–H5 全绿（门禁 M1–M3，tasks.md §2–§5）。
- **实验二（SoC）**：`soc_top`＝`pipeline_top`（扩展数据侧译码 + 引出 imem 写口）＋ `uart_ctrl`（MMIO 从机）＋ `loader`（复位期写 imem）＋ `reset_sync`（上板复位）。整机经板载 USB-UART 与 PC 通信：默认固件 console（§9.6），并支持运行间隙重载程序（§9.3）。

### 0.2 模块清单（RTL 归属 ↔ 文档）

| 归属 | 模块 | 段/角色 | 模块文档 |
|---|---|---|---|
| 实验一 | `pc_reg` / `imem` | IF：取指/指令存储 | modules/{pc_reg,imem}.md |
| 实验一 | `if_id` / `decode`+`regfile` / `id_ex` | ID | modules/{if_id,decode,regfile,id_ex}.md |
| 实验一 | `execute`（含 `alu`） | EX | modules/{execute,alu}.md |
| 实验一 | `ex_mem` / `dmem` / `mem_wb` / `wb` | MEM/WB | modules/{ex_mem,dmem,mem_wb,wb}.md |
| 实验一 | `hazard_unit` / `pipeline_top` | 冒险 / 装配 | modules/{hazard_unit,pipeline_top}.md |
| 实验二 | `dbus_decode` | core 数据侧译码（入 pipeline_top MEM 段） | modules/dbus_decode.md |
| 实验二 | `uart_ctrl` | MMIO 从机（UART） | 实验二登记（基础任务 IP） |
| 实验二 | `loader` | imem 引导装载 | 实验二登记 |
| 实验二 | `soc_top`（含 `reset_sync`） | 整机例化 / 复位同步 | 实验二登记 |

---

## 1. 总体结构：5 段 × (组合逻辑 + 段间寄存器)

一条指令沿 5 级流过，每级 = 一段组合逻辑，段间由寄存器锁存结果（§0.1 总图中的 CPU core）：

```
 取指 ─► if_id ─► 译码 ─► id_ex ─► 执行 ─► ex_mem ─► 访存 ─► mem_wb ─► 回写
  IF               ID               EX               MEM               WB
```

| 段 | 组合逻辑 | 边界寄存器（本段结束沿锁存） |
|---|---|---|
| IF 取指 | `pc_reg`、`imem`（组合读） | `if_id` |
| ID 译码 | `decode` + `regfile`（读口） | `id_ex` |
| EX 执行 | `execute`（含 `alu`、分支目标加法） | `ex_mem` |
| MEM 访存 | `dmem`（组合读/同步写） | `mem_wb` |
| WB 回写 | `wb`（选 rdata/alu 回写） | —（写回 `regfile`） |

- 段间 4 组边界寄存器由 `hazard_unit` 统一驱动：前递 `fwd_a/b_sel`、load-use 冻结 `stall`、分支冲刷 `flush`（策略见 §4）。
- 哈佛：IMEM（指令）与 DMEM（数据）物理分离 → 结构冒险靠分离化解（报告口径）。
- 模块互连信号全表见 §5；实验二在 MEM 段数据侧插入 `dbus_decode`、在 imem 引 loader 写口，见 §9.2/§9.3。

## 2. 段间寄存器边界与字段（字段名即跨模块信号名）

| 寄存器 | 位置 | 字段 | 说明 |
|---|---|---|---|
| if_id | IF/ID 间 | `ifid_inst[31:0]`, `ifid_pc[31:0]` | 冻结：`en=0`；冲刷：置 NOP `0x13` |
| id_ex | ID/EX 间 | `idex_pc, idex_rs1_data, idex_rs2_data, idex_imm, idex_rs1, idex_rs2, idex_rd`；`ctrl`：`alu_op[3:0], src_a[1:0], src_b[1:0], mem_read, mem_write, mem_to_reg, reg_write, jump[1:0], bne` | 冲刷/气泡：`ctrl` 全 0（NOP） |
| ex_mem | EX/MEM 间 | `exmem_alu_result, exmem_wdata, exmem_rd`；`mem_read, mem_write, mem_to_reg, reg_write` | 常规打入 |
| mem_wb | MEM/WB 间 | `memwb_rdata, memwb_alu_result, memwb_rd`；`mem_to_reg, reg_write` | 常规打入 |

控制组说明：
- `alu_op[3:0]`=`ALU_*`（`const_define.v`）；`jump[1:0]`=`0`无/`1`分支/`2`jal/`3`jalr；`bne`=1 表示 bne。
- `src_a[1:0]`：A 源 `0=rs1_fwd/1=idex_pc/2=0`；`src_b[1:0]`：B 源 `0=rs2_fwd/1=imm/2=4`。
- 组合约定：LUI=`src_a=0,src_b=imm,op=OR`(0|imm 直通)；jal/jalr 链接=`pc+4` 写 rd。
- 译码真值表见 `modules/decode.md`；字段全表见各模块文档。

## 3. 取指 / 分支 / 跳转语义（EX 段判决）

| 指令类 | ALU | ALU 结果用途 | 目标 | 条件 |
|---|---|---|---|---|
| beq/bne | src_a=rs1, src_b=rs2, op=SUB | 置 `zero` | `target = pc + imm`（专用加法器，A 选 pc） | taken = `bne? !zero : zero` |
| jal | src_a=pc, src_b=4, op=ADD | 链接 `pc+4` 写 rd | `target = pc + imm`（加法器，A 选 pc） | 恒 taken |
| jalr | src_a=pc, src_b=4, op=ADD | 链接 `pc+4` 写 rd | `target = rs1_fwd + imm`（加法器，A 选 rs1_fwd） | 恒 taken |
| lui | src_a=0, src_b=imm, op=OR | imm 直通写 rd | — | — |
| 普通 ALU | src_a=rs1 | 常规 | — | — |

- 目标加法器：A=`jump==3 ? rs1_fwd : pc`，B=`imm`；`br_target = A+B`（jalr 结果 &~1）。
- **控制冒险**：not-taken 预测。taken → 下一沿冲刷 2 条（IF/ID 置 NOP、ID/EX 控制清零）且 PC←br_target；not-taken 无气泡；EX 指令正常流入 EX/MEM。分支比较值由前递/旁路提供（§5），故仅在真正的 load-use 距离才停 1 拍。

## 4. 冲突（冒险）处理策略 —— hazard_unit

| 冲突 | 手段 | 条件（判定） | 代价 |
|---|---|---|---|
| 数据相关（RAW） | **前递** EX/MEM 与 MEM/WB → EX 的 A/B 源 | EX/MEM 或 MEM/WB 指令 `reg_write && rd≠0` 且 `rd==EX 的 rs1/rs2 地址`；**EX/MEM 为 load(`mem_read`)时不前递**（数据未就绪，靠下方 stall） | 0 |
| load-use | **冻结**：PC 与 IF/ID 停一拍，ID/EX 灌气泡 | ID 指令 rs1/rs2 命中 `idex` 中 load(`mem_read=1`) 的 `rd`（rd≠0） | 恰 1 气泡 |
| 控制相关 | 分支 EX 判决 + taken 冲刷 2 条（§3） | EX 段 taken | 恰 2 条 |
| 结构相关 | IMEM/DMEM 分离 + regfile 2 读 1 写 | 设计上消除 | 0 |

- 前递优先级：EX/MEM（更近）优先，同命中取 EX/MEM；MEM/WB 前递值 = `mem_to_reg ? rdata : alu_result`（已含 jal 链接值）。
- regfile **读旁路（write-first）**：读口命中当拍写口且 `reg_write` 时返回 `wdata`，消除"生产者恰在 WB、消费者同拍在 ID"的陈旧读。
- 控制输出（hazard_unit → 各段）：`fwd_a_sel/fwd_b_sel[1:0]`（`0=reg 1=EX/MEM 2=MEM/WB` → execute）；`stall`（load-use → `pc_reg.en=0, if_id.en=0, id_ex 气泡`）；`flush_branch`（=EX `br_taken` → if_id 冲刷、id_ex 气泡，`pc_src=1`）。
- 冻结与冲刷互斥：EX 段单指令不可能同时是 load 与分支。

## 5. 数据通路信号总览（模块互连）

| 段 | 模块 | 输入（来源） | 输出（去向） |
|---|---|---|---|
| IF | `pc_reg` | clk/rst, en, pc_src, pc_branch(EX) | pc → imem 地址（组合输入）、if_id 的 pc 位 |
| IF | `imem` | 地址=pc（读口） | inst → if_id（loader 写口见 §9.3） |
| ID | `if_id` | en, flush, pc, inst | ifid_pc, ifid_inst → decode |
| ID | `decode`+`regfile` | ifid_inst/ifid_pc, regfile 写回, `idex_mem_read/idex_rd`(load-use) | rs1_data/rs2_data/imm/rd/Ctrl → id_ex |
| EX | `id_ex` | decode 全部输出 + flush/气泡 | → execute、hazard_unit |
| EX | `execute`(alu+目标加法) | idex_*, fwd_a/fwd_b 源值 | alu_result/zero, wdata(rs2_fwd), br_taken/br_target → ex_mem、pc_reg、hazard_unit |
| MEM | `ex_mem` | execute 输出 | → dmem、mem_wb |
| MEM | `dmem` | 地址=exmem_alu_result, wdata=exmem_wdata, we | rdata → mem_wb（数据侧译码/MMIO 预留点，§9.2） |
| WB | `mem_wb` | dmem rdata + ex_mem 输出 | → wb |
| WB | `wb` | memwb_* | regfile 写口（经 wb 选路） |

## 6. 存储（Verilog 口径，面向下板）

- `imem`（指令存储）：读口=取指**组合读**；预留 **loader 写口**（`imem_wen/imem_waddr/imem_wdata`，字 4 对齐同步写）——运行期 `imem_wen=0` 表现只读，换程序窗口 CPU 复位、loader 独占写满（§9.3）。初值由 `.vh`（`initial` 字面量 `for` 循环）综合装载，上电不接 loader 也可直接运行；`test/*.hex` 仅供 TB `$readmemh`（两路一致性由校验脚本保证）。字节数组小端 `{mem[a+3],…,mem[a]}`，字地址 4 对齐。
- `dmem`：同步写（wmask 字节使能，默认全字）、组合读（周期内稳定）；字节数组小端。
- 规模：`IMEM_WORDS/DMEM_WORDS`（默认各 1024 字=4KB，测试集 <1KB），综合为分布式 ROM/RAM；块 BRAM 为可选优化（读出寄存器另计一拍）。
- `.vh`/`.hex` 一致且仅含指令清单内指令，由 `verify_hex.py` 校验（tasks.md T31）。

## 7. 时钟/复位

- 单时钟 `clk`；复位 `rst` **异步高有效**（对齐参考 `pc_reg.v/regfile.v` 的 `posedge rst` 写法）：复位 PC=0、流水寄存器与 regfile 清零。每模块单时钟、无门控；段间寄存器 `en/flush` 由 hazard_unit 统一驱动。

## 8. 验收口径（H1–H5）

- H1 直行无依赖链：CPI=1（首条启动流水外），cycle 数=手算。
- H2 前递：`add x1,..;` 紧接用 x1 无气泡，终值=golden。
- H3 load-use：`lw x2,0(x1); add x3,x2,x2` 恰 1 气泡。
- H4 分支：taken 刷 2 条 / not-taken 无气泡，cycle 与手算一致。
- H5 整程序（test0/test1/sort + 新增）与注释预期一致。

## 9. 实验二：SoC 集成设计（整机 = core + dbus_decode + uart_ctrl + loader）

> 本节把实验一交付的 CPU core（§1–§8，门禁 M1–M3 全绿后启动）构造成**能与 PC 通信的整机**：数据侧插入 `dbus_decode`（数据 MMIO，§9.2）、指令侧经 loader 写口在线重载程序（§9.3）、UART 外设与整机装配（§9.4/§9.5）、固件（§9.6）、验收（§9.7）。任务见 tasks.md §6（T40–T45）。core 本身不因实验二改动：`imem_wen`/MMIO 使能实验一恒 0/不例化，H1–H5 口径不变。

### 9.1 架构口径（一句话）

- 执行期**哈佛不变**：IF 直连 `imem` 读口，数据 `lw/sw` 走 MEM 段数据总线；换程序在**运行间隙**（CPU 复位/取指冻结）由 loader 经写口覆盖 `imem`，写完成释放复位、CPU 从 0 重跑。数据交互频繁→数据侧设译码；程序交互不频繁→运行间隙重写。**判定依据**：运行期 `lw/sw` 永远到不了指令存储（imem 只走 loader 写口）→ 仍是哈佛（改良哈佛），不是冯·诺依曼。

### 9.2 数据侧译码（dbus_decode：DMEM/MMIO 选路）

- 独立组合模块 **`dbus_decode`**（数据总线译码，模块文档 `doc/modules/dbus_decode.md`）。插入位置：`ex_mem` 与 `mem_wb` 之间（实验一 dmem 直连处）。按 `addr=exmem_alu_result` 选从设备并出 `cs_dmem/cs_mmio/reg_off`，回写数据 `rdata` mux。实验一不例化；T40 启用并接 dmem/uart_ctrl。
- 时序对齐：外设读与 dmem 同为周期内组合（沿前稳定）、写与 dmem 同步写同一沿 → 插入译码**不引入新冒险、不改流水级数**。与 hazard 无关（load-use/前递按 rd 判定，不关心命中 RAM 还是外设）。
- 地址映射（本设计采用；实验二经 uart 寄存器定稿后回写 `isa.md` §4）：

| 数据地址 | 目标 | 说明 |
|---|---|---|
| `0x0000_0000` +（`addr < DMEM_BYTES`，默认 4096） | `dmem` | 数据 RAM（lw/sw） |
| MMIO 窗口 `0x0000_4000` + | `uart_ctrl` | TX/STAT/RX 字槽（§9.4），`reg_off[1:0]` 拆寄存器 |
| 其余 | — | `rdata=0`、写丢弃（程序不应访问，无定义但无害） |

### 9.3 指令在线重载（loader 写口）

- `imem` 写口：`imem_wen/imem_waddr/imem_wdata`（字 4 对齐，`posedge clk` 同步写）。运行期 `wen=0` → 取指行为等同纯 ROM；仅换程序窗口 `wen=1`。口子经 `pipeline_top` 引出：`imem_wen(1)/imem_waddr(32)/imem_wdata(32)`（实验一接 0）。
- **loader**（实验二独立模块，状态机 `IDLE→LOAD→DONE`）：进入装载（复位或 reload 触发，CPU 复位：PC/流水清零、取指冻结）→ loader 独占 UART 收字节，按协议组字、逐字写满 `imem` → DONE（握手"写完"，loader 让出）→ soc_top 撤复位，CPU 从 0 跑新程序。**不得边跑边写**：取指每周期读 `imem`，边写会取到半截程序。
- 两种载入窗口：① 上电（无 loader 时跑 `.vh` 初值固件 §9.6）；② 运行中由串口命令/按键触发 **reload**——请求重新进 LOAD（CPU 复位）写完再释放，实现"运行间隙换程序"。
- loader 的数据源/去向：源=UART 收字节（与 uart_ctrl 共用收侧或独立收采样，T41 定稿）；去向=`imem` 写口。loader 与 CPU 对 UART 的归属由装载/运行态互斥：复位期 CPU 不读 uart → 无总线争用。

### 9.4 MMIO 外设：uart_ctrl（UART 接口控制器）

- 地位：基础任务 UART IP 的寄存器化封装，作 dbus_decode 的 MMIO 从机。字槽访问（`sw`/`lw` 即可，无需 sb/lbu）。
- 寄存器映射（窗口内偏移由 `reg_off[1:0]` 拆分；位义实验二定稿，示例）：

| 偏移 | 寄存器 | 读 | 写 |
|---|---|---|---|
| `0x0` | TX | 0（或上次写入回显） | 写入待发字节（低 8 位有效）→ 触发发送 |
| `0x4` | STAT | bit0 TX_BUSY / bit1 RX_VALID | 写无操作 |
| `0x8` | RX | 收到字节（低 8 位），读后清 RX_VALID | 写无操作 |

- 收发行为：半双工/全双工按基础任务 IP 语义；波特率 115200-8-N-1（或板载分频）。`soc_top` 例化两路 `uart_tx/uart_rx`（打拍）接板载 USB-UART 引脚。
- 固件访问即普通 `lw/sw`：轮询 STAT 位判断可发/有收，如 `while(STAT.TX_BUSY); SW TX; x; SW STAT=x;`。发送/接收均在 MEM 段一拍完成（寄存器操作），不卡流水——**波特率慢于 CPU**：若固件连写多个字节需等 TX_BUSY 清除（轮询），发送完成以 STAT 位回馈。

### 9.5 整机装配：soc_top（顶层 + 复位 + 引脚）

- `soc_top`（实验二最顶层）例化四个平级实例 + 复位同步：
  - `pipeline_top`（core）：内部含 `dbus_decode`（§9.2，MEM 段），并引出 `imem` loader 写口（§9.3）；
  - `uart_ctrl`：MMIO 从机（§9.4），由 dbus_decode 的 mmio 总线驱动；
  - `loader`：装载状态机（§9.3），写 `imem`；
  - `reset_sync`：复位同步（见下）。
- mmio 总线穿出 core：`cs_mmio/reg_off/wrdata/we`（pipeline_top → uart_ctrl）、`mmio_rdata`（uart_ctrl → pipeline_top → dbus_decode 的 rdata mux）——core 增加一组**外设总线端口**（实验一未用即悬空/接 0，H1–H5 不受影响）。示意：

```
 soc_top（最顶层，实验二装配）
 │
 ├─ reset_sync ：rst_n(键) ──(异步置位/同步释放)──► rst(异步高有效) ──► core & loader
 │
 ├─ pipeline_top（=core，§1–§8，dbus_decode 内置于 MEM 段）
 │     IF : pc_reg ─► imem ◄── loader 写口(imem_wen/waddr/wdata，§9.3)
 │     MEM: ex_mem ─► dbus_decode ─┬─► dmem（低区）
 │                                └─► MMIO 总线(cs_mmio/reg_off/wrdata/we，穿出 core)
 │                                     ──► uart_ctrl，读回 mmio_rdata ──► rdata mux
 │
 ├─ uart_ctrl（MMIO 从机，§9.4）
 │     ── uart_tx / uart_rx（打拍）──► 板载 USB-UART 引脚
 │
 └─ loader（装载状态机，§9.3）
       UART 收字节 ── 组字 ──► imem 写口；装载态互斥：复位/装载期独占，运行期空闲
```

- 时钟：整机**单时钟域** `clk`（板载晶振）；uart 波特率由 `clk_en` 分频产生，无第二时钟域、无异步跨域（rx 输入仅打两拍防亚稳态，与收发时序无关）。
- 复位：板上按键 `rst_n`（低有效）→ `reset_sync`（异步置位、同步释放，2 级同步器）→ core 语义的 `rst`（异步高有效，对齐 §7）。复位即上电装载窗口（§9.3）。
- 引脚（XDC）：晶振 `clk`、`rst_n`、`uart_tx`、`uart_rx`、板载 LED（运行/状态指示，可选）；引脚分配实验二定稿（精工板手册）。

### 9.6 固件与程序模型

- 内存映射（程序可见视角）：取指=`imem`（哈佛，只读）；数据=`dmem` 低区 + MMIO `0x4000` 高区（§9.2 表）。
- **默认固件（console）**：上电跑 `.vh` 初值（无 loader 也可直接演示）：初始化串口 → 打印 banner（经轮询 TX）→ 回显循环（读 RX 收到即回发，可加命令解析：如帮助/运行用户程序/触发 reload）。
- 数据/字符串归属（loader 模型下最自然）：`.data` 区由 **loader 一并载入 `dmem`**（收程序字节流 → 指令写 `imem`、数据写 `dmem`），固件字符串照常 `lw/sw` 访问；无 loader 的 `.vh` 初值演示则把字符串常量以 `lui+addi` 立即数当场拼装（或 `.vh` 同时预置 dmem，实验二定稿）。
- 用户程序模型：实验二演示一段**用户程序**（经 loader 载入，§9.3）替代固件接管串口，或固件 + 用户程序共用（任务表 T43/T45 定）。

### 9.7 实验二验收

- 仿真（系统级 TB，T44）：行为级 uart 模型回环 CPU；断言 banner 正确、回显往返一致、loader 载入后 CPU 从 0 跑新程序结果正确。
- 下板（T45）：综合/实现时序收敛 → 上板经 USB-UART 观察 banner/回显；演示 loader 在线重载一段新程序（PC 机上发字节流）→ CPU 重启跑新程序；≤5min 演示视频。
- 门禁：自 M1–M3 全绿后进入（tasks.md §6）。

## 10. 变更记录

- v1.3 2026-09-04：文档升级为**两课设一体**顶层设计：新增 §0（两级结构/模块清单，§1–§8=实验一 core，§9=实验二 SoC）；§9 由"集成预留"扩写为实验二整机设计（soc_top/uart_ctrl/loader/reset_sync/固件/验收 §9.2–§9.7）；标题改"计算机系统顶层设计"。
- v1.2 2026-09-04：新增 §9 集成预留（数据侧 MMIO + 指令在线重载）；指令存储按"带初值 + loader 写口"描述（`imem_rom`→`imem`）。
- v1.1 2026-09-04：行文精简。
- v1.0 2026-09-02：初稿。
