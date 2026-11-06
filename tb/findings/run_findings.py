#!/usr/bin/env python3
"""
===============================================================================
Script: tb/findings/run_findings.py
Description: Finding reproduction test runner for Q-Shield DDR5 controller.
             Executes checks verifying findings C-1..C-4 and H-1..H-8 fail on
             the unremediated RTL and pass once remediation is implemented.
Exit code:
  0: All failing checks match known_failing.txt and known_open_demo.txt exactly
  1: An unlisted check fails OR a listed check unexpectedly passes
===============================================================================
"""

import os
import sys
import subprocess
import shutil
import time
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FINDINGS_DIR = os.path.join(ROOT, "tb", "findings")
CHECKS_DIR = os.path.join(FINDINGS_DIR, "checks")
BUILD_DIR = os.path.join(ROOT, "build", "findings")

IVERILOG = r"D:\iverilog\bin\iverilog.exe" if os.path.exists(r"D:\iverilog\bin\iverilog.exe") else shutil.which("iverilog")
VVP = r"D:\iverilog\bin\vvp.exe" if os.path.exists(r"D:\iverilog\bin\vvp.exe") else shutil.which("vvp")

TOP_DEMO_SOURCES = [
    os.path.join(ROOT, "rtl", "crypto", "aes_pkg.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes_sbox.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes_sbox_composite.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes_tweak_gen.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes_round_pipe.sv"),
    os.path.join(ROOT, "rtl", "crypto", "subchannel_aes_xts_pipe.sv"),
    os.path.join(ROOT, "rtl", "bus", "axi4_skid_buffer.sv"),
    os.path.join(ROOT, "rtl", "core", "fault_hardened_csr.sv"),
    os.path.join(ROOT, "rtl", "bus", "apb_csr_regs.sv"),
    os.path.join(ROOT, "rtl", "bus", "axi4_slave_adapter.sv"),
    os.path.join(ROOT, "rtl", "cdc", "async_fifo_cdc.sv"),
    os.path.join(ROOT, "rtl", "memory", "ddr5_subchannel_scheduler.sv"),
    os.path.join(ROOT, "rtl", "memory", "dfi_phy_adapter.sv"),
    os.path.join(ROOT, "rtl", "crypto", "split_counter_table.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes_ctr_keystream.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes256_key_expand.sv"),
    os.path.join(ROOT, "rtl", "crypto", "aes128_enc_iter.sv"),
    os.path.join(ROOT, "rtl", "crypto", "integrity_mac_gen.sv"),
    os.path.join(ROOT, "rtl", "crypto", "qshield_crypto_top.sv"),
    os.path.join(ROOT, "rtl", "top", "sec_ddr5_controller_top.sv"),
]

CHECK_SPECS = {
    "check_c1": {
        "finding": "C-1",
        "description": "qshield_crypto_top unconnected on data path",
        "sources": TOP_DEMO_SOURCES + [os.path.join(CHECKS_DIR, "check_c1.sv")],
        "top": "check_c1",
    },
    "check_c2": {
        "finding": "C-2",
        "description": "XTS tweak unencrypted / ciphertext malleable",
        "sources": [
            os.path.join(ROOT, "rtl", "crypto", "aes_pkg.sv"),
            os.path.join(ROOT, "rtl", "crypto", "aes_sbox.sv"),
            os.path.join(ROOT, "rtl", "crypto", "aes_sbox_composite.sv"),
            os.path.join(ROOT, "rtl", "crypto", "aes_tweak_gen.sv"),
            os.path.join(ROOT, "rtl", "crypto", "aes_round_pipe.sv"),
            os.path.join(ROOT, "rtl", "crypto", "subchannel_aes_xts_pipe.sv"),
            os.path.join(CHECKS_DIR, "check_c2.sv"),
        ],
        "top": "check_c2",
    },
    "check_c3": {
        "finding": "C-3",
        "description": "AXI address dropped; DFI address takes ciphertext slice",
        "sources": TOP_DEMO_SOURCES + [os.path.join(CHECKS_DIR, "check_c3.sv")],
        "top": "check_c3",
    },
    "check_c4": {
        "finding": "C-4",
        "description": "ARVALID receives no RVALID (read channel stub)",
        "sources": TOP_DEMO_SOURCES + [os.path.join(CHECKS_DIR, "check_c4.sv")],
        "top": "check_c4",
    },
    "check_h1": {
        "finding": "H-1",
        "description": "soft_reset desynchronizes CDC FIFO write/read pointers",
        "sources": TOP_DEMO_SOURCES + [os.path.join(CHECKS_DIR, "check_h1.sv")],
        "top": "check_h1",
    },
    "check_h2": {
        "finding": "H-2",
        "description": "Scheduler bank_state indexing omits Bank Group (BG)",
        "sources": [
            os.path.join(ROOT, "rtl", "memory", "ddr5_subchannel_scheduler.sv"),
            os.path.join(CHECKS_DIR, "check_h2.sv"),
        ],
        "top": "check_h2",
    },
    "check_h3": {
        "finding": "H-3",
        "description": "Delayed RREADY causes duplicate read beats",
        "sources": [
            os.path.join(ROOT, "rtl", "bus", "axi4_skid_buffer.sv"),
            os.path.join(ROOT, "rtl", "core", "reorder_buffer_rob.sv"),
            os.path.join(CHECKS_DIR, "check_h3.sv"),
        ],
        "top": "check_h3",
    },
    "check_h4": {
        "finding": "H-4",
        "description": "enc_enable can be cleared via APB after sec_locked",
        "sources": [
            os.path.join(ROOT, "rtl", "core", "fault_hardened_csr.sv"),
            os.path.join(ROOT, "rtl", "bus", "apb_csr_regs.sv"),
            os.path.join(CHECKS_DIR, "check_h4.sv"),
        ],
        "top": "check_h4",
    },
    "check_h5": {
        "finding": "H-5",
        "description": "pprot ignored and pslverr always 0 for non-secure write",
        "sources": [
            os.path.join(ROOT, "rtl", "core", "fault_hardened_csr.sv"),
            os.path.join(ROOT, "rtl", "bus", "apb_csr_regs.sv"),
            os.path.join(CHECKS_DIR, "check_h5.sv"),
        ],
        "top": "check_h5",
    },
    "check_h6": {
        "finding": "H-6",
        "description": "AddrScrambleSeed readable after sec_locked",
        "sources": [
            os.path.join(ROOT, "rtl", "core", "fault_hardened_csr.sv"),
            os.path.join(ROOT, "rtl", "bus", "apb_csr_regs.sv"),
            os.path.join(CHECKS_DIR, "check_h6.sv"),
        ],
        "top": "check_h6",
    },
    "check_h7": {
        "finding": "H-7",
        "description": "bus_scrambler keystream reuse for same address",
        "sources": [
            os.path.join(ROOT, "rtl", "memory", "bus_scrambler.sv"),
            os.path.join(CHECKS_DIR, "check_h7.sv"),
        ],
        "top": "check_h7",
    },
    "check_h8": {
        "finding": "H-8",
        "description": "minor=127 does not advance major counter in CTR block",
        "sources": [
            os.path.join(ROOT, "rtl", "crypto", "split_counter_table.sv"),
            os.path.join(CHECKS_DIR, "check_h8.sv"),
        ],
        "top": "check_h8",
    },
}

def load_id_list(filepath):
    if not os.path.exists(filepath):
        return set()
    items = set()
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                # Normalize: allow "check_c1" or "c1" or "C-1"
                norm = line.lower().replace("-", "")
                if not norm.startswith("check_"):
                    norm = "check_" + norm
                items.add(norm)
    return items

def run_one_check(check_id, spec):
    os.makedirs(BUILD_DIR, exist_ok=True)
    vvp_path = os.path.join(BUILD_DIR, f"{check_id}.vvp")
    
    # 1. Compile
    compile_cmd = [
        IVERILOG,
        "-g2012",
        "-I", os.path.join(ROOT, "tb", "common"),
        "-s", spec["top"],
        "-o", vvp_path,
    ] + spec["sources"]

    t0 = time.time()
    res_comp = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=ROOT)
    if res_comp.returncode != 0:
        return {
            "status": "ERROR",
            "message": f"Compilation failed: {res_comp.stderr.strip()}",
            "elapsed": time.time() - t0,
        }

    # 2. Simulate
    sim_cmd = [VVP, vvp_path]
    res_sim = subprocess.run(sim_cmd, capture_output=True, text=True, cwd=ROOT, timeout=120)
    elapsed = time.time() - t0
    output = res_sim.stdout + res_sim.stderr

    # Determine PASS / FAIL:
    # A check passes if [TB_RESULT] checks > 0 and fails == 0, and returncode == 0
    # A check fails if [FAIL] is present, or fails > 0, or returncode != 0
    has_fail = ("[FAIL]" in output) or (res_sim.returncode != 0)
    tb_res_match = re.search(r"\[TB_RESULT\]\s+checks=(\d+)\s+fails=(\d+)", output)
    if tb_res_match:
        checks_cnt = int(tb_res_match.group(1))
        fails_cnt = int(tb_res_match.group(2))
        if fails_cnt > 0:
            has_fail = True
        elif checks_cnt > 0 and fails_cnt == 0 and not has_fail:
            has_fail = False

    return {
        "status": "FAIL" if has_fail else "PASS",
        "output": output,
        "elapsed": elapsed,
    }

def main():
    os.makedirs(BUILD_DIR, exist_ok=True)
    
    known_failing_path = os.path.join(FINDINGS_DIR, "known_failing.txt")
    known_open_demo_path = os.path.join(FINDINGS_DIR, "known_open_demo.txt")

    known_failing = load_id_list(known_failing_path)
    known_open_demo = load_id_list(known_open_demo_path)
    all_expected_failing = known_failing | known_open_demo

    print("=" * 88)
    print("  Q-SHIELD FINDING REPRODUCTION TEST RUNNER (tb/findings)")
    print(f"  Root Directory     : {ROOT}")
    print(f"  Known Failing (Main): {len(known_failing)} checks")
    print(f"  Known Open (Demo)   : {len(known_open_demo)} checks")
    print(f"  Total Expected Fails: {len(all_expected_failing)} checks")
    print("=" * 88)

    results = []
    unexpected_passes = []
    unexpected_failures = []
    total_start = time.time()

    # Discover and sort checks
    check_ids = sorted(CHECK_SPECS.keys())

    for idx, cid in enumerate(check_ids, 1):
        spec = CHECK_SPECS[cid]
        finding_id = spec["finding"]
        desc = spec["description"]
        expected_fail = cid in all_expected_failing
        scope = "demo" if cid in known_open_demo else "main"

        print(f"[{idx:02d}/{len(check_ids):02d}] Finding [{finding_id:<3}] {cid} ({scope}): {desc} ...", end=" ", flush=True)

        res = run_one_check(cid, spec)
        actual_status = res["status"]
        elapsed = res["elapsed"]

        if actual_status == "FAIL":
            if expected_fail:
                eval_str = "REPRODUCED (Expected FAIL)"
                print(f"[REPRODUCED] in {elapsed:.2f}s")
            else:
                eval_str = "UNEXPECTED FAILURE"
                unexpected_failures.append(cid)
                print(f"[UNEXPECTED FAIL] in {elapsed:.2f}s")
        elif actual_status == "PASS":
            if expected_fail:
                eval_str = "UNEXPECTED PASS (Must remove from known_failing)"
                unexpected_passes.append(cid)
                print(f"[UNEXPECTED PASS] in {elapsed:.2f}s")
            else:
                eval_str = "PASS (Expected PASS)"
                print(f"[PASS] in {elapsed:.2f}s")
        else:
            eval_str = "ERROR (Tool/Execution)"
            unexpected_failures.append(cid)
            print(f"[ERROR] in {elapsed:.2f}s")

        results.append({
            "id": cid,
            "finding": finding_id,
            "scope": scope,
            "desc": desc,
            "status": actual_status,
            "expected": "FAIL" if expected_fail else "PASS",
            "eval": eval_str,
            "elapsed": elapsed,
        })

    total_duration = time.time() - total_start

    print("\n" + "=" * 88)
    print("  FINDING REPRODUCTION SUMMARY TABLE")
    print("=" * 88)
    print(f"{'Check ID':<10} | {'Finding':<7} | {'Scope':<5} | {'Actual':<6} | {'Expected':<8} | {'Evaluation'}")
    print("-" * 88)
    for r in results:
        print(f"{r['id']:<10} | {r['finding']:<7} | {r['scope']:<5} | {r['status']:<6} | {r['expected']:<8} | {r['eval']}")
    print("=" * 88)
    print(f"Total Checks: {len(results)} | Execution Time: {total_duration:.2f}s")
    print(f"Reproduced Expected Fails: {len(results) - len(unexpected_failures) - len(unexpected_passes)}/{len(all_expected_failing)}")

    if unexpected_failures:
        print(f"\n[!] ERROR: {len(unexpected_failures)} check(s) failed unexpectedly: {unexpected_failures}")
    if unexpected_passes:
        print(f"\n[!] ERROR: {len(unexpected_passes)} check(s) passed unexpectedly (remove from known_failing): {unexpected_passes}")

    if unexpected_failures or unexpected_passes:
        print("\n>>> RESULT: FAILED (Exit Code 1)")
        sys.exit(1)
    else:
        print("\n>>> RESULT: SUCCESS - All open findings faithfully reproduced (Exit Code 0)")
        sys.exit(0)

if __name__ == "__main__":
    main()
