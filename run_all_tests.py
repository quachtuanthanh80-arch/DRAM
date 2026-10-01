#!/usr/bin/env python3
"""
===============================================================================
Script: run_all_tests.py
Description: Master CI & Hardware Regression Test Runner for Q-Shield
             Executes Cocotb 2.1 + Verilator test suites across all subsystems:
             1. Frontend Stage (AXI4 Slave & Skid Buffer)
             2. Frontend Multi-Arch Mapping & Bank Coloring (Intel / AMD Zen)
             3. Core Security & QoS (SDC Filter, Queue & ROB)
             4. Backend Timing Slack Arbiter
             5. Backend RS(18,16) Chipkill ECC over GF(16)
             6. Galois LFSR Bus Scrambler (128-bit/64-bit symmetric)
             7. Performance Monitor Unit (PMU & CSR telemetry)
             8. Cryptographic Suite (AES-CTR keystream, Split Counter, AES-CMAC)
             9. Top-Level E2E Subsystem Integration
             10. Industry Attack Vectors (ZenHammer, SledgeHammer, Blacksmith)
             11. Semiconductor Lifecycle & Long-Term Stress Verification
===============================================================================
"""

import os
import sys
import subprocess
import time
import shutil

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))

    # If running on Windows and native 'make' is not present, dispatch to WSL
    if sys.platform == "win32" and shutil.which("make") is None and shutil.which("wsl") is not None:
        print("[*] Native 'make' not detected on Windows host. Dispatching to WSL environment...")
        drive, rest = os.path.splitdrive(os.path.abspath(__file__))
        drive_letter = drive.replace(":", "").lower()
        wsl_path = f"/mnt/{drive_letter}" + rest.replace("\\", "/")
        ret = subprocess.run(["wsl", "--", "python3", wsl_path] + sys.argv[1:])
        sys.exit(ret.returncode)

    suites = [
        ("Frontend Stage (AXI4 Slave & Skid Buffer)", os.path.join(root_dir, "tb", "frontend"), "Makefile", {}),
        ("Frontend Multi-Arch Mapping & Bank Coloring", os.path.join(root_dir, "tb", "frontend"), "Makefile.coloring", {}),
        ("Core Security & QoS (SDC Filter, Queue & ROB)", os.path.join(root_dir, "tb", "core"), "Makefile", {}),
        ("Backend Timing Slack Arbiter", os.path.join(root_dir, "tb", "backend"), "Makefile", {}),
        ("Backend RS(18,16) Chipkill ECC", os.path.join(root_dir, "tb", "backend"), "Makefile.chipkill", {}),
        ("Galois LFSR Bus Scrambler", os.path.join(root_dir, "tb", "memory"), "Makefile", {}),
        ("Performance Monitor Unit (PMU & CSR)", os.path.join(root_dir, "tb", "bus"), "Makefile", {}),
        ("Cryptographic Engine Suite (AES-CTR, Split-Counter, AES-CMAC)", os.path.join(root_dir, "tb", "crypto"), "Makefile", {}),
        ("Top-Level E2E Subsystem Integration", os.path.join(root_dir, "tb", "top"), "Makefile", {"MODULE": "test_top_e2e", "SIM_BUILD": "sim_build_e2e"}),
        ("Industry Attack Vectors (ZenHammer, SledgeHammer, Blacksmith)", os.path.join(root_dir, "tb", "top"), "Makefile", {"MODULE": "test_industry_attack_vectors", "SIM_BUILD": "sim_build_attacks"}),
        ("AXI & Memory Channel Natural Sequence Verification", os.path.join(root_dir, "tb", "top"), "Makefile", {"MODULE": "test_channel_natural_sequence", "SIM_BUILD": "sim_build_channel_nat"}),
        ("Semiconductor Lifecycle & Stress Verification", os.path.join(root_dir, "tb", "top"), "Makefile", {"MODULE": "test_semiconductor_lifecycle", "SIM_BUILD": "sim_build_lifecycle"}),
    ]

    print("=" * 80)
    print("  Q-SHIELD MASTER HARDWARE REGRESSION SUITE (COCOTB + VERILATOR)")
    print("=" * 80)

    total_passed = 0
    total_failed = 0
    start_time = time.time()

    env = os.environ.copy()
    cocotb_share = None
    try:
        import cocotb_tools.config
        cocotb_share = str(cocotb_tools.config.makefiles_dir)
    except Exception:
        try:
            import cocotb.config
            cocotb_share = str(cocotb.config.makefiles_dir)
        except Exception:
            pass

    if cocotb_share and os.path.exists(cocotb_share):
        env["COCOTB_SHARE_DIR"] = str(cocotb_share)
        print(f"[*] Configured COCOTB_SHARE_DIR = {cocotb_share}")

    for name, path, makefile, extra_vars in suites:
        print(f"\n[*] Executing: {name}...")
        cmd = ["make", "-f", makefile, "sim"]
        for k, v in extra_vars.items():
            cmd.append(f"{k}={v}")

        t0 = time.time()
        res = subprocess.run(cmd, cwd=path, env=env, capture_output=True, text=True)
        elapsed = time.time() - t0

        if res.returncode == 0:
            print(f"[PASS] {name} completed in {elapsed:.2f}s")
            total_passed += 1
        else:
            print(f"[FAIL] {name} exited with code {res.returncode}")
            print("--- Output Log ---")
            combined_output = (res.stdout + "\n" + res.stderr).strip()
            print(combined_output if combined_output else "  (No output captured)")
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
