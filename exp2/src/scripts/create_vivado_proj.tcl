#=====================================================================
# create_vivado_proj.tcl — 生成 exp2（UART SoC）Vivado 工程
#   用法：vivado -mode batch -source exp2/src/scripts/create_vivado_proj.tcl
#   产出：board/vivado/exp2/exp2.xpr（可双击打开）
#   工程口径：
#     - part: xc7a35tcsg324-1（EES-338）
#     - sources_1: exp2/src/rtl/*.v + 计组 src/rtl/*.v（soc_top 例化 pipeline_top）
#       top = soc_top
#     - sim_1: exp2/src/test/tb_*.v，top = tb_soc_full（默认）
#     - include 目录：exp2/src 与 计组 src（计组模块 `include "defines/*.v" 解析）
#     - 文件均为原位引用（不拷贝）
#   注：程序级 TB（tb_prog_*）经 $readmemh 读 .hex，GUI 直跑需把 hex 复制到
#       xsim 工作目录；推荐用 run_tb.ps1 跑仿真。
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
set src  [file dirname $scr]
set exp2 [file dirname $src]
set board [file dirname $exp2]
set coreSrc [file join $board src]
set proj [file join $board vivado exp2]

file delete -force [file dirname $proj]

create_project exp2 [file dirname $proj] -part xc7a35tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

set fs_syn [get_filesets sources_1]
set fs_sim [get_filesets sim_1]

# ---- 设计源：exp2 rtl + 计组 core rtl（原位引用）----
set rtl_files {}
foreach f [glob -nocomplain -directory [file join $src rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
foreach f [glob -nocomplain -directory [file join $coreSrc rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
    set_property top soc_top $fs_syn
}

# ---- 仿真源：exp2 TB ----
set tb_files {}
foreach f [glob -nocomplain -directory [file join $src test] tb_*.v] {
    lappend tb_files [string map {\\ /} [file normalize $f]]
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    set_property top tb_soc_full $fs_sim
    foreach f $tb_files {
        set_property used_in_synthesis false [get_files $f]
    }
}

# ---- include 目录（双根）----
set incDirs [list [string map {\\ /} $src] [string map {\\ /} $coreSrc]]
set_property include_dirs $incDirs $fs_syn
set_property include_dirs $incDirs $fs_sim

catch { update_compile_order -fileset sources_1 }
catch { update_compile_order -fileset sim_1 }

close_project
puts "PROJ_DONE: [string map {\\ /} $proj].xpr"
exit
