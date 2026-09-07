# ==================================================================
# demo.asm — 简易演示样例（由 src/scripts/simple_asm.py 自产 .hex）
# 指令集口径：doc/isa.md（26 条冻结 + isa §3 伪指令白名单）
# 功能：把 5,4,3,2,1 递减写入 dmem[0x40..0x50]，每写一个就地 lw 读回并累加，
#       结果存 dmem[0]，最后 beq 自循环 HALT。
# 演示点：add/sub（RAW 前递）、sw→lw 同址往返、lw 后紧邻 add（load-use 恰 1 气泡）、
#         bne 循环 taken×4 + 末次 not-taken 出口、beq 自环（HALT）。
# 期望终值：x10(a0)=15  x5(t0)=0  x8(s0)=0x54  x6(t1)=4  x7(t2)=1  x28(t3)=1
#           mem[0]=15、mem[0x40..0x50]={5,4,3,2,1}（字，小端）
# ==================================================================
    addi s0, x0, 0x40        # s0 = 数据区基址 0x40
    addi a0, x0, 0           # a0 = 累加和 = 0
    addi t0, x0, 5           # t0 = 循环计数 = 5
    addi t1, x0, 4           # t1 = 步长 4（下一元素偏移）
    addi t2, x0, 1           # t2 = 递减 1
loop:
    sw   t0, 0(s0)           # dmem[s0] = t0（5..1）
    lw   t3, 0(s0)           # t3 = 读回（下句 add 即 load-use）
    add  a0, a0, t3          # 累加
    add  s0, s0, t1          # 基址 += 4
    sub  t0, t0, t2          # 计数 -= 1
    bne  t0, x0, loop        # t0≠0 → 循环
    sw   a0, 0(x0)           # mem[0] = 15
halt:
    beq  x0, x0, halt        # HALT 自循环（isa §4 停机约定）
