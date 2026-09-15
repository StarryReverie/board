#=============================================================================
# board_exp1.xdc — 实验一独立上板约束（exp1_board_top，不含 UART/SoC）
#   依据：E:\Homework\26-27-1\EES-338_UserManual_v1.0.pdf（文本版 ees338_manual.txt）
#     §4    系统时钟：100 MHz 晶振 → FPGA 全局时钟脚 T5（SYS_CLK）
#     §6.1  复位键：FPGA_RESET → P15（专用按键；手册未明示极性——
#           与实验二同口径假设"低有效、按下复位"并加上拉，上板首测第 0 步验证；
#           若实测相反，把 exp1_board_top 的 rst_n 前加一级反相即可）
#     §6.3  LED 灯：FPGA 输出**高电平点亮**；LED0-3 绿、LED4-7 黄
#             LED0=K2  LED1=J2  LED2=J3  LED3=H4  LED4=J4  LED5=G3  LED6=G4  LED7=F6
#     §6.4  七段数码管：**共阴极**，段选与位选都由 FPGA 给**高电平**才点亮
#             段选组0（LED0_CA..DP0）：A=B4 B=A4 C=A3 D=B1 E=A1 F=B3 G=B2 DP=D5
#             段选组1（LED1_CA..DP1）：A=D4 B=E3 C=D3 D=F4 E=F3 F=E2 G=D2 DP=H2
#             位选（LED_BIT1..8）   ：G2 C2 C1 H1 G1 F1 E1 G6
#           注：手册给的是"两组段选 + 8 位位选"，故本组按"组0 驱 LED_BIT1..4、
#               组1 驱 LED_BIT5..8"接线（DN0/DN1 两块 4 位数码管）。exp1_board_top
#               对两组段选输出同一图案（任一时刻只有一位被选中），因此
#               **即使两组的位序在实物上与推断相反，显示内容仍然正确**。
#   I/O 标准：LVCMOS33（依元素板惯例；与 soc/xdc/board.xdc 同口径）
#   端口 ↔ 信号对应见 pipeline/doc/modules/pipeline_top.md 与
#     pipeline/doc/board_runbook.md §2
#=============================================================================

# ---- 时钟：100 MHz（T5）----
#   时序现状（2026-09-15 实测，**保留约束、不放宽**）：
#     create_clock 10.000 ns 下 post-route WNS = −1.239 ns（构建 A，2026-09-14）
#     / −1.468 ns（构建 B，2026-09-15，自检加固固件），Fmax ≈ 89 / 87 MHz；
#     实现状态均为 "route_design Complete, Failed Timing!"（不阻塞 write_bitstream）。
#     违例端点**全部位于核心内部**：实测最差 200 条路径终点均为 u_cpu/u_id_ex、
#     u_cpu/u_pc_reg、u_cpu/u_if_id，本文件的板级逻辑（LED/数码管/复位同步）零贡献。
#   处置：**不放宽 create_clock 周期** —— 板上晶振就是 100 MHz，改周期只会掩盖问题；
#     修复路径（核心侧改可推断 BRAM / 加全局时钟使能并按 20 ns 生成派生时钟）与
#     已知缺口的完整记录见 pipeline/doc/board_runbook.md §3.3，实板功能验收见 §10。
create_clock -period 10.000 -name sys_clk [get_ports clk]

set_property PACKAGE_PIN T5       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]

# ---- 复位键：P15（低有效；上拉防浮空）----
set_property PACKAGE_PIN P15      [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]
set_property PULLUP      true     [get_ports rst_n]

# ---- LED[7:0]（高电平点亮）----
set_property PACKAGE_PIN K2       [get_ports {led[0]}]
set_property PACKAGE_PIN J2       [get_ports {led[1]}]
set_property PACKAGE_PIN J3       [get_ports {led[2]}]
set_property PACKAGE_PIN H4       [get_ports {led[3]}]
set_property PACKAGE_PIN J4       [get_ports {led[4]}]
set_property PACKAGE_PIN G3       [get_ports {led[5]}]
set_property PACKAGE_PIN G4       [get_ports {led[6]}]
set_property PACKAGE_PIN F6       [get_ports {led[7]}]
# 注：XDC 不支持 foreach 等控制命令（Vivado 报 Designutils 20-1307），故逐条显式书写
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

# ---- 数码管段选组0 seg0[7:0] = {DP,G,F,E,D,C,B,A}（高有效）----
set_property PACKAGE_PIN B4       [get_ports {seg0[0]}]   ;# A
set_property PACKAGE_PIN A4       [get_ports {seg0[1]}]   ;# B
set_property PACKAGE_PIN A3       [get_ports {seg0[2]}]   ;# C
set_property PACKAGE_PIN B1       [get_ports {seg0[3]}]   ;# D
set_property PACKAGE_PIN A1       [get_ports {seg0[4]}]   ;# E
set_property PACKAGE_PIN B3       [get_ports {seg0[5]}]   ;# F
set_property PACKAGE_PIN B2       [get_ports {seg0[6]}]   ;# G
set_property PACKAGE_PIN D5       [get_ports {seg0[7]}]   ;# DP（本设计不用，恒 0）
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg0[7]}]

# ---- 数码管段选组1 seg1[7:0] = {DP,G,F,E,D,C,B,A}（高有效）----
set_property PACKAGE_PIN D4       [get_ports {seg1[0]}]   ;# A
set_property PACKAGE_PIN E3       [get_ports {seg1[1]}]   ;# B
set_property PACKAGE_PIN D3       [get_ports {seg1[2]}]   ;# C
set_property PACKAGE_PIN F4       [get_ports {seg1[3]}]   ;# D
set_property PACKAGE_PIN F3       [get_ports {seg1[4]}]   ;# E
set_property PACKAGE_PIN E2       [get_ports {seg1[5]}]   ;# F
set_property PACKAGE_PIN D2       [get_ports {seg1[6]}]   ;# G
set_property PACKAGE_PIN H2       [get_ports {seg1[7]}]   ;# DP（本设计不用，恒 0）
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg1[7]}]

# ---- 数码管位选 an[7:0] = LED_BIT1..8（高有效，one-hot）----
set_property PACKAGE_PIN G2       [get_ports {an[0]}]     ;# LED_BIT1（DN0 第1位）
set_property PACKAGE_PIN C2       [get_ports {an[1]}]     ;# LED_BIT2
set_property PACKAGE_PIN C1       [get_ports {an[2]}]     ;# LED_BIT3
set_property PACKAGE_PIN H1       [get_ports {an[3]}]     ;# LED_BIT4
set_property PACKAGE_PIN G1       [get_ports {an[4]}]     ;# LED_BIT5（DN1 第1位）
set_property PACKAGE_PIN F1       [get_ports {an[5]}]     ;# LED_BIT6
set_property PACKAGE_PIN E1       [get_ports {an[6]}]     ;# LED_BIT7
set_property PACKAGE_PIN G6       [get_ports {an[7]}]     ;# LED_BIT8
set_property IOSTANDARD LVCMOS33 [get_ports {an[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[7]}]

#-----------------------------------------------------------------------------
# 上板自查清单（board_runbook.md §5）：
#   0) 烧录后 D24（配置成功灯）点亮；按键极性首测——松键=运行、按键=复位重跑
#   1) LED0 心跳（约 0.5 s 翻转）→ 时钟/供电/烧录正常
#   2) 松键瞬间 LED1 亮（复位释放）→ 复位同步器工作
#   3) LED2 亮（CPU 已取指）→ 程序自跑
#   4) LED3/LED4/LED5 亮 → load-use 停顿 / 分支重定向 / dmem 写入均被观测到
#   5) 数码管稳定显示 0000000F（DN0 低四位即 000F），LED6（PASS）亮、LED7 灭
#   6) 反复按键复位 ≥3 次，结果稳定复现
#-----------------------------------------------------------------------------
