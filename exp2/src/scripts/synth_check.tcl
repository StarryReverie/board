#=====================================================================
# synth_check.tcl — exp2（UART SoC）综合自检（含固件固化 + XDC 校验）
#   用法：vivado -mode batch -source exp2/src/scripts/synth_check.tcl
#   动作：内存式工程 + xc7a100tcsg324-1 → 读入 exp2 rtl + 计组 core rtl
#         （include：exp2/src、计组 src、固件 ROM 目录 out/fw_rom）
#         → verilog_define IMEM_INIT_VH（启用 imem.v 的 initial 装载）
#         → synth_design soc_top（不含 XDC——create_clock 触发时序引擎
#           加载，本机 Vivado 2019.2 在此空转；时序/实现留综合侧执行，
#           XDC 语法经 read_xdc 单独校验过（board.xdc 解析无 ERROR））
#   固件：console_init.vh（U40 产物）→ out/fw_rom/imem_init.vh（imem.v
#         硬编码 include 名），综合期固化于 IMEM、上电自跑（PC=0）
#   判定：无 ERROR、synth_design 正常收尾（日志出现 Finished Synthesize）
#   注：本机 Vivado 2019.2 synth 收尾偶发 CPU 空转不退出，判据见上，可强杀。
#=====================================================================

set scr   [file dirname [file normalize [info script]]]
set src   [file dirname $scr]
set exp2  [file dirname $src]
set board [file dirname $exp2]
set coreSrc [file join $board src]

# ---- 固件 ROM：console_init.vh → out/fw_rom/imem_init.vh ----
set fwRom  [file join $scr out fw_rom]
file mkdir $fwRom
set initVh [file join $src test console_init.vh]
if {![file exists $initVh]} {
    puts "ERROR: 缺少固件镜像 $initVh（先跑 build_fw.ps1）"
    exit 1
}
file copy -force $initVh [file join $fwRom imem_init.vh]

create_project -in_memory exp2_synth -part xc7a100tcsg324-1 -force
set_property top soc_top [current_fileset]

set incDirs [list [string map {\\ /} $src] [string map {\\ /} $coreSrc] [string map {\\ /} $fwRom]]
set_property include_dirs $incDirs [current_fileset]
set_property verilog_define {IMEM_INIT_VH IMEM_WORDS=128 DMEM_WORDS=64 IMEM_BYTES=512 DMEM_BYTES=256} [current_fileset]

set rtl_files {}
foreach f [glob -nocomplain -directory [file join $src rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
foreach f [glob -nocomplain -directory [file join $coreSrc rtl] *.v] {
    lappend rtl_files [string map {\\ /} [file normalize $f]]
}
read_verilog $rtl_files

# 注：board.xdc 的完整校验（引脚绑定+时序）在综合侧随实现跑；
#     本机仅做固件固化综合自检（XDC 已单独 read_xdc 解析验证无 ERROR）。
synth_design -top soc_top -flatten_hierarchy rebuilt

puts "SYNTH_CHECK_DONE"
exit
