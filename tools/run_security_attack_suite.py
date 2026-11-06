#!/usr/bin/env python3
"""
Script: run_security_attack_suite.py
Description: Three-tier security validation for Q-Shield. Every reported number is read from a run of this script:
             - Tier 1: Python architectural model (sim/run_attack_emulation.py), labelled as a model, not RTL.
             - Tier 2: RTL red-team suite (tb/top/tb_security_attacks_vcd.sv); verdict from its [TB_RESULT]/[XFAIL] lines.
             - Tier 3: SymbiYosys runs of formal/*.sby when sby is installed; otherwise NOT_RUN.
Outputs: sim/results/security_attack_results.json, sim/results/security_attack_audit_report.md
"""

import os
import re
import sys
import time
import json
import glob
import shutil
import platform
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
RESULTS_DIR = os.path.join(REPO_ROOT, "sim", "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

TB_RESULT_RE = re.compile(r"\[TB_RESULT\]\s+checks=(\d+)\s+fails=(\d+)\s+xfails=(\d+)")
XFAIL_RE = re.compile(r"\[XFAIL\]\s+(\S+):\s*(.*)")
FAIL_RE = re.compile(r"^\[(?:FAIL|XPASS)\].*$", re.MULTILINE)

RTL_SOURCES = [
    ("rtl", "cdc", "rst_sync.sv"),
    ("rtl", "bus", "axi4_skid_buffer.sv"),
    ("rtl", "frontend", "axi_slave_frontend.sv"),
    ("rtl", "frontend", "wdata_buffer.sv"),
    ("rtl", "frontend", "domain_bank_coloring.sv"),
    ("rtl", "core", "scarf_dram_randomizer.sv"),
    ("rtl", "frontend", "addr_mapper_ddr5.sv"),
    ("rtl", "core", "reorder_buffer_rob.sv"),
    ("rtl", "core", "fault_hardened_csr.sv"),
    ("rtl", "crypto", "multi_vm_key_table.sv"),
    ("rtl", "core", "pxor_hash_engine.sv"),
    ("rtl", "core", "sdc_resilient_filter.sv"),
    ("rtl", "core", "adaptive_threshold_engine.sv"),
    ("rtl", "backend", "directed_refresh_manager.sv"),
    ("rtl", "core", "qos_scheduler_queue.sv"),
    ("rtl", "backend", "slack_aware_arbiter.sv"),
    ("rtl", "backend", "ddr5_cmd_engine.sv"),
    ("rtl", "backend", "ecc_scrubber.sv"),
    ("rtl", "memory", "bus_scrambler.sv"),
    ("rtl", "bus", "perf_monitor_unit.sv"),
    ("rtl", "top", "axi_ddr5_mc_top.sv"),
    ("tb", "top", "tb_security_attacks_vcd.sv"),
]


def get_git_commit():
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "unknown"


def run_tier1_model():
    print("=" * 96)
    print("  [TIER 1] PYTHON ARCHITECTURAL MODEL (not RTL)")
    print("=" * 96)
    t0 = time.time()
    res = subprocess.run([sys.executable, os.path.join(REPO_ROOT, "sim", "run_attack_emulation.py")],
                         cwd=REPO_ROOT, capture_output=True, text=True)
    elapsed = time.time() - t0
    print(res.stdout)
    data = None
    path = os.path.join(RESULTS_DIR, "attack_emulation_summary.json")
    if res.returncode == 0 and os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    attacks = data["attacks"] if data else []
    tier = {
        "status": "RAN" if data else "ERROR",
        "abstraction": "Python architectural model (see attack_emulation_meta.json model_fidelity_notes)",
        "runtime_seconds": round(elapsed, 2),
        "traces_evaluated": len(attacks),
        "escaped_bitflips_total": sum(a["escaped_bitflips"] for a in attacks),
        "traces_without_exposure": [a["attack_tag"] for a in attacks
                                    if a.get("victims_exposed_without_defense", 0) == 0],
        "fuzzer": data.get("fuzzer", {}) if data else {},
    }
    return tier


def run_tier2_rtl():
    print("=" * 96)
    print("  [TIER 2] RTL RED-TEAM SUITE (Icarus Verilog)")
    print("=" * 96)
    iverilog = shutil.which("iverilog") or r"D:\iverilog\bin\iverilog.exe"
    vvp = shutil.which("vvp") or r"D:\iverilog\bin\vvp.exe"
    sources = [os.path.join(REPO_ROOT, *p) for p in RTL_SOURCES]
    vvp_out = os.path.join(REPO_ROOT, "build_security_attacks.vvp")
    compile_cmd = [iverilog, "-g2012", "-Wall", "-I", os.path.join(REPO_ROOT, "tb", "common"),
                   "-s", "tb_security_attacks_vcd", "-o", vvp_out] + sources
    res_c = subprocess.run(compile_cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if res_c.returncode != 0:
        print(res_c.stderr)
        return {"status": "COMPILE_ERROR", "checks": 0, "fails": 0, "open_vulnerabilities": []}
    t0 = time.time()
    res = subprocess.run([vvp, vvp_out], cwd=REPO_ROOT, capture_output=True, text=True)
    elapsed = time.time() - t0
    try:
        os.remove(vvp_out)
    except OSError:
        pass
    out = res.stdout + res.stderr
    print(out)
    m = TB_RESULT_RE.findall(out)
    checks, fails, _ = (int(v) for v in m[-1]) if m else (0, 0, 0)
    xfails = [{"gap": g, "detail": d.strip()} for g, d in XFAIL_RE.findall(out)]
    if not m or checks == 0:
        status = "NO_RESULT"
    elif fails > 0 or res.returncode != 0:
        status = "FAIL"
    else:
        status = "PASS_WITH_OPEN_GAPS" if xfails else "PASS"
    vcd = os.path.join(REPO_ROOT, "waveform_security_attacks.vcd")
    return {
        "status": status,
        "runtime_seconds": round(elapsed, 2),
        "checks": checks,
        "fails": fails,
        "failed_checks": FAIL_RE.findall(out),
        "open_vulnerabilities": xfails,
        "waveform_vcd_path": "waveform_security_attacks.vcd",
        "waveform_size_mb": round(os.path.getsize(vcd) / 2**20, 2) if os.path.isfile(vcd) else 0.0,
    }


def run_tier3_formal():
    print("=" * 96)
    print("  [TIER 3] FORMAL (SymbiYosys)")
    print("=" * 96)
    sby = shutil.which("sby")
    files = sorted(glob.glob(os.path.join(REPO_ROOT, "formal", "*.sby")))
    if not sby:
        print("  sby not found on PATH: formal tier NOT_RUN (use the Docker image).")
        return {"status": "NOT_RUN", "reason": "sby not installed", "jobs": [os.path.basename(f) for f in files]}
    jobs = []
    for f in files:
        t0 = time.time()
        res = subprocess.run([sby, "-f", os.path.basename(f)], cwd=os.path.dirname(f),
                             capture_output=True, text=True)
        out = res.stdout + res.stderr
        verdict = "PASS" if re.search(r"DONE \(PASS", out) else ("FAIL" if "DONE (FAIL" in out else "ERROR")
        jobs.append({"job": os.path.basename(f), "status": verdict, "runtime_seconds": round(time.time() - t0, 2)})
        print(f"  {os.path.basename(f):<32} {verdict}")
    status = "PASS" if all(j["status"] == "PASS" for j in jobs) else "FAIL"
    return {"status": status, "jobs": jobs}


def main():
    t0 = time.time()
    tier1 = run_tier1_model()
    tier2 = run_tier2_rtl()
    tier3 = run_tier3_formal()

    open_gaps = sorted({x["gap"] for x in tier2.get("open_vulnerabilities", [])})
    if tier2["status"] in ("FAIL", "NO_RESULT", "COMPILE_ERROR") or tier3["status"] == "FAIL":
        verdict = "VERIFICATION_FAILED"
    elif open_gaps:
        verdict = "OPEN_VULNERABILITIES"
    else:
        verdict = "NO_OPEN_GAPS_IN_TESTED_VECTORS"

    summary = {
        "timestamp_epoch": time.time(),
        "commit_sha": get_git_commit(),
        "platform": f"{platform.system()} {platform.release()}",
        "total_runtime_seconds": round(time.time() - t0, 2),
        "tier1_python_model": tier1,
        "tier2_rtl_red_team": tier2,
        "tier3_formal": tier3,
        "open_vulnerability_ids": open_gaps,
        "overall_verdict": verdict,
    }
    with open(os.path.join(RESULTS_DIR, "security_attack_results.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    with open(os.path.join(RESULTS_DIR, "security_attack_audit_report.md"), "w", encoding="utf-8") as f:
        f.write("# Q-Shield Security Audit Report\n\n")
        f.write(f"- Commit: `{summary['commit_sha']}`\n")
        f.write(f"- Overall verdict: **{verdict}**\n\n")
        f.write("| Tier | Abstraction | Status | Evidence |\n| :--- | :--- | :---: | :--- |\n")
        f.write(f"| 1 | Python architectural model | {tier1['status']} | {tier1['escaped_bitflips_total']} escaped flips in model; "
                f"{len(tier1['traces_without_exposure'])}/{tier1['traces_evaluated']} traces never reach HC_FIRST undefended |\n")
        f.write(f"| 2 | RTL (Icarus Verilog) | {tier2['status']} | {tier2['checks']} checks, {tier2['fails']} failed, "
                f"{len(tier2.get('open_vulnerabilities', []))} open-gap checks |\n")
        f.write(f"| 3 | Formal (SymbiYosys) | {tier3['status']} | {len(tier3.get('jobs', []))} jobs |\n\n")
        if tier2.get("open_vulnerabilities"):
            f.write("## Open vulnerabilities found by the RTL red-team suite\n\n")
            for x in tier2["open_vulnerabilities"]:
                f.write(f"- **{x['gap']}**: {x['detail']}\n")

    print("=" * 96)
    print(f"  OVERALL VERDICT: {verdict}  (open gaps: {', '.join(open_gaps) if open_gaps else 'none'})")
    print("=" * 96)
    return 0 if verdict != "VERIFICATION_FAILED" else 1


if __name__ == "__main__":
    sys.exit(main())
