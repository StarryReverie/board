#=====================================================================
# create_exp1_board_proj.tcl — 生成"实验一独立上板"Vivado 工程
#   用法：vivado -mode batch -source pipeline/src/scripts/create_exp1_board_proj.tcl
#   产出：pipeline/vivado/board_exp1.xpr（与仿真工程 board.xpr 并存、互不影响）
#   前置（缺一则直接报错退出）：
#     powershell -File pipeline/src/scripts/hex_to_vh.ps1 `
#         -Hex pipeline/src/test/exp1_board_demo_rom.hex -PadBytes 512
#     → pipeline/src/test/exp1_board_demo_init.vh（入库归档；与 soc/test/console_init.vh 同约定）
#   本脚本把该 .vh **复制为 imem_init.vh** 放进工程构建目录
#   （pipeline/vivado/board_exp1_build/，随工程目录被 .gitignore 覆盖），
#   再把该目录加入 include_dirs —— 与实验二 soc 上板流程同一做法，
#   且不会因 run_tb/run_perf 清空 scripts/out/ 而失效。
#   工程口径（pipeline/doc/board_runbook.md §3）：
#     - part: xc7a100tcsg324-1（EES-338）
#     - top : exp1_board_top（不接 UART、不例化 soc/ 任何模块）
#     - 源  : pipeline/src/rtl/*.v（原位引用，含 exp1_board_top/exp1_reset_sync）
#     - 约束: pipeline/xdc/board_exp1.xdc
#     - 编译宏: IMEM_INIT_VH、IMEM_BYTES=512、DMEM_BYTES=256（+ WORDS 口径对齐实验二）
#     - include_dirs: pipeline/src（defines/*.v）、<工程构建目录>（imem_init.vh）
#   注：本脚本只清理 board_exp1.* 自身产物，不动 board.*（仿真工程）。
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
# scr = pipeline/src/scripts → src = pipeline/src → root = pipeline
set src  [file dirname $scr]
set root [file dirname $src]
set proj [file join $root vivado board_exp1]
set xdc  [file join $root xdc board_exp1.xdc]
# 注意：Tcl 不支持行内 # 注释（会被当作参数）——本文件注释一律独占一行
# vhIn: 由 hex_to_vh.ps1 生成的固化镜像（入库归档）
set vhIn [file join $src test exp1_board_demo_init.vh]
# bdDir: 工程构建目录，存放复制过来的 imem_init.vh
set bdDir [file join $root vivado board_exp1_build]
set vh   [file join $bdDir imem_init.vh]

# ---- 前置检查 ----
if {![file exists $vhIn]} {
    puts "ERROR: 缺少 $vhIn"
    puts "       请先运行: powershell -File pipeline/src/scripts/hex_to_vh.ps1 -Hex pipeline/src/test/exp1_board_demo_rom.hex -PadBytes 512"
    exit 1
}
if {![file exists $xdc]} {
    puts "ERROR: 缺少引脚约束 $xdc"
    exit 1
}

# ---- 复制固化镜像为 imem_init.vh（imem.v 内 `include "imem_init.vh" 的名字是固定的）----
file mkdir $bdDir
file copy -force $vhIn $vh
puts "EXP1_VH: $vhIn -> $vh"

# ---- 清理旧工程（idempotent；只清 board_exp1.*）----
if {[file exists $proj.xpr]} { close_project -quiet }
foreach suf {.xpr .cache .hw .ip_user_files .runs .sim} {
    file delete -force "$proj$suf"
}

# ---- 建工程 ----
create_project board_exp1 [file dirname $proj] -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

set fs_syn [get_filesets sources_1]

# ---- 设计源：pipeline/src/rtl/*.v（原位引用）----
set rtl_files {}
foreach f [glob -nocomplain -directory [file join $src rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
if {[llength $rtl_files] == 0} { puts "ERROR: pipeline/src/rtl 下没有 .v"; exit 1 }
add_files -norecurse $rtl_files

# ---- 引脚约束 ----
add_files -fileset constrs_1 -norecurse [list [string map {\\ /} $xdc]]

# ---- 顶层与编译口径 ----
set_property top exp1_board_top $fs_syn
set_property include_dirs [list [string map {\\ /} $src] [string map {\\ /} $bdDir]] $fs_syn
# imem 固化程序 + 下板存储缩容（const_define.v 的 ifndef 守卫保证此处生效）
set_property verilog_define {IMEM_INIT_VH IMEM_WORDS=128 DMEM_WORDS=64 IMEM_BYTES=512 DMEM_BYTES=256} $fs_syn

# ---- 实现时序优化 ----
# 显式保存实现策略，避免 GUI/重建工程时退回默认 phys_opt 配置。
set impl_run [get_runs impl_1]
set_property STRATEGY Performance_Explore $impl_run
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run
puts "IMPL_STRATEGY: [get_property STRATEGY $impl_run]"
puts "PHYS_OPT: enabled=[get_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $impl_run] directive=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts "POST_ROUTE_PHYS_OPT: enabled=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $impl_run] directive=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"

catch { update_compile_order -fileset sources_1 }

close_project
puts "PROJ_DONE: $proj.xpr (top=exp1_board_top, part=xc7a100tcsg324-1)"
puts "           imem_init.vh = $vh"
puts "           xdc          = $xdc"
exit
