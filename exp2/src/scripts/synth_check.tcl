#=====================================================================
# synth_check.tcl — exp2（UART SoC）综合自检
#   用法：vivado -mode batch -source exp2/src/scripts/synth_check.tcl
#   动作：内存式工程 + xc7a35tcsg324-1 → 读入 exp2 rtl + 计组 core rtl
#         （include 目录 exp2/src 与计组 src）→ synth_design soc_top
#   判定：无 ERROR、synth_design 正常收尾（日志出现 Finished Synthesize）
#   注：本机 Vivado 2019.2 synth 收尾偶发 CPU 空转不退出，判据见上，可强杀。
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
set src  [file dirname $scr]
set exp2 [file dirname $src]
set board [file dirname $exp2]
set coreSrc [file join $board src]

create_project -in_memory exp2_synth -part xc7a35tcsg324-1 -force
set_property top soc_top [current_fileset]

set incDirs [list [string map {\\ /} $src] [string map {\\ /} $coreSrc]]
set_property include_dirs $incDirs [current_fileset]

set rtl_files {}
foreach f [glob -nocomplain -directory [file join $src rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
foreach f [glob -nocomplain -directory [file join $coreSrc rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
read_verilog $rtl_files

synth_design -top soc_top -flatten_hierarchy rebuilt

puts "SYNTH_CHECK_DONE"
exit
