# 汇编实验任务分解与验收标准（exp2）

> 工程根：`exp2/`。总体设计文档=本目录（tasks/top_design/interface/firmware/modules）；根目录原 `../汇编实验设计方案.md`（v1.0/v1.1）内容已全部并入本目录文档并于 2026-09-04 删除。跨课程契约以 `../../doc/`（top_design v1.4、isa v1.3、tasks §6 T40–T44、modules/dbus_decode.md）为单源，本目录文档引用不重复定义。状态随执行更新。

---

## 0. 目标与口径

| 项 | 口径 |
|---|---|
| 课程任务 | 汇编与接口课程设计：基础=UART 接口控制器并形成 IP 核；进阶=与计组 CPU core 集成成自定义计算机系统（仿真正确 + EES-338 下板）；ILA=可选加分 |
| 接口控制器 | **全双工 UART**（uart_tx + uart_rx），8N1@115200，单时钟域 clk_en 分频（100 MHz → 868，误差 ≈0.06%） |
| I/O 方式 | **统一编址 MMIO（方案 B）**：不新增 in/out 指令；`lw`=外设读（in/r）、`sw`=外设写（out/w）；窗口 `0x0000_4000`（TX/STAT/RX 三字槽） |
| CPU | 计组实验一交付的 RV32I 5 级流水线 core（pipeline_top），程序 **.vh 固化单程序模型**（上电自跑 0x0；换程序=重新综合重烧；无 loader/在线重载） |
| 软件 | 程序查询（轮询 TX_BUSY/RX_VALID）；固定固件 console：banner + 键盘回显；全部指令限 26 条冻结集 |
| 范围裁剪 | 无收发 FIFO、无中断、无 DMA、无硬件流控、无可配波特率寄存器（参数/分频综合前确定）；无 ILA（可选加分，U33）；无 loader/在线重载（换程序=重新生成 .vh→综合→重烧）；忙/溢出=软件轮询+丢弃 |
| 板卡 | 依元素 EES-338（XC7A35T-1CSG324C）：clk=T5(100MHz)、uart_tx=T4、uart_rx=N5、rst_n=P15（极性以 demo XDC 为准） |
| 语言/工具 | RTL=Verilog/SystemVerilog（Vivado 可混用）；汇编=musl-as `-march=rv32i` + objcopy；镜像校验=verify_hex.py（与计组共用） |
| 本机职责 | 写 源码+文档+TB+固件镜像+XDC 草稿；综合/仿真/下板在装有 Vivado 的机器执行 |

---

## 1. 需求追溯（doc/require ↔ 任务）

| require 原文要点 | 对应任务 |
|---|---|
| 基础团队任务：完成一种接口控制器，测试后形成 IP 核 | U10–U12 + U30（uart_tx/uart_rx/uart_ctrl + 单测 → IP 打包） |
| 进阶团队任务：集成控制器与处理器，形成自定义计算机系统 | U13/U14/U31/U32（dbus_decode 交付、soc_top、系统 TB、下板） |
| 仿真正确或者在精工板上实现 | U31（仿真 PASS）+ U32（EES-338 下板）双轨 |
| 可选：ILA 应用（加分项） | U33（可选，时间有余量再做） |
| 提交物：报告/源码/PPT×2/≤5min 下板视频/日志 | U40、U50（打包提交，见 §5） |

---

## 2. 模块编码任务（每模块：先文档→编码→单测 TB）

> 仓库布局：RTL 于 `exp2/rtl/`；TB 于 `exp2/tb/`；固件汇编于 `exp2/asm/`；约束于 `exp2/xdc/`；文档 `exp2/doc/`。计组 core（pipeline_top 等）在仓库根（计组交付），本工程引用不复制。

| 任务 | 模块/文件 | 依赖 | 产出 | 验收标准（可测） |
|---|---|---|---|---|
| U10 | `rtl/uart_tx.v`（8N1 发送 FSM + 可选内联分频 `clk_en`） | 方案 §3 | 发送状态机、`busy/tx` | 复位 TX=1、busy=0；start 后 1 起始+8 数据(LSB 先)+1 停止；每位=CLKS_PER_BIT 拍；done 脉冲；忙时 start 忽略 |
| U11 | `rtl/uart_rx.v`（接收采样 FSM） | 方案 §3 | 采样状态机、`valid/rx_data` | 下降沿检测起始位；位中心采样逐位正确；停止位=1 才 valid；连续字节无丢；输入打两拍 |
| U12 | `rtl/uart_ctrl.v`（MMIO 从机封装） | U10,U11 | TX/STAT/RX 字槽、位义逻辑 | 槽地址/位义与 interface.md 一致；忙写丢弃；读 RX 清 RX_VALID；未命中读 0/写无操作 |
| U13 | `rtl/dbus_decode.v`（交付于本目录；例化于计组 pipeline_top MEM 段） | 计组 core M2 | 数据侧译码代码 | 规范单源=计组 `doc/modules/dbus_decode.md`；低区行为与 dmem 直连一致；窗口命中 TX/STAT/RX |
| U14 | `rtl/reset_sync.v` + `rtl/soc_top.v` | U12,U13 + 计组 core | 整机装配、复位同步、引脚穿出 | soc_top=core+uart_ctrl+reset_sync 正确互联；rst_n(键)→异步置位/同步释放→rst(异步高有效)；无悬空；Vivado 综合通过 |

---

## 3. 验证任务

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| U30 | 模块单测 TB（每模块一份，自动断言） | `tb/uart_tx_tb.v`、`tb/uart_rx_tb.v`、`tb/uart_ctrl_tb.v` | 各 TB `$display` 全 PASS（下板侧 Vivado 运行） |
| U31 | 系统级 TB：行为级串口模型（双向）+ 整机跑固定固件 | `tb/tb_soc_top.v` | banner 字节=注释期望；回显往返断言 PASS；复位重跑一致；长串无死锁（CLKS_PER_BIT 参数覆盖加速） |
| U32 | 下板：综合/实现/时序 + 终端验收 + 演示视频 | `xdc/*.xdc`、工程、记录 | 终端 115200-8-N-1：banner、键盘回显、复位重跑；≤5min 视频；波形/日志留档 |
| U33 | （可选加分）ILA 观测 uart 总线与 TX/RX 波形 | ILA 核 + 工程 | 答辩加分项；时间不足可放弃，不影响主线 |

### 3.1 下板验证流程（分层）与证据要求

> 分层原则：先隔离 UART 自身问题，再验证整机；每层都有明确"对/错"判定（收编自原总体方案 §8.2/§8.3）。

1. **裸 UART 先行**：临时顶层仅例化 uart_tx 定时发 `0x55` → 终端收 'U' 无乱码（引脚/波特率/帧格式正确）；再临时验证 uart_rx（PC 发字符，板上回发/LED 指示）；
2. **SoC 整机**：烧录 console 固件 → 终端 115200-8-N-1 见 banner；键盘输入逐字回显；按复位键重跑；
3. **换程序**（可选）：改 asm → 重新生成 .vh → 重新综合 → 重烧 .bit，观察新固件行为。

证据：终端日志（Tera Term/SSCOM 存档）+ 示波器 TX 波形截图（空闲高、起始位低、位宽 ≈8.68µs、10 位帧 ≈86.8µs）+ 下板记录。

常见问题速查：

| 现象 | 最可能原因 |
|---|---|
| 乱码 | 波特率不一致（终端 vs HDL 参数）/分频算错 |
| 无输出 | 引脚约束错、复位极性错、`.vh` 未更新（跑 verify_hex.py） |
| 发几次即停 | TX_BUSY 状态翻转逻辑错（轮询死锁） |
| 首字符丢/花 | 复位释放后过早发送——先等 UART 空闲/加延迟 |

---

## 4. 固件与镜像任务

> 软件口径、子程序代码与字符串方案见 `doc/firmware.md`（与 U40/U41 配套）。

| 任务 | 内容 | 产出 | 验收标准 |
|---|---|---|---|
| U40 | 汇编固件（固定程序 console）：`.equ` 内存映射头、putc/getc、banner+回显主循环 | `asm/console.S/.asm` → `.hex/.vh`（verify_hex.py 校验） | 上电自跑打印 banner；键盘回显往返正确；全指令在 26 条冻结集内；`.hex`/`.vh` 一致 |
| U41 | 机器码与文档：指令展开说明、内存映射说明 | `asm/README` 或报告素材 | 机器码可 objdump/脚本核对（方案 B：无自定义指令） |

---

## 5. 里程碑、提交物与分工

| 时间 | 节点 | 责任人 |
|---|---|---|
| 9/4–9/7 | 口径定稿（interface.md 冻结）；uart_tx/uart_rx 独立开工 | 成员 1 |
| 9/8–9/12 | uart_ctrl + 从机 TB；固件与镜像（依赖计组 core M2 与 mmio 总线端口） | 成员 2/3 |
| 9/13–9/15 | soc_top + tb_soc_top 整机仿真 PASS；综合下板 | 成员 3/4 |
| 9/16–9/18 | 报告/PPT×2/日志/演示视频；提交物打包（9/18 24:00 截止，缺项 0 分） | 全员 |

### 5.1 四人分工（收编自原总体方案 §9）

| 成员 | 职责 | 交付 |
|---|---|---|
| 成员 1 | `uart_tx` + `uart_rx`（位中心采样）与波特率分频；两者时序单测；帧格式/误差分析 | `rtl/uart_tx.v`、`rtl/uart_rx.v`、分频逻辑、`tb/uart_tx_tb.v`、`tb/uart_rx_tb.v`、报告对应章节 |
| 成员 2 | `uart_ctrl`（寄存器/位义/忙丢弃/读清位）+ `dbus_decode` 代码交付与从机口适配；从机单测 | `rtl/uart_ctrl.v`、`rtl/dbus_decode.v`、`tb/uart_ctrl_tb.v`、寄存器/位义说明 |
| 成员 3 | 汇编固件（putc/getc/banner/echo）、机器码生成与校验、系统 TB 的串行监视器与断言 | `asm/*.S → .hex/.vh`、`tb/tb_soc_top.v` 软件部分、机器码说明（doc/firmware.md） |
| 成员 4 | SoC 装配（soc_top/reset_sync）、XDC（T5/T4/N5/P15）、综合时序、下板与演示视频、提交物整合 | `rtl/soc_top.v`、`rtl/reset_sync.v`、`xdc/*.xdc`、下板记录、报告/PPT 格式统一 |

技术章节各成员撰写，成员 4 只统一格式，不代写全部内容。

提交物对照（成绩组成：团队提交 20/答辩 40/测试 20/日志 10/报告 10）：
接口控制器设计实验报告（含编址方式对比、仿真与下板记录）、源码（exp2/rtl+tb+asm+xdc）、可复用 IP 核（uart_tx/uart_rx/uart_ctrl 打包 + 集成说明）、中期/验收 PPT、≤5min 下板演示视频、日志（每日）。

---

## 6. 开放项与默认假设

| 开放项 | 默认假设/缓解 |
|---|---|
| EES-338 复位键极性（P15） | 以厂家 demo XDC/实测为准；reset_sync 隔离极性（异步置位/同步释放） |
| RX 采样可靠性 | 位中心采样 + 停止位校验；TB 覆盖位边界 ±误差；实测分频误差 0.06% 余量充足 |
| 仿真速度 | CLKS_PER_BIT 参数覆盖（系统 TB 用 8–100） |
| dmem 复位不清 | 固件启动自初始化数据区（方案 §6.1） |
| 与计组联调窗口 | 依赖计组 M1–M3（core 编码与回归）与 mmio 总线端口冻结；UART IP 部分独立先行 |

---

## 7. 变更记录

- 2026-09-04：收编并删除根目录原"汇编实验设计方案"文件——其全部信息已并入本目录（tasks/top_design/interface/firmware/ref_note/modules/require）：
  - 方案 v1.1（2026-09-04 定稿改版）：UART 改全双工；统一编址方案 B（窗口 0x4000 三槽）；程序固化单程序模型（无 loader）；板卡按 EES-338 定稿；
  - 方案 v1.0（2026-09-02 初版）：UART 单向发送、0x1000_0000 窗口、自拟 mmio_decoder 总线（已被 v1.1 口径取代，仅存档沿革）。
- 2026-09-04 v1.0：初版（对齐方案 v1.1 与计组 top_design v1.4 定稿口径：全双工、方案 B、程序固化）。
