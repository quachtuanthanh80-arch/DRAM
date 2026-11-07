#!/usr/bin/env python3
"""Q-Shield Integrity Architecture Reference Model and Test Vector Generator.
Generates reference calculations for:
  1. qshield_meta_layout: memory mapping of Counter Blocks, MAC Lines, and Bonsai Merkle Tree.
  2. qshield_counter_unit: split-counter increment, major rollover, and XTS tweak generation.
Seed-fixed, bit-exact and synthesizable validation.
"""
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PROT_BASE_DEFAULT = 0
PROT_LINES_DEFAULT = 1 << 20  # 1048576 lines = 64 MiB
TREE_ARITY = 8


class MetaLayoutModel:
    def __init__(self, prot_base=PROT_BASE_DEFAULT, prot_lines=PROT_LINES_DEFAULT):
        self.prot_base = prot_base
        self.prot_lines = prot_lines
        self.line_bytes = 64
        self.prot_bytes = self.prot_lines * self.line_bytes
        self.prot_end = self.prot_base + self.prot_bytes
        
        self.meta_base = self.prot_end
        
        # 1. Counter Blocks (CB)
        self.num_cb = self.prot_lines // 64
        self.cb_bytes = self.num_cb * 64
        self.cb_base = self.meta_base
        
        # 2. MAC Lines (ML)
        self.num_ml = self.prot_lines // 8
        self.ml_bytes = self.num_ml * 64
        self.ml_base = self.cb_base + self.cb_bytes
        
        # 3. Tree Nodes (TN)
        self.tn_base = self.ml_base + self.ml_bytes
        self.level_counts = []
        cur = self.num_cb
        while cur > 1:
            nxt = math.ceil(cur / TREE_ARITY)
            self.level_counts.append(nxt)
            cur = nxt
            if nxt <= TREE_ARITY:
                break
        
        self.tree_levels = len(self.level_counts)
        self.level_offsets = [0] * (self.tree_levels + 1)
        accum = 0
        for lvl in range(1, self.tree_levels + 1):
            self.level_offsets[lvl] = accum
            accum += self.level_counts[lvl - 1]
            
        self.total_tn_nodes = accum
        self.tn_bytes = self.total_tn_nodes * 64
        self.meta_end = self.tn_base + self.tn_bytes
        self.total_meta_bytes = self.meta_end - self.meta_base
        self.overhead_pct = (self.total_meta_bytes / self.prot_bytes) * 100.0

    def print_summary(self):
        print("================================================================================")
        print("  [META_LAYOUT] Q-SHIELD METADATA LAYOUT & MERKLE TREE SUMMARY")
        print("================================================================================")
        print(f"Protected Region : 0x{self.prot_base:016X} .. 0x{self.prot_end:016X} ({self.prot_bytes / (1<<20):.2f} MiB, {self.prot_lines} lines)")
        print(f"Metadata Base    : 0x{self.meta_base:016X}")
        print(f"  Counter Blocks : 0x{self.cb_base:016X} .. 0x{self.ml_base:016X} ({self.num_cb} CBs, {self.cb_bytes / 1024:.2f} KiB)")
        print(f"  MAC Lines      : 0x{self.ml_base:016X} .. 0x{self.tn_base:016X} ({self.num_ml} MLs, {self.ml_bytes / (1<<20):.2f} MiB)")
        print(f"  Tree Nodes     : 0x{self.tn_base:016X} .. 0x{self.meta_end:016X} ({self.total_tn_nodes} nodes, {self.tn_bytes / 1024:.2f} KiB)")
        for lvl in range(1, self.tree_levels + 1):
            cnt = self.level_counts[lvl - 1]
            off = self.level_offsets[lvl]
            print(f"    - Level {lvl}: {cnt:6d} nodes (DRAM offset: +0x{off*64:08X}, {cnt*64/1024:7.2f} KiB)")
        print(f"Total Metadata   : {self.total_meta_bytes} bytes ({self.total_meta_bytes / (1<<20):.4f} MiB)")
        print(f"Metadata Overhead: {self.overhead_pct:.4f} %")
        print("================================================================================")

    def is_protected(self, addr):
        return self.prot_base <= addr < self.prot_end

    def is_metadata(self, addr):
        return self.meta_base <= addr < self.meta_end

    def line_index(self, addr):
        return (addr - self.prot_base) // self.line_bytes

    def cb_addr_and_slot(self, L):
        cb_idx = L // 64
        slot = L % 64
        return (self.cb_base + cb_idx * 64, slot)

    def ml_addr_and_slot(self, L):
        ml_idx = L // 8
        slot = L % 8
        return (self.ml_base + ml_idx * 64, slot)

    def tn_addr_and_slot(self, level, idx):
        assert 1 <= level <= self.tree_levels
        assert idx < self.level_counts[level - 1]
        base_node = self.level_offsets[level] + idx
        return (self.tn_base + base_node * 64, idx % 8)


class CounterUnitModel:
    @staticmethod
    def parse_cb(cb_bytes_or_int):
        if isinstance(cb_bytes_or_int, int):
            val = cb_bytes_or_int
        elif isinstance(cb_bytes_or_int, bytes):
            val = int.from_bytes(cb_bytes_or_int, "little")
        else:
            raise TypeError("Expected int or bytes")
        
        major = (val >> 448) & 0xFFFFFFFFFFFFFFFF
        minors = [(val >> (i * 7)) & 0x7F for i in range(64)]
        return major, minors

    @staticmethod
    def pack_cb(major, minors):
        assert len(minors) == 64
        val = (major & 0xFFFFFFFFFFFFFFFF) << 448
        for i, m in enumerate(minors):
            val |= (m & 0x7F) << (i * 7)
        return val

    @classmethod
    def apply_counter(cls, cb_val, line_idx, asid=0, inc=True):
        major, minors = cls.parse_cb(cb_val)
        slot = line_idx % 64
        cur_minor = minors[slot]
        
        if inc:
            if cur_minor == 127:
                # Overflow rollover
                overflow = 1
                new_major = (major + 1) & 0xFFFFFFFFFFFFFFFF
                new_minors = [0] * 64
                eff_major = new_major
                eff_minor = 0
            else:
                overflow = 0
                new_major = major
                new_minors = list(minors)
                new_minors[slot] = cur_minor + 1
                eff_major = major
                eff_minor = cur_minor + 1
        else:
            overflow = 0
            new_major = major
            new_minors = list(minors)
            eff_major = major
            eff_minor = cur_minor

        new_cb_val = cls.pack_cb(new_major, new_minors)
        
        # Tweak format: {eff_major[63:0], eff_minor[6:0], asid[3:0], line_idx[52:0]} = 128 bits
        tweak = (
            ((eff_major & 0xFFFFFFFFFFFFFFFF) << 64) |
            ((eff_minor & 0x7F) << 57) |
            ((asid & 0x0F) << 53) |
            (line_idx & ((1 << 53) - 1))
        )
        return new_cb_val, tweak, overflow


def main():
    layout = MetaLayoutModel()
    layout.print_summary()
    
    # Generate 10000 vectors for testbench
    print("Generating validation vectors for tb_qshield_meta_layout...")
    vec_path = ROOT / "build" / "meta_layout_vectors.txt"
    vec_path.parent.mkdir(parents=True, exist_ok=True)
    
    random.seed(42)
    # Test boundary and random lines
    test_lines = [
        0, 1, 63, 64, 65, 127, 128,
        layout.prot_lines - 65, layout.prot_lines - 64, layout.prot_lines - 1
    ]
    # Add random lines
    for _ in range(10000 - len(test_lines)):
        test_lines.append(random.randint(0, layout.prot_lines - 1))
        
    with open(vec_path, "w", encoding="utf-8") as f:
        f.write("# Format: line_idx addr cb_addr cb_slot ml_addr ml_slot\n")
        for L in test_lines:
            addr = layout.prot_base + L * 64
            cb_addr, cb_slot = layout.cb_addr_and_slot(L)
            ml_addr, ml_slot = layout.ml_addr_and_slot(L)
            f.write(f"{L:016X} {addr:016X} {cb_addr:016X} {cb_slot:02X} {ml_addr:016X} {ml_slot:02X}\n")
            
    print(f"Wrote {len(test_lines)} layout vectors to {vec_path}")


if __name__ == "__main__":
    main()
