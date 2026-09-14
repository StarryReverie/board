# 已知问题与冒险审计记录（pipeline 实验一）

本文件记录性能实验中需要特别说明的测试边界，以及曾经提出但经复核撤销的缺陷线索。它不替代 RTL 契约；冒险行为的权威说明仍在 `pipeline/doc/top_design.md` 与 `pipeline/doc/modules/hazard_unit.md`。

## L1 线索撤销：累加寄存器自 RAW × load-use

### 复核结论

原先把 `accwitness.asm` 判定为“累加寄存器自 RAW × load-use”缺陷的结论不成立。见证程序的注释和期望值与实际指令流不一致，不能用来证明 RTL 丢失更新；当前 RTL 对该指令流给出的结果是正确的。

### `accwitness` 的真实指令流与结果

`pipeline/src/test/accwitness.asm` 共 19 条有效指令（含末尾自旋）：

1. 写入 `dmem[0]=1`、`dmem[4]=2`、`dmem[8]=1`；
2. 连续执行四组 `lw xN,0(x0)` + `add x8,x8,xN`，每次加载的值都是 1；
3. 将累加结果写入 `dmem[8]`。

因此正确结果为：

```text
x8=4  x9=4  dmem[8]=4
```

该结果与 xsim 观测一致，`accwitness` 现仅作为 load-use 行为审计样例，不作为 L1 缺陷证据。此前临时探针 `build/tb_acc.v` 中的 `EXPECT: x8=8` 已确认是错误期望。

### `loop_heavy` 的真实结果

每次循环从 `dmem[0]` 和 `dmem[4]` 各累加一次，然后分别加一。初值为 1 和 2 时，循环 N 次的正确结果为：

| N | `x8` | `dmem[0]` | `dmem[4]` |
|---:|---:|---:|---:|
| 8 | 80 | 9 | 10 |
| 32 | 1088 | 33 | 34 |
| 128 | 16640 | 129 | 130 |

公式为 `x8 = N² + 2N`、`dmem[0] = N+1`、`dmem[4] = N+2`。三个规模档的 `IC/L/T/C` 计数可用于 CPI 收敛分析；性能 TB 不将 `x8` 作为功能正确性证据，因为规模档属于性能负载而非功能回归用例。

### 当前验证边界

- 普通 load-use、EX/MEM 与 MEM/WB 前递、分支冲刷由现有 21 项功能回归覆盖。
- 本轮没有可复现的 RTL 缺陷见证，因此不记录“待修”的 L1 根因或修复方案。
- 若后续发现新的失败指令流，必须同时提交最小汇编、期望值、逐拍日志和独立 TB，再更新本文件。

### 复核命令

```powershell
uv run --no-project --python 3.13.13 pipeline/src/scripts/simple_asm.py pipeline/src/test/accwitness.asm
powershell -File pipeline/src/scripts/run_tb.ps1
powershell -File pipeline/src/scripts/run_perf.ps1
```
