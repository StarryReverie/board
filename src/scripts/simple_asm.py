# /// script
# requires-python = ">=3.9"
# ///
# =============================================================================
#  simple_asm.py — 简易 RV32I 汇编器（doc/isa.md 26 条冻结集 + isa §3 伪指令）
#   本机无 riscv-none-elf-as；用 uv 提供的 Python 跑本文件，直接产出
#   objcopy -O verilog 兼容字节式 .hex（首行 @00000000 + 空格分隔小端字节），
#   供 src/test/*.v 程序级 TB 的 $readmemh 装载，与现网 *_rom.hex 格式一致。
#
#   支持的语法（刻意兼容 GNU as 的 RV32I 子集）：
#     [label:] [opcode operand[, operand ...]] [# 注释]
#     - 寄存器：ABI 名(zero..t6/fp) 或 x0..x31
#     - 立即数：十进制 / 0x 十六进制 / 负（有符号 12/20 位等按指令校验）
#     - 分支/j/jal 目标：符号标签（向前向后均可）
#     - 伪指令（isa §3 白名单）：nop / j label / ret / mv rd,rs / li rd,imm
#     - li 超 12 位时展开为 lui+addi 两条
#     - 访存/jalr 寻址：offset(reg)，reg 亦可裸写（=0(reg)）
#
#   用法（uv 自动解析已装 Python，离线可用）：
#     uv run --no-project --python 3.13.13 src/scripts/simple_asm.py src/test/demo.asm
#   输出：
#     src/test/demo_rom.hex   （objcopy -O verilog 兼容字节镜像）
#     stdout 反汇编清单（地址: 机器码 助记符），供人工核对编码
# =============================================================================
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass


class AsmError(Exception):
    pass


# ---- 寄存器 ABI 表 -----------------------------------------------------
REG = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
    "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}


def parse_reg(tok, ln):
    m = re.fullmatch(r"x(\d{1,2})", tok)
    if m:
        v = int(m.group(1))
        if 0 <= v <= 31:
            return v
        raise AsmError(f"L{ln}: 寄存器越界 x{v}")
    if tok in REG:
        return REG[tok]
    raise AsmError(f"L{ln}: 非法寄存器 '{tok}'")


def parse_int(tok, ln):
    try:
        return int(tok, 0)
    except ValueError:
        raise AsmError(f"L{ln}: 非法立即数 '{tok}'")


def chk_s12(v, ln, what):
    if not (-2048 <= v <= 2047):
        raise AsmError(f"L{ln}: {what} 越界(需有符号 12 位) {v}")


def chk_s20(v, ln, what):
    if not (-(1 << 19) <= v < (1 << 19)):
        raise AsmError(f"L{ln}: {what} 越界(需有符号 20 位) {v}")


def parse_off_reg(tok, ln):
    m = re.fullmatch(r"(-?(?:0x[0-9a-fA-F]+|\d+))\(([^()]*)\)", tok)
    if m:
        return parse_int(m.group(1), ln), parse_reg(m.group(2), ln)
    return 0, parse_reg(tok, ln)


def need(o, i, ln, name):
    if len(o) != i:
        raise AsmError(f"L{ln}: {name} 操作数个数应为 {i}")
    return o


# ---- 编码函数（RISC-V RV32I，doc/isa.md §2 位序） ------------------------
def enc_R(f7, f3, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33


def enc_I(f3, rd, rs1, imm, op=0x13):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_shift(f3, f7, rd, rs1, shamt):
    return (f7 << 25) | (shamt << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x13


def enc_S(f3, rs2, rs1, imm, op=0x23):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_B(f3, rs1, rs2, off):
    s12 = (off >> 12) & 1
    m = off & 0xFFF
    return (s12 << 31) | (((m >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((m >> 1) & 0xF) << 8) | (((m >> 11) & 1) << 7) | 0x63


def enc_U(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0x37


def enc_J(rd, off):
    s20 = (off >> 20) & 1
    m = off & 0x1FFFFF
    return (s20 << 31) | (((m >> 1) & 0x3FF) << 21) | (((m >> 11) & 1) << 20) \
        | (((m >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


# ---- 单条指令 → 1..2 条编码 + 清单文本 -----------------------------------
# 返回 [(word, text)]；label 目标由 resolve 回调提供（sign 扩展后的字节偏移）
def build(mnem, o, ln, resolve):
    m = mnem

    def R(f7, f3, oi, name):
        need(o, 3, ln, name)
        rd, rs1, rs2 = parse_reg(o[0], ln), parse_reg(o[1], ln), parse_reg(o[2], ln)
        return enc_R(f7, f3, rd, rs1, rs2)

    def I(f3, oi, name):
        need(o, 3, ln, name)
        rd, rs1 = parse_reg(o[0], ln), parse_reg(o[1], ln)
        imm = parse_int(o[2], ln); chk_s12(imm, ln, name)
        return enc_I(f3, rd, rs1, imm)

    def SH(f3, f7, name):
        need(o, 3, ln, name)
        rd, rs1 = parse_reg(o[0], ln), parse_reg(o[1], ln)
        sh = parse_int(o[2], ln)
        if not (0 <= sh <= 31):
            raise AsmError(f"L{ln}: {name} 移位量应 0..31，得 {sh}")
        return enc_shift(f3, f7, rd, rs1, sh)

    if m == "add":   return [(R(0x00, 0, o, "add"), "add")]
    if m == "sub":   return [(R(0x20, 0, o, "sub"), "sub")]
    if m == "sll":   return [(R(0x00, 1, o, "sll"), "sll")]
    if m == "slt":   return [(R(0x00, 2, o, "slt"), "slt")]
    if m == "sltu":  return [(R(0x00, 3, o, "sltu"), "sltu")]
    if m == "xor":   return [(R(0x00, 4, o, "xor"), "xor")]
    if m == "srl":   return [(R(0x00, 5, o, "srl"), "srl")]
    if m == "sra":   return [(R(0x20, 5, o, "sra"), "sra")]
    if m == "or":    return [(R(0x00, 6, o, "or"), "or")]
    if m == "and":   return [(R(0x00, 7, o, "and"), "and")]

    if m == "addi":  return [(I(0, o, "addi"), "addi")]
    if m == "slti":  return [(I(2, o, "slti"), "slti")]
    if m == "sltiu": return [(I(3, o, "sltiu"), "sltiu")]
    if m == "xori":  return [(I(4, o, "xori"), "xori")]
    if m == "ori":   return [(I(6, o, "ori"), "ori")]
    if m == "andi":  return [(I(7, o, "andi"), "andi")]
    if m == "slli":  return [(SH(0b001, 0x00, "slli"), "slli")]
    if m == "srli":  return [(SH(0b101, 0x00, "srli"), "srli")]
    if m == "srai":  return [(SH(0b101, 0x20, "srai"), "srai")]

    if m == "lui":
        need(o, 2, ln, "lui")
        rd = parse_reg(o[0], ln); v = parse_int(o[1], ln)
        if not (0 <= v <= 0xFFFFF):
            raise AsmError(f"L{ln}: lui 立即数取高 20 位无符号(0..0xFFFFF)，得 {v}")
        return [(enc_U(rd, v), "lui")]

    if m == "lw":
        need(o, 2, ln, "lw")
        rd = parse_reg(o[0], ln); imm, rs1 = parse_off_reg(o[1], ln)
        chk_s12(imm, ln, "lw")
        return [(enc_I(0b010, rd, rs1, imm, op=0x03), "lw")]
    if m == "sw":
        need(o, 2, ln, "sw")
        rs2 = parse_reg(o[0], ln); imm, rs1 = parse_off_reg(o[1], ln)
        chk_s12(imm, ln, "sw")
        return [(enc_S(0b010, rs2, rs1, imm), "sw")]

    if m in ("beq", "bne"):
        need(o, 3, ln, m)
        rs1, rs2 = parse_reg(o[0], ln), parse_reg(o[1], ln)
        off = resolve(o[2], ln, m)
        if off % 2:
            raise AsmError(f"L{ln}: {m} 目标未 2 字节对齐")
        if not (-4096 <= off <= 4094):
            raise AsmError(f"L{ln}: {m} 偏移越界(±4KiB) {off}")
        f3 = 0 if m == "beq" else 1
        return [(enc_B(f3, rs1, rs2, off), m)]

    if m == "jal":
        if len(o) == 1:
            rd, tgt = 1, o[0]   # GNU/RV32I 惯例: 单操作数 jal label == jal ra,label
        else:
            need(o, 2, ln, "jal")
            rd, tgt = parse_reg(o[0], ln), o[1]
        off = resolve(tgt, ln, "jal")
        if off % 2:
            raise AsmError(f"L{ln}: jal 目标未 2 字节对齐")
        if not (-(1 << 20) <= off <= (1 << 20) - 2):
            raise AsmError(f"L{ln}: jal 偏移越界(±1MiB) {off}")
        return [(enc_J(rd, off), "jal")]

    if m == "jalr":
        need(o, 2, ln, "jalr")
        rd = parse_reg(o[0], ln); imm, rs1 = parse_off_reg(o[1], ln)
        chk_s12(imm, ln, "jalr")
        return [(enc_I(0, rd, rs1, imm, op=0x67), "jalr")]

    # ---- 伪指令（isa §3 白名单） ----
    if m == "nop":
        need(o, 0, ln, "nop")
        return [(0x00000013, "nop")]
    if m == "j":
        need(o, 1, ln, "j")
        off = resolve(o[0], ln, "j")
        if off % 2:
            raise AsmError(f"L{ln}: j 目标未 2 字节对齐")
        if not (-(1 << 20) <= off <= (1 << 20) - 2):
            raise AsmError(f"L{ln}: j 偏移越界(±1MiB) {off}")
        return [(enc_J(0, off), "j")]
    if m == "ret":
        need(o, 0, ln, "ret")
        return [(enc_I(0, 0, 1, 0, op=0x67), "ret")]
    if m == "mv":
        need(o, 2, ln, "mv")
        rd, rs = parse_reg(o[0], ln), parse_reg(o[1], ln)
        return [(enc_I(0, rd, rs, 0), "mv")]
    if m == "li":
        need(o, 2, ln, "li")
        rd = parse_reg(o[0], ln)
        imm = parse_int(o[1], ln)
        if -2048 <= imm <= 2047:
            return [(enc_I(0, rd, 0, imm), "li")]
        if not (-(1 << 31) <= imm < (1 << 31)):
            raise AsmError(f"L{ln}: li 立即数越界(32 位) {imm}")
        upper = (imm + 0x800) >> 12
        low = imm - (upper << 12)
        if not (-2048 <= low <= 2047):
            raise AsmError(f"L{ln}: li 内部展开 low={low} 越界")
        return [(enc_U(rd, upper & 0xFFFFF), "li(h)"), (enc_I(0, rd, rd, low), "li(l)")]

    raise AsmError(f"L{ln}: 不支持助记符 '{m}'（26 条冻结集或伪指令白名单内）")


def wordsize(mnem, o, ln):
    if mnem == "li":
        if len(o) != 2:
            raise AsmError(f"L{ln}: li 操作数个数应为 2")
        imm = parse_int(o[1], ln)
        return 2 if not (-2048 <= imm <= 2047) else 1
    return 1


# ---- 解析一行 → 事件（label 事件 / instr 事件） --------------------------
def parse_line(line, ln):
    s = line.split("#", 1)[0].strip()
    if not s:
        return []
    toks = re.split(r"[\s,]+", s)
    events = []
    while toks and toks[0].endswith(":"):
        name = toks.pop(0)[:-1]
        if not re.fullmatch(r"[A-Za-z_.$][A-Za-z0-9_.$]*", name):
            raise AsmError(f"L{ln}: 非法标签 '{name}'")
        events.append(("label", ln, name))
    if toks:
        events.append(("instr", ln, toks[0], tuple(toks[1:])))
    return events


def assemble(text):
    lines = text.splitlines()
    events = []
    for i, raw in enumerate(lines, 1):
        events.extend(parse_line(raw, i))

    labels = {}
    pc = 0
    for e in events:
        if e[0] == "label":
            name = e[2]
            if name in labels:
                raise AsmError(f"L{e[1]}: 重复标签 '{name}'")
            labels[name] = pc
        else:
            pc += wordsize(e[2], e[3], e[1]) * 4

    words, listing, pc = [], [], 0
    for e in events:
        if e[0] == "label":
            continue
        _, ln, mnem, o = e
        base = pc

        def res(name, l, w):
            if name not in labels:
                raise AsmError(f"L{l}: {w} 引用未定义标签 '{name}'")
            return labels[name] - base

        for word, txt in build(mnem, o, ln, res):
            listing.append((pc, word, txt))
            words.append(word & 0xFFFFFFFF)
            pc += 4
    return labels, words, listing


def dump_hex(words, path):
    n = len(words)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("@00000000\n")
        row = []
        for w in words:
            for b in w.to_bytes(4, "little"):
                row.append("%02X" % b)
                if len(row) == 16:
                    f.write(" ".join(row) + "\n")
                    row = []
        if row:
            f.write(" ".join(row) + "\n")


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("用法: simple_asm.py <asm 文件>\n")
        return 2
    src = argv[1]
    if not src.endswith(".asm"):
        sys.stderr.write("输入应为 .asm 文件\n")
        return 2
    with open(src, "r", encoding="utf-8") as f:
        text = f.read()
    labels, words, listing = assemble(text)
    out = src[:-4] + "_rom.hex"
    dump_hex(words, out)
    print(f"{len(words)} 字(指令) -> {out}")
    for pc, w, txt in listing:
        print(f"  {pc:08x}: {w:08x}  {txt}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
