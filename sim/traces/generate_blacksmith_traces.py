#!/usr/bin/env python3
"""
===============================================================================
Script: generate_blacksmith_traces.py
Description: Generates multi-sided, non-uniform frequency-domain RowHammer traces
             based on the BLACKSMITH methodology (IEEE S&P 2022).
Features:
- Multi-sided aggressors: 4 aggressor rows (Row N-2, N-1, N+1, N+2) attacking victim N.
- Non-uniform frequency modulation (alternating burst periods and activation ratios).
- Mixed background benign traffic interleaved across other banks and bank groups.
===============================================================================
"""

import os
import random

TRACES_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(TRACES_DIR, "trace_blacksmith.trace")

TOTAL_COMMANDS = 5000
VICTIM_ROW = 500
AGGRESSORS = [VICTIM_ROW - 2, VICTIM_ROW - 1, VICTIM_ROW + 1, VICTIM_ROW + 2]
AGGRESSOR_WEIGHTS = [0.35, 0.40, 0.15, 0.10] # Non-uniform frequency domain distribution

# Base DRAM Mapping Parameters (64B Cacheline, 10-bit Col, 3-bit Bank, 3-bit BG)
# Addr: [Row: 16b | BG: 3b | Bank: 3b | Col: 10b | Offset: 6b]

def make_dram_addr(row, bg, ba, col):
    addr = (row << 22) | (bg << 19) | (ba << 16) | (col << 6)
    return addr

def main():
    print(f"[*] Generating Blacksmith-style multi-sided RowHammer trace -> {OUT_PATH}")
    random.seed(42)

    lines = []
    # 70% Adversarial Blacksmith traffic targeting Bank Group 0, Bank 0
    # 30% Benign traffic distributed across other Bank Groups (1-7)
    
    for i in range(TOTAL_COMMANDS):
        is_attack = (random.random() < 0.70)
        
        if is_attack:
            # Multi-sided aggressor chosen via non-uniform frequency weights
            target_row = random.choices(AGGRESSORS, weights=AGGRESSOR_WEIGHTS, k=1)[0]
            col = random.randint(0, 15) # Hammering same page columns
            bg = 0
            ba = 0
            is_write = (random.random() < 0.20)
            addr = make_dram_addr(target_row, bg, ba, col)
        else:
            # Benign memory request to random rows in other bank groups
            target_row = random.randint(1000, 8000)
            col = random.randint(0, 1023)
            bg = random.randint(1, 7) # Non-conflicting bank group
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.30)
            addr = make_dram_addr(target_row, bg, ba, col)

        cmd_type = "ST" if is_write else "LD"
        lines.append(f"{cmd_type} 0x{addr:X}\n")

    with open(OUT_PATH, "w") as f:
        f.writelines(lines)

    print(f"[SUCCESS] Generated {len(lines)} memory trace commands in {OUT_PATH}")

if __name__ == "__main__":
    main()
