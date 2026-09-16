# sim_shots/exp2 — 实验二仿真截图与波形配置归档

实验二（UART 接口控制器 IP + SoC 集成）四项关键仿真的**人工截图**、**波形配置**与**运行日志**归档，
对应 `soc/doc/实验二仿真补齐清单.md`。截图由队友在 Vivado 2019.2 中按预置 `wcfg` 打开波形库截取。

## 目录内容

| 路径 | 内容 | 入库 |
|---|---|---|
| `*.png` | 13 张人工截图，命名 `<项号>_<名称>_<日期>.png` | 是 |
| `wcfg/*.wcfg` | 13 个预置波形配置（信号表、缩放窗口、游标、标记） | 是（对 `*.wcfg` 忽略规则开例外） |
| `logs/*.log` `logs/*.txt` | 四项波形仿真 xsim 日志、8/8 回归证据、每字节耗时折算 | 是（对 `*.log` 忽略规则开例外） |
| `wdb/*.wdb` | 波形库（xsim 产出，含完整跳变） | 否（`*.wdb` 忽略；由 `run_exp2_wave.ps1` 重新生成） |

## 截图清单

| 文件 | 项 | 内容 |
|---|---|---|
| `1_frame868_20260915.png` | 1 | 8N1 帧位时序（8680 ns/位、86800 ns/帧、跳变在比特边界） |
| `2a_rx_in_tolerance_20260915.png` | 2 | 注入 860/876 clk 偏移仍正确（`valid=1`，0x3C / 0xA5） |
| `2b_rx_glitch_rejected_20260915.png` | 2 | 短毛刺在起始位中心复检处被拒，无 `valid` |
| `2c_rx_badstop_discarded_20260915.png` | 2 | 停止位=0 判帧错误，整帧丢弃 |
| `2d_rx_off_30pct_wrong_20260915.png` | 2 | 注入 607 clk（−30%）给出错字节 0xFE |
| `3a_duplex_overlap_20260915.png` | 3 | 全双工同现：`tx_busy=1` 且 `rx_valid=1`（`STAT=2'b11`） |
| `3b_busy_write_dropped_20260915.png` | 3 | 移位期写被丢弃，停止位后 12 bit 内无第二帧 |
| `3c_putc_consecutive_20260915.png` | 3 | 连续三次 putc 三帧首尾相接、不丢字 |
| `4a_mmio_stat_poll_sw_tx_20260915.png` | 4 | STAT 读轮询 + `sw` 写 TX=0x41，窗口基址 0x0000_4000 |
| `4b_tx_frame_0x41_20260915.png` | 4 | 写 TX 后出 8N1 帧 0x41（缺截图，wcfg 已备） |
| `4c_mmio_rx_read_sw_echo_20260915.png` | 4 | 注入 0x42 → `lw` RX 槽读回 0x42 → 写 TX 回显 |
| `4d_echo_frame_0x42_20260915.png` | 4 | 回显帧 0x42 的位形，监视器独立解码一致 |
| `4e_full_chain_overview_20260915.png` | 4 | 全链路总览（轮询→写→出帧→注入→读→回显） |

## 复现

```powershell
powershell -File UART/src/scripts/run_exp2_wave.ps1            # 重生成第 3/4 项波形库与逐拍 CSV
powershell -File UART/src/scripts/run_exp2_wave.ps1 -Item 3     # 只重跑第 3 项
```

波形库（`wdb/`）与 `run_exp2_wave.ps1` 的中间产物落在 `build/`，不入库。
`wcfg` 由队友工作区导出，其中 `db_ref` 记录的是导出机的绝对路径，换机后需按实际路径重新生成或在 Vivado 中重新指定波形库。

## 说明与边界

- 第 2 项第 6 个场景（−30% 偏移）的结论是**会给出错字节**，不是"判无效丢弃"；UART 收端能可靠判废的是短毛刺与停止位错误。此条按实测写入，报告与 PPT 均按此口径。
- 截图证明的是**仿真时序与功能正确**，不替代下板；下板记录见 `soc/doc/board_runbook.md`。
