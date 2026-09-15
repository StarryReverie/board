"""Render the structural diagrams for the defense slides as PNG images.

Run with:
    uv run --no-project --python 3.13.13 --with matplotlib python ppt/make_diagrams.py
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

PRIMARY = "#1f3a5f"
ACCENT = "#2e8b8b"
TEXT = "#222222"
LIGHT = "#e8eef4"
LIGHT2 = "#f4f7fa"
WARN = "#b06000"
DPI = 200


def new_ax(w: float, h: float):
    fig = plt.figure(figsize=(w, h), dpi=DPI)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, w)
    ax.set_ylim(0, h)
    ax.invert_yaxis()
    ax.set_axis_off()
    return fig, ax


def box(ax, x, y, w, h, text, fs=10, fc=LIGHT, ec=PRIMARY, tc=TEXT, bold=False):
    patch = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0,rounding_size=0.06",
        linewidth=1.0, edgecolor=ec, facecolor=fc, mutation_aspect=1,
    )
    ax.add_patch(patch)
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fs, color=tc, fontweight="bold" if bold else "normal",
            linespacing=1.9)


def label(ax, x, y, text, fs=10, color=TEXT, ha="left", bold=False):
    ax.text(x, y, text, ha=ha, va="center", fontsize=fs, color=color,
            fontweight="bold" if bold else "normal")


def arrow(ax, x1, y1, x2, y2, color=PRIMARY, lw=1.4):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw,
                                shrinkA=0, shrinkB=0, mutation_scale=12))


def save(fig, name: str):
    fig.savefig(ASSETS / f"diagram-{name}.png", facecolor="white")
    plt.close(fig)


def three_layer():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    label(ax, W / 2, 0.28, "SoC 整机（soc_top）", 12, PRIMARY, "center", True)
    box(ax, 0.1, 0.55, W - 0.2, 3.2, "", fc=LIGHT2)
    bw = (W - 0.6 - 0.2) / 2
    box(ax, 0.3, 1.55, bw, 1.45, "处理器核心\npipeline_top\nRV32I 五级流水线", 10)
    box(ax, 0.3 + bw + 0.2, 1.55, bw, 1.45, "UART IP\nuart_ip_top\n8N1 全双工", 10)
    arrow(ax, 0.3 + bw, 2.28, 0.3 + bw + 0.2, 2.28)
    label(ax, 0.3 + bw + 0.1, 1.25, "mmio 总线", 9, ACCENT, "center")
    box(ax, 0.9, 4.35, W - 1.8, 0.8, "主机 PC（USB 转串口）", 10)
    arrow(ax, W / 2, 3.75, W / 2, 4.35)
    save(fig, "three-layer")


def dir_tree():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    items = [
        ("pipeline/src", "RTL 源码、宏定义、测试平台、脚本"),
        ("UART/src", "IP 顶层、发送模块、接收模块、测试平台"),
        ("soc", "顶层装配、复位同步、数据侧译码、约束、固件、系统测试"),
    ]
    h = 1.5
    for i, (name, desc) in enumerate(items):
        y = 0.3 + i * (h + 0.25)
        box(ax, 0.1, y, W - 0.2, h, f"{name}\n{desc}", 10,
            LIGHT if i % 2 == 0 else LIGHT2)
    save(fig, "dir-tree")


def pipeline_5stage():
    W, H = 12.09, 2.57
    fig, ax = new_ax(W, H)
    stages = ["取指 IF", "译码 ID", "执行 EX", "访存 MEM", "回写 WB"]
    regs = ["if_id", "id_ex", "ex_mem", "mem_wb"]
    gap = 0.3
    bw = (W - 0.4 - 4 * gap) / 5
    for i, s in enumerate(stages):
        x = 0.2 + i * (bw + gap)
        box(ax, x, 0.35, bw, 1.0, s, 12, LIGHT, PRIMARY, PRIMARY, True)
        if i < 4:
            arrow(ax, x + bw, 0.85, x + bw + gap, 0.85)
    for i, r in enumerate(regs):
        x = 0.2 + i * (bw + gap) + bw
        label(ax, x, 1.62, r, 10, ACCENT, "center")
    label(ax, W / 2, 2.2, "指令存储器与数据存储器分离（哈佛结构），取指与访存不冲突",
          11, "#5a6672", "center")
    save(fig, "pipeline-5stage")


def uart_fsm(name, title, states, note):
    W, H = 5.9, 3.37
    fig, ax = new_ax(W, H)
    label(ax, W / 2, 0.3, title, 12, PRIMARY, "center", True)
    gap = 0.16
    bw = (W - 0.3 - 3 * gap) / 4
    y = 0.95
    bh = 1.15
    for i, s in enumerate(states):
        x = 0.15 + i * (bw + gap)
        box(ax, x, y, bw, bh, s, 9)
        if i < 3:
            arrow(ax, x + bw, y + bh / 2, x + bw + gap, y + bh / 2)
    arrow(ax, 0.15 + 3 * (bw + gap) + bw / 2, y + bh + 0.12,
          0.15 + bw / 2, y + bh + 0.12, color=ACCENT)
    label(ax, W / 2, y + bh + 0.42, note, 9, ACCENT, "center")
    save(fig, name)


def addr_map():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    rows = [
        ("0x0000_0000 至 0x0000_0FFF", "dmem 数据存储器", LIGHT),
        ("0x0000_4000", "TX 槽（sw 写发送）", LIGHT2),
        ("0x0000_4004", "STAT 槽（lw 读状态）", LIGHT2),
        ("0x0000_4008", "RX 槽（lw 读字节）", LIGHT2),
        ("其余地址", "读 0，写丢弃", LIGHT),
    ]
    h = 0.92
    for i, (addr, desc, fc) in enumerate(rows):
        y = 0.25 + i * (h + 0.16)
        box(ax, 0.1, y, W - 0.2, h, f"{addr}\n{desc}", 9, fc)
    save(fig, "addr-map")


def txbusy_timing():
    W, H = 12.09, 2.57
    fig, ax = new_ax(W, H)
    label(ax, W / 2, 0.3, "TX_BUSY 由挂起与移位两个状态共同置位", 10, "#5a6672", "center")
    segs = [
        ("空闲", "busy=0", LIGHT),
        ("接受并挂起", "busy=1", LIGHT2),
        ("移位中", "busy=1", "#d6e6e6"),
        ("空闲", "busy=0", LIGHT),
    ]
    bw = W / 4
    y = 0.6
    bh = 0.9
    for i, (name, busy, fc) in enumerate(segs):
        box(ax, i * bw, y, bw, bh, f"{name}\n{busy}", 10, fc)
    arrow(ax, 0.05, y + bh + 0.5, W - 0.05, y + bh + 0.5, color="#5a6672", lw=1.0)
    label(ax, W / 2, y + bh + 0.28, "写操作仅在 busy=0 时被接受；busy=1 期间写入被丢弃",
          10, WARN, "center")
    save(fig, "txbusy-timing")


def soc_assembly():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    box(ax, 0.1, 0.3, W - 0.2, 5.0, "", fc=LIGHT2)
    label(ax, W / 2, 0.62, "soc_top（整机顶层）", 11, PRIMARY, "center", True)
    rows = ["reset_sync（复位同步）", "pipeline_top（含 dbus_decode）", "uart_ip_top（UART IP）"]
    x = 0.4
    bw = W - 0.8
    bh = 0.9
    y3 = 1.15 + 2 * (bh + 0.28)
    for i, r in enumerate(rows):
        y = 1.15 + i * (bh + 0.28)
        box(ax, x, y, bw, bh, r, 10)
        if i < 2:
            arrow(ax, x + bw * 0.5, y + bh, x + bw * 0.5, y + bh + 0.28)
    arrow(ax, x + bw * 0.5, y3 + bh, x + bw * 0.5, y3 + bh + 0.2, color=ACCENT)
    label(ax, W / 2, y3 + bh + 0.46, "mmio 总线：片选、槽偏移、写使能、写数据", 9, ACCENT, "center")
    save(fig, "soc-assembly")


def reset_timing():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    label(ax, W / 2, 0.3, "复位同步 reset_sync", 11, PRIMARY, "center", True)
    label(ax, 0.15, 1.15, "rst_n（按键）", 9, "#5a6672")
    label(ax, 0.15, 2.55, "rst（核心）", 9, "#5a6672")
    x0, x1, x2, x3, x4 = 1.35, 2.2, 3.0, 3.8, W - 0.15
    yh, yl = 1.0, 1.35
    ax.plot([x0, x1, x1, x2, x2, x4], [yh, yh, yl, yl, yh, yh], color=PRIMARY, lw=1.6)
    ayh, ayl = 2.4, 2.75
    ax.plot([x0, x1, x1, x3, x3, x4], [ayl, ayl, ayh, ayh, ayl, ayl], color=ACCENT, lw=1.6)
    label(ax, W / 2, 3.35, "异步置位，同步释放", 10, ACCENT, "center")
    label(ax, W / 2, 3.8, "复位后程序从头重新运行，数据区由固件初始化", 9, "#5a6672", "center")
    save(fig, "reset-timing")


def pinout():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    bx, by, bw, bh = 1.25, 1.5, 2.4, 2.4
    box(ax, bx, by, bw, bh, "EES-338\nFPGA", 12, LIGHT2, PRIMARY, PRIMARY, True)
    pins = [
        ("clk T5", bx + bw + 0.15, by + 0.3),
        ("uart_tx T4", bx + bw + 0.15, by + 0.95),
        ("uart_rx N5", bx + bw + 0.15, by + 1.6),
    ]
    for name, x, y in pins:
        box(ax, x, y, 1.05, 0.42, name, 9)
    box(ax, bx - 1.2, by + 0.95, 1.05, 0.42, "rst_n P15", 9)
    label(ax, W / 2, 4.4, "uart 经板载 CP2102 与主机串口通信", 9, "#5a6672", "center")
    save(fig, "pinout")


def console_flow():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    steps = [
        "上电复位，从地址 0 执行",
        "初始化数据区（自初始化字符串）",
        "轮询 TX_BUSY，逐字符发送 banner",
        "进入回显循环",
        "轮询 RX_VALID，读 RX 并回发",
    ]
    h = 0.85
    bw = W - 0.85
    for i, s in enumerate(steps):
        y = 0.2 + i * (h + 0.18)
        box(ax, 0.15, y, bw, h, s, 9, LIGHT if i % 2 == 0 else LIGHT2)
        if i < len(steps) - 1:
            arrow(ax, 0.15 + bw / 2, y + h, 0.15 + bw / 2, y + h + 0.18)
    y_lo = 0.2 + 4 * (h + 0.18) + h / 2
    y_hi = 0.2 + 3 * (h + 0.18) + h / 2
    arrow(ax, W - 0.52, y_lo, W - 0.52, y_hi, color=ACCENT)
    label(ax, W - 0.34, (y_lo + y_hi) / 2, "循环", 9, ACCENT, "center")
    save(fig, "console-flow")


def build_flow():
    W, H = 12.09, 2.57
    fig, ax = new_ax(W, H)
    steps = [
        "console.S",
        "汇编\n（simple_asm.py）",
        "console_rom.hex\nconsole_init.vh",
        "综合固化 imem\n（.vh 初值）",
        "生成比特流\nsoc_top.bit",
        "JTAG 烧录\n上电运行",
    ]
    gap = 0.2
    bw = (W - 0.4 - 5 * gap) / 6
    for i, s in enumerate(steps):
        x = 0.2 + i * (bw + gap)
        box(ax, x, 0.45, bw, 1.15, s, 9, LIGHT if i % 2 == 0 else LIGHT2)
        if i < 5:
            arrow(ax, x + bw, 1.02, x + bw + gap, 1.02)
    label(ax, W / 2, 2.2, "更换程序需重新生成 .vh、重新综合、重新烧录", 10, "#5a6672", "center")
    save(fig, "build-flow")


def verify_3level():
    W, H = 4.89, 5.46
    fig, ax = new_ax(W, H)
    rows = [
        ("系统级", "行为级串口模型驱动整机固件：banner、回显、复位重跑"),
        ("IP 级", "UART IP：帧格式、状态位、忙时写丢弃、读清标志、全双工"),
        ("模块级", "逐个 RTL 模块：端口时序与功能"),
    ]
    h = 1.3
    for i, (name, desc) in enumerate(rows):
        y = 0.3 + i * (h + 0.22)
        box(ax, 0.15, y, W - 0.3, h, f"{name}\n{desc}", 9,
            LIGHT if i % 2 == 0 else LIGHT2)
    label(ax, W / 2, 4.95, "三层测试平台在仿真结束时自动比对期望值", 9, "#5a6672", "center")
    save(fig, "verify-3level")


def main():
    three_layer()
    dir_tree()
    pipeline_5stage()
    uart_fsm("uart-tx-fsm", "发送状态机 uart_tx",
             ["IDLE\n输出高", "START\n起始位", "DATA\n8 位", "STOP\n停止位"],
             "完成回 IDLE，输出 done")
    uart_fsm("uart-rx-fsm", "接收状态机 uart_rx",
             ["IDLE\n检测下降沿", "SAMPLE\n位中心采样", "ASSEMBLE\n组装 8 位", "STOP\n停止位校验"],
             "停止位为高输出有效字节，输入打两拍")
    addr_map()
    txbusy_timing()
    soc_assembly()
    reset_timing()
    pinout()
    console_flow()
    build_flow()
    verify_3level()
    print("diagrams written to", ASSETS)


if __name__ == "__main__":
    main()
