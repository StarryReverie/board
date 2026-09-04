# 汇编固件（软件）设计文档

- 版本：v1.0（2026-09-04）。代码位置：`../asm/`；本文件收编原"汇编实验设计方案"中的软件章节（程序查询模型、子程序、console、字符串方案），与 tasks.md U40/U41 配套。硬件口径见 `interface.md` 与 modules/*.md。
- 汇编约束：只使用计组 26 条冻结指令 + 白名单伪指令（isa `../../doc/isa.md` v1.3）；无 auipc/lb——地址常量用 `lui(+进位)+addi` 构造，字符收发只用字槽低 8 位。

---

## 1. I/O 模型（程序查询方式）

- CPU 是唯一总线主设备，UART 是纯从机：从不主动访问总线（无 DMA、无中断、无外设写内存）；
- 软件模型：**轮询**——发前轮询 `STAT.TX_BUSY=0` 再 `sw` TX；收前轮询 `STAT.RX_VALID=1` 再 `lw` RX；
- 方向语义：`lw`=外设读（in/r）、`sw`=外设写（out/w）；同一窗口槽位读写各司其职（interface.md §3）。

## 2. 内存映射（.equ 头）

```asm
.equ DMEM_BASE,  0x00000000   # 数据 RAM（0x0–0xFFF）
.equ UART_BASE,  0x00004000   # MMIO 窗口（lui t0, 0x4 可得）
.equ UART_TX,    0x00004000   # sw=out/w：写低 8 位发送；读=0
.equ UART_STAT,  0x00004004   # lw=in/r：bit0 TX_BUSY / bit1 RX_VALID
.equ UART_RX,    0x00004008   # lw=in/r：读字节并清 RX_VALID
.equ STAT_TX_BUSY,  1
.equ STAT_RX_VALID, 2
```

## 3. 子程序（t0=UART_BASE，a0=参数/返回，ra=返回地址）

```asm
# 发送单字节：a0=字符（低 8 位有效）
uart_putc:
wait_tx: lw   t1, UART_STAT-UART_BASE(t0)   # lw 读 STAT（in/r）
         andi t1, t1, STAT_TX_BUSY
         bne  t1, x0, wait_tx               # TX_BUSY=1 则继续轮询
         sw   a0, UART_TX-UART_BASE(t0)     # sw 写 TX（out/w），忙时写入会被丢弃
         jalr x0, 0(ra)

# 接收单字节：返回 a0=收到字节
uart_getc:
wait_rx: lw   t1, UART_STAT-UART_BASE(t0)
         andi t1, t1, STAT_RX_VALID
         beq  t1, x0, wait_rx
         lw   a0, UART_RX-UART_BASE(t0)     # 读 RX，访存段末沿自动清 RX_VALID
         jalr x0, 0(ra)

# 回显主循环（console 核心）
echo_main:
         jal  ra, uart_getc
         jal  ra, uart_putc                 # 收到即回发
         jal  x0, echo_main
```

- 调用约定：caller 负责置 a0；子程序用 ra 返回（示例未用栈；若固件引入嵌套调用/栈，须自行初始化 sp 指向 dmem 安全区且不撞数据区）。
- 无停机指令：console 常驻轮询（非 HALT 自循环）；系统 TB 按"期望字节收齐"判结束（见 tasks.md U31）。

## 4. console 主程序流程（固定固件）

1. 启动初始化：数据区自初始化（**dmem 复位不清**，每次启动重写字符串/变量区，保证复位重跑幂等）；
2. 打印 banner（如 "EES-338 RV32I UART OK\r\n"）：逐字符 uart_putc（轮询 TX_BUSY）；
3. 回显主循环：uart_getc → uart_putc（可加简单命令，如收到 '?' 打印帮助）；
4. 无 reload 命令（换程序=重新生成 .vh → 综合 → 重烧）。

## 5. 字符串方案（无 auipc/lb，实现二选一）

- **做法一（推荐，演示 dmem 读写）**："字内低 8 位一字符"：4 字符/字，字值=小端拼装（如 "ABC\n" → 0x0A434241），启动时 `lui(+1 进位技巧)+addi` 构造字常量、`sw` 写入 dmem 数据区；发送时逐字 `lw`，`andi`/`srl` 拆出低字节字符再 uart_putc；
- **做法二**：banner 逐字符 `addi a0,x0,'H'`（ASCII <12 位有符号立即数）现场发送，不占数据区。

## 6. 镜像与机器码流程

- `asm/*.S → (riscv-none-elf-as -march=rv32i，计组 scripts/build_asm.ps1) → objcopy -O verilog → *.hex`；镜像校验=反汇编清单/verify_hex.py，全部指令在 26 条冻结集内（方案 B 无自定义指令，objdump 反查照常）；
- 上电路径：综合期 .vh 固化 → PC=0 自跑；换程序=重烧（见 top_design.md §6）。

## 7. 变更记录

- v1.0 2026-09-04：初版（收编自原"汇编实验设计方案"v1.1 软件章节，内容未删减）。
