#!/usr/bin/env python3
"""
===============================================================================
Script: run_full_lifecycle_validation.py
Description: Master Runner for the Industrial 3-Stage Semiconductor Memory
             Verification & Validation Suite:
             - Stage 1: Pre-Silicon Verification (Protocol, Timing, DFI 5.0, MBIST)
             - Stage 2: Post-Silicon Core Array Emulation (March C-, Own Address, ECC SEC-DED)
             - Stage 3: Platform Validation (Multi-Channel Scaling & Multi-Tenant Stress)
===============================================================================
"""

import os
import subprocess
import sys
import time

def run_step(step_name, command, cwd=None):
    print(f"\n{'='*80}")
    print(f"[*] EXECUTING: {step_name}")
    print(f"[*] Command:   {command}")
    print(f"{'='*80}")
    t0 = time.time()
    res = subprocess.run(command, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    elapsed = time.time() - t0
    
    # Print the last few lines of output
    lines = res.stdout.strip().split("\n")
    display_lines = lines[-15:] if len(lines) > 15 else lines
    for line in display_lines:
        print(f"  | {line}")
        
    if res.returncode == 0:
        print(f"[SUCCESS] {step_name} completed in {elapsed:.2f}s")
        return True
    else:
        print(f"[FAILED] {step_name} exited with code {res.returncode}")
        return False

def main():
    print("=" * 80)
    print("  Q-SHIELD FULL INDUSTRIAL 3-STAGE MEMORY LIFECYCLE VALIDATION SUITE")
    print("=" * 80)

    stages = [
        # Giai đoạn 1: Pre-Silicon Verification
        ("Stage 1.1: SystemVerilog RTL Linting (Verilator)", 
         "wsl verilator --lint-only -Wall --top-module dfi_phy_adapter rtl/memory/dfi_phy_adapter.sv"),
        ("Stage 1.2: DFI 5.0 PHY Adapter & Timing Handshake Verification", 
         "wsl -e bash -c \"verilator --binary --timing rtl/memory/dfi_phy_adapter.sv tb/memory/tb_dfi_phy_adapter.sv --top tb_dfi_phy_adapter -Wno-fatal && ./obj_dir/Vtb_dfi_phy_adapter\""),
        
        # Giai đoạn 2: Post-Silicon Core Array & MBIST Emulation
        ("Stage 2: Core Array March C-, Own Address & ECC SEC-DED (Cocotb RTL)", 
         "wsl -e bash -c \"cd /mnt/d/RAM/tb/top && make sim MODULE=test_semiconductor_lifecycle\""),
         
        # Giai đoạn 3: Platform Validation & Multi-Channel Scaling
        ("Stage 3.1: Multi-Channel Scaling Benchmark (1-CH to 8-CH Modulo-3)", 
         "wsl python3 /mnt/d/RAM/sim/test_multichannel.py"),
        ("Stage 3.2: SOTA Architectural Benchmark Matrix (PRAC, BlockHammer, Q-Shield)", 
         "wsl python3 /mnt/d/RAM/sim/run_benchmarks.py"),
        ("Stage 3.3: Generation of Publication Figures (PDF/PNG)", 
         "python sim/plot_multichannel_scaling.py"),
    ]

    all_pass = True
    start_total = time.time()
    summary = []

    for name, cmd in stages:
        ok = run_step(name, cmd)
        summary.append((name, "PASS" if ok else "FAIL"))
        if not ok:
            all_pass = False

    total_time = time.time() - start_total
    print("\n" + "=" * 80)
    print("                 LIFECYCLE VALIDATION SUMMARY REPORT")
    print("=" * 80)
    for name, status in summary:
        print(f"  [{status:<4}] {name}")
    print("-" * 80)
    print(f"Total Execution Time: {total_time:.2f} seconds")
    print(f"Final Status: {'100% ALL STAGES PASSED' if all_pass else 'SOME STAGES FAILED'}")
    print("=" * 80)

if __name__ == "__main__":
    main()
