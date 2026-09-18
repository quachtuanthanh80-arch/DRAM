#!/usr/bin/env python3
"""
===============================================================================
Script: run_iverilog_regression.py
Description: Master SystemVerilog Hardware Regression Test Suite for Q-Shield
             Compiles and runs all unit testbenches and top-level integration
             testbenches using Icarus Verilog (iverilog + vvp).
===============================================================================
"""

import os
import sys
import subprocess
import time
import shutil

def find_tool(tool_name, default_dir=r"D:\iverilog\bin"):
    found = shutil.which(tool_name)
    if found:
        return found
    fallback = os.path.join(default_dir, tool_name + ".exe")
    if os.path.isfile(fallback):
        return fallback
    return tool_name

def run_test(name, iverilog, vvp, sources, top_module, cwd):
    print(f"\n[*] Running: {name} (Top: {top_module})...")
    vvp_file = f"build_{top_module}.vvp"
    vvp_path = os.path.join(cwd, vvp_file)

    compile_cmd = [iverilog, "-g2012", "-Wall", "-s", top_module, "-o", vvp_file] + sources
    t0 = time.time()
    res_compile = subprocess.run(compile_cmd, cwd=cwd, capture_output=True, text=True)

    if res_compile.returncode != 0:
        print(f"[FAIL] Compilation error in {name}")
        print(res_compile.stdout + "\n" + res_compile.stderr)
        return False, time.time() - t0, "Compile Error"

    sim_cmd = [vvp, vvp_file]
    res_sim = subprocess.run(sim_cmd, cwd=cwd, capture_output=True, text=True)
    elapsed = time.time() - t0

    # Clean up vvp file
    try:
        if os.path.exists(vvp_path):
            os.remove(vvp_path)
    except Exception:
        pass

    output = res_sim.stdout + "\n" + res_sim.stderr
    has_explicit_fail = "[FAIL]" in output or "FAILED]" in output or "fatal" in output.lower()
    if res_sim.returncode == 0 and not has_explicit_fail and ("ALL TESTS PASSED" in output or "PASSED SUCCESSFULLY" in output or "[PASS]" in output):
        print(f"[PASS] {name} passed in {elapsed:.2f}s")
        return True, elapsed, "Passed"
    else:
        print(f"[FAIL] {name} failed in {elapsed:.2f}s")
        for line in output.splitlines()[-20:]:
            print(f"  {line}")
        return False, elapsed, "Sim Failure"

def main():
    root = os.path.abspath(os.path.dirname(__file__))
    iverilog = find_tool("iverilog")
    vvp = find_tool("vvp")

    print("=" * 80)
    print("  Q-SHIELD MASTER HARDWARE REGRESSION SUITE (IVERILOG + VVP)")
    print(f"  iverilog: {iverilog}")
    print(f"  vvp:      {vvp}")
    print("=" * 80)

    tests = [
        {
            "name": "Upgrade 4: APB4 CSR Register File Extension",
            "top": "tb_apb_csr_regs",
            "sources": [
                os.path.join(root, "rtl", "bus", "apb_csr_regs.sv"),
                os.path.join(root, "tb", "bus", "tb_apb_csr_regs.sv"),
            ]
        },
        {
            "name": "Frontend: AXI4 Slave Adapter & Skid Buffers",
            "top": "tb_axi4_slave_adapter",
            "sources": [
                os.path.join(root, "rtl", "bus", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "bus", "axi4_slave_adapter.sv"),
                os.path.join(root, "tb", "bus", "tb_axi4_slave_adapter.sv"),
            ]
        },
        {
            "name": "Upgrade 1: Adaptive Threshold Engine (ATE)",
            "top": "tb_adaptive_threshold_engine",
            "sources": [
                os.path.join(root, "rtl", "core", "adaptive_threshold_engine.sv"),
                os.path.join(root, "tb", "core", "tb_adaptive_threshold_engine.sv"),
            ]
        },
        {
            "name": "Upgrade 3: Write-Drain / Read-Burst Mode Scheduler",
            "top": "tb_slack_aware_arbiter",
            "sources": [
                os.path.join(root, "rtl", "backend", "slack_aware_arbiter.sv"),
                os.path.join(root, "tb", "backend", "tb_slack_aware_arbiter.sv"),
            ]
        },
        {
            "name": "Upgrade 7: RowPress Attack Detection",
            "top": "tb_ddr5_cmd_engine",
            "sources": [
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "tb", "backend", "tb_ddr5_cmd_engine.sv"),
            ]
        },
        {
            "name": "Upgrade 2: Directed Refresh Manager (DRM)",
            "top": "tb_directed_refresh_manager",
            "sources": [
                os.path.join(root, "rtl", "backend", "directed_refresh_manager.sv"),
                os.path.join(root, "tb", "backend", "tb_directed_refresh_manager.sv"),
            ]
        },
        {
            "name": "Crypto Stage 1: AES S-Box NIST Vector Verification",
            "top": "tb_aes_sbox_test",
            "sources": [
                os.path.join(root, "rtl", "crypto", "aes_sbox.sv"),
                os.path.join(root, "tb", "crypto", "tb_aes_sbox_test.sv"),
            ]
        },
        {
            "name": "Crypto Stage 2: Dual-Lane AES-256-XTS Pipelined Engine",
            "top": "tb_aes_xts_pipe",
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
            "sources": [
                os.path.join(root, "rtl", "cdc", "rst_sync.sv"),
                os.path.join(root, "rtl", "frontend", "axi4_skid_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "axi_slave_frontend.sv"),
                os.path.join(root, "rtl", "frontend", "wdata_buffer.sv"),
                os.path.join(root, "rtl", "frontend", "addr_mapper_ddr5.sv"),
                os.path.join(root, "rtl", "core", "reorder_buffer_rob.sv"),
                os.path.join(root, "rtl", "core", "sdc_resilient_filter.sv"),
                os.path.join(root, "rtl", "core", "adaptive_threshold_engine.sv"),
                os.path.join(root, "rtl", "backend", "directed_refresh_manager.sv"),
                os.path.join(root, "rtl", "core", "qos_scheduler_queue.sv"),
                os.path.join(root, "rtl", "backend", "slack_aware_arbiter.sv"),
                os.path.join(root, "rtl", "backend", "ddr5_cmd_engine.sv"),
                os.path.join(root, "rtl", "backend", "ecc_scrubber.sv"),
                os.path.join(root, "rtl", "top", "axi_ddr5_mc_top.sv"),
                os.path.join(root, "tb", "top", "tb_axi_ddr5_mc_top.sv"),
            ]
        },
        {
            "name": "Top-Level Integration: Inline AES-256-XTS Secure DDR5 Controller",
            "top": "tb_sec_ddr5_controller_top",
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
        }
    ]

    total_passed = 0
    total_failed = 0
    results = []
    start_time = time.time()

    for t in tests:
        passed, elapsed, msg = run_test(
            name=t["name"],
            iverilog=iverilog,
            vvp=vvp,
            sources=t["sources"],
            top_module=t["top"],
            cwd=root
        )
        results.append((t["name"], passed, elapsed, msg))
        if passed:
            total_passed += 1
        else:
            total_failed += 1

    total_time = time.time() - start_time
    print("\n" + "=" * 80)
    print("  Q-SHIELD REGRESSION TEST EXECUTION REPORT")
    print("=" * 80)
    print(f"{'Test Description':<55} | {'Result':<8} | {'Time (s)':<8}")
    print("-" * 80)
    for name, passed, elapsed, msg in results:
        status_str = "PASS" if passed else "FAIL"
        print(f"{name:<55} | {status_str:<8} | {elapsed:6.2f}s")
    print("=" * 80)
    print(f"  TOTAL: {total_passed}/{len(tests)} PASSED, {total_failed} FAILED in {total_time:.2f}s")
    print("=" * 80)

    if total_failed > 0:
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()
