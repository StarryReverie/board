# ==================================================================
# test1.asm — 由 ref/CPU/test/test1.asm 迁移（流水线工程）
# 覆盖: ori/add/sub/sw/lw/beq(taken/not-taken)；寄存器用 ABI 名
# 注: ori 按规范符号扩展（imm 全为正，结果不变）
#
# 预期结果:
#   t0=x5=1  tp=x4=1  t2=x7=3  s0=x8=3  s1=x9=4
#   a0=x10=0x100  a1=x11=2  a3=x13=2  a4=x14=0
#   a5=x15=0xFF  a6=x16=0x100  a7=x17=0xFE
#   mem[0x100]=3 mem[0x104]=2 mem[0x108]=0xFE
# ==================================================================
    ori  t0, zero, 1
    ori  t1, zero, 2
    ori  a0, zero, 0x0100

    add  t2, t0, t1
    sub  tp, t1, t0

    sw   t2, 0(a0)
    lw   s0, 0(a0)

    add  s1, s0, t0
    sub  a1, s1, t1

    sw   a1, 4(a0)
    lw   a3, 4(a0)

    # BEQ taken (0==0)
    ori  a4, zero, 0
    beq  zero, a4, skip1
    ori  a5, zero, 0x0BD

skip1:
    # BEQ not taken (1 != 2)
    beq  t0, t1, dead
    ori  a5, zero, 0x0FF

    add  a6, a5, t0
    sub  a7, a6, t1
    sw   a7, 8(a0)

end:
    beq  zero, zero, end

dead:
    ori  a5, zero, 0x0DE   # 不应到达
