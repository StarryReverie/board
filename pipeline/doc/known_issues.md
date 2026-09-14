# 已知缺陷与待办（pipeline 实验一）

> 记录仿真/规模测试中发现、但**尚未在 RTL 修复**的问题，供后续修复与报告"问题及解决方法"章节引用。
> 每条含：现象 / 最小复现 / 根因（逐拍证据）/ 已验证的候选方案与取舍 / 影响面。
> 文档口径单源在 `pipeline/doc/top_design.md` §4 与 `pipeline/doc/modules/hazard_unit.md`；本文件是缺陷台账。

---

## L1 累加寄存器自 RAW × load-use 批量载荷下丢失更新

### 现象

`pipeline/src/test/accwitness.asm`（19 条指令，`addi x1,x0,1` → 存 dmem[0] → `addi x1,x0,2` → 存 dmem[4] → 四条 `lw` 紧接 `add x8,x8,xN`）在 xsim 下得到

```
RESULT: x8=4  x9=4  dmem8=4
EXPECT: x8=8  x9=8  dmem8=8
```

即**每一次 load-use 冻结后的那条 `add` 都少加了一个源**，四组载荷共丢 4。同一缺陷使 `loop_heavy` 规模档
（`loop_heavy_{8,32,128}.asm`）的累加和偏小：N=8 实测 `x8=80`，应为 `2N²+3N=152`（`dmem0`、`dmem4` 均正确）。

### 触发条件（必要且充分）

同时满足两条：

1. 存在 load-use 冻结（`hazard_unit.stall=1`，即 ID 指令依赖 EX 段 load 的 `rd`）；
2. 被冻结的消费者读**同一个累加寄存器**，而该寄存器由**非 load** 指令产生，且该生产者的 WB 拍
   恰好落在"冻结拍"或"冻结拍后一拍"。

只满足第 1 条不会出错：`pipeline/src/test/bypass_witness.asm`（`lw x5,0(x0)` 紧接 `add x6,x5,x4`）
实测 `x6=16` 完全正确 —— 普通 load-use 前递链路正常。

### 根因（逐拍证据，`build/tb_acc.v` 打印）

以第一条 `lw x6,0(x0)` + `add x8,x8,x6` 为例（`idex_mem_read=1` 为 load 进 EX）：

| 拍 | 事件 | 关键观察 |
|---|---|---|
| e=8 | load 进 EX，`hazard_unit.stall=1` | `id_ex.bubble = stall \| br_taken = 1` → **ID/EX 被清零，消费者 `add` 被冲成气泡** |
| e=9 | 消费者由 IF/ID/PC 冻结"重放"进 EX | 操作数快照来自 e=9 锁存沿；此时生产者 `addi x8,x0,0` 已进 WB，regfile **写优先旁路**（`we && waddr==raddr → wdata`）当拍给出的新值**正好被气泡占用的那一拍丢掉** |
| e=10 | 同一条 `add` 第二次出现在 ID/EX | 重放拍读口已回落到旧数组值 → 锁到陈旧操作数 → 结果偏小 |

`build/tb_acc.v` 的 `X8W` 写事件日志证实写回序列被"每隔一次丢一次"污染；`accwitness` 的 `HIST` 直方图显示
`pc=1c` 被计数 16 次（8 次真实 + 8 次重放）。

**一句话**：`id_ex.bubble` 在 load-use 冻结拍把消费者冲掉，消费者的操作数快照推迟到下一拍才锁存，
而"生产者恰在 WB"那一拍由 regfile 写优先旁路给出的新值没有被任何寄存器捕获，重放拍已取不到 ⇒ 陈旧源。

> 补充事实（排除误判）：
> - `pipeline/src/test/fwd_witness.asm`（EX/MEM→EX 紧邻前递）与 `bypass_witness.asm`（WB→ID 同拍旁路）
>   **均正确**，故前递与写优先旁路本身无缺陷；
> - `pipeline/src/test/backedge.asm`（最小回边分支）正确，分支冲刷/回边机制无缺陷；
> - 21 个既有回归用例全部通过，故缺陷只在上述组合条件下显形。

### 已验证的候选方案与取舍

| 方案 | 实测结果 | 结论 |
|---|---|---|
| A. `id_ex.bubble = stall \| br_taken`（现状） | `x8=4`（丢更新） | 现状，有缺陷 |
| B. `id_ex.bubble = br_taken`（冻结期不冲消费者） | `x8=12`（重复执行：消费者在冻结拍与重放拍各执行一次并都写回） | 不可用 |
| C. `id_ex` 增加 `hold`（冻结期整体保持） | **死锁**：load 被一起 hold 在 ID/EX，`stall` 永久为 1 | 不可用 |
| D. 方案 A + WB→ID 追加旁路（写口数据绕开写优先旁路直连 ID/EX 输入） | `x8=7`（仍差 1；旁路命中拍与重放锁存拍错位） | 未解决 |
| E. 方案 A + 仅冻结操作数快照 `op_freeze` | `x8=7`（同上错位） | 未解决 |

**正确修法方向**（尚未实现）：让消费者在冻结解除的那一拍、以**当拍** regfile 读口值锁存进 ID/EX。
可行做法是给 `id_ex` 增加独立的操作数锁存使能 `en`，且该 `en` 在冻结解除拍为 1、
在冻结拍为 0（控制字仍按 `bubble` 清零），即方案 C 的"只 hold 操作数、不 hold 控制字"版本；
需要同步核对 ID/EX 的 `pc/rd/rs1/rs2` 是否需与操作数同拍锁存，并用 21 例全量回归 + 全部见证程序验证。

### 影响面

- **性能测量不受影响**：`C_total`、`IC`、`L`、`T` 与数据值无关，`loop_heavy` 的拍数/冻结数/重定向数均自洽
  （恒等式 A/B 残差为 0），只是**架构态断言（x8）无法作为正确性判据**。
- **报告口径**：`loop_heavy` 规模档可作为"CPI 随规模收敛"的证据（拍数与 IC 正确），
  但**不得**用它声称累加和正确；功能正确性以 21 例回归 + `fwd_witness`/`bypass_witness`/`backedge` 为准。
- 该缺陷属"仿真发现的设计问题"，可写入报告的"问题及解决方法"章节；若在报告提交前完成修复，
  需重跑 21 例回归与三档 `loop_heavy` 并更新本文件。

### 复现命令

最小复现程序在仓库内：`pipeline/src/test/accwitness.asm`（19 条指令，见下）。用任一已在库的
`tb_prog_*` 风格 TB 换载该镜像即可复现；本机用的临时逐拍探针 TB 放在 gitignored 的 `build/`，
不入库，命令如下：

```powershell
# 1) 汇编出镜像
uv run --no-project --python 3.13.13 pipeline/src/scripts/simple_asm.py pipeline/src/test/accwitness.asm

# 2) 用现成回归 TB 载入该镜像（把 PERF_HEX/程序名换成 accwitness 即可）：
#    pipeline/src/scripts/run_tb.ps1 会为 pipeline/src/test/tb_*.v 生成用例；
#    临时做法是把 accwitness_rom.hex 复制到某个 tb_prog_* 的工作目录并改名。
#    本机实测输出：RESULT: x8=4 x9=4 dmem8=4 / EXPECT: x8=8 x9=8 dmem8=8
```
