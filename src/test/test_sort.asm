# ==================================================================
# test_sort.asm — 冒泡排序，由 ref/CPU/test/test_sort.asm 迁移（流水线工程）
# 数据 [4,2,5,1,3] 自初始化于 RAM 0x200，排序为 [1,2,3,4,5]
# 注: 比较技巧依赖 ori 立即数 0x7FF（正数，符号/零扩展结果一致，可迁移）
#
# 预期: mem[0x200..0x210] = 1,2,3,4,5（小端字）
#       t1=x6=4（外循环终值）s0=x8=4 s1=x9=1 t0=x5=0x200
# ==================================================================
    ori  t0, zero, 0x200

    ori  t1, zero, 4
    sw   t1, 0(t0)
    ori  t1, zero, 2
    sw   t1, 4(t0)
    ori  t1, zero, 5
    sw   t1, 8(t0)
    ori  t1, zero, 1
    sw   t1, 12(t0)
    ori  t1, zero, 3
    sw   t1, 16(t0)

    ori  s3, zero, 0x7FF
    ori  s0, zero, 4
    ori  s1, zero, 1
    ori  t1, zero, 0

outer:
    beq  t1, s0, done

    ori  t2, zero, 0
    sub  s2, s0, t1

inner:
    beq  t2, s2, next_i

    add  t3, t2, t2
    add  t3, t3, t3
    add  t4, t0, t3

    lw   t5, 0(t4)
    lw   t6, 4(t4)

    sub  t3, t6, t5
    ori  t3, t3, 0x7FF
    add  t3, t3, s1
    beq  t3, zero, do_swap
    beq  zero, zero, no_swap

do_swap:
    sw   t6, 0(t4)
    sw   t5, 4(t4)

no_swap:
    add  t2, t2, s1
    beq  zero, zero, inner

next_i:
    add  t1, t1, s1
    beq  zero, zero, outer

done:
    beq  zero, zero, done
