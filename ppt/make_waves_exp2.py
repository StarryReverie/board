"""Render the focused experiment-2 waveforms for the defense slides.

Reads the per-change / per-cycle CSVs in ppt/wave/exp2/ (produced by
UART/src/scripts/run_exp2_wave.ps1) and draws two clean digital waveforms:

  * exp2-duplex.png  item 3 - full-duplex + TX_BUSY write-accept (busy write dropped)
  * exp2-mmio.png    item 4 - unified MMIO + UART echo chain

Only the waveform is drawn (signal names, time axis, value labels, numbered
markers); no simulator UI. Run with:

    uv run --no-project --python 3.13.13 --with matplotlib python ppt/make_waves_exp2.py
"""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)
WAVE = HERE / "wave" / "exp2"

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

HIGH = "#ceeece"
HIGH_LINE = "#288228"
BUS_FILL = "#dce8fa"
BUS_LINE = "#4664b4"
GRID = "#e2e2e2"
TEXT = "#1e1e1e"
ACCENT = "#b06000"
MARK = "#c04040"

FIG_W = 12.09
FIG_H = 2.62
GUTTER_FRAC = 0.205
PLOT_FRAC = 1.0 - GUTTER_FRAC


def load(name: str) -> list[dict]:
    with open(WAVE / name, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def intervals(rows: list[dict], t_end: int, value_of) -> list[tuple[int, int, str]]:
    """Merge consecutive rows with the same value of one signal into intervals."""
    out: list[tuple[int, int, str]] = []
    n = len(rows)
    for i, r in enumerate(rows):
        t0 = int(r["time_ns"])
        t1 = int(rows[i + 1]["time_ns"]) if i + 1 < n else t_end
        if t1 <= t0:
            t1 = t0 + 10
        v = value_of(r)
        if out and out[-1][2] == v:
            out[-1] = (out[-1][0], t1, out[-1][2])
        else:
            out.append((t0, t1, v))
    return out


def bit_of(raw: str) -> int:
    if raw in ("x", "X", "z", "Z", ""):
        return 0
    try:
        return 1 if int(raw) != 0 else 0
    except ValueError:
        return 0


def fmt_val(raw: str, kind: str) -> str:
    if raw in ("x", "X", "z", "Z"):
        return raw.lower()
    try:
        n = int(raw)
    except ValueError:
        return raw
    return f"0x{n:X}" if kind == "hex" else str(n)


def _bus_value(row: dict, spec: dict) -> str:
    gate = spec.get("gate")
    if gate is not None and not gate(row):
        return "0"
    return row.get(spec["col"], "0")


def render(
    out_path: Path,
    rows: list[dict],
    window: tuple[int, int],
    scale: float,
    signals: list[dict],
    markers: list[tuple[int, str]],
    legend: list[str],
) -> None:
    t0, t1 = window
    n = len(signals)
    span = t1 - t0
    pad = span * GUTTER_FRAC / PLOT_FRAC
    x_left = (t0 - pad) * scale
    x0 = t0 * scale
    x1 = t1 * scale

    fig = plt.figure(figsize=(FIG_W, FIG_H), dpi=200)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_axis_off()
    ax.set_xlim(x_left, x1)
    ax.set_ylim(n + 1.35, -0.78)
    ax.set_aspect("auto")

    plot_w_in = FIG_W * PLOT_FRAC

    # time grid + tick labels
    step = _nice_step(span)
    tick = (int(t0 / step) + 1) * step
    while tick <= t1:
        x = tick * scale
        ax.plot([x, x], [-0.62, n], color=GRID, linewidth=0.8, zorder=0)
        ax.text(x, -0.70, _tick_label(tick, scale), ha="center", va="center",
                fontsize=8, color=TEXT)
        tick += step

    # numbered markers (vertical dashed lines + number above the waveform)
    for i, (mt, _) in enumerate(markers):
        if t0 <= mt <= t1:
            ax.plot([mt * scale, mt * scale], [-0.55, n], color=MARK, linewidth=1.0,
                    linestyle=(0, (4, 3)), zorder=0.4)
            ax.text(mt * scale, -0.28, str(i + 1), ha="center", va="center",
                    fontsize=8, color=MARK, fontweight="bold")

    for r, spec in enumerate(signals):
        ax.text(x_left + 0.008 * span * scale, r + 0.5, spec["name"], ha="left",
                va="center", fontsize=9, color=TEXT)
        ax.plot([x0, x1], [r + 1, r + 1], color=GRID, linewidth=0.8)

        if spec["type"] == "bit":
            ivs = intervals(rows, t1, lambda rr, s=spec: bit_of(rr.get(s["col"], "0")))
            yhi, ylo = r + 0.28, r + 0.72
            prev = None
            for a, b, v in ivs:
                if b <= t0:
                    continue
                a, b = max(a, t0), min(b, t1)
                y = yhi if v else ylo
                if v:
                    ax.add_patch(Rectangle((a * scale, yhi), (b - a) * scale, ylo - yhi,
                                           facecolor=HIGH, edgecolor="none", zorder=0.5))
                if prev is not None and prev != v:
                    ax.plot([a * scale, a * scale], [yhi, ylo], color=HIGH_LINE, linewidth=1.4)
                ax.plot([a * scale, b * scale], [y, y], color=HIGH_LINE, linewidth=1.4)
                prev = v
            continue

        ivs = intervals(rows, t1, lambda rr, s=spec: _bus_value(rr, s))
        yt, yb = r + 0.20, r + 0.80
        ax.plot([x0, x1], [r + 0.5, r + 0.5], color=BUS_LINE, linewidth=0.9, zorder=0.5)
        for a, b, raw in ivs:
            if b <= t0:
                continue
            a, b = max(a, t0), min(b, t1)
            txt = fmt_val(raw, spec.get("fmt", "hex"))
            if txt in ("0", "0x0"):
                continue
            w_in = (b - a) / span * plot_w_in
            ax.add_patch(Rectangle((a * scale, yt), (b - a) * scale, yb - yt,
                                   facecolor=BUS_FILL, edgecolor=BUS_LINE, linewidth=0.8,
                                   zorder=0.6))
            if w_in >= 0.45:
                ax.text((a + b) / 2 * scale, r + 0.5, txt, ha="center", va="center",
                        fontsize=7.2, color=TEXT, zorder=1)

    for i, line in enumerate(legend):
        ax.text(x0, n + 0.42 + 0.40 * i, line, ha="left", va="center", fontsize=7.5,
                color=ACCENT)

    fig.savefig(out_path, facecolor="white")
    plt.close(fig)


def _nice_step(span: int) -> int:
    for s in (10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000,
              10000, 20000, 25000, 50000, 100000):
        if span / s <= 12:
            return s
    return 200000


def _tick_label(tick: int, scale: float) -> str:
    return str(tick) if scale == 1.0 else f"{tick * scale:g}"


def duplex() -> None:
    rows = load("ip_duplex.csv")
    signals = [
        {"name": "uart_tx_pin", "col": "uart_tx_pin", "type": "bit"},
        {"name": "accept", "col": "accept", "type": "bit"},
        {"name": "tx_busy", "col": "tx_busy", "type": "bit"},
        {"name": "tx_pend", "col": "tx_pend", "type": "bit"},
        {"name": "wdata[31:0]", "col": "wdata", "type": "bus", "fmt": "hex"},
        {"name": "tx_buf[7:0]", "col": "tx_buf", "type": "bus", "fmt": "hex"},
    ]
    markers = [
        (138976, "0xA1"),
        (147646, "0xB2"),
        (234436, "silence"),
    ]
    render(
        ASSETS / "exp2-duplex.png", rows, (137500, 350000), 1 / 1000.0, signals, markers,
        ["① 空闲写 0xA1：accept=1（被接受）　② 移位期写 0xB2：accept=0（丢弃）　"
         "③ 停止位后 12 bit 无第二帧　｜　时间轴 µs"],
    )


def mmio() -> None:
    rows = load("wave_soc.csv")
    signals = [
        {"name": "uart_tx_pin", "col": "uart_tx_pin", "type": "bit"},
        {"name": "uart_rx_pin", "col": "uart_rx_pin", "type": "bit"},
        {"name": "cs_mmio", "col": "cs_mmio", "type": "bit"},
        {"name": "mmio_we", "col": "mmio_we", "type": "bit"},
        {"name": "mmio_wdata[31:0]", "col": "mmio_wdata", "type": "bus", "fmt": "hex",
         "gate": lambda r: r.get("cs_mmio") == "1" and r.get("mmio_we") == "1"},
        {"name": "mmio_rdata[31:0]", "col": "mmio_rdata", "type": "bus", "fmt": "hex"},
    ]
    markers = [
        (176, "STAT"),
        (216, "TX=0x41"),
        (256, "frame 0x41"),
        (1006, "inject 0x42"),
        (1506, "RX=0x42"),
        (1566, "TX=0x42"),
        (1616, "echo 0x42"),
    ]
    render(
        ASSETS / "exp2-mmio.png", rows, (0, 2050), 1.0, signals, markers,
        ["① STAT 读 0x4004（reg_off=01）　② sw 写 TX 0x4000 ← 0x41　③ 出帧 0x41　④ 注入 0x42",
         "⑤ lw 读 RX 0x4008 → 0x42　⑥ sw 写 TX 0x4000 ← 0x42　⑦ 回显帧 0x42　"
         "｜　窗口基址 0x0000_4000　｜　时间轴 ns"],
    )


def main() -> None:
    duplex()
    mmio()
    print("exp2 waveforms written to", ASSETS)


if __name__ == "__main__":
    main()
