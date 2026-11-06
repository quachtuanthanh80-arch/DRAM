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
import re
import sys
import subprocess
import time
import shutil
import json
import platform

# PASS is decided only from this machine-readable line (tb/common/tb_check.svh), never from banners.
TB_RESULT_RE = re.compile(r"\[TB_RESULT\]\s+checks=(\d+)\s+fails=(\d+)\s+xfails=(\d+)")
XFAIL_RE = re.compile(r"\[XFAIL\]\s+(\S+):\s*(.*)")

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

    # Shared packages must be compiled before their importers; harmless for tests that do not import them
    pkgs = [os.path.join(cwd, "rtl", "backend", "secded_72_64_pkg.sv"), os.path.join(cwd, "tb", "common", "ddr5_jedec_bin_pkg.sv")]
    sources = pkgs + [s for s in sources if s not in pkgs]
    compile_cmd = [iverilog, "-g2012", "-Wall", "-I", os.path.join(cwd, "tb", "common"),
                   "-s", top_module, "-o", vvp_file] + sources
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
            "checks": 0,
            "fails": 1,
            "xfails": [],
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
    results = TB_RESULT_RE.findall(output)
    xfails = [{"gap": g, "detail": d.strip()} for g, d in XFAIL_RE.findall(output)]
    has_explicit_fail = ("[FAIL]" in output or "fatal" in output.lower()
                         or re.search(r"^ERROR:", output, re.MULTILINE) is not None)

    checks = fails = 0
    if not results:
        status, reason = "FAIL", "No [TB_RESULT] line (testbench reports no checked result)"
    elif len(results) > 1:
        status, reason = "FAIL", "Multiple [TB_RESULT] lines"
    else:
        checks, fails, _ = (int(v) for v in results[0])
        if res_sim.returncode != 0:
            status, reason = "FAIL", f"Simulator exit code {res_sim.returncode}"
        elif checks == 0:
            status, reason = "FAIL", "Zero checks executed"
        elif fails > 0 or has_explicit_fail:
            status, reason = "FAIL", f"{fails} failed check(s)"
        else:
            status, reason = "PASS", f"{checks} checks passed"

    return {
        "name": name,
        "top": top_module,
        "status": status,
        "reason": reason,
        "checks": checks,
        "fails": fails,
        "xfails": xfails,
        "runtime_seconds": round(elapsed, 3),
        "command": " ".join(sim_cmd),
        "log_path": log_file,
        "error_snippet": None if status == "PASS" else "\n".join(output.splitlines()[-20:]),
        "stdout": res_sim.stdout,
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

    top_common_sources = [
        os.path.join(root, "rtl", "cdc", "rst_sync.sv"),
        os.path.join(root, "rtl", "bus", "axi4_skid_buffer.sv"),
        os.path.join(root, "rtl", "frontend", "axi_slave_frontend.sv"),
        os.path.join(root, "rtl", "frontend", "wdata_buffer.sv"),
        os.path.join(root, "rtl", "frontend", "wr_data_store.sv"),
        os.path.join(root, "rtl", "frontend", "axi_burst_splitter.sv"),
        os.path.join(root, "rtl", "frontend", "rd_issue_queue.sv"),
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
        os.path.join(root, "rtl", "memory", "scrambler_ks_pipe.sv"),
        os.path.join(root, "rtl", "bus", "perf_monitor_unit.sv"),
        os.path.join(root, "rtl", "top", "bank_credit_ctrl.sv"),
        os.path.join(root, "rtl", "top", "axi_ddr5_mc_top.sv"),
        os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
        os.path.join(root, "tb", "common", "dram_model.sv"),
        os.path.join(root, "tb", "common", "qs_axi_txn_chk.sv"),
        os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
        os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
        os.path.join(root, "tb", "common", "qs_top_probe_chk.sv"),
    ]

    tests = [
        {
            "name": "Upgrade 4: APB4 CSR Register File Extension",
            "top": "tb_apb_csr_regs",
            "module_covered": "rtl/bus/apb_csr_regs.sv",
            "behavior_verified": "APB4 read/write handshake, security mode locks, and telemetry registers",
            "sources": [
                os.path.join(root, "rtl", "core", "fault_hardened_csr.sv"),
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
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
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
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_axi_ddr5_mc_top.sv")],
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
            "name": "DV Self-Test: JEDEC DFI Protocol Checker Detects Every Violation Class",
            "top": "tb_dfi_jedec_checker",
            "module_covered": "tb/common/dfi_jedec_checker.sv",
            "behavior_verified": "Checker v2 in ps (SA-J01..J21): each rule has a violating DFI sequence that is flagged and a just-legal one that stays clean",
            "sources": [
                os.path.join(root, "tb", "common", "ddr5_jedec_bin_pkg.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "tb_dfi_jedec_checker.sv"),
            ]
        },
        {
            "name": "Chipkill: Single Parity-Chip Failure (RS(18,16) over GF(2^8))",
            "top": "tb_rs_parity_chip",
            "module_covered": "rtl/backend/rs_chipkill_decoder.sv",
            "behavior_verified": "Every magnitude of a P0/P1 chip failure is corrected or flagged, never silently miscorrected into data",
            "sources": [
                os.path.join(root, "rtl", "backend", "gf256_arith_pkg.sv"),
                os.path.join(root, "rtl", "backend", "rs_chipkill_encoder.sv"),
                os.path.join(root, "rtl", "backend", "rs_chipkill_decoder.sv"),
                os.path.join(root, "tb", "backend", "tb_rs_parity_chip.sv"),
            ]
        },
        {
            "name": "Crypto: Iterative AES-128 Core (FIPS-197 C.1 + 64 Python cryptography vectors)",
            "top": "tb_aes128_enc_iter",
            "module_covered": "rtl/crypto/aes128_enc_iter.sv",
            "behavior_verified": "Bit-exact AES-128 encryption against FIPS-197 C.1 and 64 random vectors from the Python cryptography package",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes128_enc_iter.sv"),
                os.path.join(root, "tb", "crypto", "tb_aes128_enc_iter.sv"),
            ]
        },
        {
            "name": "Scrambler keystream pipeline: bit-exact with bus_scrambler after 6 cycles",
            "top": "tb_scrambler_ks_pipe",
            "module_covered": "rtl/memory/scrambler_ks_pipe.sv",
            "behavior_verified": "1,496 random keys: pipelined ARX keystream equals the combinational bus_scrambler mask, sideband aligned",
            "sources": [
                os.path.join(root, "rtl", "memory", "bus_scrambler.sv"),
                os.path.join(root, "rtl", "memory", "scrambler_ks_pipe.sv"),
                os.path.join(root, "tb", "memory", "tb_scrambler_ks_pipe.sv"),
            ]
        },
        {
            "name": "AXI4 Burst Splitter: INCR/WRAP/FIXED/narrow beat addresses vs A3.4.1",
            "top": "tb_axi_burst_splitter",
            "module_covered": "rtl/frontend/axi_burst_splitter.sv",
            "behavior_verified": "3,000 random bursts split into line-confined chunks of <= 8 beats whose beat addresses match the AXI4 formula; RLAST/B flag only on the final chunk",
            "sources": [
                os.path.join(root, "rtl", "frontend", "axi_burst_splitter.sv"),
                os.path.join(root, "rtl", "frontend", "rd_issue_queue.sv"),
                os.path.join(root, "tb", "frontend", "tb_axi_burst_splitter.sv"),
            ]
        },
        {
            "name": "Crypto: AES-256 Key Expansion + 14-Round Pipeline (FIPS-197 A.3/C.3 + 64 Python vectors)",
            "top": "tb_aes256_key_expand",
            "module_covered": "rtl/crypto/aes256_key_expand.sv",
            "behavior_verified": "FIPS-197 key schedule and the project's aes_round_pipe chain produce bit-exact AES-256",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_pkg.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes_round_pipe.sv"),
                os.path.join(root, "rtl", "crypto", "aes256_key_expand.sv"),
                os.path.join(root, "tb", "crypto", "tb_aes256_key_expand.sv"),
            ]
        },
        {
            "name": "Reorder Buffer: Per-ID AXI Ordering & OoO Writeback Scoreboard",
            "top": "tb_reorder_buffer_rob",
            "module_covered": "rtl/core/reorder_buffer_rob.sv",
            "behavior_verified": "Per-ID in-order retirement, cross-ID bypass of pending reads, 400-request random OoO writeback with R backpressure",
            "sources": [
                os.path.join(root, "rtl", "core", "reorder_buffer_rob.sv"),
                os.path.join(root, "tb", "core", "tb_reorder_buffer_rob.sv"),
            ]
        },
        {
            "name": "QoS Scheduler Queue: Same-Address Hazard Ordering & QoS Bypass",
            "top": "tb_qos_scheduler_queue",
            "module_covered": "rtl/core/qos_scheduler_queue.sv",
            "behavior_verified": "RAW/WAR/WAW same-address commands never reordered; independent commands still QoS-prioritized; 600-command random scoreboard",
            "sources": [
                os.path.join(root, "rtl", "core", "qos_scheduler_queue.sv"),
                os.path.join(root, "tb", "core", "tb_qos_scheduler_queue.sv"),
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
                os.path.join(root, "rtl", "core", "fault_hardened_csr.sv"),
                os.path.join(root, "rtl", "bus", "apb_csr_regs.sv"),
                os.path.join(root, "rtl", "bus", "axi4_slave_adapter.sv"),
                os.path.join(root, "rtl", "cdc", "async_fifo_cdc.sv"),
                os.path.join(root, "rtl", "memory", "ddr5_subchannel_scheduler.sv"),
                os.path.join(root, "rtl", "memory", "dfi_phy_adapter.sv"),
                os.path.join(root, "rtl", "crypto", "split_counter_table.sv"),
                os.path.join(root, "rtl", "crypto", "aes_ctr_keystream.sv"),
                os.path.join(root, "rtl", "crypto", "aes256_key_expand.sv"),
                os.path.join(root, "rtl", "crypto", "aes128_enc_iter.sv"),
                os.path.join(root, "rtl", "crypto", "integrity_mac_gen.sv"),
                os.path.join(root, "rtl", "crypto", "qshield_crypto_top.sv"),
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
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
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
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
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
                os.path.join(root, "rtl", "bus", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "axi_slave_frontend.sv"),
                os.path.join(root, "tb", "frontend", "tb_axi5_compliance.sv"),
            ]
        },
        {
            "name": "Security V3.1: Two-Tier Decoupled AES-CTR Pre-computation Engine",
            "top": "tb_qshield_crypto_top",
            "module_covered": "rtl/crypto/qshield_crypto_top.sv",
            "behavior_verified": "Profiles 0-3, 0-cycle CTR pre-computation, MAC integrity, and ASIL-D poisoning",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_pkg.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes_sbox_composite.sv"),
                os.path.join(root, "rtl", "crypto", "aes_round_pipe.sv"),
                os.path.join(root, "rtl", "crypto", "split_counter_table.sv"),
                os.path.join(root, "rtl", "crypto", "aes_ctr_keystream.sv"),
                os.path.join(root, "rtl", "crypto", "aes256_key_expand.sv"),
                os.path.join(root, "rtl", "crypto", "aes128_enc_iter.sv"),
                os.path.join(root, "rtl", "crypto", "integrity_mac_gen.sv"),
                os.path.join(root, "rtl", "crypto", "qshield_crypto_top.sv"),
                os.path.join(root, "tb", "crypto", "tb_qshield_crypto_top.sv"),
            ]
        },
        {
            "name": "Red Team: Integrity MAC Forgery, Relocation & Replay",
            "top": "tb_integrity_mac_attack",
            "module_covered": "rtl/crypto/integrity_mac_gen.sv",
            "behavior_verified": "MAC must be key-dependent, non-linear, and bound to address, counter and all data bits",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "rtl", "crypto", "aes128_enc_iter.sv"),
                os.path.join(root, "rtl", "crypto", "integrity_mac_gen.sv"),
                os.path.join(root, "tb", "crypto", "tb_integrity_mac_attack.sv"),
            ]
        },
        {
            "name": "Interconnect: PCIe Gen5 / CXL.io APB CSR Shim & DVSEC Header",
            "top": "tb_pcie_cxl_io_shim",
            "module_covered": "rtl/interfaces/pcie_cxl_io_apb_shim.sv",
            "behavior_verified": "PCIe TLP to APB4 bridge, CXL 3.0 DVSEC header readback, and TMR CSR programming",
            "sources": [
                os.path.join(root, "rtl", "core", "fault_hardened_csr.sv"),
                os.path.join(root, "rtl", "bus", "apb_csr_regs.sv"),
                os.path.join(root, "rtl", "interfaces", "pcie_cxl_io_apb_shim.sv"),
                os.path.join(root, "tb", "interfaces", "pcie", "tb_pcie_cxl_io_shim.sv"),
            ]
        },
        {
            "name": "Form Factor A: CXL.mem 3.0 Flit Expander & Multi-VM Isolation",
            "top": "tb_cxl_mem_axi_shim",
            "module_covered": "rtl/interfaces/cxl_mem_axi_shim.sv",
            "behavior_verified": "M2S/S2M 68B/256B Flit unpacking/packing, SPID to AXI mapping, and poison reflection",
            "sources": [
                os.path.join(root, "rtl", "interfaces", "cxl_mem_axi_shim.sv"),
                os.path.join(root, "tb", "interfaces", "cxl", "tb_cxl_mem_axi_shim.sv"),
            ]
        },
        {
            "name": "Form Factor B: UCIe 1.1 FDI Bring-Up & AoU Streaming",
            "top": "tb_ucie_fdi_axi_shim",
            "module_covered": "rtl/interfaces/ucie_fdi_axi_shim.sv",
            "behavior_verified": "UCIe 1.1 FDI bring-up state machine, AoU streaming flits, and Tau-scaling delay",
            "sources": [
                os.path.join(root, "rtl", "interfaces", "ucie_fdi_axi_shim.sv"),
                os.path.join(root, "tb", "interfaces", "ucie", "tb_ucie_fdi_axi_shim.sv"),
            ]
        },
        {
            "name": "CDC Stage: Dual-Clock Gray-Code Async FIFO (250->400MHz)",
            "top": "tb_async_fifo_cdc",
            "module_covered": "rtl/cdc/async_fifo_cdc.sv",
            "behavior_verified": "Dual-clock Gray-code pointer synchronization, full backpressure, and 100-block streaming",
            "sources": [
                os.path.join(root, "rtl", "cdc", "async_fifo_cdc.sv"),
                os.path.join(root, "tb", "memory", "tb_async_fifo_cdc.sv"),
            ]
        },
        {
            "name": "Memory Stage 1: DDR5 Dual-Subchannel Command Scheduler",
            "top": "tb_ddr5_subchannel_scheduler",
            "module_covered": "rtl/memory/ddr5_subchannel_scheduler.sv",
            "behavior_verified": "Cold-start ACT->tRCD->WR, zero-penalty Page Hit RD, and Page Conflict PRE->tRP->ACT",
            "sources": [
                os.path.join(root, "rtl", "memory", "ddr5_subchannel_scheduler.sv"),
                os.path.join(root, "tb", "memory", "tb_ddr5_subchannel_scheduler.sv"),
            ]
        },
        {
            "name": "Memory Stage 2: Industrial DFI 5.0 Physical Layer Adapter",
            "top": "tb_dfi_phy_adapter",
            "module_covered": "rtl/memory/dfi_phy_adapter.sv",
            "behavior_verified": "DFI 5.0 init handshake, ACT/PRE/WR/RD pin encoding, CL=14 pipeline, and PHY update interlock",
            "sources": [
                os.path.join(root, "rtl", "memory", "dfi_phy_adapter.sv"),
                os.path.join(root, "tb", "memory", "tb_dfi_phy_adapter.sv"),
            ]
        },
        {
            "name": "Backend SOTA 1: JEDEC PRAC ABO, Phoenix (CVE-2025-6202) & Decoy",
            "top": "tb_prac_abo_phoenix",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "JEDEC PRAC Alert-Back-Off recovery, Phoenix CVE-2025-6202 RFM defense, and S3ORAM Decoy access",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "backend", "tb_prac_abo_phoenix.sv"),
            ]
        },
        {
            "name": "Backend SOTA 2: SEC-DED, USENIX '25 ECCfail Trap & ZEM Cache",
            "top": "tb_eccfail_zem_scrubber",
            "module_covered": "rtl/backend/ecc_scrubber.sv",
            "behavior_verified": "SEC-DED (72,64) vs independent reference: all 72 single and 2556 double errors, 3-bit cluster trap rate, ZEM address capture",
            "sources": [
                os.path.join(root, "rtl", "backend", "ecc_scrubber.sv"),
                os.path.join(root, "tb", "backend", "tb_eccfail_zem_scrubber.sv"),
            ]
        },
        {
            "name": "Backend SOTA 3: RS(18,16) GF(2^8) Chipkill x4 Die Failure ECC",
            "top": "tb_rs_chipkill_selfcheck",
            "module_covered": "rtl/backend/rs_chipkill_decoder.sv",
            "behavior_verified": "RS(18,16)/GF(2^8): exhaustive single x4-chip correction (4590 cases), measured double-chip detection rate",
            "sources": [
                os.path.join(root, "rtl", "backend", "gf256_arith_pkg.sv"),
                os.path.join(root, "rtl", "backend", "rs_chipkill_encoder.sv"),
                os.path.join(root, "rtl", "backend", "rs_chipkill_decoder.sv"),
                os.path.join(root, "tb", "backend", "tb_rs_chipkill.sv"),
                os.path.join(root, "tb", "backend", "tb_rs_chipkill_selfcheck.sv"),
            ]
        },
        {
            "name": "Security Attack Validation: Master 17-Vector Suite & VCD Generation",
            "top": "tb_security_attacks_vcd",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "17 hardware security attack vectors (incl. Phoenix, Half-Double, TRRespass, RAMBleed, Throwhammer, Decoy) and VCD GTKWave dump",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_security_attacks_vcd.sv")],
        },
        {
            "name": "End-to-End Scoreboard: AXI -> DRAM -> AXI Data Integrity (random multi-ID, WSTRB, scrambler on/off)",
            "top": "tb_e2e_scoreboard",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "1,200+ random AXI ops: every read beat matches an AXI-legal reference value, RAW from AW handshake, all posted writes reach DRAM, DQ/JEDEC clean, scrambled DRAM content",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_e2e_scoreboard.sv")],
        },
        {
            "name": "Industry Benchmarks: STREAM, SPEC2017, GAPBS & YCSB-A",
            "top": "tb_standard_benchmarks",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "McCalpin STREAM Triad, SPEC CPU2017 505.mcf_r, UC Berkeley GAPBS bfs, and Yahoo! YCSB-A",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_standard_benchmarks.sv")],
        },
        {
            "name": "T-RT01a (unit): REF under row-hit write stream, ref_mode drain watchdog (RT-01 / M-01)",
            "top": "tb_eng_ref_starve",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Row-hit write flood 25k cycles: REF gap <= 5 x tREFI in ps (SA-J21), REF count (SA-R04), drain <= REF_WD (SA-R01); FI-27 user_blk_q 1->0 detected on o_fault[4]",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
                os.path.join(root, "tb", "backend", "tb_eng_ref_starve.sv"),
            ]
        },
        {
            "name": "T-RT03a/c/e (unit): read-beat sync, FLUSH/resync (RT-03 / M-03)",
            "top": "tb_eng_rd_sync",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Dropped/extra/late/early beats and 1000 rddata_valid glitches: no cross-tag OKAY data (SA-D06), SLVERR + o_fault[5], FI-31..FI-42 traps and resync (SA-D01..D11)",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "dfi_rd_fault_shim.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
                os.path.join(root, "tb", "backend", "tb_eng_rd_sync.sv"),
            ]
        },
        {
            "name": "T-RT05a/b/c (unit): engine safety-flop fault injection (RT-05 / M-05)",
            "top": "tb_eng_fault_inject",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "FI-01..FI-30: last_act/last_wr dual events, RAA cross counters, timer *_z flags, rfc_z/rfc_z2, lat_kind one-hot, ref_owed bounds, watchdog; RFM within K_RFM, o_fault[1..4] at +1",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
                os.path.join(root, "tb", "backend", "tb_eng_fault_inject.sv"),
            ]
        },
        {
            "name": "T-RT05d (unit): DRM inj_oh one-hot / blkp_a,b / pq_v fault injection (RT-05.4 / M-05.4)",
            "top": "tb_drm_fault_inject",
            "module_covered": "rtl/backend/directed_refresh_manager.sv",
            "behavior_verified": "FI-49..FI-55: invalid inj_oh traps to S_P1R with o_drm_fault, dual PROQ block masks single loss, per-BG PROQ blocking (SA-F08, SA-F10, SA-F11)",
            "sources": [
                os.path.join(root, "rtl", "backend", "directed_refresh_manager.sv"),
                os.path.join(root, "tb", "backend", "tb_drm_fault_inject.sv"),
            ]
        },
        {
            "name": "T-V01 (unit): engine constrained-random v2 traffic, 32 seeds",
            "top": "tb_eng_v2_random",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "Random RD/WR/RMW/ABO honouring o_bank_free and o_engine_mit_only: all qs_engine_port_chk rules + JEDEC ps checker, SA-F06/F13 clean; FI-64 dropped command flagged on o_fault[6]",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
                os.path.join(root, "tb", "backend", "tb_eng_v2_random.sv"),
            ]
        },
        {
            "name": "T-V02 (unit): engine edge cases spec_v2 §10",
            "top": "tb_eng_edge_cases",
            "module_covered": "rtl/backend/ddr5_cmd_engine.sv",
            "behavior_verified": "§10.1/.4/.5/.6/.7/.8/.9/.16/.17: stray beat after reset, ABO + ref_mode, overdue REF vs RFM, persistent cnt_err, RMW across ref_mode, desync in ref_mode, decoy during FLUSH",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "common", "dfi_jedec_checker.sv"),
                os.path.join(root, "tb", "common", "dram_model.sv"),
                os.path.join(root, "tb", "common", "dfi_rd_fault_shim.sv"),
                os.path.join(root, "tb", "common", "qs_rd_beat_model.sv"),
                os.path.join(root, "tb", "common", "qs_engine_port_chk.sv"),
                os.path.join(root, "tb", "backend", "tb_eng_edge_cases.sv"),
            ]
        },
        {
            "name": "T-RT01a/b/c (top): REF starvation by AXI row-hit write stream (RT-01)",
            "top": "tb_rt01_ref_starvation",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "AXI row-hit writes 25k cycles + second-master read latency: REF gap <= 5 x tREFI (ps), REF count, DoS latency bound, read-stream control",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt01_ref_starvation.sv")],
        },
        {
            "name": "T-RT02a (top): QoS credit race, read + write same BG same cycle (RT-02 / M-02)",
            "top": "tb_rt02_credit_race",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "Directed BG0 (5,1,1,0)/(4,1,1,1) states and constrained random: no dropped command, per-BG credit <= 8 (SA-C01..C05), writes read back; FI-56/57 flagged on fault[8]",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt02_credit_race.sv")],
        },
        {
            "name": "T-RT03a..e (top): AXI read integrity under DFI read-beat faults (RT-03 / M-03)",
            "top": "tb_rt03_rd_integrity",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "Dropped/extra beats (scrambler on), rddata_valid glitches, RMW with lost beat, ECC 1/2-bit flips: no OKAY with foreign data (SA-D06), rdata=0 on error (SA-D05), recovery",
            "sources": top_common_sources + [
                os.path.join(root, "tb", "common", "dfi_rd_fault_shim.sv"),
                os.path.join(root, "tb", "top", "tb_rt03_rd_integrity.sv"),
            ],
        },
        {
            "name": "T-RT04 (top): JEDEC compliance in ps at 400 MHz (RT-04 / M-04)",
            "top": "tb_rt04_jedec_400mhz",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "clk_axi 2.5 ns, TCK_PS=2500, mixed read/write/row-miss/REF/RFM/ABO traffic over 16 seeds: 0 violations of SA-J01..J21",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt04_jedec_400mhz.sv")],
        },
        {
            "name": "T-RT05e/d (top): sticky fault aggregator and cfg_fault_clr (RT-05.6)",
            "top": "tb_rt05_fault_agg",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "FI-06, FI-60..FI-63: o_fault_cause sticky until clear, event wins over clear, alert == |o_fault_cause (SA-F02..F05), multi-source faults",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt05_fault_agg.sv")],
        },
        {
            "name": "T-RT06 (top): cross-BG timing channel via PROQ blocking (RT-06 / M-06)",
            "top": "tb_rt06_xbg_channel",
            "module_covered": "rtl/frontend/addr_mapper_ddr5.sv",
            "behavior_verified": "64-bit LeakyHammer-style sender on BG a vs receiver on BG b: decoded bits <= 40/64, single SDC alert adds <= 1 cycle to BG b latency (A-S1); Q16 residual channel measured",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt06_xbg_channel.sv")],
        },
        {
            "name": "T-RT07 (top): logical-bank credit vs physical-bank blocking (RT-07, deferred, strict XFAIL)",
            "top": "tb_rt07_phys_bank_credit",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "V19 with SCARF mode 2: receiver on other physical bank keeps credit; tb_check_xfail RT-07 (XPASS counts as failure)",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt07_phys_bank_credit.sv")],
        },
        {
            "name": "T-RT08 (top): runtime address-mapping change with shadow config (RT-08 / M-08)",
            "top": "tb_rt08_cfg_change",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "cfg_mapping_mode / bank_coloring change with reads in IQ and RAW-blocked write: credit returned to same BG (SA-C03, C06..C08, C10), no deadlock; FI-58/59 rollback",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt08_cfg_change.sv")],
        },
        {
            "name": "T-RT09 (top): decoy ACT address predictability (RT-09 / M-09)",
            "top": "tb_rt09_decoy_prf",
            "module_covered": "rtl/backend/directed_refresh_manager.sv",
            "behavior_verified": "cfg_decoy_en idle 50k cycles: row[1:0]==bank rate, BG sequence runs, LFSR-17 predictor success; XFAIL RT-09 if M-09 absent",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt09_decoy_prf.sv")],
        },
        {
            "name": "T-RT12 (top): legal parameter corners (RT-12 / M-12)",
            "top": "tb_rt12_param_corners",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "ROB_PTR_WIDTH == AXI_ID_WIDTH, tRFC 410 ns (T_RFC 164), T_RDV = 2, T_CWL+7+T_WR = 63: elaborate and run short traffic with SA-P06/P07 and JEDEC checks",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_rt12_param_corners.sv")],
        },
        {
            "name": "Top-Level Integration @ 400 MHz (TB_TCK_PS = 2500)",
            "top": "tb_axi_ddr5_mc_top_400",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "tb_axi_ddr5_mc_top run with clk_axi 2.5 ns and TCK_PS = 2500 for DUT and checker",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_axi_ddr5_mc_top.sv"), os.path.join(root, "tb", "top", "tb_axi_ddr5_mc_top_400.sv")],
        },
        {
            "name": "End-to-End Scoreboard @ 400 MHz (TB_TCK_PS = 2500)",
            "top": "tb_e2e_scoreboard_400",
            "module_covered": "rtl/top/axi_ddr5_mc_top.sv",
            "behavior_verified": "tb_e2e_scoreboard run with clk_axi 2.5 ns and TCK_PS = 2500 for DUT and checker",
            "sources": top_common_sources + [os.path.join(root, "tb", "top", "tb_e2e_scoreboard.sv"), os.path.join(root, "tb", "top", "tb_e2e_scoreboard_400.sv")],
        },
    ]

    # --only <top>[,<top>...]: chạy tập con khi debug; không ghi đè regression_summary.json của lần chạy đầy đủ.
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
        tests = [t for t in tests if t["top"] in only]
        if not tests:
            sys.exit(f"--only: no testbench matches {sorted(only)}")

    total_passed = 0
    total_failed = 0
    test_records = []
    failed_records = []
    start_time = time.time()
    verbose = "-v" in sys.argv or "--verbose" in sys.argv

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
            xf = f", {len(record['xfails'])} XFAIL" if record["xfails"] else ""
            print(f"[PASS] {record['checks']} checks{xf} in {record['runtime_seconds']:.2f}s")
            if verbose and record.get("stdout"):
                for line in record["stdout"].strip().splitlines():
                    print(f"       | {line}")
        else:
            total_failed += 1
            failed_records.append(record)
            print(f"[FAIL] ({record['reason']})")
            if record["error_snippet"]:
                print(f"       >> Error Snippet:\n{record['error_snippet']}\n")

    total_duration = time.time() - start_time
    known_gaps = sorted({x["gap"] for r in test_records for x in r["xfails"]})

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
        "total_checks": sum(r["checks"] for r in test_records),
        "total_xfails": sum(len(r["xfails"]) for r in test_records),
        "known_gaps": known_gaps,
        "total_duration_seconds": round(total_duration, 2),
        "timestamp_epoch": time.time(),
        "tests": test_records,
    }

    summary_json_path = os.path.join(log_dir if only else root, "regression_summary.json")
    with open(summary_json_path, "w", encoding="utf-8") as f:
        json.dump(summary_payload, f, indent=2)

    # 2. Save Failure Diagnostics JSON
    failure_json_path = os.path.join(log_dir, "failure_report.json")
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
    print(f"{'Test Description':<56} | {'Result':<6} | {'Checks':>6} | {'XFAIL':>5} | {'Time (s)':<8} | {'Covered Module'}")
    print("-" * 110)
    for rec in test_records:
        mod_short = os.path.basename(rec["module_covered"])
        print(f"{rec['name'][:56]:<56} | {rec['status']:<6} | {rec['checks']:>6} | {len(rec['xfails']):>5} | "
              f"{rec['runtime_seconds']:6.2f}s | {mod_short}")
    print("=" * 110)
    print(f"  FINAL VERDICT: {total_passed}/{len(tests)} PASSED, {total_failed} FAILED (Duration: {total_duration:.2f}s)")
    if known_gaps:
        print(f"  KNOWN GAPS (XFAIL, not counted as PASS): {', '.join(known_gaps)}")
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
