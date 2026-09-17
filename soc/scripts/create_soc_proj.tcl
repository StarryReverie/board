#=====================================================================
# create_soc_proj.tcl — 生成实验二 SoC 的 Vivado 工程（top = soc_top）
#   用法：vivado -mode batch -source soc/scripts/create_soc_proj.tcl
#         （也可在 Vivado GUI 的 Tcl Console 里 `source` 本文件）
#   产出：soc/vivado/soc.xpr（工程目录 = soc/vivado；本脚本只清理其中
#         soc.* 自身产物，与实验一 pipeline/vivado/board_exp1.* 互不影响）
#   工程口径：
#     - part: xc7a100tcsg324-1
#         ⚠ EES-338 **实物 idcode 实测为 XC7A100T**，用户手册误标 35T；
#           必须用实测值，否则生成的 bit 烧不进实物。
#     - sources_1: UART/src/rtl/*.v + pipeline/src/rtl/*.v + soc/rtl/*.v
#       （均为原位引用），top = soc_top（例化 pipeline_top 与 uart_ip_top）
#     - sim_1: UART/src/test/tb_*.v + soc/test/tb_*.v，top = tb_soc_full（默认）
#     - include 目录：UART/src、pipeline/src（计组模块 `include "defines/*.v"
#       由此解析）与 soc/vivado/soc_build（固件 ROM imem_init.vh）
#     - verilog_define: IMEM_INIT_VH + 存储缩容（IMEM_WORDS=128=512B、
#       DMEM_WORDS=64=256B、IMEM_BYTES=512、DMEM_BYTES=256——组合读寄存器
#       阵列的容量约束见 pipeline/src/defines/const_define.v 头注）
#     - constrs_1: soc/xdc/board.xdc（T5 clk 100 MHz / T4 uart_tx /
#       N5 uart_rx / P15 rst_n）
#   固件固化：把 soc/test/console_init.vh 复制成 soc/vivado/soc_build/imem_init.vh
#     （imem.v 硬编码 include 该文件名）。要换固件：先跑
#     UART/src/scripts/build_fw.ps1 重生成 console_init.vh，再重跑本脚本。
#   本脚本**只建工程**（不综合、不出 bit）：之后在 GUI 里
#     Run Synthesis → Run Implementation → Generate Bitstream，
#     产物 soc/vivado/soc.runs/impl_1/soc_top.bit。
#   注：程序级 TB 经 $readmemh 读 .hex，GUI 直跑需把 hex 复制到 xsim 工作目录；
#       推荐用 pipeline/src/scripts/run_tb.ps1 跑仿真（自动拷贝）。
#   变更：2026-09-15 由 UART/src/scripts/create_vivado_proj.tcl 迁移而来，
#         落点由 UART/vivado/exp2.xpr 统一为 soc/vivado/soc.xpr（口径不变），
#         固件副本由 UART/src/scripts/out/fw_rom/ 改放工程内 soc_build/。
#=====================================================================

set scr    [file dirname [file normalize [info script]]]
set socDir [file dirname $scr]
set board  [file dirname $socDir]
set uartSrc [file join $board UART     src]
set coreSrc [file join $board pipeline src]
set fwRom   [file join $socDir vivado soc_build]
set proj    [file join $socDir vivado soc]

# 清理旧工程（idempotent；只清 soc/vivado 下 soc.*，与 exp1 的 pipeline/vivado 互不影响）
foreach suf {.xpr .cache .hw .ip_user_files .runs .sim} {
    file delete -force "$proj$suf"
}

# 建工程（soc/vivado/ 内生成 soc.xpr 及产物）
create_project soc [file dirname $proj] -part xc7a100tcsg324-1 -force
set_property target_language    Verilog [current_project]
set_property simulator_language Verilog [current_project]

set fs_syn [get_filesets sources_1]
set fs_sim [get_filesets sim_1]

# ---- 设计源：UART rtl + 计组 core rtl + SoC 集成 rtl（原位引用）----
set rtl_files {}
foreach d [list [file join $uartSrc rtl] [file join $coreSrc rtl] [file join $socDir rtl]] {
    foreach f [glob -nocomplain -directory $d *.v] {
        lappend rtl_files [string map {\\ /} [file normalize $f]]
    }
}
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
    set_property top soc_top $fs_syn
}

# ---- 仿真源：UART TB + SoC TB（不参与综合）----
set tb_files {}
foreach d [list [file join $uartSrc test] [file join $socDir test]] {
    foreach f [glob -nocomplain -directory $d tb_*.v] {
        lappend tb_files [string map {\\ /} [file normalize $f]]
    }
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    set_property top tb_soc_full $fs_sim
    foreach f $tb_files {
        set_property used_in_synthesis false [get_files $f]
    }
}

# ---- include 目录（两个源码根 + 固件 ROM 目录）----
file mkdir $fwRom
set fwSrc [file join $socDir test console_init.vh]
if {[file exists $fwSrc]} {
    file copy -force $fwSrc [file join $fwRom imem_init.vh]
} else {
    puts "WARN: 未找到固件源 $fwSrc —— 请先跑 UART/src/scripts/build_fw.ps1 生成"
}
set incDirs [list [string map {\\ /} $uartSrc] [string map {\\ /} $coreSrc] [string map {\\ /} $fwRom]]
set_property include_dirs $incDirs $fs_syn
set_property include_dirs $incDirs $fs_sim
set_property verilog_define {IMEM_INIT_VH IMEM_WORDS=128 DMEM_WORDS=64 IMEM_BYTES=512 DMEM_BYTES=256} $fs_syn

# ---- 实现时序优化 ----
# 与实验一保持相同的实现口径，且在重建工程后仍然生效。
set impl_run [get_runs impl_1]
set_property STRATEGY Performance_Explore $impl_run
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run
puts "IMPL_STRATEGY: [get_property STRATEGY $impl_run]"
puts "PHYS_OPT: enabled=[get_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $impl_run] directive=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts "POST_ROUTE_PHYS_OPT: enabled=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $impl_run] directive=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"

# ---- 板级约束（U32）：soc/xdc/board.xdc ----
set xdc [file join $socDir xdc board.xdc]
if {[file exists $xdc]} {
    add_files -fileset constrs_1 -norecurse [string map {\\ /} [file normalize $xdc]]
} else {
    puts "WARN: 未找到约束 $xdc"
}

catch { update_compile_order -fileset sources_1 }
catch { update_compile_order -fileset sim_1 }

# ---- 口径摘要（供人工核对）----
puts "SOCPROJ_XPR:      [string map {\\ /} $proj].xpr"
puts "SOCPROJ_PART:     [get_property part [current_project]]"
puts "SOCPROJ_TOP:      [get_property top [get_filesets sources_1]]"
puts "SOCPROJ_SIMTOP:   [get_property top [get_filesets sim_1]]"
puts "SOCPROJ_DEFINE:   [get_property verilog_define [get_filesets sources_1]]"
puts "SOCPROJ_INCDIR:   [get_property include_dirs [get_filesets sources_1]]"
puts "SOCPROJ_CONSTR:   [get_files -of [get_filesets constrs_1]]"
puts "SOCPROJ_COUNT:    sources=[llength [get_files -of [get_filesets sources_1]]] sim=[llength [get_files -of [get_filesets sim_1]]] constrs=[llength [get_files -of [get_filesets constrs_1]]]"
puts "SOCPROJ_FWROM:    [file join $fwRom imem_init.vh] exists=[file exists [file join $fwRom imem_init.vh]]"
puts "SOCPROJ_DONE"

close_project -quiet
