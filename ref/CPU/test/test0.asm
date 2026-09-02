    ori x1, x0, 0x001
    ori x2, x0, 0x002
    ori x10, x0, 0x010

    add x3, x1, x2
    sub x4, x2, x1

    sw x3, 4(x0)
    sw x4, 0(x10)

    lw x5, 4(x0)
    lw x6, 0(x10)

end:
    beq x0, x0, end
