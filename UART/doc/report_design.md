# 接口控制器设计实验报告 · 设计部分（新稿）

> 版本：v1.1（2026-09-16）｜用途：替换 `汇编与接口课程设计报告_前五章.docx` 中需修订的正文（项目简述/组员分工/设计目的/设计环境/第 5 章设计原理及内容），并**新增 §5.8「与计组实验的接口与分工」**。
> 事实依据（单源）：`pipeline/doc/isa.md` v1.4、`pipeline/doc/top_design.md` v1.7、`pipeline/doc/modules/{pipeline_top,dbus_decode}.md`、`UART/doc/top_design.md` v1.2、`UART/doc/interface.md` v1.3、`UART/doc/modules/*.md`、`soc/doc/{top_design.md v1.1, firmware.md v1.3, machine_code.md, board_runbook.md v1.6}`、`UART/doc/tasks.md`。
> 待人工补充项统一以 ⬜ 标注（姓名、下板记录、波形/视频、最终回归数字）。

---

## 1 项目简述（修订版）

本课程设计在计组实验一交付的 RV32I 五级流水线 CPU core（`pipeline_top`）之上，设计并实现了一种**全双工 UART 接口控制器 IP 核**：8N1 帧格式、115200 波特率、位误差约 0.0064%；IP 对外只暴露一条**通用从机总线**（`cs/addr/we/wdata → rdata`）与两条串行引脚，不依赖任何宿主 CPU，经模块级与 IP 级独立测试后打包为可复用 IP。在此基础上，将 UART IP 与计组 core 集成为一台自定义计算机系统（**SoC 为两门课共建的项目顶层，不属于单一课程交付物**）：采用统一编址 MMIO（不新增 in/out 指令，`lw` 即外设读、`sw` 即外设写），程序镜像经 `.vh` 固化于指令存储器、上电自跑，运行固定固件 console（启动打印 banner、键盘逐字回显）。

项目突出特色：

- **全双工 UART**：`uart_tx` / `uart_rx` 两路独立收发，8N1@115200，位误差约 0.0064%；
- **统一编址 MMIO**：外设寄存器与内存同一地址空间，仅用 `lw`/`sw` 访问，不扩指令集；
- **单时钟域设计**：整机仅一个 100 MHz 时钟，波特率由分频脉冲产生，无异步跨域；
- **TX_BUSY 语义修正**：把"发送忙"定义为**含挂起待发**，写接受仅限完全空闲，消除连续发送的丢字窗口；
- **独立可复用 IP**：`uart_ip_top` 自含槽译码与寄存器层，对外零 CPU 依赖，可直接挂接任意总线主机；
- **器件与容量口径实测校正**：板卡实测器件为 `xc7a100tcsg324-1`（手册误标 35T）；存储容量参数化，下板 build 缩容为 IMEM 512 B / DMEM 256 B；
- **验证充分**：计组 core、UART IP、SoC 三层回归全部通过，带固件综合自检无错误，并已完成上板实测（banner 逐字节比对 + 回显往返 ALL PASS）。

## 2 组员分工（修订版，表 2.1）

| 组员 | 分工任务 |
|---|---|
| 组长 ⬜ | 统筹进度；跨课程接口契约协调（对接计组 core 侧口径） |
| 成员 1 | `uart_tx` + `uart_rx`（位中心采样）与波特率分频；两者时序单测、帧格式与误差分析 |
| 成员 2 | 寄存器层（分频/挂起/丢弃/位义，已并入 `uart_ip_top`）+ `uart_ip_top` IP 顶层与 IP 级独立测试；`dbus_decode` 代码交付与从机口适配 |
| 成员 3 | 汇编固件（putc/getc/banner/echo）、机器码生成与校验、系统 TB 串行监视器与断言 |
| 成员 4 | SoC 装配（`soc_top`/`reset_sync`）、XDC 约束、综合实现、下板与演示视频、提交物整合 |

表 2.1 小组分工

## 3 设计目的

1. 熟悉汇编语言与机器码生成流程，掌握 RV32I 指令子集（26 条）的编程与编码；
2. 理解 UART 串行通信协议原理，掌握帧格式（8N1）、波特率计算与收发时序设计；
3. 掌握统一编址 MMIO 外设接口设计方法，学会把外设封装为**独立可复用 IP 核**并完成测试；
4. 掌握 CPU 与外设的 SoC 集成方法，理解数据通路、地址译码、总线适配与复位同步；
5. 培养 FPGA 综合、仿真、下板调试的完整工程能力。

## 4 设计环境（修订版，表 4.1）

| 项目 | 内容 |
|---|---|
| 操作系统 | Windows 10 / 11 |
| 编程语言 | Verilog（RTL 设计，Verilog-2001 风格） |
| EDA 工具 | Xilinx Vivado 2019.2（仿真 xsim / 综合 / 实现 / 下板） |
| 目标器件 | EES-338 开发板，**实测器件 `xc7a100tcsg324-1`**（Artix-7；用户手册误标 35T，以 JTAG idcode 实测为准） |
| 汇编语言 | RISC-V 汇编（RV32I 冻结子集 26 条 + 白名单伪指令） |
| 汇编器（本机） | **`pipeline/src/scripts/simple_asm.py`**（零依赖自研汇编器，Python 3.13.13 由 uv 提供）：`uv run --no-project --python 3.13.13 pipeline/src/scripts/simple_asm.py <asm>` |
| 汇编器（备选） | GNU `riscv-none-elf-as -march=rv32i -mabi=ilp32` + `objcopy -O verilog`（其他装有 xPack 工具链的机器） |
| 串口终端 | Tera Term / SSCOM，115200-8-N-1 无流控 |

> 说明：本机不再依赖 GNU RISC-V 工具链；自研汇编器覆盖 26 条冻结指令与 isa §3 伪指令（`li` 超 12 位自动展开 `lui+addi`，`jal label` 按 GNU 惯例写 `ra`），产出 `*_rom.hex` 并打印反汇编清单。

---

## 5 设计原理及内容

### 5.1 系统整体架构

本设计采用**三级工程结构**，使两门课的交付边界与复用关系清晰：

| 层级 | 目录 | 内容 | 归属 |
|---|---|---|---|
| 实验一 core | `pipeline/src/` | RV32I 五级流水线 CPU core（14 模块，含 `pipeline_top`、参数化 `imem`/`dmem`） | 计组课程 |
| 实验二 IP | `UART/src/` | UART 控制器 IP：`uart_ip_top`（IP 顶层，寄存器层已并入）+ `uart_tx` + `uart_rx` | 汇编课程 |
| SoC 集成 | `soc/` | `soc_top`（整机装配）、`reset_sync`、`dbus_decode`、XDC、固件、系统 TB | **两课共建** |

`soc_top` 例化三个平级实例：`reset_sync`（复位同步）、`pipeline_top #(.SOC_BUILD(1))`（core，MEM 段含 `dbus_decode`）、`uart_ip_top`（UART IP），并引出板级引脚，构成可与 PC 串口通信的自定义计算机系统：

```
soc_top
 ├─ reset_sync      : rst_n(P15) ──异步置位/同步释放──► rst(异步高有效)
 ├─ pipeline_top    : IF pc_reg→imem(.vh 固化, PC=0 自跑)
 │                    MEM ex_mem→dbus_decode─┬─► dmem(低区)
 │                                            └─► MMIO 窗口 0x4000
 │                    mmio 总线穿出：cs_mmio/reg_off/mmio_we/mmio_wdata
 └─ uart_ip_top     : cs/addr={reg_off,2'b00}/we/wdata→rdata；uart_tx_pin(T4)/uart_rx_pin(N5)
```

- **core 零改动**：实验二只通过 `pipeline_top` 的既有参数与 mmio 端口接入，不改其译码、冒险与时序逻辑；
- **地址译码分两级**：`dbus_decode` 做系统级选路（dmem 低区 / MMIO 窗口），`uart_ip_top` 内部按 `addr[3:2]` 自含槽译码（TX/STAT/RX）；
- CPU 支持的指令共 26 条 RV32I（完整编码表见附录 A），程序镜像在综合期经 `.vh` 固化于指令存储器。

### 5.2 数据通路

- **取指侧**：`pc_reg` 输出程序计数器驱动 `imem`（指令存储器）组合读出指令，经 `if_id` 锁存进入译码段；指令存储器内容由 `.vh` 在综合期固化，上电复位后 PC 恒从 `0x0000_0000` 开始取指。
- **访存侧**：`ex_mem` 输出访存地址与写数据进入 `dbus_decode` 做统一编址译码——低区 `0x0000_0000–0x0000_0FFF` 命中 `dmem`；MMIO 窗口 `0x0000_4000` 命中 UART IP，译码器产生 `cs_mmio / reg_off / mmio_we / mmio_wdata` 穿出 core，读回 `mmio_rdata` 经 rdata 多路选择写回 `mem_wb`，最终回写寄存器堆。**整机单时钟域：访存一拍完成，外设读写不卡流水、不引入新冒险。**
- **串行侧**：`uart_ip_top` 内部例化 `uart_tx`（发送）与 `uart_rx`（接收）；发送引脚经 `soc_top` 连至板载 T4（FPGA 发送端，接 USB-UART 桥），接收引脚连至 N5（FPGA 接收端），与 PC 的 USB 转串口直接通信。桥型号以**设备管理器实测**为准：本机实物板载桥为 **FTDI（VID_0403/PID_6010，枚举 "USB Serial Port (COM8)"）**，手册标 CP2102（见 `soc/doc/board_runbook.md` §4）。
- **复位与时钟**：板上复位键 `rst_n`（P15，实测低有效）→ `reset_sync`（异步置位、同步释放的两级同步器）→ `rst`（异步高有效，对齐 core 语义）；`soc_top` 提供 `RST_ACTIVE_LOW` 参数（默认 1）以便极性相反时仅顶层反相。整机单时钟 100 MHz（T5）。
- **存储容量双口径**（详见 §5.7）：

| 口径 | IMEM | DMEM | 用途 |
|---|---|---|---|
| 仿真/程序契约默认 | 4 KB | 4 KB | 回归测试与程序可见语义 |
| 下板 build 缩容 | 512 B | 256 B | 组合读寄存器阵列容量约束下的上板实现 |

### 5.3 控制逻辑

- **CPU 侧**：沿用计组五级流水线的译码与控制信号（`alu_op`、`src_a/src_b`、`mem_read/mem_write`、`mem_to_reg`、`reg_write`、`jump`、`bne` 等），由 `decode` 产生并随段间寄存器逐级传递；冒险由 `hazard_unit` 以前递/冻结/冲刷处理。**本实验不改动 core 的译码与冒险逻辑。**
- **系统级译码**：`dbus_decode` 为纯组合地址译码，按地址选从设备、拆槽并选路回读数据；dmem 写使能由 `we & cs_dmem` 门控，MMIO 写使能由 `we & cs_mmio` 产生。
- **IP 寄存器层**：`uart_ip_top` 内实现分频节拍、TX 挂起/缓冲、RX 字节与有效位、槽位义逻辑——写 TX 槽触发发送、读 RX 槽清除 `RX_VALID`，以及 `uart_tx`/`uart_rx` 各自的收发状态机。
- **TX_BUSY 语义修正（本设计要点）**：`STAT.bit0 = tx_pend | tx_busy`，写接受条件为 `!tx_busy && !tx_pend`。修正前"忙"仅指移位中，写入接受到分频脉冲启动之间存在挂起窗口（最长近 1 个位时间），软件按"busy=0 才写"轮询会覆盖待发字节导致丢字；修正后接受沿即置忙、直至整帧发完，软件轮询模型无丢字窗口。

### 5.4 UART 接口控制器设计原理

- **帧格式**：8N1——1 起始位（低）、8 数据位（LSB 先发）、1 停止位（高），无校验；空闲时线路保持高电平，靠起始位下降沿标识一帧开始。
- **波特率**：板载 100 MHz，目标 115200，每个位持续 `100_000_000 ÷ 115_200 ≈ 868` 个时钟周期，取整误差约 0.0064%，远小于接收端容忍范围。IP 内用 `clk_en` 分频脉冲作节拍，每 868 拍产生一拍位时钟（`CLKS_PER_BIT` 参数化，仿真可覆盖），**不引入第二时钟域**。
- **发送器 `uart_tx`**：8N1 发送状态机——IDLE 输出高；收到 `start` 后进入 START 输出起始位 0，随后按 `bit_index` 0–7 逐位输出数据位（LSB 先），再输出 1 位停止位；完成后置 1 拍 `done` 脉冲并回到 IDLE。`busy` 表示发送中，忙时新的 `start` 被忽略；复位后 TX=1、busy=0。
- **接收器 `uart_rx`**：检测起始位下降沿后，在每位**中心位置**采样（起始位中心先复检一次），逐位组装 8 位数据；停止位采样为 1 则本次接收有效、置 `valid` 并输出字节，为 0（帧错误）则丢弃。输入先打两拍消除亚稳态。位中心采样相比边沿采样抗干扰与容错更好。
  - **节拍口径**：`uart_rx` 的 `clk_en` 端口仅为与 `uart_tx` 接口对齐而保留，**RX 内部以系统时钟自行计数**（`HALF_TICKS = CLKS_PER_BIT >> 1` 定位位中心），不依赖 TX 的分频脉冲；两路独立，可全双工并行。

### 5.5 统一编址 MMIO 与寄存器位义

外设接口采用**统一编址**（方案 B）：外设寄存器与数据存储器共用同一地址空间与同一组访存指令，不新增 in/out 指令——`lw` 即外设读（in/r）、`sw` 即外设写（out/w）。UART 在 MMIO 窗口 `0x0000_4000` 占用三个 32 位字槽：

| 地址 | 槽 | 写（sw = out/w） | 读（lw = in/r） |
|---|---|---|---|
| `0x0000_4000` | TX | 写低 8 位为待发字节；**完全空闲**（无挂起、非移位忙）时接受并触发发送；挂起/忙时写丢弃 | 0 |
| `0x0000_4004` | STAT | 无操作 | bit0=TX_BUSY（1=发送忙：挂起待发或移位中）、bit1=RX_VALID（1=有未读字节） |
| `0x0000_4008` | RX | 无操作 | 读低 8 位为收到字节，读后清 RX_VALID（访存段末沿） |
| 其余地址 | — | 写丢弃 | 读 0（无定义但无害） |

**时序硬约束**（从机不得违反）：读=组合（MEM 拍内稳定，`mem_wb` 末沿捕获）；写=访存段末沿锁存（与 dmem 同步写同沿）；总线固定 1 拍完成、**无 wait/无反压**；字访问 4 对齐、小端，槽内仅低 8 位有语义。软件必须先轮询状态再收发（程序查询方式）：无 FIFO，`RX_VALID=1` 期间新到字节丢弃，TX 忙时写入丢弃。

> 契约版本：`pipeline/doc/isa.md` v1.4 §4（程序可见语义单源）、`UART/doc/interface.md` v1.3（冻结契约）、`pipeline/doc/top_design.md` v1.7 §9（系统集成口径）。

### 5.6 程序固化与固件模型

- **固化单程序模型**：console 固件汇编后生成字节式 `.hex`，再由脚本生成 `.vh`，综合期以 `initial` 初值固化进 `imem`，上电复位后 PC=0 直接执行；换程序需重新生成 `.vh`、重新综合、重烧 `.bit`。
- **构建链**（脚本保留）：`UART/src/scripts/build_fw.ps1`（默认 `-Name console -PadBytes 512`）——输入 `soc/test/console.S`，输出 `console_rom.hex`（仿真 `$readmemh` 直读）+ `console_init.vh`（补零到 512 B=下板 IMEM 容量）+ objdump 反汇编清单；内置校验：指令助记符 ⊆ 26 条冻结集、hex 字节数=指令数×4、`-PadBytes` 必须 4 字节对齐且不小于固件长度。综合前把 `console_init.vh` 复制为 `imem_init.vh`（`imem.v` 硬编码 include 名）。
- **console 流程**：启动时先自初始化数据区（dmem 复位不清，需保证复位重跑幂等）→ 逐字符轮询 `TX_BUSY` 打印 banner（`"EES-338 RV32I UART OK\r\n"`，共 23 字节）→ 进入回显主循环（轮询 `RX_VALID` → 读 RX → 回发）。固件共 **51 条指令、10 种助记符**，全部落在 26 条冻结指令集内。
- **字符串方案（做法一）**：banner 以"字内低 8 位一字符"由 `lui+addi` 构造字常量、`sw` 写入 dmem 数据区（`0x40–0x57`），发送时逐字 `lw` 拆字节；`print_banner` 嵌套调用 `uart_putc`，故初始化 `sp=0x100`（下板 256 B dmem 顶；仿真 4 KB 亦兼容）并在进入/退出时保存/恢复 `ra`（栈向低生长，不撞 banner 数据区）。

### 5.7 其他特色与实现约束

- **器件口径实测校正**：JTAG idcode 实测板卡器件为 `xc7a100tcsg324-1`（用户手册标注 35T 有误）；工程、脚本与文档均已按实测器件统一。
- **存储缩容参数化**：`imem`/`dmem` 为组合读字节数组，只能实现为寄存器阵列。实测约束：4 KB×2 = 65 k FF 超出 35T（41.6 k FF）且 Vivado 器件/时序加载阶段空转；1 KB×2 组合读逻辑约需 35.5 k LUT，超出 35T 的 20.8 k LUT。最终下板 build 经 `verilog_define` 缩容为 **IMEM 512 B + DMEM 256 B**（XC7A100T 容量 63.4 k LUT / 126.8 k FF），synth→place→route→bitgen 全流程通过；仿真与程序契约仍默认 4 KB。容量宏按 `*_BYTES` 生效，地址索引固定 `addr[11:0]`，**参数化仅支持 ≤4 KB 缩容**。
- **单时钟域**：整机仅一个 100 MHz 时钟，波特率用分频脉冲实现，无异步跨域、无门控时钟。
- **IP 可复用**：`uart_ip_top`（含寄存器层）+ `uart_tx` + `uart_rx` 构成独立、可打包的 UART IP 核，对外仅 `cs/addr/we/wdata→rdata` 与串行引脚，接口清晰、零 CPU 依赖。
- **验证充分性**（运行方式与最终数字见附录 B）：

| 层 | 测试用例 | 运行方式 |
|---|---|---|
| 计组 core | 23 项（模块单测 + 程序级回归 + 性能 TB） | `powershell -File pipeline/src/scripts/run_tb.ps1`（并行，全量约 20–30 s） |
| UART IP | 4 项：`tb_uart_tx` / `tb_uart_rx` / `tb_uart_ip_top`（IP 级：帧逐位、STAT 位义含挂起、忙写丢弃、读清位、溢出丢弃、全双工同现）+ `tb_wave_868`（868 分频波形取证） | `powershell -File soc/scripts/run_soc_tb.ps1 -All`（仓库自带 runner，覆盖 `UART/src/test` 全部 `tb_*.v`，判据 `sim.log` 内 `ALL PASS` 且退出码 0） |
| SoC 集成 | 5 项：`tb_dbus_decode` / `tb_reset_sync` / `tb_pipe_soc` / `tb_soc_full` / `tb_soc_console`（banner 23 B、回显往返、长串、复位重跑、复位释放抖动） | `powershell -File soc/scripts/run_soc_tb.ps1`（默认 3 项：`tb_reset_sync`/`tb_soc_console`/`tb_soc_full`；`-All` 跑满 5 项 SoC + 4 项 UART = **9 项**） |

- **上板实测**：`xc7a100tcsg324-1` 全流程出 bit → JTAG 烧录 → COM 口 115200-8-N-1 验收：banner 23 字节**逐字节精确匹配**、`AB` 回显往返正确、两次独立重跑一致（`== UART CHECK ALL PASS ==`）；余留人工取证：P15 按键复位、示波器 TX 波形、≤5 min 视频 ⬜。

### 5.8 与计组实验的接口与分工（新增）

本节说明本实验与计组实验的**交叉契约、职责边界与协同规则**，是两门课成果可复用地集成的前提。

#### (1) 单源契约映射

| 契约项 | 单源（权威） | 本报告/本实验引用视图 |
|---|---|---|
| 26 条指令集、MMIO 映射、存储容量 | `pipeline/doc/isa.md` **v1.4** §1/§4 | `UART/doc/interface.md` v1.3 §3 |
| core 结构、`SOC_BUILD` 双态、固化模型 | `pipeline/doc/top_design.md` **v1.7** §0.2/§9 | `soc/doc/top_design.md` v1.1 §1–§6 |
| `pipeline_top` 端口与 mmio 总线 | `pipeline/doc/modules/pipeline_top.md` | `soc/doc/modules/soc_top.md` |
| `dbus_decode` 职责/归属 | `pipeline/doc/modules/dbus_decode.md` v1.1 | `soc/doc/modules/dbus_decode.md` |
| 从机时序硬约束与槽位义 | `UART/doc/interface.md` **v1.3** | 本报告 §5.5 |

#### (2) 职责边界

| 角色 | 交付 | 约束 |
|---|---|---|
| 计组实验一 | `pipeline/src/rtl/*`（含 `pipeline_top` 的 `SOC_BUILD` 分支、参数化 `imem`/`dmem`） | 本实验**不改 core 译码/冒险/时序**；仅以 `SOC_BUILD=1` 例化 |
| 本实验（汇编） | `UART/src/rtl/{uart_ip_top,uart_tx,uart_rx}` + IP 级测试 | IP 只按 `cs/addr/we/wdata→rdata` 工作，**不感知宿主 CPU 与窗口基址** |
| 共建 SoC 层 | `soc/rtl/{soc_top,reset_sync,dbus_decode}` + XDC + 固件 + 系统 TB | 地址分配表两课共管；系统级选路与总线适配在此层完成 |

#### (3) 交叉接口与参数清单

| 项 | 约定 |
|---|---|
| core 构建模式 | `SOC_BUILD=0`（实验一：`dbus_decode` 不例化、mmio 悬空/接 0，H1–H5 不变）；`SOC_BUILD=1`（实验二：MEM 段例化 `dbus_decode`，mmio 总线穿出） |
| mmio 总线 | `cs_mmio`(1) / `reg_off[1:0]` / `mmio_we`(1) / `mmio_wdata[31:0]` 出；`mmio_rdata[31:0]` 入 |
| 总线适配 | `soc_top` 内 `addr[3:0] = {reg_off, 2'b00}`；槽译码在 IP 内自含（`addr[3:2]`） |
| MMIO 窗口 | `0x0000_4000`：TX(+0)/STAT(+4)/RX(+8)；`lw`=in/r、`sw`=out/w |
| 状态位义 | `TX_BUSY`=挂起或移位中（写接受仅限完全空闲）；`RX_VALID` 读 RX 槽末沿清除 |
| 存储容量 | 仿真/契约 4 KB×2；下板 build 缩容 IMEM 512 B / DMEM 256 B（`*_BYTES` 宏，`verilog_define` 覆盖） |
| 复位语义 | core 侧 `rst` 异步高有效；板上 `rst_n` 经 `reset_sync` 异步置位/同步释放；极性由 `RST_ACTIVE_LOW` 兜底 |
| 停机约定 | 无停机指令；程序末尾自循环，TB 按固定周期运行后采样比对 |

#### (4) 变更同步规则

任何**位义 / 地址映射 / 容量 / 器件**变更，必须按"**先改计组单源文档 → 再改实现 → 最后同步本报告与 PPT**"的顺序执行；两侧不一致时以计组单源为准。范例：2026-09-06 的 `TX_BUSY` 语义修正即同步更新了 `isa v1.4`、`pipeline/doc/top_design.md v1.5`、`UART/doc/interface.md v1.1`（后续结构合并再同步为 v1.3/v1.7）。

#### (5) 联合验证口径

三层回归全绿后再下板：计组 core **23** 项 → UART IP **4** 项 → SoC **5** 项（三条命令：`run_tb.ps1`、`run_soc_tb.ps1 -All`、`run_soc_tb.ps1`；`-All` 合计 9 项）；下板整机一次验收（banner/回显/复位重跑），证据与下板记录归档见 `soc/doc/board_runbook.md`。

---

## 附录 A 26 条 RV32I 指令编码表

（内容取自原报告表 5.1-1，建议随本附录迁移，正文 5.1 不再展开。）

| 序号 | 指令 | opcode | funct3 | 功能 |
|---|---|---|---|---|
| 1 | add | 0110011 | 000 | rd=rs1+rs2 |
| 2 | sub | 0110011 | 000 | rd=rs1−rs2 |
| 3 | sll | 0110011 | 001 | rd=rs1<<shamt |
| 4 | slt | 0110011 | 010 | rd=(rs1<rs2) 有符号 |
| 5 | sltu | 0110011 | 011 | rd=(rs1<rs2) 无符号 |
| 6 | xor | 0110011 | 100 | rd=rs1^rs2 |
| 7 | srl | 0110011 | 101 | rd=rs1>>shamt 逻辑 |
| 8 | sra | 0110011 | 101 | rd=rs1>>shamt 算术 |
| 9 | or | 0110011 | 110 | rd=rs1\|rs2 |
| 10 | and | 0110011 | 111 | rd=rs1&rs2 |
| 11 | addi | 0010011 | 000 | rd=rs1+sext(imm) |
| 12 | slli | 0010011 | 001 | rd=rs1<<shamt |
| 13 | slti | 0010011 | 010 | rd=(rs1<sext(imm)) 有符号 |
| 14 | sltiu | 0010011 | 011 | rd=(rs1<sext(imm)) 无符号 |
| 15 | xori | 0010011 | 100 | rd=rs1^sext(imm) |
| 16 | srli | 0010011 | 101 | rd=rs1>>shamt 逻辑 |
| 17 | srai | 0010011 | 101 | rd=rs1>>shamt 算术 |
| 18 | ori | 0010011 | 110 | rd=rs1\|sext(imm) |
| 19 | andi | 0010011 | 111 | rd=rs1&sext(imm) |
| 20 | lui | 0110111 | — | rd={imm,12'b0} |
| 21 | lw | 0000011 | 010 | rd=DMEM[rs1+imm] |
| 22 | sw | 0100011 | 010 | DMEM[rs1+imm]=rs2 |
| 23 | beq | 1100011 | 000 | rs1==rs2 则跳转 |
| 24 | bne | 1100011 | 001 | rs1≠rs2 则跳转 |
| 25 | jal | 1101111 | — | rd=pc+4；跳转 |
| 26 | jalr | 1100111 | 000 | rd=pc+4；pc=rs1+imm |

## 附录 B 待补数据与运行方式

| 项 | 状态 | 说明 |
|---|---|---|
| 计组 core 回归最终数字 | ⬜ | `powershell -File pipeline/src/scripts/run_tb.ps1`（提交前跑一次全量，记录 PASS n/23） |
| UART IP 回归数字 | ✅ 已可复现 | `powershell -File soc/scripts/run_soc_tb.ps1 -All`（仓库自带 runner，覆盖 `UART/src/test` 的 `tb_uart_tx`/`tb_uart_rx`/`tb_uart_ip_top`/`tb_wave_868`；判据 `sim.log` 内 `ALL PASS`） |
| SoC 回归数字 | ✅ 已可复现 | `powershell -File soc/scripts/run_soc_tb.ps1`（默认 3 项：`tb_reset_sync`/`tb_soc_console`/`tb_soc_full`；`-All` 追加 `tb_dbus_decode`/`tb_pipe_soc` 等共 9 项） |
| 下板记录 | ⬜ | 按 `soc/doc/board_runbook.md` 分层记录（banner/回显/复位重跑/证据） |
| 仿真时序证据（替代示波器） | ✅ 已具备 | `UART/doc/wave/uart_frame_868.txt`：真实分频 868 下单帧实测——位宽 8680 ns≈8.68 µs、帧长 86800 ns≈86.8 µs、波特率误差 0.0064%、跳变全落整数比特边界；复现命令见 `UART/doc/wave/README.md`（本方案不接示波器，故原"示波器波形"项改为仿真时序证据） |
| ≤5 min 演示视频 | ⬜ | 拍摄脚本见 `soc/doc/board_runbook.md` §6：开发板全景 → banner → 键盘回显 → P15 复位重跑（至少两次），与实验一视频分开归档 |
| 架构框图/状态机图 | ⬜ | 按 §5.1 文字框图重绘（建议标注 `uart_ip_top` 与 `dbus_decode` 归属） |

## 附录 C 本稿相对旧稿的主要修改

1. **模块命名**：`uart_ctrl` → `uart_ip_top`（寄存器层已并入 IP 顶层，功能/契约不变）；
2. **交付边界**：明确"实验二交付 = 独立 UART IP；SoC 为两课共建项目顶层"，新增 §5.1 三级结构表与 §5.8 交叉章节；
3. **器件口径**：`XC7A35T-1CSG324C` → 实测 `xc7a100tcsg324-1`（手册误标 35T）；
4. **存储容量**：补充下板缩容 512 B/256 B 与容量选型实测依据，dmem 低区描述加缩容注；
5. **UART 节拍**：澄清 TX 用 `clk_en` 节拍、RX 内部独立计数（`clk_en` 仅接口对齐）；
6. **复位/时钟**：补充 `reset_sync` 异步置位/同步释放、`RST_ACTIVE_LOW` 极性兜底；
7. **固件模型**：补充 `sp=0x100`、`PadBytes 512` 校验与 `imem_init.vh` 复制步骤；
8. **工具链**：汇编器改记自研 `simple_asm.py`（uv + Python 3.13.13），GNU 工具链列为备选；
9. **验证数字**：改为可复现的三层用例清单（core 23 / UART IP 4 / SoC 5；`-All` 合计 9 项），并新增上板实测结论；三层均由仓库自带 runner 复现（`run_tb.ps1` / `run_soc_tb.ps1 -All` / `run_soc_tb.ps1`）；
10. **26 条指令表**：迁至附录 A；
11. **USB-UART 桥口径**：按设备管理器实测写为 FTDI（VID_0403/PID_6010，COM8），并注明手册标 CP2102（§5.7 与附录 B）。

## 变更记录

- v1.1 2026-09-16：附录 B 的 SoC/UART 回归"运行器待补"改为仓库自带 `soc/scripts/run_soc_tb.ps1`（默认 3 项 / `-All` 9 项），core 回归项数按现状记 23；§5.7 串行侧补实测桥型号口径。
- v1.0 2026-09-07：新稿（依据重构后单源文档全面修订；新增 §5.8 与附录 A/B/C）。
