# ==================================================================
# 冒泡排序 — 对 5 个整数排序
# RV32I 子集: ORI, ADD, SUB, LW, SW, BEQ
#
# 数据: [4, 2, 5, 1, 3] 存储在 RAM 0x200
# 结果: [1, 2, 3, 4, 5]
#
# 寄存器用途:
#   t0 = 基址 (0x200)
#   t1 = 外循环计数器 i
#   t2 = 内循环计数器 j
#   t3 = 临时量, 用于 sub/计算地址
#   t4 = &arr[j] 地址
#   t5 = arr[j]
#   t6 = arr[j+1]
#   s0 = 常量 4 (外循环上限, n-1)
#   s1 = 常量 1 (增量)
#   s2 = 内循环上限 (4-i)
#   s3 = 常量 0x7FF (用于 slt 替代)

# 本测试样例由Claude Code + Deepseek-v4-pro API生成，经作者审查
# ==================================================================

    # ===== 1: 初始化数组 =====
    ori  t0, zero, 0x200        # t0 = 基址

    ori  t1, zero, 4
    sw   t1, 0(t0)              # arr[0] = 4
    ori  t1, zero, 2
    sw   t1, 4(t0)              # arr[1] = 2
    ori  t1, zero, 5
    sw   t1, 8(t0)              # arr[2] = 5
    ori  t1, zero, 1
    sw   t1, 12(t0)             # arr[3] = 1
    ori  t1, zero, 3
    sw   t1, 16(t0)             # arr[4] = 3

    # ===== 2: 常量准备 =====
    ori  s3, zero, 0x7FF        
    ori  s0, zero, 4            # 外循环上限 = 4 (n-1)
    ori  s1, zero, 1            # 增量常量
    ori  t1, zero, 0            # i = 0

    # ===== 3: 外循环 =====
outer:
    beq  t1, s0, done           # if i == 4 → 排序完成

    ori  t2, zero, 0            # j = 0
    sub  s2, s0, t1             # 内循环上限 = 4 - i

    # ===== 4: 内循环 =====
inner:
    beq  t2, s2, next_i         # if j == 4-i → 本轮完成

    # 计算地址: &arr[j] = 基址 + j*4
    add  t3, t2, t2             # t3 = 2j
    add  t3, t3, t3             # t3 = 4j
    add  t4, t0, t3             # t4 = &arr[j]

    # 读取相邻元素
    lw   t5, 0(t4)              # t5 = arr[j]
    lw   t6, 4(t4)              # t6 = arr[j+1]

    # 比较: if (arr[j] > arr[j+1]) 则交换
    sub  t3, t6, t5             # t3 = t6 - t5 (负值 → 需交换)
    ori  t3, t3, 0x7FF          # 负值 → 0xFFFFFFFF; 非负 → 原值|0x7FF
    add  t3, t3, s1             # 负值溢出归0; 非负 → 正数
    beq  t3, zero, do_swap      # 归0说明 t6<t5, 需交换
    beq  zero, zero, no_swap    # 否则不交换

    # 交换
do_swap:
    sw   t6, 0(t4)              # arr[j] = arr[j+1]
    sw   t5, 4(t4)              # arr[j+1] = arr[j]

no_swap:
    add  t2, t2, s1             # j++
    beq  zero, zero, inner      # 继续内循环

    # ===== 5: 外循环迭代 =====
next_i:
    add  t1, t1, s1             # i++
    beq  zero, zero, outer      # 继续外循环

    # ===== 6: 停机 =====
done:
    beq  zero, zero, done       # 自循环停机


# ==================================================================
# 预期结果:
#   存储器 0x200 ~ 0x210:
#     mem[0x200] = 0x00000001
#     mem[0x204] = 0x00000002
#     mem[0x208] = 0x00000003
#     mem[0x20C] = 0x00000004
#     mem[0x210] = 0x00000005
#
#   寄存器最终值:
#     t0 = 0x200 (基址不变)
#     t1 = 4 (i 循环结束值)
#     s0 = 4
#     s1 = 1
# ==================================================================
