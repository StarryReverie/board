# ==================================================================
# fwd_priority.asm — 前递优先级定向场景（EX/MEM 双命中优先于 MEM/WB）
#   I1 addi x11, x0, 1     写 x11=1
#   I2 addi x11, x0, 2     同址连写 x11=2（背靠背）
#   I3 add  x12, x11, x0   I3 在 EX 时：I2 在 EX/MEM、I1 在 MEM/WB
#                          两处 rd 均为 x11 → 双命中，正确取 EX/MEM
#                          故 x12=2；若误取 MEM/WB 则 x12=1
#   I4 add  x13, x11, x11  I4 在 EX 时 I2 在 MEM/WB → 单命中取 2 → x13=4
#   I5 addi x14, x0, 0     x14=0
# 期望终值：x11=2 x12=2 x13=4 x14=0
# ==================================================================
    addi x11, x0, 1
    addi x11, x0, 2
    add  x12, x11, x0
    add  x13, x11, x11
    addi x14, x0, 0

halt:
    beq  x0, x0, halt
