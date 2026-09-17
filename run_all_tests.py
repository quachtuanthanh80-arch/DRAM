#!/usr/bin/env python3
"""
===============================================================================
Script: run_all_tests.py
Description: Master CI & Hardware Regression Test Runner for Q-Shield
             Executes Cocotb 2.1 + Verilator test suites across all modules:
             1. Frontend (AXI4 Slave, Skid Buffer, Address Mapper)
             2. Core (SDC Resilient Filter, QoS Queue, 16-entry ROB)
             3. Backend (Timing-Slack Matrix Arbiter, DDR5 Command Engine, ECC)
             4. Top-Level E2E Full Subsystem Integration
===============================================================================
"""

import os
import sys
import subprocess
import time

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    suites = [
        ("Frontend Stage (AXI4 Slave, Skid Buffer & Mapper)", os.path.join(root_dir, "tb", "frontend")),
        ("Core Security & QoS (SDC Filter, Queue & ROB)", os.path.join(root_dir, "tb", "core")),
        ("Backend & Timing Slack (Arbiter, FSM & ECC)", os.path.join(root_dir, "tb", "backend")),
        ("Top-Level E2E Subsystem Integration", os.path.join(root_dir, "tb", "top")),
    ]

    print("=" * 80)
    print("  Q-SHIELD MASTER HARDWARE REGRESSION SUITE (COCOTB + VERILATOR)")
    print("=" * 80)

    total_passed = 0
    total_failed = 0
    start_time = time.time()

    for name, path in suites:
        print(f"\n[*] Executing: {name}...")
        t0 = time.time()
        res = subprocess.run(["make", "sim"], cwd=path, capture_output=True, text=True)
        elapsed = time.time() - t0

        if res.returncode == 0:
            print(f"[PASS] {name} completed in {elapsed:.2f}s")
            total_passed += 1
        else:
            print(f"[FAIL] {name} exited with code {res.returncode}")
            print("--- Error Output Tail ---")
            lines = (res.stdout + res.stderr).strip().splitlines()
            for l in lines[-25:]:
                print(f"  | {l}")
            total_failed += 1

    total_time = time.time() - start_time
    print("\n" + "=" * 80)
    print(f"  REGRESSION SUMMARY: {total_passed}/{len(suites)} Suites Passed in {total_time:.2f}s")
    print("=" * 80)

    if total_failed > 0:
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()
