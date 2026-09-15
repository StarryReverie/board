"""Render unannotated waveform PNGs for the defense slides.

Reads the sampled CSVs produced by run_wave.ps1 and draws only the waveform
(signal names, cycle numbers, bus values). No title, notes, cursor or highlight.

Run with:
    uv run --no-project --python 3.13.13 --with matplotlib python ppt/make_waves.py
"""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ASSETS = HERE / "assets"
ASSETS.mkdir(exist_ok=True)
WAVE = ROOT / "pipeline" / "src" / "scripts" / "out" / "wave"

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

LINE = "#1f3a5f"
HIGH = "#ceeece"
HIGH_LINE = "#288228"
BUS_FILL = "#dce8fa"
BUS_LINE = "#4664b4"
GRID = "#e2e2e2"
TEXT = "#1e1e1e"

FIG_W = 12.09
FIG_H = 2.62


def load_csv(name: str) -> list[dict]:
    with open(WAVE / name, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_marks() -> dict:
    marks = {}
    with open(WAVE / "wave_marks.csv", newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            marks[row["item"]] = int(row["cycle"])
    return marks


def sx(v: int, bits: int) -> int:
    v &= (1 << bits) - 1
    if v >= (1 << (bits - 1)):
        v -= 1 << bits
    return v


def decode(w: int) -> str:
    w &= 0xFFFFFFFF
    if w == 0:
        return "bubble"
    if w == 0x13:
        return "nop"
    op = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 0x7
    rs1 = (w >> 15) & 0x1F
    rs2 = (w >> 20) & 0x1F
    f7 = (w >> 25) & 0x7F
    sh = (w >> 20) & 0x1F
    if op == 0x13:
        imm = sx(w >> 20, 12)
        if f3 == 0:
            return f"addi x{rd},x{rs1},{imm}"
        if f3 == 2:
            return f"slti x{rd},x{rs1},{imm}"
        if f3 == 3:
            return f"sltiu x{rd},x{rs1},{imm}"
        if f3 == 4:
            return f"xori x{rd},x{rs1},{imm}"
        if f3 == 6:
            return f"ori x{rd},x{rs1},{imm}"
        if f3 == 7:
            return f"andi x{rd},x{rs1},{imm}"
        if f3 == 1:
            return f"slli x{rd},x{rs1},{sh}"
        if f3 == 5:
            return f"srai x{rd},x{rs1},{sh}" if f7 == 0x20 else f"srli x{rd},x{rs1},{sh}"
    if op == 0x33:
        base = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}.get(f3, "r")
        if f3 == 0 and f7 == 0x20:
            base = "sub"
        if f3 == 5 and f7 == 0x20:
            base = "sra"
        return f"{base} x{rd},x{rs1},x{rs2}"
    if op == 0x03:
        return f"lw x{rd},{sx(w >> 20, 12)}(x{rs1})"
    if op == 0x23:
        return f"sw x{rs2},{sx((w >> 25) << 5 | ((w >> 7) & 0x1F), 12)}(x{rs1})"
    if op == 0x63:
        b = (((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1)
        return f"{'beq' if f3 == 0 else 'bne'} x{rs1},x{rs2},{sx(b, 13)}"
    if op == 0x6F:
        j = (((w >> 31) & 1) << 20) | (((w >> 21) & 0x3FF) << 1) | (((w >> 20) & 1) << 11) | (((w >> 12) & 0xFF) << 12)
        return f"jal x{rd},{sx(j, 21)}"
    if op == 0x67:
        return f"jalr x{rd},{sx(w >> 20, 12)}(x{rs1})"
    if op == 0x37:
        return f"lui x{rd},0x{(w >> 12) & 0xFFFFF:X}"
    return f"0x{w:08X}"


def fmt(kind: str, raw: str) -> str:
    if raw in ("x", "X"):
        return "x"
    if raw in ("z", "Z"):
        return "z"
    n = int(raw)
    if kind == "inst":
        return decode(n)
    if kind == "pc":
        return f"0x{n:X}"
    if kind == "hex":
        return f"0x{n:08X}"
    if kind == "fwd":
        return {1: "01 EX/MEM", 2: "10 MEM/WB"}.get(n, "00 reg")
    return str(n)


def render(data, start, end, rows, out_path: Path) -> None:
    ncyc = end - start + 1
    nrow = len(rows)
    gutter = 2.05
    fig = plt.figure(figsize=(FIG_W, FIG_H), dpi=200)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_axis_off()
    cell = (FIG_W - gutter) / ncyc
    left = -gutter / cell
    ax.set_xlim(left, ncyc)
    ax.set_ylim(nrow, -0.62)
    ax.set_aspect("auto")

    for c in range(ncyc + 1):
        ax.plot([c, c], [-0.45, nrow], color=GRID, linewidth=0.8, zorder=0)
    for c in range(ncyc):
        ax.text(c + 0.5, -0.30, str(start + c), ha="center", va="center", fontsize=8.5, color=TEXT)
    ax.plot([left, ncyc], [0, 0], color=GRID, linewidth=0.8)

    for r, spec in enumerate(rows):
        ax.text(left + 0.05, r + 0.5, spec["name"], ha="left", va="center", fontsize=9.5, color=TEXT)
        ax.plot([left, ncyc], [r + 1, r + 1], color=GRID, linewidth=0.8)
        kind = spec["type"]
        if kind == "clk":
            yhi, ylo = r + 0.28, r + 0.72
            for c in range(ncyc):
                ax.plot([c, c + 0.5, c + 0.5, c + 1], [yhi, yhi, ylo, ylo], color=HIGH_LINE, linewidth=1.2)
                ax.plot([c + 1, c + 1], [ylo, yhi], color=HIGH_LINE, linewidth=1.2)
            continue
        if kind == "bit":
            yhi, ylo = r + 0.28, r + 0.72
            prev = None
            for c in range(ncyc):
                raw = data[start + c - 1].get(spec["col"], "0")
                v = 1 if raw.isdigit() and int(raw) != 0 else 0
                y = yhi if v else ylo
                if v:
                    ax.add_patch(Rectangle((c, yhi), 1, ylo - yhi, facecolor=HIGH, edgecolor="none", zorder=0.5))
                if prev is not None and prev != v:
                    ax.plot([c, c], [yhi, ylo], color=HIGH_LINE, linewidth=1.4)
                ax.plot([c, c + 1], [y, y], color=HIGH_LINE, linewidth=1.4)
                prev = v
            continue
        for c in range(ncyc):
            raw = data[start + c - 1].get(spec["col"], "0")
            txt = fmt(spec.get("fmt", "dec"), raw)
            ax.add_patch(Rectangle((c + 0.04, r + 0.16), 0.92, 0.68, facecolor=BUS_FILL,
                                   edgecolor=BUS_LINE, linewidth=0.9, zorder=0.6))
            ax.text(c + 0.5, r + 0.5, txt, ha="center", va="center", fontsize=8.2, color=TEXT, zorder=1)

    fig.savefig(out_path, facecolor="white")
    plt.close(fig)


def main() -> None:
    marks = load_marks()
    cover = load_csv("wave_cover.csv")
    hazard = load_csv("wave_hazard.csv")
    priority = load_csv("wave_priority.csv")

    render(
        cover, marks["1"] - 2, marks["1"] + 3,
        [
            {"name": "clk 100MHz", "type": "clk"},
            {"name": "pc", "type": "bus", "col": "pc", "fmt": "pc"},
            {"name": "IF inst", "type": "bus", "col": "if_inst", "fmt": "inst"},
            {"name": "ID inst", "type": "bus", "col": "id_inst", "fmt": "inst"},
            {"name": "EX inst", "type": "bus", "col": "ex_inst", "fmt": "inst"},
            {"name": "MEM inst", "type": "bus", "col": "mem_inst", "fmt": "inst"},
            {"name": "WB inst", "type": "bus", "col": "wb_inst", "fmt": "inst"},
        ],
        ASSETS / "wave-overview.png",
    )

    render(
        priority, marks["2b"] - 1, marks["2b"] + 2,
        [
            {"name": "fwd_a_sel", "type": "bus", "col": "fwd_a", "fmt": "fwd"},
            {"name": "exmem_alu_result", "type": "bus", "col": "exmem_alu", "fmt": "hex"},
            {"name": "wb_data", "type": "bus", "col": "wb_data", "fmt": "hex"},
            {"name": "alu_a", "type": "bus", "col": "alu_a", "fmt": "hex"},
            {"name": "alu_out", "type": "bus", "col": "alu_out", "fmt": "hex"},
        ],
        ASSETS / "wave-priority.png",
    )

    render(
        hazard, marks["3"] - 2, marks["3"] + 3,
        [
            {"name": "stall", "type": "bit", "col": "stall"},
            {"name": "pc", "type": "bus", "col": "pc", "fmt": "pc"},
            {"name": "ID inst", "type": "bus", "col": "id_inst", "fmt": "inst"},
            {"name": "EX inst", "type": "bus", "col": "ex_inst", "fmt": "inst"},
            {"name": "MEM inst", "type": "bus", "col": "mem_inst", "fmt": "inst"},
            {"name": "WB inst", "type": "bus", "col": "wb_inst", "fmt": "inst"},
        ],
        ASSETS / "wave-loaduse.png",
    )

    render(
        hazard, marks["4"] - 1, marks["4"] + 3,
        [
            {"name": "br_taken", "type": "bit", "col": "br_taken"},
            {"name": "br_target", "type": "bus", "col": "br_target", "fmt": "pc"},
            {"name": "pc", "type": "bus", "col": "pc", "fmt": "pc"},
            {"name": "IF inst", "type": "bus", "col": "if_inst", "fmt": "inst"},
            {"name": "ID inst", "type": "bus", "col": "id_inst", "fmt": "inst"},
            {"name": "EX inst", "type": "bus", "col": "ex_inst", "fmt": "inst"},
        ],
        ASSETS / "wave-branch.png",
    )

    print("waveforms written to", ASSETS)


if __name__ == "__main__":
    main()
