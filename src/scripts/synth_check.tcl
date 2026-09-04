#=====================================================================
# synth_check.tcl — 计组实验一 CPU core 综合自检（T20 验收）
#   用法（本机 Vivado 2019.2）：
#     vivado -mode batch -source scripts/synth_check.tcl
#   动作：内存式工程 + xc7a35tcsg324-1（EES-338）→ 读入 rtl/ 全部 RTL
#         （defines/ 纯宏以 include_dirs 引入；test/ 为 TB 不读入）
#         → synth_design pipeline_top
#   判定：无 ERROR、synth_design 正常收尾即通过
#   注：include_dirs=仓库根，模块内 `include "defines/*.v" 由此解析
#=====================================================================

set root [file normalize [file dirname [info script]]/..]
set out  [file join $root scripts out synth]
file mkdir $out

# 内存式工程（不落 .xpr）
create_project -in_memory synth_check -part xc7a35tcsg324-1 -force
set_property top pipeline_top [current_fileset]

# include 目录（模块内 `include "defines/*.v"）
set_property include_dirs $root [current_fileset]

# 读入 rtl/ 全部 RTL（*.v）
set rtl_files [glob -nocomplain -directory [file join $root rtl] *.v]
read_verilog $rtl_files

# 综合
# 注：本机 Vivado 2019.2 在 synth_design 收尾（teardown）阶段偶发 CPU 空转、
#     进程不退出——以日志出现 "Finished Synthesize" 且无 ERROR 为通过判据，
#     空转时手动终止进程即可，不影响结果。
synth_design -top pipeline_top -flatten_hierarchy rebuilt

# 注：report_utilization 需加载器件时序模型，本机实测会长时间空转；
# 综合通过判据以"无 ERROR、synth_design 正常收尾"为准，资源表可改日再跑。
# report_utilization -file [file join $out utilization.rpt]
# report_control_sets -file [file join $out control_sets.rpt]

puts "SYNTH_CHECK_DONE"
exit
