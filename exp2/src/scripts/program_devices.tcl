#=====================================================================
# program_devices.tcl — 批处理烧录 .bit 到 EES-338（XC7A35T）
#   用法：
#     vivado -mode batch -source program_devices.tcl -tclargs <bit 路径>
#   无参时自动寻找 exp2/vivado/exp2.runs/impl_1/soc_top.bit（仓库内）
#   成功打印 PROGRAM_DONE；找不到板打印可用目标/设备清单并报错
#=====================================================================

set scr  [file dirname [file normalize [info script]]]
set src  [file dirname $scr]
set exp2 [file dirname $src]
set board [file dirname $exp2]

# ---- bit 路径：优先 -tclargs，其次工程默认产物 ----
set bitFile ""
if {$argc >= 1} {
    set bitFile [lindex $argv 0]
} else {
    set cand [file join $board exp2 vivado exp2.runs impl_1 soc_top.bit]
    if {[file exists $cand]} { set bitFile $cand }
}
if {$bitFile eq "" || ![file exists $bitFile]} {
    puts "ERROR: 未找到 .bit（用法: ... -tclargs <bit 路径>）"
    exit 1
}

open_hw_manager
connect_hw_server

if {[llength [get_hw_targets]] == 0} {
    puts "ERROR: 未发现 JTAG 目标（检查 USB-JTAG 线与驱动）"
    exit 1
}
open_hw_target [lindex [get_hw_targets] 0]

if {[llength [get_hw_devices]] == 0} {
    puts "ERROR: 目标上未发现器件"
    exit 1
}
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE [string map {\\ /} $bitFile] [current_hw_device]
program_hw_devices
puts "PROGRAM_DONE: $bitFile"
exit
