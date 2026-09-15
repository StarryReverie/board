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

    # ---- 阶段5：逐项自检（失配计数）→ 写验收签名 dmem[0] = 0x0000000F ----
    #   每一项：比较 → sltu 归一成 0/1 → add 累加进 x31（失配计数）。
    #     全部相符 → x31 = 0 → 掩码 x6 = 0 → x8 = 0x0F（板上有 PASS）
    #     任一项错 → x31 ≥ 1 → x6 = 0xFFFFFFFF → x8 = 0（板上无 PASS）
    #   **不用 `or` 累加**：若 ALU_OR 本身故障（恒 0），`or x31,x31,x29`
    #     会把所有失配项一并吞掉、x31 恒 0 → 板上假 PASS。改为 sltu+add 后，
    #     ALU_OR 故障由"x6 == 30"这一项算出失配并计入 x31 → 不亮 PASS
    #     （已由 build/tb_mut_aluor.v 的 ALU 级故障变异实测确认）。
    #   **比较用 xor 与 sub 交替**：同一条链里两种比较机制各占一半，
    #     任一者故障时另一半仍能算出失配。
    #   核对范围：本版 22 项 = 阶段1 的 add/sub/and/or/xor/slt/sltu 结果、
    #     lui+srli 折半核对、阶段2 sw→lw 往返与两处 load-use 前递、
    #     阶段3 循环累加和、阶段4 三种移位与有/无符号对照。
    #   受 imem 512 B 限制未单列：x17（循环计数——已由 x18 与"必须停机"覆盖）、
    #     x10 低 12 位（lui 只写高 20 位——已由 x10>>20 与 x11 两项部分覆盖）。
    #   残留依赖（自检机制自身用到的 SLTU/ADD opcode）与边界见
    #     pipeline/doc/board_runbook.md §5.1。
    #   x27/x28/x29/x30/x31 为自检专用暂存寄存器（此前未使用）。
    addi x31, x0, 0           # x31 = 失配计数（sltu 归一 + add 累加路径）
    addi x30, x0, 0           # x30 = 独立 OR 路径的失配标志（见下 x9/x26 两项）
    # -- 期望 30：x3(add) / x6(or) --
    addi x28, x0, 30
    xor  x29, x3, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x6, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 10：x4(sub) / x5(and) --
    addi x28, x0, 10
    xor  x29, x4, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x5, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 20：x7(xor) ★里程碑 --
    addi x28, x0, 20
    xor  x29, x7, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 1：x8(slt) / x25(slt) 走 sltu+add 路径 --
    addi x28, x0, 1
    sub  x29, x8, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x25, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- x9(sltu) 走**独立 OR 路径**（不依赖 sltu）--
    #    取值由 ALU_SLTU 产生的项（x9 / x26）：若 SLTU 故障，其失配只能靠
    #    这条不经 sltu 的路径检出（实测见 build/tb_mut_alu.v 的 ALU 级矩阵）。
    xor  x29, x9, x28
    or   x30, x30, x29
    # -- x10/x11：大立即数用移位折成小常数核对 --
    addi x28, x0, 291         # 期望 (x10 >> 20) = 0x123 = 291
    srli x29, x10, 20
    xor  x29, x29, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    addi x28, x0, 18          # 期望 (x11 >> 12) = 0x12 = 18
    srli x29, x11, 12
    sub  x29, x29, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    addi x28, x0, 837         # 期望 x11 低 12 位 = 0x345 = 837
    slli x29, x11, 20
    srli x29, x29, 20
    xor  x29, x29, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 30：x13(lw 取回值) / x20(srli) --
    addi x28, x0, 30
    xor  x29, x13, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x20, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 40：x14 / x15（两处 load-use 的取值）--
    addi x28, x0, 40
    xor  x29, x14, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x15, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 60：x16（load-use 消费者） / x19（slli）--
    addi x28, x0, 60
    xor  x29, x16, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x19, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 15：x18（循环累加和）★里程碑 / x21（srai） / x24（srli）--
    addi x28, x0, 15
    xor  x29, x18, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    sub  x29, x21, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    xor  x29, x24, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 -4：x23（srai 保留符号）--
    addi x28, x0, -4
    xor  x29, x23, x28
    sltu x29, x0, x29
    add  x31, x31, x29
    # -- 期望 0：x26（sltu 无符号为假）走 OR 路径 —— 置于最后，使 x28 终值为 0 --
    addi x28, x0, 0
    sub  x29, x26, x28
    or   x30, x30, x29
    # -- 生成签名（多机制叠加：任一**单个** opcode 故障都不会写出 0x0F）--
    #   实测：只靠 sltu→sub→xor→and 时，ALU_SUB 恒 0 会让 x6 = 0 而写出 0x0F；
    #   只靠 sltu 归一化时，ALU_SLTU 恒 0 会把全部失配吞掉（build/tb_mut_alu.v
    #   两条都已复现）。因此这里：(a) 先把独立 OR 路径的标志并进计数；
    #   (b) 再并联一条与 sltu/sub/xor 无关的机制 `srl x8, 15, x31`
    #   （计数为 0 得 15；计数 ≥ 1 右移后必 < 15），相与后签名必 ≠ 0x0F。
    addi x27, x0, 15          # 签名常数 15
    add  x31, x31, x30        # 并入独立 OR 路径的失配标志            （ADD）
                              #   —— 不能用 or 合并：ALU_OR 故障时 `or` 恒 0，
                              #      会把已经累计好的失配计数一并清零（实测复现过）
    sltu x5,  x0, x31         # x5 = 1 若有错，否则 0              （SLTU）
    sub  x6,  x0, x5          # x6 = 0 若无错；0xFFFFFFFF 若有错    （SUB）
    xor  x7,  x6, x27         # x7 = 0x0F 若无错；0xFFFFFFF0 若有错（XOR）
    srl  x8,  x27, x31        # x8 = 15 若无错；15 >> 计数 < 15     （SRL）
    and  x8,  x7, x8          # 无错 → 0x0F；有错 → 0             （AND）
    sw   x8,  0(x0)           # ★ 验收签名：dmem[0] = 0x0000000F
halt:
    beq  x0, x0, halt         # HALT 自循环（isa §4 停机约定）
