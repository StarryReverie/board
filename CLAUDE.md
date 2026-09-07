# CLAUDE.md — 仓库指南入口（必读）

> **本文件只是入口，不含正文。** 开始任何任务前，**必须完整读取本仓库根的 `AGENTS.md`**——
> 它是唯一权威的仓库指南（结构与单源文档、环境与工具、测试口径、GitHub/CodeRabbit 自动化流程、本机坑）。
> 本文件只保留几条最容易被忽略的硬约束，避免与 AGENTS.md 重复维护导致失同步。

## 硬约束速览（详见 AGENTS.md）

1. **先读文档再动代码**：涉及功能/结构先看 `AGENTS.md` §0 列出的文档（`doc/*`、`exp2/doc/*`、`SUBMISSION.md`）；修改设计语义先改文档单源。
2. **分支一律基于 `dev`，PR 指向 `dev`**；review 由 CodeRabbit 自动做（`.coderabbit.yaml`）。
3. **测试**：`powershell -File src/scripts/run_tb.ps1`（并行、默认满核、全量 ~20-30s）。迭代可用 `-Case <kw>` 定向；**最终提交前跑一次全量**。
4. **汇编**：本机无 GNU riscv 工具链，用
   `uv run --no-project --python 3.13.13 src/scripts/simple_asm.py <asm>`
5. **不要提交** Vivado 运行产物；跑脚本**直接看流式输出**（勿 `Select-Object -Last` 截流）；搜索用 `rg`/`fd`。

> 若本文件与 `AGENTS.md` 冲突，**以 `AGENTS.md` 为准**；改动口径同步到 AGENTS.md 即可，本文件不再复制正文。
