# console 固件机器码与内存映射说明（U41）

- 版本：v1.0（2026-09-06）。固件：`../src/test/console.S`（U40）；反汇编完整清单：`../src/scripts/out/asm/console.lst`（objdump `-M no-aliases`，51 条逐条可复核）；镜像：`console_rom.hex`（204 B）+ `console_init.vh`（综合固化）。构建/双校验：`build_fw.ps1`。

## 1. 内存映射（程序可见）

| 空间 | 范围 | 用途（console 内） |
|---|---|---|
| IMEM（哈佛，只读） | `0x0000_0000` 起（仿真 4KB；**下板 build 512B**） | 51 条指令（0x00–0xCC），综合期 .vh 固化，上电 PC=0 自跑 |
| DMEM（数据） | `0x0000_0000`–`0x0FFF` | `0x40`–`0x57`：banner 字串（6 字，自初始化）；`0x100` 顶向下：栈（sp=0x100，下板 256B 顶；仿真 4KB 亦兼容） |
| MMIO 窗口 | `0x0000_4000` | TX(+0)/STAT(+4)/RX(+8) 字槽，`lw`=in/r、`sw`=out/w（isa.md §4 / interface.md §3） |

寄存器使用约定：`t0`=UART_BASE（putc/getc 全局专用）；`t1`=STAT 轮询临时；`a0`=putc 字符/ getc 返回；`sp`=栈顶（0x100，下板 256B 顶）；`t4/t3/t2`=print_banner 指针/计数/字值；`ra`=返回地址（print_banner 内压栈保护）。

## 2. 伪指令 li 的展开（lui + addi 两例实测）

规则：`li rd,imm` → 12 位小立即数 `addi rd,x0,imm`；大立即数 `lui rd,hi20` + `addi rd,rd,lo12`，其中当 `imm[11]==1` 时 hi20 需 +1（addi 符号扩展回补）。

| 源（console.S） | 机器码 | 展开 |
|---|---|---|
| `li t0, UART_BASE`(0x4000) | `000042b7` | `lui t0,0x4`（lo12=0，无 addi） |
| `li t2, 0x2D534545` | `2d5343b7` + `54538393` | `lui t2,0x2d534` + `addi t2,t2,1349`（0x545，正 lo12） |
| `li t2, 0x000A0D4B` | `000a13b7` + `d4b38393` | `lui t2,0xa1` + `addi t2,t2,-693`（0xD4B 符号扩展→hi 补 1，0xA1000−0xD4B… = 0xA0D4B，hi=0xA1 已含进位） |
| `li sp, STACK_TOP`(0x100) | `10000113` | `addi sp,x0,0x100`（12 位小立即数，无需 lui） |

## 3. 分支/跳转编码示例（相对 PC，字节偏移）

| 源 | 地址 | 机器码 | 说明 |
|---|---|---|---|
| `bne t1,x0,putc_wait`（自循环） | 0x6C | `fe031ce3` | B 型偏移 −4（imm[12:1]=0x1FE…） |
| `beq a0,x0,pb_done` | 0xA8 | `00050c63` | 偏移 +0x18（前跳 6 条） |
| `jal ra,print_banner` | 0x54 | `038000ef` | J 型偏移 +0x38（=0x8C−0x54） |
| `jal zero,echo_loop`（j） | 0x60 | `ff9ff06f` | 偏移 −8（0x58−0x60） |
| `ret`（jalr x0,0(ra)） | 0x74 等 | `00008067` | I 型 imm=0，rs1=ra=x1 |

## 4. 指令使用统计（10 种，全在 26 条冻结集）

| 助记符 | 次数 | 用途 |
|---|---|---|
| addi | 13 | li 展开、栈指针、循环计数/指针步进 |
| lui | 8 | li 展开（基址/字常量） |
| sw | 8 | banner 入 dmem、栈保存 ra |
| lw | 5 | dmem 读、STAT/RX 槽、栈恢复 |
| jal | 6 | 子程序调用/跳转（含 j 展开） |
| jalr | 3 | ret（返回） |
| andi | 3 | STAT 位测、拆字节 |
| beq / bne | 各 2 | 轮询、NUL 判终、循环计数 |
| srli | 1 | 字内取下一字节 |

统计口径：objdump `-M no-aliases` 输出解析（build_fw.ps1 校验 1 通过 + hex 字节数=51×4 校验 2 通过）。

## 5. 上电路径（固化单程序模型）

```
console.S --build_fw.ps1--> console_rom.hex（仿真 $readmemh）
                         \-> console_init.vh --synth_check/create_proj tcl
                             复制为 out/fw_rom/imem_init.vh（imem.v 硬编码 include 名）
                             + verilog_define IMEM_INIT_VH
                             --> 综合 .bit（IMEM initial 固化，上电 PC=0 自跑）
换程序 = 重生成 .vh → 重综合 → 重烧（无 loader/在线重载）
```

## 6. 变更记录

- v1.0 2026-09-06：初版（配合 U40 console.S / build_fw.ps1 / tb_soc_console 全绿）。
