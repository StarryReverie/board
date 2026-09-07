# ==================================================================
# hazard_cover.asm — 冒险定向场景（T31）
#  场景1 连续 RAW：addi x1 → addi x2,x1 → add x3,x2,x1（EX/MEM 前递）
#  场景2 load-use：lw x4 → addi x5,x4,1（恰 1 气泡）
#  场景3 双 load 混合依赖：lw x6 → lw x7 → add x8,x7,x6
#  场景4 load 值进 EX 分支判决：beq x6,x4（双 load 前递）
#  场景5 MEM/WB 前递长链末端使用：addi x10,x10? 用 x5
# 期望终值：x1=1 x2=2 x3=3 x4=3 x5=4 x6=3 x7=4 x8=8 x9=7 x10=15
#           dmem[0]=3 dmem[4]=4
# ==================================================================
    addi x1, x0, 1            # 生产者
    addi x2, x1, 1            # 场景1 RAW(EX/MEM 前递) → 2
    add  x3, x2, x1           # 场景1 双源前递 → 3

    # ---- 场景2：load-use（x4 出 load 后立即被用）----
    sw   x3, 0(x0)
    lw   x4, 0(x0)            # x4 = 3
    addi x5, x4, 1            # load-use → 4

    # ---- 场景3：双 load + 混合依赖 ----
    sw   x5, 4(x0)
    lw   x6, 0(x0)            # x6 = 3
    lw   x7, 4(x0)            # x7 = 4
    add  x8, x7, x6           # 依赖两 load：7
    addi x8, x8, 1            # 8

    # ---- 场景4：load 值经前递进 EX 分支判决 ----
    beq  x6, x4, ok_path      # 3==3 taken（x4 亦出自 load）
    addi x9, x0, 99           # 被跳过
ok_path:
    addi x9, x0, 7

    # ---- 场景5：WB 侧值末端使用（x5 久置后读取）----
    addi x10, x0, 11
    add  x10, x10, x5         # 11 + 4 = 15

halt:
    beq  x0, x0, halt
