#!/usr/bin/env python3
"""
===============================================================================
Script: run_all_tests.py
Description: Master CI & End-to-End Hardware Regression Test Runner for Q-Shield
             Executes Cocotb 2.1 + Verilator test suites across functional,
             integration, cryptographic, and stress testing stages.
Output Artifacts:
  - ci_test_summary.json : Multi-stage test plan summary, runtimes, and status
===============================================================================
"""

import os
import sys
import subprocess
import time
import shutil
import json
import platform

def get_git_commit(root):
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "clean_repository_archive"

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))

    # Multi-Stage Test Plan Categorization
    suites = [
        # Stage 1: Functional Unit Tests
        {
            "name": "Frontend Stage (AXI4 Slave & Skid Buffer)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "frontend"),
            "makefile": "Makefile",
            "env_overrides": {},
        },
        {
            "name": "Frontend Multi-Arch Mapping & Bank Coloring",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "frontend"),
            "makefile": "Makefile.coloring",
            "env_overrides": {},
        },
        {
            "name": "Frontend Write Data Buffer (WDATA)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "frontend"),
            "makefile": "Makefile.wdata_buffer",
            "env_overrides": {},
        },
        {
            "name": "Core Security & QoS (SDC Filter, Queue & ROB)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "core"),
            "makefile": "Makefile",
            "env_overrides": {},
        },
        {
            "name": "Backend Timing Slack Arbiter",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "backend"),
            "makefile": "Makefile",
            "env_overrides": {"SIM_BUILD": "sim_build_arbiter"},
        },
        {
            "name": "Backend PRAC Alert-Back-Off (ABO) Protocol",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "backend"),
            "makefile": "Makefile",
            "env_overrides": {
                "VERILOG_SOURCES": os.path.join(root_dir, "rtl", "backend", "ddr5_cmd_engine.sv"),
                "TOPLEVEL": "ddr5_cmd_engine",
                "MODULE": "test_prac_abo_protocol",
                "SIM_BUILD": "sim_build_abo"
            },
        },
        {
            "name": "Backend Scrub-and-Verify Engine (ECCfail Defense)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "backend"),
            "makefile": "Makefile",
            "env_overrides": {
                "VERILOG_SOURCES": os.path.join(root_dir, "rtl", "backend", "ecc_scrubber.sv"),
                "TOPLEVEL": "ecc_scrubber",
                "MODULE": "test_eccfail_scrub_verify",
                "SIM_BUILD": "sim_build_eccfail"
            },
        },
        {
            "name": "Backend RS(18,16) Chipkill ECC",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "backend"),
            "makefile": "Makefile.chipkill",
            "env_overrides": {},
        },
        {
            "name": "Galois LFSR Bus Scrambler",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "memory"),
            "makefile": "Makefile",
            "env_overrides": {},
        },
        {
            "name": "Reset Synchronizer (CDC rst_sync)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "memory"),
            "makefile": "Makefile.rst_sync",
            "env_overrides": {},
        },
        {
            "name": "Performance Monitor Unit (PMU & CSR)",
            "stage": "Functional",
            "cwd": os.path.join(root_dir, "tb", "bus"),
            "makefile": "Makefile",
            "env_overrides": {},
        },

        # Stage 2: Cryptographic Engine Tests
        {
            "name": "Cryptographic Engine Suite (AES-CTR, Split-Counter, AES-CMAC)",
            "stage": "Crypto",
            "cwd": os.path.join(root_dir, "tb", "crypto"),
            "makefile": "Makefile",
            "env_overrides": {},
        },
        {
            "name": "AES Tweak Vector Generator (GF(2^128) Alpha Mul)",
            "stage": "Crypto",
            "cwd": os.path.join(root_dir, "tb", "crypto"),
            "makefile": "Makefile.tweak_gen",
            "env_overrides": {},
        },
        {
            "name": "AES Pipelined Round Unit (KAT & Backpressure)",
            "stage": "Crypto",
            "cwd": os.path.join(root_dir, "tb", "crypto"),
            "makefile": "Makefile.round_pipe",
            "env_overrides": {},
        },

        # Stage 3: Integration & System E2E Tests
        {
            "name": "Top-Level E2E Subsystem Integration",
            "stage": "Integration",
            "cwd": os.path.join(root_dir, "tb", "top"),
            "makefile": "Makefile",
            "env_overrides": {"MODULE": "test_top_e2e", "SIM_BUILD": "sim_build_e2e"},
        },
        {
            "name": "AXI & Memory Channel Natural Sequence Verification",
            "stage": "Integration",
            "cwd": os.path.join(root_dir, "tb", "top"),
            "makefile": "Makefile",
            "env_overrides": {"MODULE": "test_channel_natural_sequence", "SIM_BUILD": "sim_build_channel_nat"},
        },

        # Stage 4: Adversarial & Long-Term Stress Tests
        {
            "name": "Core Blacksmith Multi-Frequency & Many-Sided Hammering",
            "stage": "Stress",
            "cwd": os.path.join(root_dir, "tb", "core"),
            "makefile": "Makefile",
            "env_overrides": {"MODULE": "test_blacksmith_patterns", "SIM_BUILD": "sim_build_blacksmith"},
        },
        {
            "name": "Backend RowPress Non-Linear Dynamic Threshold Engine",
            "stage": "Stress",
            "cwd": os.path.join(root_dir, "tb", "backend"),
            "makefile": "Makefile",
            "env_overrides": {
                "VERILOG_SOURCES": os.path.join(root_dir, "rtl", "backend", "ddr5_cmd_engine.sv"),
                "TOPLEVEL": "ddr5_cmd_engine",
                "MODULE": "test_rowpress_dynamic",
                "SIM_BUILD": "sim_build_rowpress"
            },
        },
        {
            "name": "Industry Attack Vectors (ZenHammer, SledgeHammer, Blacksmith)",
            "stage": "Stress",
            "cwd": os.path.join(root_dir, "tb", "top"),
            "makefile": "Makefile",
            "env_overrides": {"MODULE": "test_industry_attack_vectors", "SIM_BUILD": "sim_build_attacks"},
        },
        {
            "name": "Semiconductor Lifecycle & Stress Verification",
            "stage": "Stress",
            "cwd": os.path.join(root_dir, "tb", "top"),
            "makefile": "Makefile",
            "env_overrides": {"MODULE": "test_semiconductor_lifecycle", "SIM_BUILD": "sim_build_lifecycle"},
        },
    ]

    # Check execution environment
    is_windows = sys.platform == "win32"
    has_make = shutil.which("make") is not None
    has_wsl = shutil.which("wsl") is not None

    print("=" * 96)
    print("  Q-SHIELD MASTER HARDWARE REGRESSION SUITE (COCOTB 2.1 + VERILATOR)")
    print(f"  Platform   : {platform.system()} {platform.release()} ({platform.machine()})")
    print(f"  Python     : {platform.python_version()}")
    print(f"  Native Make: {'Available' if has_make else 'Not found'}")
    print(f"  WSL Engine : {'Available' if has_wsl else 'Not found'}")
    print(f"  Total Tests: {len(suites)} suites across 4 stages (Functional, Crypto, Integration, Stress)")
    print("=" * 96)

    # If running on Windows host without native make, check WSL dispatch
    if is_windows and not has_make and has_wsl:
        print("[*] Host is Windows and native 'make' is not present. Dispatching execution into WSL environment...")
        drive, rest = os.path.splitdrive(os.path.abspath(__file__))
        drive_letter = drive.replace(":", "").lower()
        wsl_path = f"/mnt/{drive_letter}" + rest.replace("\\", "/")
        ret = subprocess.run(["wsl", "--", "python3", wsl_path] + sys.argv[1:])
        sys.exit(ret.returncode)

    # Native execution loop
    total_passed = 0
    total_failed = 0
    total_skipped = 0
    test_results = []
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

    if cocotb_share:
        env["COCOTB_SHARE"] = cocotb_share

    for idx, item in enumerate(suites, 1):
        name = item["name"]
        stage = item["stage"]
        cwd = item["cwd"]
        makefile = item["makefile"]
        overrides = item["env_overrides"]

        print(f"[{idx:02d}/{len(suites):02d}] Stage: {stage:<11} | Running: {name} ...", end=" ", flush=True)

        if not os.path.isdir(cwd):
            print(f"[SKIP] (Directory not found: {cwd})")
            total_skipped += 1
            test_results.append({"name": name, "stage": stage, "status": "SKIPPED", "runtime_seconds": 0.0, "exit_code": -1})
            continue

        cmd = ["make", "-f", makefile]
        run_env = env.copy()
        for k, v in overrides.items():
            run_env[k] = v

        t0 = time.time()
        try:
            res = subprocess.run(cmd, cwd=cwd, env=run_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            elapsed = time.time() - t0
            output = res.stdout

            # Clean output parsing
            passed = res.returncode == 0 and "FAIL" not in output and "Error" not in output
            if passed:
                total_passed += 1
                status = "PASS"
                print(f"[PASS] in {elapsed:.2f}s")
            else:
                total_failed += 1
                status = "FAIL"
                print(f"[FAIL] (Exit Code: {res.returncode})")
            
            test_results.append({
                "name": name,
                "stage": stage,
                "status": status,
                "runtime_seconds": round(elapsed, 2),
                "exit_code": res.returncode,
            })
        except Exception as e:
            elapsed = time.time() - t0
            total_failed += 1
            print(f"[ERROR] ({str(e)})")
            test_results.append({
                "name": name,
                "stage": stage,
                "status": "ERROR",
                "runtime_seconds": round(elapsed, 2),
                "exit_code": -1,
            })

    total_duration = time.time() - start_time

    # Save CI Test Summary JSON
    summary_path = os.path.join(root_dir, "ci_test_summary.json")
    summary_data = {
        "suite": "Cocotb 2.1 + Verilator Hardware Regression",
        "commit_sha": get_git_commit(root_dir),
        "platform": f"{platform.system()} {platform.release()}",
        "python_version": platform.python_version(),
        "total_tests": len(suites),
        "passed": total_passed,
        "failed": total_failed,
        "skipped": total_skipped,
        "pass_rate_pct": round((total_passed / max(1, len(suites) - total_skipped)) * 100.0, 2),
        "total_duration_seconds": round(total_duration, 2),
        "timestamp_epoch": time.time(),
        "tests": test_results,
    }
    with open(summary_path, "w") as f:
        json.dump(summary_data, f, indent=2)

    print("\n" + "=" * 96)
    print("  COCOTB HARDWARE REGRESSION SUMMARY REPORT")
    print("=" * 96)
    print(f"{'Test Description':<54} | {'Stage':<11} | {'Status':<7} | {'Duration'}")
    print("-" * 96)
    for r in test_results:
        print(f"{r['name']:<54} | {r['stage']:<11} | {r['status']:<7} | {r['runtime_seconds']:6.2f}s")
    print("=" * 96)
    print(f"  TOTAL: {total_passed} Passed, {total_failed} Failed, {total_skipped} Skipped in {total_duration:.2f}s")
    print(f"  [+] Saved Summary JSON: {summary_path}")
    print("=" * 96)

    sys.exit(0 if total_failed == 0 else 1)

if __name__ == "__main__":
    main()
