#!/usr/bin/env python3
"""
run_minimal_example.py
Fast End-to-End Reproduction Script for Reviewers, Docker Artifact Evaluation, and CI/CD.
Validates 30 RTL testbenches (incl. 8 Global Benchmarks & 13 Attack Vectors),
Attack Emulation, SOTA Comparison Matrices, and Golden Reference Outputs.
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
    print("      Q-SHIELD ARTIFACT EVALUATION & REPRODUCIBILITY VALIDATION       ")
    print("======================================================================")

    # 1. RTL Master Regression (30 Testbenches including 8 Global Benchmarks & 13 Security Vectors)
    run_command(
        f"{sys.executable} run_iverilog_regression.py",
        "Phase 1: RTL Master Regression (30 Testbenches + 8 Global Benchmarks)"
    )

    # 2. Attack Emulation
    run_command(
        f"{sys.executable} sim/run_attack_emulation.py",
        "Phase 2: Security Attack Emulation on Memory Traces (8 Workloads)"
    )

    # 3. SOTA Architectural Comparison Matrix Generation
    run_command(
        f"{sys.executable} sim/generate_sota_comparison.py",
        "Phase 3: SOTA Architectural & Performance Comparison Matrices"
    )

    # 4. Golden Reference Check
    run_command(
        f"{sys.executable} tools/verify_golden_outputs.py",
        "Phase 4: Golden Reference Artifact Verification"
    )

    with open("regression_summary.json") as f1, open("GOLDEN_OUTPUTS/regression_summary.json") as f2:
        cur = json.load(f1)
        gold = json.load(f2)
        assert cur["failed"] == 0, f"RTL regression failed with {cur['failed']} failures"
        assert cur["passed"] == gold["passed"], "Passed test count mismatch with golden"
        print(f"  [PASS] RTL Master Regression: {cur['passed']}/{cur['total_tests']} testbenches verified.")

    total_elapsed = time.time() - total_start
    print("\n======================================================================")
    print(f"  ALL REPRODUCIBILITY CHECKS PASSED SUCCESSFULLY IN {total_elapsed:.2f}s")
    print("======================================================================")

if __name__ == "__main__":
    main()
