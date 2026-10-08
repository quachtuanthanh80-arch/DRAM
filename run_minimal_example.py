#!/usr/bin/env python3
"""
run_minimal_example.py
Fast Minimal Reproduction Script (< 60s) for Reviewers and CI/CD.
Validates RTL unit tests, attack mitigation emulation, and golden outputs.
"""

import os
import sys
import json
import subprocess
import time

def run_command(cmd, desc):
    print(f"\n=== {desc} ===")
    start = time.time()
    res = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    elapsed = time.time() - start
    if res.returncode != 0:
        print(f"[FAIL] {desc} (exited with {res.returncode} in {elapsed:.2f}s)")
        print(res.stderr or res.stdout)
        sys.exit(res.returncode)
    print(f"[PASS] {desc} completed in {elapsed:.2f}s")
    return res.stdout

def main():
    total_start = time.time()
    print("======================================================================")
    print("           Q-SHIELD FAST REPRODUCIBILITY VALIDATION                   ")
    print("======================================================================")

    # 1. RTL Unit Test Filter
    run_command(
        f"{sys.executable} run_iverilog_regression.py",
        "Phase 1: RTL Master Regression (14 Synthesizable Modules)"
    )

    # 2. Attack Emulation
    run_command(
        f"{sys.executable} sim/run_attack_emulation.py",
        "Phase 2: Security Attack Emulation on Memory Traces"
    )

    # 3. Golden Reference Check
    print("\n=== Phase 3: Golden Consistency Verification ===")
    with open("sim/results/attack_emulation_summary.json") as f1, open("GOLDEN_OUTPUTS/attack_emulation_summary.json") as f2:
        cur_list = json.load(f1)
        gold_list = json.load(f2)
        assert len(cur_list) == len(gold_list), "Trace count mismatch"
        total_escaped = sum(item["escaped_bitflips"] for item in cur_list)
        assert total_escaped == 0, f"Security failure: {total_escaped} escaped bit-flips detected"
        print("  [PASS] Attack Emulation: 0 escaped bit-flips verified against golden reference.")

    with open("regression_summary.json") as f1, open("GOLDEN_OUTPUTS/regression_summary.json") as f2:
        cur = json.load(f1)
        gold = json.load(f2)
        assert cur["failed"] == 0, f"RTL regression failed with {cur['failed']} failures"
        assert cur["passed"] == gold["passed"], "Passed test count mismatch with golden"
        print(f"  [PASS] RTL Master Regression: {cur['passed']}/{cur['total_tests']} tests verified.")

    total_elapsed = time.time() - total_start
    print("\n======================================================================")
    print(f"  ALL REPRODUCIBILITY CHECKS PASSED SUCCESSFULLY IN {total_elapsed:.2f}s")
    print("======================================================================")

if __name__ == "__main__":
    main()
