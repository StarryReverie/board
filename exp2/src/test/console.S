#=============================================================================
# console.S — U40 固定固件：console（banner + 键盘回显）
#   文档：exp2/doc/firmware.md（子程序口径/字符串方案）；interface.md §3
#   I/O 模型：程序查询（轮询 STAT.TX_BUSY/RX_VALID，lw=in/r、sw=out/w）
#   指令约束：仅 26 条冻结集 + 白名单伪指令 li/j/ret/mv/nop（doc/isa.md §3）
#   数据区：dmem 复位不清 → 启动时把 banner 字常量 sw 自初始化进 BANNER_BUF
#           （复位重跑幂等），再逐字 lw 拆分发送——演示 dmem 读写（做法一）
#   栈：sp=STACK_TOP，print_banner 嵌套调用（→uart_putc）需保存/恢复 ra
#   构建：exp2/src/scripts/build_fw.ps1 → console_rom.hex + console_init.vh
#=============================================================================

    # ---- 内存映射（interface.md §3，与计组 isa.md §4 单源一致）----
    .equ UART_BASE,     0x00004000   # MMIO 窗口
    .equ OFF_TX,        0            # sw=out/w：写低 8 位发送
    .equ OFF_STAT,      4            # lw=in/r：bit0 TX_BUSY bit1 RX_VALID
    .equ OFF_RX,        8            # lw=in/r：读字节并清 RX_VALID
    .equ STAT_TX_BUSY,  1
    .equ STAT_RX_VALID, 2
    .equ BANNER_BUF,    0x00000040   # dmem 数据区（banner 字串，4 字符/字）
    .equ STACK_TOP,     0x00000100   # dmem 顶（下板 256B 容量=0x100；仿真 4KB 亦兼容），栈向下生长

    .text
    .globl _start
_start:
    li   sp, STACK_TOP               # 栈初始化（无复位不清依赖）
    li   t0, UART_BASE               # t0 全局专用（uart_putc/getc 约定）

    # ---- 数据区自初始化：banner 写入 dmem（每字低 8 位=第 1 字符）----
    # banner = "EES-338 RV32I UART OK\r\n"（23 字符 + NUL 收尾 24 字节）
    li   t1, BANNER_BUF
    li   t2, 0x2D534545              # 'E','E','S','-'
    sw   t2, 0(t1)
    li   t2, 0x20383333              # '3','3','8',' '
    sw   t2, 4(t1)
    li   t2, 0x32335652              # 'R','V','3','2'
    sw   t2, 8(t1)
    li   t2, 0x41552049              # 'I',' ','U','A'
    sw   t2, 12(t1)
    li   t2, 0x4F205452              # 'R','T',' ','O'
    sw   t2, 16(t1)
    li   t2, 0x000A0D4B              # 'K',CR,LF,NUL
    sw   t2, 20(t1)

    # ---- 打印 banner ----
    jal  ra, print_banner

    # ---- 回显主循环：getc → putc（收到即回发）----
echo_loop:
    jal  ra, uart_getc
    jal  ra, uart_putc
    j    echo_loop

#---------------------------------------------------------------------------
# uart_putc：发送单字节（a0=字符低 8 位；t0=UART_BASE 约定）
#   轮询 STAT.TX_BUSY（挂起/移位中恒 1，见 interface.md v1.1）→ sw TX
#---------------------------------------------------------------------------
uart_putc:
putc_wait:
    lw   t1, OFF_STAT(t0)
    andi t1, t1, STAT_TX_BUSY
    bne  t1, x0, putc_wait
    sw   a0, OFF_TX(t0)
    ret

#---------------------------------------------------------------------------
# uart_getc：接收单字节（返回 a0；轮询 STAT.RX_VALID → lw RX 读清位）
#---------------------------------------------------------------------------
uart_getc:
getc_wait:
    lw   t1, OFF_STAT(t0)
    andi t1, t1, STAT_RX_VALID
    beq  t1, x0, getc_wait
    lw   a0, OFF_RX(t0)
    ret

#---------------------------------------------------------------------------
# print_banner：逐字读 dmem 数据区（4 字符/字，低字节先发），遇 NUL 结束
#   嵌套调用 uart_putc → ra 压栈保护（sp 见 _start）
#   用 t4=字指针、t3=剩余字节计数、t2=当前字；putc 只动 t1/a0，安全
#---------------------------------------------------------------------------
print_banner:
    addi sp, sp, -4
    sw   ra, 0(sp)                   # 保护返回地址（嵌套 putc）
    li   t4, BANNER_BUF
pb_wloop:
    lw   t2, 0(t4)                   # 读一个字（4 字符）
    addi t4, t4, 4
    li   t3, 4                       # 本字 4 字节
pb_byte:
    andi a0, t2, 0xFF                # 拆低字节
    beq  a0, x0, pb_done             # NUL → banner 结束
    jal  ra, uart_putc
    srli t2, t2, 8                   # 取下个字节
    addi t3, t3, -1
    bne  t3, x0, pb_byte
    j    pb_wloop
pb_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

.end
