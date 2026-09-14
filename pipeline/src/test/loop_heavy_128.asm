# loop_heavy: dynamic-IC load tier for perf_analysis v2.0 sec.3
# body per iteration: lw-add-sw-lw-add-sw + backward bne (taken)
#   -> 1 load-use stall + 1 branch redirect (2-slot flush) per iteration
# expected: N=8 x8=27 dmem0=9 dmem4=9 ; N=32 99/33/33 ; N=128 387/129/129
    addi x1, x0, 1
    sw   x1, 0(x0)
    addi x1, x0, 2
    sw   x1, 4(x0)
    addi x8, x0, 0
    addi x5, x0, 128
loop:
    lw   x6, 0(x0)
    add x8, x8, x6
    addi x6, x6, 1
    sw   x6, 0(x0)
    lw   x7, 4(x0)
    add x8, x8, x7
    addi x7, x7, 1
    sw   x7, 4(x0)
    addi x5, x5, -1
    bne  x5, x0, loop
halt:
    beq  x0, x0, halt