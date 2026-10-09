#!/usr/bin/env python3
"""
===============================================================================
Script: run_iverilog_regression.py
Description: Master SystemVerilog Hardware Regression Test Suite for Q-Shield
             Compiles and runs all unit testbenches and top-level integration
             testbenches using Icarus Verilog (iverilog + vvp).
Output Artifacts:
  - regression_summary.json : Comprehensive execution log per test and overall stats
  - failure_report.json     : Detailed failure diagnostics, logs, and stack traces
  - regression_logs/        : Directory containing full stdout/stderr traces per test
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

def get_iverilog_version(iverilog_bin):
    try:
        res = subprocess.run([iverilog_bin, "-V"], capture_output=True, text=True)
        first_line = res.stdout.splitlines()[0] if res.stdout else "Icarus Verilog"
        return first_line.strip()
    except Exception:
        return "Unknown Icarus Version"

def find_tool(tool_name, default_dir=r"D:\iverilog\bin"):
    found = shutil.which(tool_name)
    if found:
        return found
    fallback = os.path.join(default_dir, tool_name + ".exe")
    if os.path.isfile(fallback):
        return fallback
    return tool_name

def run_test(name, top_module, sources, iverilog, vvp, cwd, log_dir):
    log_file = os.path.join(log_dir, f"{top_module}.log")
    vvp_file = f"build_{top_module}.vvp"
    vvp_path = os.path.join(cwd, vvp_file)

    compile_cmd = [iverilog, "-g2012", "-Wall", "-s", top_module, "-o", vvp_file] + sources
    t0 = time.time()
    res_compile = subprocess.run(compile_cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")

    if res_compile.returncode != 0:
        elapsed = time.time() - t0
        err_msg = res_compile.stdout + "\n" + res_compile.stderr
        with open(log_file, "w", encoding="utf-8") as f:
            f.write(f"=== COMPILE COMMAND ===\n{' '.join(compile_cmd)}\n\n=== ERROR LOG ===\n{err_msg}\n")
        return {
            "name": name,
            "top": top_module,
            "status": "FAIL",
            "reason": "Compilation Error",
            "runtime_seconds": round(elapsed, 3),
            "command": " ".join(compile_cmd),
            "log_path": log_file,
            "error_snippet": err_msg[-500:],
        }

    sim_cmd = [vvp, vvp_file]
    res_sim = subprocess.run(sim_cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    elapsed = time.time() - t0

    # Clean up intermediate vvp binary
    try:
        if os.path.exists(vvp_path):
            os.remove(vvp_path)
    except Exception:
        pass

    full_log = f"=== COMPILE COMMAND ===\n{' '.join(compile_cmd)}\n\n=== SIM COMMAND ===\n{' '.join(sim_cmd)}\n\n=== STDOUT ===\n{res_sim.stdout}\n\n=== STDERR ===\n{res_sim.stderr}\n"
    with open(log_file, "w", encoding="utf-8") as f:
        f.write(full_log)

    output = res_sim.stdout + "\n" + res_sim.stderr
    has_explicit_fail = "[FAIL]" in output or "FAILED]" in output or "fatal" in output.lower()
    has_pass_banner = "ALL TESTS PASSED" in output or "PASSED SUCCESSFULLY" in output or "[PASS]" in output

    if res_sim.returncode == 0 and not has_explicit_fail and has_pass_banner:
        return {
            "name": name,
            "top": top_module,
            "status": "PASS",
            "reason": "Simulation Passed",
            "runtime_seconds": round(elapsed, 3),
            "command": " ".join(sim_cmd),
            "log_path": log_file,
            "error_snippet": None,
        }
    else:
        return {
            "name": name,
            "top": top_module,
            "status": "FAIL",
            "reason": "Simulation Failure",
            "runtime_seconds": round(elapsed, 3),
            "command": " ".join(sim_cmd),
            "log_path": log_file,
            "error_snippet": "\n".join(output.splitlines()[-20:]),
        }

def main():
    root = os.path.abspath(os.path.dirname(__file__))
    log_dir = os.path.join(root, "regression_logs")
    os.makedirs(log_dir, exist_ok=True)

    iverilog = find_tool("iverilog")
    vvp = find_tool("vvp")
    iverilog_ver = get_iverilog_version(iverilog)
    git_sha = get_git_commit(root)

    print("=" * 96)
    print("  Q-SHIELD MASTER HARDWARE REGRESSION SUITE (IVERILOG + VVP)")
    print(f"  Toolchain  : {iverilog_ver}")
    print(f"  Platform   : {platform.system()} {platform.release()} ({platform.machine()})")
    print(f"  Python     : {platform.python_version()}")
    print(f"  Commit SHA : {git_sha}")
    print(f"  Logs Dir   : {log_dir}")
    print("=" * 96)

    tests = [
        {
            "name": "Upgrade 4: APB4 CSR Register File Extension",
            "top": "tb_apb_csr_regs",
            "module_covered": "rtl/bus/apb_csr_regs.sv",
            "behavior_verified": "APB4 read/write handshake, security mode locks, and telemetry registers",
            "sources": [
                os.path.join(root, "rtl", "bus", "apb_csr_regs.sv"),
                os.path.join(root, "tb", "bus", "tb_apb_csr_regs.sv"),
            ]
        },
        {
            "name": "Frontend: AXI4 Slave Adapter & Skid Buffers",
            "top": "tb_axi4_slave_adapter",
            "module_covered": "rtl/bus/axi4_slave_adapter.sv",
            "behavior_verified": "Zero-bubble forward registration, AW/W burst decoupling, and B/R channels",
            "sources": [
                os.path.join(root, "rtl", "bus", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "bus", "axi4_slave_adapter.sv"),
                os.path.join(root, "tb", "bus", "tb_axi4_slave_adapter.sv"),
            ]
        },
        {
            "name": "Upgrade 1: Adaptive Threshold Engine (ATE)",
            "top": "tb_adaptive_threshold_engine",
            "module_covered": "rtl/core/adaptive_threshold_engine.sv",
            "behavior_verified": "EWMA dynamic threshold calculation against non-uniform evasion attacks",
            "sources": [
                os.path.join(root, "rtl", "core", "adaptive_threshold_engine.sv"),
                os.path.join(root, "tb", "core", "tb_adaptive_threshold_engine.sv"),
            ]
        },
        {
            "name": "Upgrade 3: Write-Drain / Read-Burst Mode Scheduler",
            "top": "tb_slack_aware_arbiter",
            "module_covered": "rtl/backend/slack_aware_arbiter.sv",
            "behavior_verified": "Hysteresis write-drain queue switching and bank group timing-slack bypassing",
            "sources": [
                os.path.join(root, "rtl", "backend", "slack_aware_arbiter.sv"),
                os.path.join(root, "tb", "backend", "tb_slack_aware_arbiter.sv"),
            ]
        },
        {
            "name": "Upgrade 7: RowPress Attack Detection",
            "top": "tb_ddr5_cmd_engine",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Row duration tracking and JEDEC tRAS_max auto-precharge clamping",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "backend", "tb_ddr5_cmd_engine.sv"),
            ]
        },
        {
            "name": "Upgrade 2: Directed Refresh Manager (DRM)",
            "top": "tb_directed_refresh_manager",
            "module_covered": "rtl/backend/directed_refresh_manager.sv",
            "behavior_verified": "Targeted refresh queue dispatch (Row +/- 1, +/- 2) and backpressure stall",
            "sources": [
                os.path.join(root, "rtl", "backend", "directed_refresh_manager.sv"),
                os.path.join(root, "tb", "backend", "tb_directed_refresh_manager.sv"),
            ]
        },
        {
            "name": "Crypto Stage 1: AES S-Box NIST Vector Verification",
            "top": "tb_aes_sbox_test",
            "module_covered": "rtl/crypto/aes_sbox.sv",
            "behavior_verified": "NIST SP 800-38A known-answer test vectors for composite field AES S-Box",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "tb", "crypto", "tb_aes_sbox_test.sv"),
            ]
        },
        {
            "name": "Crypto Stage 2: Dual-Lane AES-256-XTS Pipelined Engine",
            "top": "tb_aes_xts_pipe",
            "module_covered": "rtl/crypto/subchannel_aes_xts_pipe.sv",
            "behavior_verified": "GF(2^128) tweak generation, pipelined round stages, and wire-speed encryption",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_pkg.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox_composite.sv"),
                os.path.join(root, "rtl", "crypto", "aes_tweak_gen.sv"),
                os.path.join(root, "rtl", "crypto", "aes_round_pipe.sv"),
                os.path.join(root, "rtl", "crypto", "subchannel_aes_xts_pipe.sv"),
                os.path.join(root, "tb", "crypto", "tb_aes_xts_pipe.sv"),
            ]
        },
        {
            "name": "Top-Level Integration: AXI4 DDR5 Secure Memory Controller",
            "top": "tb_axi_ddr5_mc_top",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "Full top-level pipeline: AXI slave -> Skid buffer -> SDC filter -> ROB -> DFI",
            "sources": [
                os.path.join(root, "rtl", "cdc", "rst_sync.sv"),
                os.path.join(root, "rtl", "frontend", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "axi_slave_frontend.sv"),
                os.path.join(root, "rtl", "frontend", "wdata_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "domain_bank_coloring.sv"),
                os.path.join(root, "rtl", "core", "scarf_dram_randomizer.sv"),
                os.path.join(root, "rtl", "frontend", "addr_mapper_ddr5.sv"),
                os.path.join(root, "rtl", "core", "reorder_buffer_rob.sv"),
                os.path.join(root, "rtl", "core", "fault_hardened_csr.sv"),
                os.path.join(root, "rtl", "crypto", "multi_vm_key_table.sv"),
                os.path.join(root, "rtl", "core", "pxor_hash_engine.sv"),
                os.path.join(root, "rtl", "core", "sdc_resilient_filter.sv"),
                os.path.join(root, "rtl", "core", "adaptive_threshold_engine.sv"),
                os.path.join(root, "rtl", "backend", "directed_refresh_manager.sv"),
                os.path.join(root, "rtl", "core", "qos_scheduler_queue.sv"),
                os.path.join(root, "rtl", "backend", "slack_aware_arbiter.sv"),
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "rtl", "backend", "ecc_scrubber.sv"),
                os.path.join(root, "rtl", "memory", "bus_scrambler.sv"),
                os.path.join(root, "rtl", "bus", "perf_monitor_unit.sv"),
                os.path.join(root, "rtl", "top", "axi_ddr5_mc_top.sv"),
                os.path.join(root, "tb", "top", "tb_axi_ddr5_mc_top.sv"),
            ]
        },
        {
            "name": "Security V3.0: SCARF 1-Cycle DRAM Address Randomizer",
            "top": "tb_scarf_randomizer",
            "module_covered": "rtl/core/scarf_dram_randomizer.sv",
            "behavior_verified": "10-round Feistel permutation, non-linear S-Box, bijectivity, and seed avalanche",
            "sources": [
                os.path.join(root, "rtl", "core", "scarf_dram_randomizer.sv"),
                os.path.join(root, "tb", "core", "tb_scarf_randomizer.sv"),
            ]
        },
        {
            "name": "Security V3.0: Crystalor PXOR-Hash Universal Hashing Engine",
            "top": "tb_pxor_sdc_filter",
            "module_covered": "rtl/core/pxor_hash_engine.sv",
            "behavior_verified": "Parallel XOR universal hashing with bounded collision and uniform distribution",
            "sources": [
                os.path.join(root, "rtl", "core", "pxor_hash_engine.sv"),
                os.path.join(root, "tb", "core", "tb_pxor_sdc_filter.sv"),
            ]
        },
        {
            "name": "Security V3.0: AMD SEV Multi-ASID Confidential Key Table",
            "top": "tb_multi_vm_key_table",
            "module_covered": "rtl/crypto/multi_vm_key_table.sv",
            "behavior_verified": "16-VM key isolation, C-bit DMA bypass, and APB4 supervisor privilege protection",
            "sources": [
                os.path.join(root, "rtl", "crypto", "multi_vm_key_table.sv"),
                os.path.join(root, "tb", "crypto", "tb_multi_vm_key_table.sv"),
            ]
        },
        {
            "name": "Security V3.0: HOST '20 Fault-Hardened CSR with TMR Glitch Watchdog",
            "top": "tb_fault_hardened_csr",
            "module_covered": "rtl/core/fault_hardened_csr.sv",
            "behavior_verified": "Triple Modular Redundancy 2-out-of-3 voting, single-rail SEU masking, and glitch latch",
            "sources": [
                os.path.join(root, "rtl", "core", "fault_hardened_csr.sv"),
                os.path.join(root, "tb", "core", "tb_fault_hardened_csr.sv"),
            ]
        },
        {
            "name": "Top-Level Integration: Inline AES-256-XTS Secure DDR5 Controller",
            "top": "tb_sec_ddr5_controller_top",
            "module_covered": "rtl/top/sec_ddr5_controller_top.sv",
            "behavior_verified": "End-to-end encrypted DDR5 subchannel scheduling and CDC synchronization",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_pkg.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox_composite.sv"),
                os.path.join(root, "rtl", "crypto", "aes_tweak_gen.sv"),
                os.path.join(root, "rtl", "crypto", "aes_round_pipe.sv"),
                os.path.join(root, "rtl", "crypto", "subchannel_aes_xts_pipe.sv"),
                os.path.join(root, "rtl", "bus", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "bus", "apb_csr_regs.sv"),
                os.path.join(root, "rtl", "bus", "axi4_slave_adapter.sv"),
                os.path.join(root, "rtl", "memory", "async_fifo_cdc.sv"),
                os.path.join(root, "rtl", "memory", "ddr5_subchannel_scheduler.sv"),
                os.path.join(root, "rtl", "memory", "dfi_phy_adapter.sv"),
                os.path.join(root, "rtl", "top", "sec_ddr5_controller_top.sv"),
                os.path.join(root, "tb", "top", "tb_sec_ddr5_controller_top.sv"),
            ]
        },
        {
            "name": "McSee Defense: Autonomous JEDEC DDR5 RFM Generation",
            "top": "tb_mcsee_autonomous_rfm",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Autonomous RFM command issuance upon host command omission",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "backend", "tb_mcsee_autonomous_rfm.sv"),
            ]
        },
        {
            "name": "RowPress Defense: tRAS_max Auto-Precharge Clamping",
            "top": "tb_rowpress_tras_clamping",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Forced precharge activation when open time exceeds JEDEC tRAS_max threshold",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "backend", "tb_rowpress_tras_clamping.sv"),
            ]
        },
        {
            "name": "SledgeHammer Defense: Cross-Bank Multi-Active Monitoring",
            "top": "tb_sledgehammer_multibank",
            "module_covered": "rtl/core/sdc_resilient_filter.sv",
            "behavior_verified": "Cross-bank multi-aggressor tracking and bin saturation mitigation",
            "sources": [
                os.path.join(root, "rtl", "core", "pxor_hash_engine.sv"),
                os.path.join(root, "rtl", "core", "sdc_resilient_filter.sv"),
                os.path.join(root, "tb", "core", "tb_sledgehammer_multibank.sv"),
            ]
        },
        {
            "name": "Frontend: AMBA AXI5 Poison & ASIL-D Parity Compliance",
            "top": "tb_axi5_compliance",
            "module_covered": "rtl/frontend/axi_slave_frontend.sv",
            "behavior_verified": "AW/AR/W/R parity error detection and AXI poison signal propagation",
            "sources": [
                os.path.join(root, "rtl", "frontend", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "axi_slave_frontend.sv"),
                os.path.join(root, "tb", "frontend", "tb_axi5_compliance.sv"),
            ]
        }
    ]

    total_passed = 0
    total_failed = 0
    test_records = []
    failed_records = []
    start_time = time.time()

    for idx, t in enumerate(tests, 1):
        print(f"[{idx:02d}/{len(tests):02d}] Running: {t['name']} (Top: {t['top']}) ...", end=" ", flush=True)
        record = run_test(
            name=t["name"],
            top_module=t["top"],
            sources=t["sources"],
            iverilog=iverilog,
            vvp=vvp,
            cwd=root,
            log_dir=log_dir
        )
        record["module_covered"] = t["module_covered"]
        record["behavior_verified"] = t["behavior_verified"]
        test_records.append(record)

        if record["status"] == "PASS":
            total_passed += 1
            print(f"[PASS] in {record['runtime_seconds']:.2f}s")
        else:
            total_failed += 1
            failed_records.append(record)
            print(f"[FAIL] ({record['reason']})")
            if record["error_snippet"]:
                print(f"       >> Error Snippet:\n{record['error_snippet']}\n")

    total_duration = time.time() - start_time

    # 1. Save Full Regression Summary JSON
    summary_payload = {
        "suite": "Icarus Verilog Master Hardware Regression",
        "tool_version": iverilog_ver,
        "platform": f"{platform.system()} {platform.release()}",
        "python_version": platform.python_version(),
        "commit_sha": git_sha,
        "total_tests": len(tests),
        "passed": total_passed,
        "failed": total_failed,
        "pass_rate_pct": round((total_passed / len(tests)) * 100.0, 2),
        "total_duration_seconds": round(total_duration, 2),
        "timestamp_epoch": time.time(),
        "tests": test_records,
    }

    summary_json_path = os.path.join(root, "regression_summary.json")
    with open(summary_json_path, "w", encoding="utf-8") as f:
        json.dump(summary_payload, f, indent=2)

    # 2. Save Failure Diagnostics JSON
    failure_json_path = os.path.join(root, "failure_report.json")
    failure_payload = {
        "total_failures": total_failed,
        "failures": failed_records,
        "timestamp_epoch": time.time(),
    }
    with open(failure_json_path, "w", encoding="utf-8") as f:
        json.dump(failure_payload, f, indent=2)

    print("\n" + "=" * 96)
    print("  Q-SHIELD REGRESSION EXECUTION SUMMARY REPORT")
    print("=" * 96)
    print(f"{'Test Description':<56} | {'Result':<8} | {'Time (s)':<8} | {'Covered Module'}")
    print("-" * 96)
    for rec in test_records:
        status_str = rec["status"]
        mod_short = os.path.basename(rec["module_covered"])
        print(f"{rec['name']:<56} | {status_str:<8} | {rec['runtime_seconds']:6.2f}s | {mod_short}")
    print("=" * 96)
    print(f"  FINAL VERDICT: {total_passed}/{len(tests)} PASSED, {total_failed} FAILED (Duration: {total_duration:.2f}s)")
    print(f"  [+] Saved Summary JSON : {summary_json_path}")
    print(f"  [+] Saved Failures JSON: {failure_json_path}")
    print(f"  [+] Detailed Logs Dir  : {log_dir}")
    print("=" * 96)

    if total_failed > 0:
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()
