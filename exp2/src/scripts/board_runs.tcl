#=====================================================================
# board_runs.tcl — 一键下板构建（在 Vivado 正常的机器上执行）
#   用法（GUI 或 batch 均可）：
#     vivado -mode batch -source exp2/src/scripts/board_runs.tcl
#   动作：打开 exp2/vivado/exp2.xpr（含固件 ROM 固化 define + board.xdc 全约束）
#         → launch synth_1 → launch impl_1(-to write_bitstream) → 出 .bit
#   bit 产物：exp2/vivado/exp2.runs/impl_1/soc_top.bit
#   编程：Vivado Hardware Manager → open target → Program Device
#   已知限制（2026-09-06 实测本机）：Vivado 2019.2 在本机(Intel i9-13900HX/
#       Win)对 soc_top 规模设计在"器件/时序模型加载"阶段 CPU 空转（小设计
#       正常；in-memory/project/OOC/单线程/P 核亲和均无效）——综合出网表但
#       无法收尾，故 .bit 需在健康的 Vivado 主机执行（脚本双击/batch 即用，
#       工程已含全部源与约束，无额外准备）。
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
set src  [file dirname $scr]
set exp2 [file dirname $src]
set board [file dirname $exp2]
set xpr [file join $board exp2 vivado exp2.xpr]
if {![file exists $xpr]} {
    puts "ERROR: 缺少工程 $xpr（先跑 exp2/src/scripts/create_vivado_proj.tcl）"
    exit 1
}

open_project $xpr
set_property top soc_top [current_fileset]

# 防呆：确认固件 ROM 与 XDC 就位
set fwRom [file join $scr out fw_rom]
if {![file exists [file join $fwRom imem_init.vh]]} {
    file mkdir $fwRom
    file copy -force [file join $src test console_init.vh] [file join $fwRom imem_init.vh]
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne {100%}} {
    puts "BOARD_BUILD_FAIL_SYNTH"
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne {100%}} {
    puts "BOARD_BUILD_FAIL_IMPL"
    exit 1
}

puts "BOARD_BUILD_DONE"
puts "BIT: [file join $board exp2 vivado exp2.runs impl_1 soc_top.bit]"
exit
