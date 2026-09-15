# ==================================================================
# exp1_board_demo.asm — 实验一独立上板验收程序（固化进 imem）
#   用途：作为 imem_init.vh 的程序源，上板后 CPU 自跑；板级监视器
#         （pipeline/src/rtl/exp1_board_top.v）检测到 dmem[0] 被写入
#         0x0000000F 且 CPU 进入 HALT 自循环后锁存 PASS（LED6）。
#   覆盖：ALU 全类（add/sub/and/or/xor/slt/sltu/lui/slli/srli/srai）、
#         EX/MEM 与 MEM/WB 前递（背靠背 RAW）、sw→lw 同址往返、
#         lw 后紧邻 add（load-use 恰 1 气泡）、bne 循环（taken×4 +
#         末次 not-taken 出口，含分支冲刷）、beq 自循环 HALT。
#   自检：阶段5 把**每一项**声明的中间结果都与期望值异或，失配标志或进
#         累积器 x31；只有 x31 == 0（全部相符）才把 0x0F 写入 dmem[0]，
#         任一项错误则写入 0 → 板上不出现 PASS。
#         即：0x0F 是"全部覆盖项均正确"的结果，而不是只看两个里程碑
#         （只看两个的话，lw / load-use 前递 / lui / 移位 / 有符号比较
#         出错时仍可能写出 0x0F）。
#         大立即数（x10=0x12345000、x11=0x00012345）用移位折成小常数比较，
#         因为 `addi` 的 12 位立即数放不下。
#   生成：uv run --no-project --python 3.13.13 pipeline/src/scripts/simple_asm.py \
#           pipeline/src/test/exp1_board_demo.asm
#         powershell -File pipeline/src/scripts/hex_to_vh.ps1 \
#           -Hex pipeline/src/test/exp1_board_demo_rom.hex -PadBytes 512
#   回归：pipeline/src/test/tb_prog_board_demo.v（期望值与本文件注释逐一对应）
# ==================================================================

    # ---- 阶段1：ALU 与背靠背前递（EX/MEM）----
    addi x1,  x0, 10          # x1  = 10
    addi x2,  x0, 20          # x2  = 20
    add  x3,  x1, x2          # x3  = 30
    sub  x4,  x2, x1          # x4  = 10
    and  x5,  x3, x4          # x5  = 10   （30 & 10）
    or   x6,  x3, x4          # x6  = 30   （30 | 10）
    xor  x7,  x3, x4          # x7  = 20   （30 ^ 10）  ★里程碑
    slt  x8,  x4, x3          # x8  = 1    （10 < 30 有符号）
    sltu x9,  x4, x3          # x9  = 1    （10 < 30 无符号）
    lui  x10, 0x12345         # x10 = 0x12345000
    srli x11, x10, 12         # x11 = 0x00012345

    # ---- 阶段2：sw→lw 同址往返 + load-use 停顿 ----
    addi x12, x0, 0x40        # x12 = 0x40（数据区基址）
    sw   x3,  0(x12)          # dmem[0x40] = 30
    lw   x13, 0(x12)          # x13 = 30
    add  x14, x13, x1         # x14 = 40   ← load-use 消费者（恰 1 气泡）
    sw   x14, 4(x12)          # dmem[0x44] = 40
    lw   x15, 4(x12)          # x15 = 40
    add  x16, x15, x2         # x16 = 60   ← load-use 消费者（恰 1 气泡）

    # ---- 阶段3：bne 循环（累加 5+4+3+2+1）----
    addi x17, x0, 5           # x17 = 循环计数
    addi x18, x0, 0           # x18 = 累加和
loop:
    add  x18, x18, x17        # 累加
    addi x17, x17, -1         # 计数递减
    bne  x17, x0, loop        # taken×4；末次 not-taken 出口（冲刷 2 条）
                              # 出口时：x18 = 15  ★里程碑、x17 = 0

    # ---- 阶段4：移位与有符号/无符号对照 ----
    slli x19, x18, 2          # x19 = 60
    srli x20, x19, 1          # x20 = 30
    srai x21, x19, 2          # x21 = 15
    addi x22, x0, -16         # x22 = 0xFFFFFFF0
    srai x23, x22, 2          # x23 = 0xFFFFFFFC（算术右移保留符号）
    srli x24, x22, 28         # x24 = 0x0000000F（逻辑右移）
    slt  x25, x22, x0         # x25 = 1（有符号：-16 < 0）
    sltu x26, x22, x0         # x26 = 0（无符号：0xFFFFFFF0 < 0 为假）

    # ---- 阶段5：自检 → 写入验收签名 dmem[0] = 0x0000000F ----
    #   方法：每项结果与期望值异或得失配项（x29），再或进累积器 x31。
    #     全部相符 → x31 = 0 → 掩码 x6 = 0 → x8 = 0x0F（板上有 PASS）
    #     任一项错 → x31 ≠ 0 → x6 = 0xFFFFFFFF → x8 = 0（板上无 PASS）
    #   核对范围：阶段1 全部 ALU 结果与 lui/srli、阶段2 sw→lw 往返与两处
    #     load-use 前递、阶段3 循环计数与累加和、阶段4 三种移位与有/无符号
    #     对照。x27/x28/x29/x30/x31 为自检专用暂存寄存器（此前未使用）。
    addi x31, x0, 0           # x31 = 失配累积器（0 = 全对）
    # -- 阶段1：ALU --
    addi x28, x0, 30          # 期望 x3 = 30（add）
    xor  x29, x3, x28
    or   x31, x31, x29
    addi x28, x0, 10          # 期望 x4 = 10（sub）
    xor  x29, x4, x28
    or   x31, x31, x29
    addi x28, x0, 10          # 期望 x5 = 10（and）
    xor  x29, x5, x28
    or   x31, x31, x29
    addi x28, x0, 30          # 期望 x6 = 30（or）
    xor  x29, x6, x28
    or   x31, x31, x29
    addi x28, x0, 20          # 期望 x7 = 20（xor）★里程碑
    xor  x29, x7, x28
    or   x31, x31, x29
    addi x28, x0, 1           # 期望 x8 = 1（slt）
    xor  x29, x8, x28
    or   x31, x31, x29
    addi x28, x0, 1           # 期望 x9 = 1（sltu）
    xor  x29, x9, x28
    or   x31, x31, x29
    # -- 阶段1：lui + srli（x10 = 0x12345000 折成两个小常数核对）--
    addi x28, x0, 0           # 期望 x10 低 12 位 = 0（lui 只写高 20 位）
    slli x29, x10, 20
    srli x29, x29, 20
    xor  x29, x29, x28
    or   x31, x31, x29
    addi x28, x0, 291         # 期望 (x10 >> 20) = 0x123 = 291
    srli x29, x10, 20
    xor  x29, x29, x28
    or   x31, x31, x29
    addi x28, x0, 18          # 期望 (x11 >> 12) = 0x12 = 18
    srli x29, x11, 12
    xor  x29, x29, x28
    or   x31, x31, x29
    addi x28, x0, 837         # 期望 x11 低 12 位 = 0x345 = 837
    slli x29, x11, 20
    srli x29, x29, 20
    xor  x29, x29, x28
    or   x31, x31, x29
    # -- 阶段2：sw→lw 往返 + 两处 load-use 前递 --
    addi x28, x0, 30          # 期望 x13 = 30（lw 取回 sw 存入值）
    xor  x29, x13, x28
    or   x31, x31, x29
    addi x28, x0, 40          # 期望 x14 = 40（lw 后紧邻 add，load-use）
    xor  x29, x14, x28
    or   x31, x31, x29
    addi x28, x0, 40          # 期望 x15 = 40（第二次 lw）
    xor  x29, x15, x28
    or   x31, x31, x29
    addi x28, x0, 60          # 期望 x16 = 60（第二次 load-use 消费者）
    xor  x29, x16, x28
    or   x31, x31, x29
    # -- 阶段3：bne 循环 --
    addi x28, x0, 0           # 期望 x17 = 0（计数递减到 0 才出口）
    xor  x29, x17, x28
    or   x31, x31, x29
    addi x28, x0, 15          # 期望 x18 = 15（5+4+3+2+1）★里程碑
    xor  x29, x18, x28
    or   x31, x31, x29
    # -- 阶段4：三种移位 + 有/无符号对照 --
    addi x28, x0, 60          # 期望 x19 = 60（slli）
    xor  x29, x19, x28
    or   x31, x31, x29
    addi x28, x0, 30          # 期望 x20 = 30（srli）
    xor  x29, x20, x28
    or   x31, x31, x29
    addi x28, x0, 15          # 期望 x21 = 15（srai）
    xor  x29, x21, x28
    or   x31, x31, x29
    addi x28, x0, -4          # 期望 x23 = 0xFFFFFFFC（srai 保留符号）
    xor  x29, x23, x28
    or   x31, x31, x29
    addi x28, x0, 15          # 期望 x24 = 15（srli 逻辑右移）
    xor  x29, x24, x28
    or   x31, x31, x29
    addi x28, x0, 1           # 期望 x25 = 1（slt 有符号：-16 < 0）
    xor  x29, x25, x28
    or   x31, x31, x29
    addi x28, x0, 0           # 期望 x26 = 0（sltu 无符号：0xFFFFFFF0 < 0 为假）
    xor  x29, x26, x28
    or   x31, x31, x29
    # -- 生成签名 --
    xor  x30, x31, x0         # x30 = 失配标志副本（0 = 全对）
    sltu x5,  x0, x31         # x5  = 1 若有错，否则 0
    sub  x6,  x0, x5          # x6  = 0 若无错；0xFFFFFFFF 若有错
    addi x27, x0, 15          # 签名掩码常数
    xor  x7,  x6, x27         # x7  = 0x0F 若无错；0xFFFFFFF0 若有错
    and  x8,  x7, x27         # x8  = 0x0F 若无错；0 若有错
    sw   x8,  0(x0)           # ★ 验收签名：dmem[0] = 0x0000000F
halt:
    beq  x0, x0, halt         # HALT 自循环（isa §4 停机约定）
