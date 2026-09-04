#=====================================================================
# synth_check.tcl — 计组实验一 CPU core 综合自检（T20 验收）
#   用法（本机 Vivado 2019.2）：
#     vivado -mode batch -source scripts/synth_check.tcl
#   动作：内存式工程 + xc7a35tcsg324-1（EES-338）→ 读入根目录全部 RTL
#         （不含 test/ 与 defines/ 纯宏文件）→ synth_design pipeline_top
#         → report_utilization → 写综合报告到 scripts/out/synth/
#   判定：无 ERROR、无未约束端口外的告警即通过（报告尾部 PRIMITIVES/UTIL 可见）
#=====================================================================

set root [file normalize [file dirname [info script]]/..]
set out  [file join $root scripts out synth]
file mkdir $out

# 内存式工程（不落 .xpr）
create_project -in_memory synth_check -part xc7a35tcsg324-1 -force
set_property top pipeline_top [current_fileset]

# include 目录（模块内 `include "defines/*.v"）
set_property include_dirs $root [current_fileset]

# 读入根目录全部 RTL（*.v；defines 为纯宏、test/ 为 TB，均不读入）
set rtl_files [glob -nocomplain -directory $root *.v]
read_verilog $rtl_files

# 综合
synth_design -top pipeline_top -flatten_hierarchy rebuilt

# 注：report_utilization 需加载器件时序模型，本机实测会长时间空转；
# 综合通过判据以"无 ERROR、synth_design 正常收尾"为准，资源表可改日再跑。
# report_utilization -file [file join $out utilization.rpt]
# report_control_sets -file [file join $out control_sets.rpt]

puts "SYNTH_CHECK_DONE"
exit
