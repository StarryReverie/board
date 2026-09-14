# accwitness.asm: accumulator self-RAW + load-use, strict unit steps
#   per iteration: x8 += dmem[0]; x8 += dmem[4]; dmem[0]++; dmem[4]++; dmem[8]++
#   dmem[0]=dmem[4]=dmem[8]=1 at entry, so every term grows by exactly 1
#   4 iterations -> second-add terms 2,3,4,5 (sum 14); final x8 = 10 + 14 = 24
#   final dmem[0]=5 dmem[4]=5 dmem[8]=5
    addi x1, x0, 1
    sw   x1, 0(x0)
    sw   x1, 4(x0)
    sw   x1, 8(x0)
    addi x8, x0, 0
    addi x1, x0, 2
    sw   x1, 4(x0)
    lw   x6, 0(x0)
    add  x8, x8, x6
    lw   x7, 0(x0)
    add  x8, x8, x7
    lw   x9, 0(x0)
    add  x8, x8, x9
    lw   x10, 0(x0)
    add  x8, x8, x10
    addi x9, x0, 0
    addi x9, x8, 0
    sw   x9, 8(x0)
halt:
    beq  x0, x0, halt
