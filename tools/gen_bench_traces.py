#!/usr/bin/env python3
"""gen_bench_traces.py: seeded synthetic memory-access traces for the RTL benchmark harness.

Each trace is a list of 64-byte cache-line operations ("LD <hex addr>" / "ST <hex addr>").
They reproduce the *access pattern* of well-known kernels; they are not recordings of those
programs, and results must be reported as synthetic patterns.
Address map of axi_ddr5_mc_top: row = a[31:18], bank = a[17:16], col = a[15:3], BG = a[8:6] ^ a[20:18].
"""
import argparse
import os
import random

LINE = 64


def row_addr(row, bank, line):
    """Line `line` (0..1023) of (row, bank). Low line bits [8:6] pick the bank group."""
    return (row << 18) | (bank << 16) | (line << 6)


def stream_copy(n, rnd):
    # c[i] = a[i]: read one array, write another, both sequential. Arrays start in different banks: with
    # 16 MB-aligned bases both streams would map to the same bank and every access would be a row conflict.
    a, c = 0x0100_0000, 0x0200_0000 + (1 << 16)
    ops = []
    for i in range(n // 2):
        ops.append(("LD", a + i * LINE))
        ops.append(("ST", c + i * LINE))
    return ops


def stream_triad(n, rnd):
    # a[i] = b[i] + s*c[i]: two sequential reads, one sequential write
    a, b, c = 0x0100_0000, 0x0200_0000 + (1 << 16), 0x0300_0000 + (2 << 16)
    ops = []
    for i in range(n // 3):
        ops += [("LD", b + i * LINE), ("LD", c + i * LINE), ("ST", a + i * LINE)]
    return ops


def gups_read(n, rnd):
    # uniform random line reads over 64 MB (no locality)
    return [("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)) for _ in range(n)]


def random_rw(n, rnd):
    # uniform random lines, 2:1 read:write
    return [("ST" if rnd.random() < 1 / 3 else "LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)) for _ in range(n)]


def row_local(n, rnd):
    # 16 lines from one row, then a random row: high row-buffer locality
    ops = []
    while len(ops) < n:
        row, bank = rnd.randrange(0, 1 << 10), rnd.randrange(4)
        base = rnd.randrange(0, 1024 - 16 * 8, 8)
        for k in range(16):
            ops.append(("LD", row_addr(row, bank, base + 8 * k)))
    return ops[:n]


def bank_conflict(n, rnd):
    # alternate two rows of the same bank and bank group: every access is a row conflict
    return [("LD", row_addr(0x40 + 2 * (i % 2), 1, 0)) for i in range(n)]


def hammer_double(n, rnd):
    # double-sided RowHammer around victim row 0x101, mixed 1:1 with random benign reads
    ops = []
    for i in range(n):
        if i % 2 == 0:
            ops.append(("LD", row_addr(0x100 + 2 * ((i // 2) % 2), 2, 0)))
        else:
            ops.append(("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)))
    return ops


def hammer_many(n, rnd):
    # TRRespass-style 16-sided hammer in one bank, mixed 1:1 with random benign reads
    ops = []
    for i in range(n):
        if i % 2 == 0:
            ops.append(("LD", row_addr(0x200 + 2 * ((i // 2) % 16), 3, 0)))
        else:
            ops.append(("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)))
    return ops


WORKLOADS = {
    "stream_copy": (stream_copy, "benign", "STREAM Copy pattern: sequential read + sequential write"),
    "stream_triad": (stream_triad, "benign", "STREAM Triad pattern: 2 sequential reads + 1 sequential write"),
    "gups_read": (gups_read, "benign", "GUPS-like uniform random line reads over 64 MB"),
    "random_rw": (random_rw, "benign", "Uniform random lines, 2:1 read:write"),
    "row_local": (row_local, "benign", "16 lines per row then a random row (high row locality)"),
    "bank_conflict": (bank_conflict, "stress", "Two rows of one bank alternating (every access a row conflict)"),
    "hammer_double": (hammer_double, "attack", "Double-sided RowHammer interleaved 1:1 with random reads"),
    "hammer_many": (hammer_many, "attack", "16-sided TRRespass hammer interleaved 1:1 with random reads"),
}


# 6 mẫu giữ lại ngoài mẫu (holdout T90) khác biệt với 8 mẫu cũ để kiểm chéo không hiệu chuẩn lại
def random_70_30(n, rnd):
    return [("ST" if rnd.random() < 0.30 else "LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)) for _ in range(n)]


def large_stride(n, rnd):
    # Bước nhảy 32 KB (512 cache line) quét qua nhiều hàng/bank theo tỷ lệ 3 đọc : 1 ghi
    base = 0x0040_0000
    stride = 32768
    mask = (1 << 26) - 1
    ops = []
    for i in range(n):
        addr = ((base + i * stride) & mask) & ~(LINE - 1)
        ops.append(("ST" if (i % 4 == 3) else "LD", addr))
    return ops


def dual_interleaved(n, rnd):
    # Hai luồng tuần tự khác bank xen kẽ với luồng truy cập ngẫu nhiên
    a, b = 0x0080_0000, 0x0180_0000 + (2 << 16)
    ia = ib = 0
    ops = []
    for i in range(n):
        m = i % 3
        if m == 0:
            ops.append(("LD", a + ia * LINE))
            ia += 1
        elif m == 1:
            ops.append(("ST", b + ib * LINE))
            ib += 1
        else:
            ops.append(("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)))
    return ops


def burst_idle_rw(n, rnd):
    # Cụm 16 đọc tuần tự xen kẽ cụm 16 ghi tuần tự rồi nhảy sang hàng/bank ngẫu nhiên (mô phỏng burst rồi chuyển pha)
    ops = []
    phase = 0
    while len(ops) < n:
        row, bank = rnd.randrange(0, 1 << 10), rnd.randrange(4)
        base_line = rnd.randrange(0, 1024 - 16 * 8, 8)
        op = "LD" if (phase % 2 == 0) else "ST"
        for k in range(16):
            ops.append((op, row_addr(row, bank, base_line + 8 * k)))
        phase += 1
    return ops[:n]


def hammer_3row(n, rnd):
    # Tấn công 3 hàng (0x140, 0x142, 0x144) trong cùng bank 0 xen kẽ 2:1 với đọc ngẫu nhiên lành tính
    rows = (0x140, 0x142, 0x144)
    ops = []
    h_idx = 0
    for i in range(n):
        if i % 3 != 2:
            ops.append(("LD", row_addr(rows[h_idx % 3], 0, 0)))
            h_idx += 1
        else:
            ops.append(("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)))
    return ops


def hammer_multibank(n, rnd):
    # Tấn công SledgeHammer nhiều bank (4 bank, mỗi bank kẹp 2 hàng) xen kẽ 1:1 với đọc ngẫu nhiên
    ops = []
    h_idx = 0
    for i in range(n):
        if i % 2 == 0:
            b = h_idx % 4
            side = (h_idx // 4) % 2
            ops.append(("LD", row_addr(0x180 + 2 * side, b, 0)))
            h_idx += 1
        else:
            ops.append(("LD", rnd.randrange(0, 1 << 26) & ~(LINE - 1)))
    return ops


HOLDOUT_WORKLOADS = {
    "random_70_30": (random_70_30, "benign", "Uniform random lines over 64 MB, 70% read / 30% write"),
    "large_stride": (large_stride, "benign", "32 KB large-stride traversal across rows/banks, 3:1 read:write"),
    "dual_interleaved": (dual_interleaved, "benign", "Two sequential RD/WR streams interleaved with random reads"),
    "burst_idle_rw": (burst_idle_rw, "benign", "Alternating 16-line sequential read and write bursts across random rows"),
    "hammer_3row": (hammer_3row, "attack", "3-row RowHammer in bank 0 interleaved 2:1 with random reads"),
    "hammer_multibank": (hammer_multibank, "attack", "4-bank multi-bank RowHammer interleaved 1:1 with random reads"),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "sim", "traces", "rtl_bench"))
    ap.add_argument("--ops", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--holdout", action="store_true", help="Generate T90 out-of-sample holdout traces instead of original 8")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    selected = HOLDOUT_WORKLOADS if args.holdout else WORKLOADS
    for name, (fn, kind, desc) in selected.items():
        ops = fn(args.ops, random.Random(args.seed))
        path = os.path.join(args.out, f"{name}.trace")
        with open(path, "w", newline="\n") as f:
            for op, a in ops:
                f.write(f"{op} {a:08x}\n")
        print(f"{name:16s} {kind:7s} {len(ops):6d} ops  {desc}")


if __name__ == "__main__":
    main()
