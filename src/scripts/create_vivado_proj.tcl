#=====================================================================
# create_vivado_proj.tcl — 生成 Vivado 工程（计组实验一 CPU core）
#   用法：vivado -mode batch -source src/scripts/create_vivado_proj.tcl
#   产出：board/vivado/board.xpr（可双击打开）
#   工程口径：
#     - part: xc7a35tcsg324-1（EES-338）
#     - sources_1（设计源）: src/rtl/*.v，top=pipeline_top
#     - sim_1（仿真源）    : src/test/tb_*.v，top=tb_pipeline_top（默认）
#     - include_dirs = src/（模块内 `include "defines/*.v" 由此解析）
#     - 文件均为"原位引用"（不拷贝进工程，代码仍以 src/ 为准）
#   注：程序级 TB（tb_prog_*）经 $readmemh 读 .hex，GUI 直跑时需把
#       src/test/*.hex 复制到 xsim 工作目录；推荐用 run_tb.ps1 跑仿真。
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
# 路径推导：scr=src/scripts, src=board/src, root=board, proj=board/vivado/board
set src  [file dirname $scr]
set root [file dirname $src]
set proj [file join $root vivado board]

# 清理旧工程（idempotent）
if {[file exists $proj.xpr]} { close_project -quiet }
file delete -force [file dirname $proj]

# 建工程
create_project board [file dirname $proj] -part xc7a35tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

set fs_syn [get_filesets sources_1]
set fs_sim [get_filesets sim_1]

# ---- 设计源：src/rtl/*.v（原位引用）----
set rtl_files {}
foreach f [glob -nocomplain -directory [file join $src rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
    set_property top pipeline_top $fs_syn
}

# ---- 仿真源：src/test/tb_*.v ----
set tb_files {}
foreach f [glob -nocomplain -directory [file join $src test] tb_*.v] {
    lappend tb_files [string map {\\ /} [file normalize $f]]
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    set_property top tb_pipeline_top $fs_sim
    foreach f $tb_files {
        set_property used_in_synthesis false [get_files $f]
    }
}

# ---- include 目录：src/ ----
set_property include_dirs [list [string map {\\ /} $src]] $fs_syn
set_property include_dirs [list [string map {\\ /} $src]] $fs_sim

# ---- 编译顺序 ----
catch { update_compile_order -fileset sources_1 }
catch { update_compile_order -fileset sim_1 }

close_project
puts "PROJ_DONE: $proj.xpr"
exit
