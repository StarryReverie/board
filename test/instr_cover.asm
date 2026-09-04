# ==================================================================
# instr_cover.asm — 26 条冻结指令全覆盖（doc/isa.md v1.3）
# 运算 19：add/sub/sll/slt/sltu/xor/srl/sra/or/and + 9 条 I 型
# 传送 3 ：lui/lw/sw     控制 4：beq/bne/jal/jalr
# 期望终值：
#   x1=3 x2=5 x3=8 x4=2 x5=1 x6=7 x7=6 x8=96 x9=3
#   x10=0xFFFFFFF8 x11=0xFFFFFFFF x12=1 x13=0 x14=1 x15=0
#   x16=12 x17=19 x18=3 x19=48 x20=12 x21=3 x22=0xFFFFFFFE
#   x23=0x12345000 x24=0x12345000 x25=8（哨兵：任何被跳指令执行都会破坏）
#   dmem[0]=0x12345000
# 说明：jal/jalr 的链接值(x26/x27/x28)为地址，不作数值断言；jalr 段作为
#       结尾自旋（等同 HALT，TB 固定周期采样）。
# ==================================================================

    # ---- 运算类 R 型 + I 型 ----
    addi x1,  x0, 3            # x1 = 3
    addi x2,  x0, 5            # x2 = 5
    add  x3,  x1, x2           # 8
    sub  x4,  x2, x1           # 2
    and  x5,  x1, x2           # 1
    or   x6,  x1, x2           # 7
    xor  x7,  x1, x2           # 6
    sll  x8,  x1, x2           # 3 << 5 = 96
    srl  x9,  x8, x2           # 96 >> 5 = 3
    addi x10, x0, -8           # 0xFFFFFFF8
    sra  x11, x10, x1          # 0xFFFFFFF8 >>a 3 = 0xFFFFFFFF
    slt  x12, x10, x0          # -8 < 0 → 1
    sltu x13, x10, x0          # 无符号：0xFFFFFFF8<0 假 → 0
    slti x14, x10, 0           # 1
    sltiu x15, x10, 0          # imm 0 符号扩展后无符号比：0xFFFFFFF8<0 假 → 0
    xori x16, x1, 0xF          # 3^15 = 12
    ori  x17, x1, 0x10         # 3|16 = 19
    andi x18, x1, 0x1F         # 3&31 = 3
    slli x19, x1, 4            # 48
    srli x20, x19, 2           # 12
    srai x21, x20, 2           # 3
    srai x22, x10, 2           # -2 → 0xFFFFFFFE

    # ---- 传送类 ----
    lui  x23, 0x12345          # 0x12345000
    sw   x23, 0(x0)
    lw   x24, 0(x0)            # 0x12345000

    # ---- 控制类（流程控制 + 哨兵 x25，终值必须=8）----
    addi x25, x0, 0
    beq  x1, x1, beq_ok        # taken
    addi x25, x0, 99           # 被跳过
beq_ok:
    addi x25, x0, 7
    bne  x1, x2, bne_ok        # 3 != 5 taken
    addi x25, x0, 88           # 被跳过
bne_ok:
    jal  x26, jal_ok           # x26 = 链接值（地址，不断言）
    addi x25, x0, 77           # 被跳过
jal_ok:
    addi x25, x25, 1           # x25 = 8

    # ---- jalr 验证段：jal 链接值即 jr_mark 地址，jalr 经链接回跳自旋 ----
    # 注：jal rd 的链接值 = jal 下一条指令地址 → 令 jr_mark 紧贴 jal，
    #     使 x27 = &jr_mark，jalr 0(x27) 稳定自旋（等同停机）
    jal  x27, jr_mark          # x27 = &jr_mark
jr_mark:
    jalr x28, 0(x27)           # 跳回 jr_mark（自旋；x28 为链接值，不断言）
