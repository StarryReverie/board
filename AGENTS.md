# board — 仓库智能体指南（opencode / Claude Code 通用）

> **`AGENTS.md` 是唯一权威正文**（opencode 直接读取）。**`CLAUDE.md` 仅为入口指引**：它强制 Claude Code 先完整读取本文件，不复制正文（避免双源失同步）。改动口径一律维护在本文件；入口指向维护见 §6。

---

## 0. 开始任何任务前：先读文档，勿过早直接读代码

本仓库是**两门课程设计**的产物，代码是文档契约的实现。涉及功能/结构问题先读：

| 文档 | 内容 |
|---|---|
| `doc/tasks.md` `doc/top_design.md` `doc/isa.md` `doc/modules/*.md` | 计组（实验一）：RV32I 5 级流水线 core（26 条冻结集、冲突策略、模块契约） |
| `exp2/doc/tasks.md` `exp2/doc/top_design.md` `interface.md` `firmware.md` `modules/*.md` | 汇编与接口（实验二）：UART SoC（统一编址 MMIO、.vh 固化、下板） |
| `SUBMISSION.md` | 两课提交物核对清单与当前总态 |
| `.coderabbit.yaml` | CodeRabbit 自动 review 配置 |

- 代码布局：计组 `src/{rtl,defines,test,scripts}`；汇编 `exp2/src/{rtl,test,xdc,scripts}`；文档 `doc/` 与 `exp2/doc/`；参考工程 `ref/CPU/`（只读）。
- 修改设计语义前**先改文档**；实现与文档冲突时，以文档口径修正实现并同步反馈。

## 1. 环境与工具（本机 Windows，PowerShell 5.1）

- **RISC-V 工具链**：本机**无** `riscv-none-elf-as`。汇编改用自研
  `src/scripts/simple_asm.py`（零依赖；26 条冻结集 + isa §3 伪指令；`jal label` 单操作数按 GNU 惯例写 `ra`；`li` 超 12 位展开 lui+addi）。Python 由 **uv** 提供（离线已装 3.13.13）：
  ```powershell
  uv run --no-project --python 3.13.13 src/scripts/simple_asm.py src/test/demo.asm   # 产出 demo_rom.hex + 打印清单
  ```
- **Vivado 2019.2**：`C:\Xilinx\Vivado\2019.2`，xsim 本机可用。板卡实测 **XC7A100T**（非手册误标 35T）；综合实现亦可（存储缩容口径见 `src/defines/const_define.v` 头注）。
- 搜索**优先 `rg`/`fd`**，不要用 `Get-ChildItem`/`Select-String` 全盘遍历。
- 跑脚本**直接执行看流式输出**；禁止 `| Select-Object -Last N` 之类截流。要看结果就 read/grep 打开的日志（`src/scripts/out/*.log`）。
- 编码：全仓 UTF-8；含中文的 `.ps1` 需 UTF-8 BOM（PS 5.1 解析）；校验/修复 `src/scripts/fix_encoding.ps1`（默认只报告）。

## 2. 测试（21 例）

- 运行器 `src/scripts/run_tb.ps1`：**并行 worker，默认自动满核**（`min(#TB, 逻辑核数)`）。
  ```powershell
  powershell -File src/scripts/run_tb.ps1                    # 全量 ~20-30s
  powershell -File src/scripts/run_tb.ps1 -Case prog_demo     # 按关键字子集
  powershell -File src/scripts/run_tb.ps1 -Jobs 8             # 限制并发；-Jobs 1=串行
  powershell -File src/scripts/run_tb.ps1 -TimeoutSec 60      # 每例预算（须 ≥1）
  ```
- **runner 已并行化，全量 ~20-30s**：开发迭代可用 `-Case …` 定向加速；**最终提交前跑一次全量**确认无回归（允许全量）。仅改文档/脚本文案时可跳过仿真。
- TB 装载 hex 用 `$readmemh(<名>_rom.hex)`：改了 `.asm` 必须先重新生成 hex 再跑。
- 断言约定：TB 打印 `PASS/FAIL`，末行 `=== ALL PASS ===`；汇总 `PASS n/n`。
- 性能：`src/scripts/run_perf.ps1`（5 档，汇总 out/perf_summary.csv）。

## 3. GitHub 自动化工作流（CodeRabbit 接管 review，弃用 Copilot）

**默认分支 = `dev`，所有 PR 指向 `dev`。** 用户期望高自主度（“no human in the loop”）：开 PR → CodeRabbit 审查 → 修复迭代 → 合并全程自动，仅在需要人决策时停下报告。

1. 基于最新 dev 建分支（语义前缀：`feature/`、`fix/`、`opt/`、`docs/`、`ci/`）：
   `git checkout -b <前缀>/<主题> origin/dev`
2. 提交并推送：`git commit …`、`git push -u origin <分支>`
3. 开 PR：`gh pr create --base dev --head <分支> --title … --body …`
4. **CodeRabbit 自动审查**（`.coderabbit.yaml`：非 draft、base dev、每次 push 增量、不自动暂停）。等待/检查：
   - `gh pr checks <n>`：CodeRabbit 状态 `pending → pass`（每次 push 后约 1-3 分钟自动触发）
   - 结论正文：`gh api repos/StarryReverie/board/pulls/<n>/reviews --jq '.[-1].body'`
   - 行内评论：`gh api repos/StarryReverie/board/pulls/<n>/comments`（注意 PowerShell 转义，jq 含 `[bot]` 等易被拆词，可把 filter 写入临时文件再 `--jq`）
5. 采纳意见 → 修代码 → **本地定向验证** → commit+push → 循环直到 check `pass`。采纳后 CodeRabbit 会给评论标 `✅ Addressed in commit …`。
6. 全绿合并并清理：
   ```powershell
   gh pr merge <n> --merge --delete-branch
   git checkout dev; git pull origin dev
   git branch -d <已合并本地分支>   # 若仍在本地
   ```

**经验/边界：**
- `copilot-pull-request-reviewer` 已因额度停用，**不再是主要 reviewer**；不可依赖。
- `gh` **无法**直接把 CodeRabbit bot 加为 reviewer；靠 push 自动触发增量审查（`auto_incremental_review: true`、`auto_pause_after_reviewed_commits: 0`）。
- 旧版 run_tb 串行慢的根因是每例冷启动 xelab+xsim 进程；并行后全量 ~20-30s。

## 4. 本机坑与备忘

- **僵尸 Vivado 进程**会让一切变慢/看似卡死（exp2 soc_top 综合曾异常退出仍空转占核）。遇疑似卡住：先 `Get-Process` 或 `Get-CimInstance Win32_Process`（看命令行归属）再清理，勿直接全杀。
- `run_tb.ps1` 的 `out/` 每次清空重建；hex 由脚本自动拷贝（并行 worker 各含副本）。程序级 TB 依赖 cwd 内有 `.hex`。
- 代码风格沿用仓库既有 Verilog-2001 / PS 脚本约定；**未经要求不写注释不新增多余文件**。
- 不要提交 Vivado 运行产物（`usage_statistics_webtalk.*`、`tight_setup_hold_pins.txt`、`*.jou/log`、`vivado runs`、`.bit` 等）；`.gitignore`/`.coderabbit.yaml path_filters` 已配合。

## 5. 一句话速查（命令）

| 用途 | 命令 |
|---|---|
| 全量回归（并行） | `powershell -File src/scripts/run_tb.ps1` |
| 定向回归 | `powershell -File src/scripts/run_tb.ps1 -Case <kw>` |
| 汇编 → hex | `uv run --no-project --python 3.13.13 src/scripts/simple_asm.py <asm>` |
| PR 检查 | `gh pr checks <n>` |
| CodeRabbit 结论 | `gh api repos/StarryReverie/board/pulls/<n>/reviews --jq '.[-1].body'` |
| 合并 PR | `gh pr merge <n> --merge --delete-branch` |

## 6. AGENTS.md ↔ CLAUDE.md 约定

- `AGENTS.md` 为**唯一权威正文**，所有仓库指南内容只维护在这里；不把正文复制进 `CLAUDE.md`（避免双源失同步）。
- `CLAUDE.md` 是面向 Claude Code 的**入口文件**：它强制要求先完整读取本文件，并只摘几条硬约束速览。
- 若重命名/移动 `AGENTS.md`，需同步更新 `CLAUDE.md` 中的指向路径；内容有分歧时以 `AGENTS.md` 为准。
