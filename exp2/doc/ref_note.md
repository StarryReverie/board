# 参考梳理（计组 core 口径 + EES-338 板卡要点）

- 版本：v1.0（2026-09-04）。用途：本实验设计/编码/下板时引用的外部口径速查，避免每次回翻长文档；不改动任何参考工程。

---

## 1. 计组 CPU core 关键口径（引用 `../../doc/top_design.md` v1.4）

| 主题 | 口径 | 对本实验的意义 |
|---|---|---|
| 流水线 | 5 级 IF→ID→EX→MEM→WB，哈佛 IMEM/DMEM 分离 | 集成不改流水级数；dbus_decode 插 MEM 段不引入新冒险 |
| 访存时序 | dmem 同步写（末沿）+ 组合读；lw/sw 一拍完成 | uart_ctrl 写采样沿=MEM 末沿；读须组合且在拍内稳定 |
| 控制/冒险 | 前递 EX/MEM·MEM/WB→EX；load-use 冻结 1 拍；分支 taken 冲刷 2 条 | 与 hazard 无关：外设访问按 rd 判定，前递/冻结机制对 MMIO lw 同样生效（lw 读外设=load，紧接使用会停 1 拍） |
| 复位 | `rst` **异步高有效**；复位 PC=0、流水与 regfile 清零 | reset_sync 输出必须满足该语义；**dmem 不清**→固件自初始化数据区 |
| imem | `.vh` 初值固化（综合装载），$readmemh 仅供仿真；运行期只读（写口预留恒 0） | 固件=固定程序；换程序=重生成 .vh 重综合 |
| MMIO | 统一编址（方案 B），窗口 0x4000；`lw`=in/r、`sw`=out/w；rdata 无命中=0 | 汇编程序直接 lw/sw 访问外设，无自定义指令 |
| 端口 | 实验二 build 穿出 cs_mmio/reg_off/mmio_we/mmio_wdata/mmio_rdata | uart_ctrl 只接这组信号，不依赖 core 内部信号 |

> 计组 core 的 RTL 属于计组交付物（`rtl/`）；本实验**引用不复制**，soc_top 例化 pipeline_top。

## 2. EES-338 板卡要点（依元素口袋计算机用户手册 v1.0）

| 项 | 值 | 备注 |
|---|---|---|
| FPGA | XC7A35T-1CSG324C（Artix-7） | — |
| 系统时钟 | 100 MHz，SYS_CLK → **T5** | 全局时钟；波特率分频=868@115200 |
| UART 桥 | CP2102（USB-UART，Type-C/板上丝印 USB-UART） | 插 PC 枚举为 "Silicon Labs CP210x USB to UART Bridge"+COMx |
| FPGA 发送 | 网络名 `UART_RX`（CP2102 25 脚）→ **T4** | 命名以 CP2102 视角，方向以 FPGA 为准（输出） |
| FPGA 接收 | 网络名 `UART_TX`（CP2102 26 脚）→ **N5** | 输入；全双工第二根线 |
| 复位键 | FPGA_RESET → **P15**（S8/S6） | 极性手册未明示，以 demo XDC/实测为准 |
| 帧格式 | 8N1（手册明确无校验、1 停止位） | 与设计一致 |
| 配置 | USB-JTAG(J6)/6-pin JTAG(J3)/SPI-Flash(25Q064) 自启动 | 固化程序烧 .bit：JTAG 易失或写 Flash 上电自启 |
| IO 电平 | 通常 LVCMOS33 | 以厂家 demo XDC 为准 |

## 3. 工具链要点

- 汇编：`riscv-none-elf-as -march=rv32i -mabi=ilp32`（计组侧已装，与 musl-as 等价）→ `objcopy -O verilog` → 字节式 `.hex`；构建脚本见计组 `scripts/build_asm.ps1`；
- 固件镜像：`.hex`（仿真 $readmemh）+ `.vh`（综合 initial，verify_hex.py 生成/校验两路一致）；
- 校验：verify_hex.py 用 objdump 反查——方案 B 无自定义指令，全流程照常（若未来引入自定义指令需改造，当前不做）。

## 4. 变更记录

- v1.0 2026-09-04：初版。
