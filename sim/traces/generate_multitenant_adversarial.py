#!/usr/bin/env python3
"""
===============================================================================
Script: generate_multitenant_adversarial.py
Description: Generates multi-tenant 8-thread realistic server memory traces.
Workload Composition:
- 2 Adversarial Threads:
  * Thread 0: Variable-frequency Blacksmith multi-sided RowHammer on BG 0, Bank 0.
  * Thread 1: RowPress prolonged activation hammering on BG 2, Bank 1.
- 6 Benign Co-tenant Threads (PARSEC / STREAM / Cloud Workloads):
  * Thread 2: STREAM Triad streaming bandwidth on BG 1.
  * Thread 3: PARSEC Blackscholes financial PDE solver on BG 3.
  * Thread 4: Sparse Graph Breadth-First-Search (pointer chasing) on BG 4.
  * Thread 5: In-Memory Key-Value Store (Memcached-like) on BG 5.
  * Thread 6: DNN Inference Matrix-Vector activation fetch on BG 6.
  * Thread 7: Database OLTP transaction log writes on BG 7.
===============================================================================
"""

import os
import random

TRACES_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(TRACES_DIR, "trace_multitenant_adversarial.trace")

TOTAL_COMMANDS = 8000

# Base DRAM Mapping Parameters (64B Cacheline, 10-bit Col, 3-bit Bank, 3-bit BG)
# Addr: [Row: 16b | BG: 3b | Bank: 3b | Col: 10b | Offset: 6b]

def make_dram_addr(row, bg, ba, col):
    return (row << 22) | (bg << 19) | (ba << 16) | (col << 6)

def main():
    print(f"[*] Generating 8-Tenant Multi-Core Adversarial Trace -> {OUT_PATH}")
    random.seed(1337)

    # Thread 0: Blacksmith aggressors around victim row 1200
    bs_aggressors = [1198, 1199, 1201, 1202]
    bs_weights = [0.35, 0.40, 0.15, 0.10]

    # Thread 1: RowPress target row 3400
    rp_row = 3400

    # Benign stream pointers
    stream_row = 10000
    stream_col = 0

    lines = []

    for i in range(TOTAL_COMMANDS):
        thread_id = random.choices(
            population=[0, 1, 2, 3, 4, 5, 6, 7],
            weights   =[0.20, 0.15, 0.15, 0.12, 0.13, 0.10, 0.08, 0.07],
            k=1
        )[0]

        if thread_id == 0:
            # Thread 0: Blacksmith RowHammer
            row = random.choices(bs_aggressors, weights=bs_weights, k=1)[0]
            col = random.randint(0, 15)
            bg = 0
            ba = 0
            is_write = (random.random() < 0.10)
        elif thread_id == 1:
            # Thread 1: RowPress Hammering
            row = rp_row
            col = random.randint(0, 63)
            bg = 2
            ba = 1
            is_write = (random.random() < 0.05)
        elif thread_id == 2:
            # Thread 2: STREAM Triad
            row = stream_row
            col = stream_col
            stream_col += 1
            if stream_col >= 1024:
                stream_col = 0
                stream_row += 1
            bg = 1
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.33)
        elif thread_id == 3:
            # Thread 3: PARSEC Blackscholes
            row = random.randint(4000, 4200)
            col = random.randint(0, 511)
            bg = 3
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.25)
        elif thread_id == 4:
            # Thread 4: Sparse Graph BFS
            row = random.randint(5000, 9000)
            col = random.randint(0, 1023)
            bg = 4
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.15)
        elif thread_id == 5:
            # Thread 5: Memcached Key-Value
            row = random.randint(12000, 14000)
            col = random.randint(0, 127)
            bg = 5
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.20)
        elif thread_id == 6:
            # Thread 6: DNN Activation fetch
            row = random.randint(16000, 18000)
            col = random.randint(0, 1023)
            bg = 6
            ba = random.randint(0, 3)
            is_write = (random.random() < 0.10)
        else:
            # Thread 7: Database WAL Log
            row = random.randint(20000, 21000)
            col = random.randint(0, 255)
            bg = 7
            ba = random.randint(0, 3)
            is_write = 1 # Sequential log write

        addr = make_dram_addr(row, bg, ba, col)
        cmd_type = "ST" if is_write else "LD"
        lines.append(f"{cmd_type} 0x{addr:X}\n")

    with open(OUT_PATH, "w") as f:
        f.writelines(lines)

    print(f"[SUCCESS] Generated {len(lines)} memory trace commands in {OUT_PATH}")

if __name__ == "__main__":
    main()
