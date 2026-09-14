# accwitness.asm: load-use sequence used to audit the retired L1 hypothesis
#   setup writes dmem[0]=1, dmem[4]=2 and dmem[8]=1, then performs four
#   loads from dmem[0], each immediately consumed by add x8,x8,xN.
#   The stream has no increment loop: final x8=4, x9=4 and dmem[8]=4.
#   These values match the RTL result, so this program is not a defect witness.
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
