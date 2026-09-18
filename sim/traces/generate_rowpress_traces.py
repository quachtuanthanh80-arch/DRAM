#!/usr/bin/env python3
"""
===============================================================================
Script: generate_rowpress_traces.py
Description: Generates RowPress attack traces (Kang et al., ISCA 2023)
             targeting aggressive cumulative activation duration (t_ACT)
             to bypass traditional activation-count-only defenses.
Features:
- Long open-row duration: Keeps the target row continuously activated
  by issuing back-to-back requests across columns of the same row.
- Interleaves benign traffic on alternative bank groups to test
  opportunistic timing-slack scheduling and isolation under RowPress attacks.
===============================================================================
"""

import os
import random

TRACES_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(TRACES_DIR, "trace_rowpress.trace")

TOTAL_COMMANDS = 5000
VICTIM_ROW = 888
AGGRESSOR_ROWS = [VICTIM_ROW - 1, VICTIM_ROW + 1]

# Base DRAM Mapping Parameters (64B Cacheline, 10-bit Col, 3-bit Bank, 3-bit BG)
# Addr: [Row: 16b | BG: 3b | Bank: 3b | Col: 10b | Offset: 6b]

def make_dram_addr(row, bg, ba, col):
    addr = (row << 22) | (bg << 19) | (ba << 16) | (col << 6)
    return addr

def main():
    print(f"[*] Generating RowPress attack trace -> {OUT_PATH}")
    random.seed(1337)

    lines = []
    # RowPress Attack Pattern:
    # 75% RowPress traffic keeping victim-adjacent rows open with high cumulative t_ACT
    # 25% Benign traffic distributed across non-conflicting Bank Groups (1-7)
    
    current_aggressor = AGGRESSORS[0] if 'AGGRESSORS' in globals() else AGGRESSOR_ROWS[0]
    aggressor_col = 0
    row_hold_count = 0
    HOLD_DURATION = 80 # Read consecutive columns to sustain row activation

    for i in range(TOTAL_COMMANDS):
        is_attack = (random.random() < 0.75)
        
        if is_attack:
            # Prolonged activation on aggressor row
            bg = 0
            ba = 0
            col = aggressor_col
            addr = make_dram_addr(current_aggressor, bg, ba, col)
            is_write = (random.random() < 0.15)
            
            aggressor_col = (aggressor_col + 1) % 64
            row_hold_count += 1
            if row_hold_count >= HOLD_DURATION:
                row_hold_count = 0
                current_aggressor = random.choice(AGGRESSOR_ROWS)
        else:
            # Benign memory traffic to other bank groups
            target_row = random.randint(2000, 9000)
            col = random.randint(0, 1023)
            bg = random.randint(1, 7)
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.35)
            addr = make_dram_addr(target_row, bg, ba, col)

        cmd_type = "ST" if is_write else "LD"
        lines.append(f"{cmd_type} 0x{addr:08x}\n")

    with open(OUT_PATH, "w") as f:
        f.writelines(lines)

    print(f"[+] Successfully generated {len(lines)} RowPress instructions to {OUT_PATH}")

if __name__ == "__main__":
    main()
