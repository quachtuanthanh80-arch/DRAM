#!/usr/bin/env python3
"""
tools/check_gate.py: Gate kiểm tra tính trung thực của test runner.

Tạo 2 testbench tí hon trong build/check_gate/:
  1. tb_gate_fail.sv: cố ý fail (tb_check(1'b0, ...))
  2. tb_gate_hang.sv: cố ý treo (vòng lặp vô hạn)

Chạy cả hai qua runner (run_iverilog_regression).
Thoát 0 CHỈ KHI runner báo FAIL cho cả hai testbench.
"""
import os
import sys
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from run_iverilog_regression import run_one

FAIL_SV_CONTENT = """// File:      tb_gate_fail.sv
// Chức năng: Testbench tí hon cố ý fail để kiểm tra runner bắt đúng FAIL.
`timescale 1ns/1ps
module tb_gate_fail;
    `include "tb_check.svh"
    initial begin
        tb_check(1'b0, "Deliberate failure to verify test runner catches FAIL");
        tb_report();
        $finish;
    end
endmodule
"""

HANG_SV_CONTENT = """// File:      tb_gate_hang.sv
// Chức năng: Testbench tí hon cố ý treo để kiểm tra runner bắt đúng TIMEOUT.
`timescale 1ns/1ps
module tb_gate_hang;
    initial begin
        forever begin
            #1000;
        end
    end
endmodule
"""

def main():
    print("=" * 80)
    print("  Q-SHIELD TEST RUNNER INTEGRITY GATE (check_gate.py)")
    print("=" * 80)

    gate_dir = ROOT / "build" / "check_gate"
    gate_dir.mkdir(parents=True, exist_ok=True)

    fail_sv = gate_dir / "tb_gate_fail.sv"
    hang_sv = gate_dir / "tb_gate_hang.sv"

    fail_sv.write_text(FAIL_SV_CONTENT, encoding="utf-8")
    hang_sv.write_text(HANG_SV_CONTENT, encoding="utf-8")

    # 1. Chạy test cố ý fail
    print("[1/2] Running deliberate-fail testbench (tb_gate_fail)...", end=" ", flush=True)
    res_fail = run_one(
        top_module="tb_gate_fail",
        sources=[str(fail_sv)],
        timeout=15,
        cwd=str(ROOT),
        log_dir=str(gate_dir),
    )
    fail_detected = (res_fail["status"] == "FAIL")
    if fail_detected:
        print(f"[OK] Runner correctly reported FAIL ({res_fail['reason']})")
    else:
        print(f"[FATAL] Runner falsely reported PASS for a failing test!")

    # 2. Chạy test cố ý treo (timeout 2s)
    print("[2/2] Running deliberate-hang testbench (tb_gate_hang, timeout=2s)...", end=" ", flush=True)
    res_hang = run_one(
        top_module="tb_gate_hang",
        sources=[str(hang_sv)],
        timeout=2,
        cwd=str(ROOT),
        log_dir=str(gate_dir),
    )
    hang_detected = (res_hang["status"] == "FAIL" and "TIMEOUT" in res_hang["reason"])
    if hang_detected:
        print(f"[OK] Runner correctly reported TIMEOUT ({res_hang['reason']})")
    else:
        print(f"[FATAL] Runner failed to catch timeout! Status={res_hang['status']}, reason={res_hang['reason']}")

    print("=" * 80)
    if fail_detected and hang_detected:
        print("  [GATE PASS] Both failure and timeout are strictly caught by the runner.")
        print("=" * 80)
        sys.exit(0)
    else:
        print("  [GATE FAIL] Runner integrity compromised!")
        print("=" * 80)
        sys.exit(1)

if __name__ == "__main__":
    main()
