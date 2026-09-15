"""Generate PNG figures for the defense slides.

Run with:
    uv run --no-project --python 3.13.13 --with matplotlib python ppt/make_figs.py
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

PRIMARY = "#1f3a5f"
ACCENT = "#2e8b8b"
TEXT = "#222222"


def uart_frame() -> None:
    bits = [
        ("str", 0),
        ("d0", 0),
        ("d1", 1),
        ("d2", 0),
        ("d3", 1),
        ("d4", 1),
        ("d5", 0),
        ("d6", 1),
        ("d7", 0),
        ("stp", 1),
    ]
    fig, ax = plt.subplots(figsize=(10.5, 3.0), dpi=200)

    prev = 1
    ax.plot([-1, 0], [1, 1], color=PRIMARY, linewidth=2.2)
    ax.plot([-1, 0], [1, bits[0][1]], color=PRIMARY, linewidth=1.4, linestyle="--")
    for i, (_, level) in enumerate(bits):
        if level != prev:
            ax.plot([i, i], [prev, level], color=PRIMARY, linewidth=2.2)
        ax.plot([i, i + 1], [level, level], color=PRIMARY, linewidth=2.2)
        prev = level
    ax.plot([10, 11], [1, 1], color=PRIMARY, linewidth=2.2)

    for i, (name, level) in enumerate(bits):
        ax.text(
            i + 0.5,
            1.35,
            f"{name}\n{level}",
            ha="center",
            va="bottom",
            fontsize=9,
            color=TEXT,
        )
    for i in range(len(bits) + 1):
        ax.plot([i, i], [-0.35, 1.05], color="#c9d3df", linewidth=0.8, zorder=0)

    ax.annotate(
        "",
        xy=(1, -0.28),
        xytext=(0, -0.28),
        arrowprops=dict(arrowstyle="<->", color=ACCENT, linewidth=1.4),
    )
    ax.text(0.5, -0.5, "位宽 8.68 微秒", ha="center", va="top", fontsize=9, color=ACCENT)

    ax.annotate(
        "",
        xy=(10, 0.62),
        xytext=(0, 0.62),
        arrowprops=dict(arrowstyle="<->", color="#b06000", linewidth=1.4),
    )
    ax.text(
        5,
        0.68,
        "帧长 86.8 微秒（10 位）",
        ha="center",
        va="bottom",
        fontsize=9,
        color="#b06000",
    )

    ax.set_xlim(-1.3, 11.3)
    ax.set_ylim(-0.9, 1.9)
    ax.set_yticks([0, 1])
    ax.set_yticklabels(["低", "高"], fontsize=9)
    ax.set_xticks([])
    ax.set_title(
        "8N1 帧时序：1 起始位（低）、8 数据位（LSB 先）、1 停止位（高）",
        fontsize=11,
        color=TEXT,
    )
    for spine in ("top", "right", "bottom"):
        ax.spines[spine].set_visible(False)
    ax.spines["left"].set_color("#c9d3df")
    fig.tight_layout()
    fig.savefig(ASSETS / "uart-frame.png", bbox_inches="tight", facecolor="white")
    plt.close(fig)


def instr_bar() -> None:
    cats = ["运算类 R 型", "运算类 I 型", "传送类", "控制类"]
    vals = [10, 9, 3, 4]
    fig, ax = plt.subplots(figsize=(6.2, 4.0), dpi=200)
    bars = ax.bar(cats, vals, color=[PRIMARY, PRIMARY, ACCENT, ACCENT], width=0.55)
    for bar, val in zip(bars, vals):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            val + 0.2,
            str(val),
            ha="center",
            va="bottom",
            fontsize=11,
            color=TEXT,
        )
    ax.set_ylim(0, 12)
    ax.set_ylabel("指令条数", fontsize=10, color=TEXT)
    ax.set_title("指令类别与条数（共 26 条）", fontsize=11, color=TEXT)
    ax.tick_params(axis="x", labelsize=10)
    ax.tick_params(axis="y", labelsize=9)
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    fig.tight_layout()
    fig.savefig(ASSETS / "instr-bar.png", bbox_inches="tight", facecolor="white")
    plt.close(fig)


def main() -> None:
    uart_frame()
    instr_bar()
    print("figures written to", ASSETS)


if __name__ == "__main__":
    main()
