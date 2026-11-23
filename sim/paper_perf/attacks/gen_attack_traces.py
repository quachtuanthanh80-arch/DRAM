# File: sim/paper_perf/attacks/gen_attack_traces.py
# Chức năng: Sinh 4 trace tấn công RowHammer/RowPress chuẩn định dạng SimpleO3/BHO3 để kiểm cổng hợp lệ T80.

from pathlib import Path


OUT_DIR = Path(__file__).resolve().parent
# DDR5_16Gb_x4 + RoBaRaCoCh: bits [5:0]=byte, [12:6]=col, [15:13]=BG, [17:16]=bank, [33:18]=row
ROW_STRIDE = 1 << 18
COL_STRIDE = 64


def addr(row: int, col: int = 0, bank: int = 0, bg: int = 0) -> int:
    return (row << 18) | (bank << 16) | (bg << 13) | (col << 6)


def evict_rows_for_mod4(mod4: int, count: int = 8, start_base: int = 4096):
    # With 8-way 8MB (4-core) or 2MB (1-core) LLC, rows congruent mod 4 map to the same LLC set
    base = start_base + (mod4 % 4)
    return [base + 4 * k for k in range(count)]


def write_trace(filename: str, lines: list[str]) -> Path:
    p = OUT_DIR / filename
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def gen_double_sided():
    # Hammer rows 100 and 102 around victim row 101; flush 8-way LLC sets 0 and 0x2000 each round
    ev0 = evict_rows_for_mod4(100 % 4, 8, 4096)
    ev2 = evict_rows_for_mod4(102 % 4, 8, 8192)
    lines = []
    for _ in range(100):
        lines.append(f"0 {addr(100)}")
        lines.append(f"0 {addr(102)}")
        for r in ev0:
            lines.append(f"0 {addr(r)}")
        for r in ev2:
            lines.append(f"0 {addr(r)}")
    return write_trace("double_sided.trace", lines)


def gen_many_sided():
    # 18-sided aggressors (rows 100..134 step 2): 9 rows mod4==0 and 9 rows mod4==2 self-evict 8-way LLC
    aggs = [100 + 2 * k for k in range(18)]
    lines = []
    for _ in range(100):
        for r in aggs:
            lines.append(f"0 {addr(r)}")
    return write_trace("many_sided.trace", lines)


def gen_half_double():
    # Distance-1 & distance-2 aggressors (100, 101, 103, 104) around victim row 102
    ev0 = evict_rows_for_mod4(0, 7, 4096)   # 100 & 104 share set 0 -> 2 + 7 = 9 ways
    ev1 = evict_rows_for_mod4(1, 8, 8192)   # 101 -> 1 + 8 = 9 ways
    ev3 = evict_rows_for_mod4(3, 8, 12288)  # 103 -> 1 + 8 = 9 ways
    lines = []
    for _ in range(80):
        for r in (100, 101, 103, 104):
            lines.append(f"0 {addr(r)}")
        for r in ev0 + ev1 + ev3:
            lines.append(f"0 {addr(r)}")
    return write_trace("half_double.trace", lines)


def gen_rowpress_hold():
    # Hold rows 100 and 102 open across 16 column loads (bubble=400), followed by 80 rapid double-sided hammers
    ev0 = evict_rows_for_mod4(0, 8, 4096)
    ev2 = evict_rows_for_mod4(2, 8, 8192)
    lines = []
    for round_idx in range(10):
        # Hold row 100 open across 16 column cache lines with bubble=400
        for c in range(16):
            lines.append(f"400 {addr(100, col=(round_idx * 16 + c) & 127)}")
        # Hold row 102 open across 16 column cache lines with bubble=400
        for c in range(16):
            lines.append(f"400 {addr(102, col=(round_idx * 16 + c) & 127)}")
        # Burst of 80 rapid double-sided hammer rounds (bubble=0)
        for _ in range(80):
            lines.append(f"0 {addr(100)}")
            lines.append(f"0 {addr(102)}")
            for r in ev0 + ev2:
                lines.append(f"0 {addr(r)}")
    return write_trace("rowpress_hold.trace", lines)


def generate_all():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    paths = [
        gen_double_sided(),
        gen_many_sided(),
        gen_half_double(),
        gen_rowpress_hold(),
    ]
    return paths


if __name__ == "__main__":
    for p in generate_all():
        print(f"Generated {p} ({p.stat().st_size} bytes)")
