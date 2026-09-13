# UART 波形资产（替代示波器）

本目录由 `UART/src/test/tb_wave_868.v` + `UART/src/scripts/run_wave868.ps1` + `UART/src/scripts/extract_frame_vcd.ps1` 生成，
用于在**不接示波器**的前提下，用仿真证据说明 UART IP 的**时序正确**。生成器与产物**都在版本库内**，随时可复现。

> 为什么需要它：21 例回归里的 `tb_uart_ip_top` 用的是 `CLKS_PER_BIT=4`（位宽 40 ns，为了跑得快），
> 也就是说 **"868" 这个真实分频值本身此前没有被仿真验证过**——分频计数器在 `baud_cnt == 867` 的比较、
> RX 内部半位计数 `HALF_TICKS`（= 868/2 = 434）这些**与分频值绑定的逻辑**，只在小参数下跑通过。
> 本资产用真实分频跑一次，把结论补上。

## 文件

| 文件 | 内容 |
|---|---|
| `uart_frame_868.txt` | 位级 ASCII 时序图 + 帧内每个跳变的相对时刻（**报告直接引用/贴图用这个**） |
| `uart_frame_868.vcd` | 一帧 8N1 的 TX 引脚波形（`timescale 1 ns`，可用 Vivado / xsim 打开；`*.vcd` 的忽略规则已对本目录开例外） |

## 实测结论（`CLKS_PER_BIT=868`，100 MHz）

| 项 | 值 |
|---|---|
| 位宽 | 868 个时钟 = 8680 ns = **8.68 µs** |
| 帧长（1 起始 + 8 数据 + 1 停止） | 86800 ns = **86.8 µs** |
| 波特率误差 | **0.0064%**（100 MHz ÷ 868 = 115207.4 bps，相对 115200） |
| 帧格式 | start=0、数据 LSB 先、stop=1（8N1，无校验） |
| 帧内跳变位置 | 全部落在整数比特边界（+0 / +2 / +3 / +4 / +6 / +7 / +8 / +9 位） |
| 覆盖的激励 | ① 写 TX 槽 0x5A 抓帧；② 注入 0x3C 帧经 RX_VALID 读回；③ 连发 23 字节横幅逐帧校验 |

## 怎么复现

```powershell
powershell -File UART/src/scripts/run_wave868.ps1        # xsim 跑一次真实分频（CLKS_PER_BIT=868），产出引脚跳变事件表
powershell -File UART/src/scripts/extract_frame_vcd.ps1  # 由事件表生成 VCD + 位级 ASCII 时序图
```

xsim 的中间产物（xsim.dir、事件表等）落在 `build/wave868/`，该目录不入库（`.gitignore`）。

## 用在哪里（报告引用）

`UART/doc/report_design.md` 的证据表里有一条"仿真时序证据（替代示波器）"，对应本目录的 `uart_frame_868.txt`。

## 说明与边界

- 本机 xsim 2019.2 的 `$dumpvars` **只写初值、不记录后续值变化**（已用一次性探针 TB 实测确认），
  因此改由 TB 侧在 `bit_tick` 拍采样引脚、记录跳变事件，再离线生成标准 VCD。
- 该仿真证明的是**时序正确**，**不能替代下板**；下板证据见 `soc/doc/board_runbook.md` 与串口验收日志。
