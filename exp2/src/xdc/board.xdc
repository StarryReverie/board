#=============================================================================
# board.xdc — EES-338（依元素口袋计算机, XC7A35T-1CSG324C）板级约束
#   用途：U32 下板（soc_top：clk/rst_n/uart_tx_pin/uart_rx_pin）
#   时钟：100 MHz 晶振 T5；复位：FPGA_RESET 按键 P15（低有效，经 reset_sync
#         异步置位/同步释放为内部高有效 rst）
#   串口：uart_tx T4（板载 USB-UART RX）、uart_rx N5（板载 USB-UART TX）
#   注：I/O 标准按 EES-338 手册（LVCMOS33，bank 3.3V）；若与厂家 demo XDC
#       不一致，以实测/demo 为准修改（见 exp2/doc/tasks.md §3.1 下板流程）
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
#   1) 裸 UART 先行（临时顶层发 0x55 → 终端收 'U' 无乱码）
#   2) 烧 console 固件 → 终端 115200-8-N-1 见 banner、键盘逐字回显、按 P15 重跑
#   3) 证据：终端日志 + 示波器 TX 波形（空闲高/起始低/位宽≈8.68us/10 位≈86.8us）
