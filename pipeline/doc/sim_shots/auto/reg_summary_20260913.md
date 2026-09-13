# §7 回归测试汇总（21/21）

命令：`powershell -File pipeline/src/scripts/run_tb.ps1`　日期：
20260913
　（每例 PASS/FAIL 见 `out/w*/tb_*.log`）

| 层级 | # | 用例 | 断言数 | 结果 |
|---|---|---|---|---|
| **模块单测（14）** | | | | |
| 模块单测（14） | 1 | tb_pc_reg | 11 | PASS |
| 模块单测（14） | 2 | tb_imem | 8 | PASS |
| 模块单测（14） | 3 | tb_if_id | 10 | PASS |
| 模块单测（14） | 4 | tb_decode | 42 | PASS |
| 模块单测（14） | 5 | tb_regfile | 8 | PASS |
| 模块单测（14） | 6 | tb_id_ex | 5 | PASS |
| 模块单测（14） | 7 | tb_alu | 20 | PASS |
| 模块单测（14） | 8 | tb_execute | 14 | PASS |
| 模块单测（14） | 9 | tb_ex_mem | 4 | PASS |
| 模块单测（14） | 10 | tb_dmem | 7 | PASS |
| 模块单测（14） | 11 | tb_mem_wb | 4 | PASS |
| 模块单测（14） | 12 | tb_wb | 5 | PASS |
| 模块单测（14） | 13 | tb_hazard_unit | 12 | PASS |
| 模块单测（14） | 14 | tb_pipeline_top | 3 | PASS |
| **程序级（6）** | | | | |
| 程序级（6） | 15 | tb_prog_test0 | 9 | PASS |
| 程序级（6） | 16 | tb_prog_test1 | 16 | PASS |
| 程序级（6） | 17 | tb_prog_sort | 9 | PASS |
| 程序级（6） | 18 | tb_prog_cover | 26 | PASS |
| 程序级（6） | 19 | tb_prog_hazard | 12 | PASS |
| 程序级（6） | 20 | tb_prog_demo | 15 | PASS |
| **性能（1）** | | | | |
| 性能（1） | 21 | tb_perf | 10（单档）/ 74（5 档） | PASS |

**合计：21/21 PASS**；本次运行断言数 250（含性能 5 档合计 tb_perf=74）
