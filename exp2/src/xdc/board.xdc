#=============================================================================
# board.xdc — EES-338（依元素口袋计算机, XC7A35T-1CSG324C）板级约束
#   依据：E:\Homework\26-27-1\EES-338_UserManual_v1.0.pdf（2026-09-06 核验）
#     §4  系统时钟：100 MHz 晶振 → FPGA 全局时钟脚 T5（SYS_CLK）
#     §6.1 复位键：FPGA_RESET → P15（S8/S6=RST、S7/S5=PROG；专用按键，
#          手册未明示电平极性——假设"低有效、按下复位"（上拉，见下），
#          上板首测第 0 步验证：松键应运行、按键应复位；若相反（按下=高）
#          则将 soc_top 的 rst_n 改为经反相后接入（fallback 方案已记录）
#     §9  串口：CP2102 USB-UART —— CP2102.UART_RX → T4（=FPGA 串口发送端）、
#          CP2102.UART_TX → N5（=FPGA 串口接收端）；8N1、1 停止位、无校验
#   I/O 标准：LVCMOS33（依元素板惯例 + 同校 24-25-2 数字逻辑工程实证：
#         clk=T5 配 LVCMOS33 与本节一致）
#   构建：见 exp2/src/scripts/synth_check.tcl / create_vivado_proj.tcl
#=============================================================================

# ---- 时钟：100 MHz ----
create_clock -period 10.000 -name sys_clk [get_ports clk]

# ---- clk：T5（晶振输入）----
set_property PACKAGE_PIN T5      [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]

# ---- rst_n：P15（FPGA_RESET 按键，低有效；上拉防浮空）----
set_property PACKAGE_PIN P15     [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]
set_property PULLUP      true     [get_ports rst_n]

# ---- uart_tx_pin：T4（CPU→PC，板载 CP2102 RXD）----
set_property PACKAGE_PIN T4      [get_ports uart_tx_pin]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx_pin]

# ---- uart_rx_pin：N5（PC→CPU，板载 CP2102 TXD）----
set_property PACKAGE_PIN N5      [get_ports uart_rx_pin]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_rx_pin]

# 下板自查清单（tasks.md §3.1）：
#   0) 配置：JTAG/SPI 烧 .bit 后 D24 点亮；复位极性首测——松键=运行（见 banner），
#      按键=复位重跑；若极性相反走 fallback（header 说明）
#   1) 裸 UART 先行（临时顶层发 0x55 → 终端收 'U' 无乱码）
#   2) 烧 console 固件 → 终端 115200-8-N-1 见 banner、键盘逐字回显、按 P15 重跑
#   3) 证据：终端日志 + 示波器 TX 波形（空闲高/起始低/位宽≈8.68us/10 位≈86.8us）
