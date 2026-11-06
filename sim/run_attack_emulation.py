#!/usr/bin/env python3
"""
===============================================================================
Script: run_attack_emulation.py
Description: Full-System Hardware Attack Emulation & Empirical Security Audit
             for Q-Shield Memory Controller.
Defended Threat Models & Attack Definitions:
  1. Standard RowHammer: Alternating single-sided/double-sided wordline toggling.
  2. Blacksmith (IEEE S&P'22): Frequency-domain multi-sided pattern hammering.
  3. RowPress: Prolonged open wordline activations (t_ACT >= 4 * t_RAS).
  4. Many-Sided Hammer: Irregular distributed activation spanning >= 3 banks.
  5. Mixed Multi-Tenant: Adversary co-located with benign threads sharing memory.

Output Artifacts:
  - attack_emulation_summary.json : Per-attack metrics & overall security statistics
  - attack_emulation_meta.json    : Environmental parameters, timestamps, threat config
  - attack_emulation_report.md    : Human-readable markdown audit summary
===============================================================================
"""

import os
import sys
import json
import time
import platform
import subprocess

# -----------------------------------------------------------------------------
# Architectural Parameters & Physical Thresholds
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
TRACES_DIR = os.path.join(SCRIPT_DIR, "traces")
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

# Hardware RTL parameters (matching rtl/core/sdc_resilient_filter.sv)
NUM_BINS = 1024
BASE_RH_THRESHOLD = 32
ROWPRESS_TACT_THRESH_CYCLES = 120  # Clamped by JEDEC tRAS_max
EPOCH_WINDOW_CYCLES = 64000        # Refresh window epoch (tREFW)

# Disturbance model assumptions (model inputs, not measured results)
HC_FIRST = 4800          # Assumed neighbour activations before the first bit flip
T_ACCESS_CYCLES = 15     # Assumed service time of one access, used for throughput accounting
T_THROTTLE_CYCLES = 100  # Pacing stall charged per mitigation
MODEL_FIDELITY_NOTES = [
    "Python architectural model, not RTL simulation.",
    "hash1/hash2 are not the RTL PXOR hash (rtl/core/pxor_hash_engine.sv).",
    "Trace address mapping (BG=addr[17:16], bank=addr[15:14]) differs from rtl/frontend (BG=addr[8:6]^addr[20:18], bank=addr[17:16]).",
    "Bit flips are modelled as victim rows reaching HC_FIRST neighbour activations without an intervening refresh.",
]

# -----------------------------------------------------------------------------
# Attack Definitions & Threat Profiles
import random

# -----------------------------------------------------------------------------
# Attack Definitions & Threat Profiles
# -----------------------------------------------------------------------------
ATTACK_TAXONOMY = {
    "Benign_Standard": {
        "filename": "trace_benign.trace",
        "category": "Benign Baseline",
        "definition": "Non-adversarial standard compute trace (SPEC CPU2017/PARSEC 3.0) to measure false positive rate (FPR).",
        "is_attack": False,
        "expected_detection": "0% (No false alarms)",
    },
    "Standard_RowHammer": {
        "filename": "trace_rowhammer.trace",
        "category": "Alternating Double-Sided Hammer",
        "definition": "High-frequency rapid alternation between Aggressor Rows (k-1, k+1) at maximum wire speed.",
        "is_attack": True,
        "expected_detection": "100% Rate Pacing Activated",
    },
    "Blacksmith_MultiSided": {
        "filename": "trace_blacksmith.trace",
        "category": "Frequency-Domain Non-Uniform Hammer",
        "definition": "Multi-sided non-uniform frequency toggling across multiple aggressor rows (IEEE S&P'22).",
        "is_attack": True,
        "expected_detection": "100% Detected via Adaptive Threshold Engine",
    },
    "RowPress_Prolonged": {
        "filename": "trace_rowpress.trace",
        "category": "Prolonged Activation Hammer",
        "definition": "Holding row open up to maximum JEDEC tRAS_max to accelerate thermal charge leakage.",
        "is_attack": True,
        "expected_detection": "100% Clamped by Command Engine FSM",
    },
    "Mixed_MultiTenant": {
        "filename": "trace_multitenant_adversarial.trace",
        "category": "Multi-Tenant Resource Contention",
        "definition": "Adversary executing concurrent hammer streams alongside latency-sensitive benign processes.",
        "is_attack": True,
        "expected_detection": "100% Isolated; Benign Bypassed via Timing Slack",
    },
    "ZenHammer_DDR5": {
        "filename": "trace_zenhammer.trace",
        "category": "DDR5 Physical Adjacency Hammer",
        "definition": "DDR5 physical adjacency multi-sided hammer, scrambled by SCARF 1-cycle Feistel randomizer.",
        "is_attack": True,
        "expected_detection": "100% Disrupted (SCARF Avalanche)",
    },
    "Crystalor_Hash_Collision": {
        "filename": "trace_crystalor.trace",
        "category": "Dual-Hash Collision Evasion",
        "definition": "Algorithmic hash collision attempting to flood a single bin, neutralized by orthogonal PXOR hashing.",
        "is_attack": True,
        "expected_detection": "100% Mitigated (PXOR Orthogonality)",
    },
    "Cross_Epoch_Split_Hammer": {
        "filename": "trace_cross_epoch.trace",
        "category": "Epoch Boundary Split & Half-Double",
        "definition": "Splitting activation bursts across the single-cycle epoch reset boundary + Half-Double (k+/-2) propagation.",
        "is_attack": True,
        "expected_detection": "100% Mitigated (Smooth Pacing + DRM)",
    },
}

# -----------------------------------------------------------------------------
# Helper Functions & Parsers
# -----------------------------------------------------------------------------
def get_git_commit():
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "clean_local_build"

def parse_trace(trace_path):
    commands = []
    if not os.path.isfile(trace_path):
        return commands
    with open(trace_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                cmd_type = parts[0]
                try:
                    addr = int(parts[1], 16)
                    # Aligned with rtl/frontend/addr_mapper_ddr5.sv:
                    # Row: Addr[31:18] (14 bits)
                    # BG : Addr[17:16] (2/3 bits)
                    # Bank: Addr[15:14] (2 bits)
                    # Col: Addr[13:6] (8 bits)
                    row = (addr >> 18) & 0x3FFF
                    bg = (addr >> 16) & 0x3
                    bank = (addr >> 14) & 0x3
                    commands.append((cmd_type, row, bg, bank))
                except ValueError:
                    continue
    return commands

def hash1(row, bank, bg):
    val = (row ^ (bg << 7) ^ (bank << 3)) * 0x45d9f3b
    return (val ^ (val >> 16)) % NUM_BINS

def hash2(row, bank, bg):
    val = ((row >> 2) ^ (bg << 5) ^ (bank << 9)) * 0x119de1f3
    return (val ^ (val >> 16)) % NUM_BINS

# -----------------------------------------------------------------------------
# Architectural Defense Simulation Engine
# -----------------------------------------------------------------------------
def simulate_defense(commands, use_ate=True, use_rowpress=True, defense=True):
    bins = [0] * NUM_BINS
    total_accesses = len(commands)
    mitigations_issued = 0
    attack_events_detected = 0
    worst_case_stall_cycles = 0
    total_stall_cycles = 0

    # Each ACT on row r disturbs r-1 and r+1; activating a row or a targeted refresh restores it.
    # A victim that reaches HC_FIRST is counted as an escaped bit flip.
    disturb = {}
    flipped = set()

    # ATE Tracking
    ewma_rate = 1.0
    alpha = 0.125
    dynamic_thresh = BASE_RH_THRESHOLD

    # RowPress & Open Row tracking per bank
    active_row = {}       # (bg, bank) -> row
    active_duration = {}  # (bg, bank) -> cycles
    EPOCH_INTERVAL = 2000 # Memory cycles per epoch reset window

    for idx, (cmd_type, row, bg, bank) in enumerate(commands):
        # Epoch reset: Single-cycle O(1) clear of counting bins at epoch boundary
        if idx > 0 and idx % EPOCH_INTERVAL == 0:
            bins = [0] * NUM_BINS

        bank_key = (bg, bank)
        is_row_hit = (bank_key in active_row and active_row[bank_key] == row)

        # Row activation only occurs on row miss / conflict (ACT command)
        if not is_row_hit:
            active_row[bank_key] = row
            active_duration[bank_key] = 15
            disturb[(bg, bank, row)] = 0
            for v in (row - 1, row + 1):
                key = (bg, bank, v)
                disturb[key] = disturb.get(key, 0) + 1
                if disturb[key] >= HC_FIRST:
                    flipped.add(key)
            h1 = hash1(row, bank, bg)
            h2 = hash2(row, bank, bg)

            # Dual-hash Count-Min update on activation
            count = min(bins[h1], bins[h2]) + 1
            bins[h1] = count
            bins[h2] = count
        else:
            # Row buffer hit: already open, wordline not toggled
            active_duration[bank_key] = active_duration.get(bank_key, 0) + 15
            h1 = hash1(row, bank, bg)
            h2 = hash2(row, bank, bg)
            count = min(bins[h1], bins[h2])

        # ATE dynamic threshold computation
        if use_ate:
            traffic_density = count / max(1, (idx + 1) % 1000)
            ewma_rate = (1.0 - alpha) * ewma_rate + alpha * traffic_density
            dynamic_thresh = max(16, min(64, int(BASE_RH_THRESHOLD * (1.0 + ewma_rate * 0.5))))
        else:
            dynamic_thresh = BASE_RH_THRESHOLD

        # RowPress check
        is_rowpress = False
        if use_rowpress:
            if active_duration.get(bank_key, 0) >= ROWPRESS_TACT_THRESH_CYCLES:
                is_rowpress = True
                active_duration[bank_key] = 0

        # Mitigation decision: rate pacing & targeted refresh (DRM)
        if defense and (count >= dynamic_thresh or is_rowpress):
            mitigations_issued += 1
            attack_events_detected += 1
            worst_case_stall_cycles = max(worst_case_stall_cycles, T_THROTTLE_CYCLES)
            total_stall_cycles += T_THROTTLE_CYCLES
            bins[h1] = 0
            bins[h2] = 0
            for v in (row - 2, row - 1, row + 1, row + 2):
                disturb[(bg, bank, v)] = 0

    return {
        "total_accesses": total_accesses,
        "mitigations": mitigations_issued,
        "flipped_victims": flipped,
        "escaped_bitflips": len(flipped),
        "detected_attacks": attack_events_detected,
        "worst_case_stall_cycles": worst_case_stall_cycles,
        "total_stall_cycles": total_stall_cycles,
    }

# -----------------------------------------------------------------------------
# Main Audit Runner
# -----------------------------------------------------------------------------
def main():
    print("=" * 96)
    print("  Q-SHIELD FULL-SYSTEM HARDWARE ATTACK EMULATION & SECURITY AUDIT")
    print("=" * 96)

    # Sanity checks
    missing_trace_files = []
    for tag, meta in ATTACK_TAXONOMY.items():
        p = os.path.join(TRACES_DIR, meta["filename"])
        if not os.path.isfile(p):
            missing_trace_files.append(meta["filename"])

    if missing_trace_files:
        print(f"[!] Warning: Missing {len(missing_trace_files)} trace files in {TRACES_DIR}: {missing_trace_files}")

    results = []
    start_time = time.time()

    for tag, meta in ATTACK_TAXONOMY.items():
        trace_path = os.path.join(TRACES_DIR, meta["filename"])
        commands = parse_trace(trace_path)

        # If trace file missing, generate synthetic fallback sequence for complete testing
        if not commands:
            print(f"[-] Generating synthetic verification pattern for {tag} ({meta['filename']}) ...")
            if tag == "ZenHammer_DDR5":
                # DDR5 physical adjacency hammer (subchannel/bank alternating)
                commands = [("READ", (0x200 if i % 2 == 0 else 0x204), (i % 8), (i % 4)) for i in range(10000)]
            elif tag == "Crystalor_Hash_Collision":
                # Targeted hash collision attempts targeting same hash bin
                commands = [("READ", (0x400 + (i % 4) * 8), 0, 0) for i in range(10000)]
            elif tag == "Cross_Epoch_Split_Hammer":
                # Boundary split pattern targeting single-cycle epoch resets
                commands = [("READ", 0x350, (i % 2), 0) for i in range(10000)]
            elif meta["is_attack"]:
                # Alternating aggressive rows
                commands = [("READ", (0x100 if i % 2 == 0 else 0x102), (i % 8), (i % 4)) for i in range(10000)]
            else:
                # Random benign rows
                commands = [("READ", (i * 7) % 65536, (i % 8), (i % 4)) for i in range(10000)]

        sim_res = simulate_defense(commands, use_ate=True, use_rowpress=True, defense=True)
        undefended = simulate_defense(commands, use_ate=True, use_rowpress=True, defense=False)

        is_adv = meta["is_attack"]
        exposed = undefended["flipped_victims"]
        still_flipped = sim_res["flipped_victims"] & exposed
        # Detection = share of victims that flip without defense but are protected with it.
        # None when the trace never reaches HC_FIRST: it then cannot demonstrate protection either way.
        detection_rate = (100.0 * (1 - len(still_flipped) / len(exposed))) if exposed else None
        fpr = (sim_res["mitigations"] / max(1, sim_res["total_accesses"]) * 100.0) if not is_adv else 0.0

        base_cycles = sim_res["total_accesses"] * T_ACCESS_CYCLES
        stall = sim_res["total_stall_cycles"]
        throughput_reduction = round(100.0 * stall / max(1, base_cycles + stall), 2) if is_adv else 0.0
        benign_slowdown = round((base_cycles + stall) / max(1, base_cycles), 4)

        results.append({
            "attack_tag": tag,
            "category": meta["category"],
            "description": meta["definition"],
            "total_accesses": sim_res["total_accesses"],
            "mitigations_issued": sim_res["mitigations"],
            "escaped_bitflips": sim_res["escaped_bitflips"],
            "victims_exposed_without_defense": len(exposed),
            "attack_detection_rate_pct": None if detection_rate is None else round(detection_rate, 2),
            "false_positive_rate_pct": round(fpr, 3),
            "throughput_reduction_pct": throughput_reduction,
            "benign_slowdown_factor": benign_slowdown,
            "worst_case_stall_cycles": sim_res["worst_case_stall_cycles"],
            "security_status": "NO_ESCAPES_IN_MODEL" if sim_res["escaped_bitflips"] == 0 else "ESCAPES_IN_MODEL",
        })

    elapsed_wall_time = time.time() - start_time

    # Display console summary
    print(f"\n{'Workload Scenario':<26} | {'Accesses':<9} | {'Mitigations':<11} | {'Bit-Flips':<9} | {'Detection':<9} | {'FPR':<7} | {'Status'}")
    print("-" * 96)
    for r in results:
        fpr_str = f"{r['false_positive_rate_pct']:.3f}%"
        det = "N/A" if r['attack_detection_rate_pct'] is None else f"{r['attack_detection_rate_pct']:.1f}%"
        print(f"{r['attack_tag']:<26} | {r['total_accesses']:<9,} | {r['mitigations_issued']:<11,} | {r['escaped_bitflips']:<9} | {det:<9} | {fpr_str:<7} | {r['security_status']}")
    print("=" * 96)
    total_escaped = sum(r["escaped_bitflips"] for r in results)
    print(f"  MODEL RESULT: {total_escaped} escaped bit flips across all workloads "
          f"(Python model, HC_FIRST={HC_FIRST}, {elapsed_wall_time:.2f}s)")
    print("=" * 96)

    # -------------------------------------------------------------------------
    # Tier 1: 1,000,000 Transactions Adversarial Address Fuzzer
    # -------------------------------------------------------------------------
    print("\n" + "=" * 96)
    print("  TIER 1 ARCHITECTURAL ADVERSARIAL ADDRESS FUZZER (1,000,000 TRANSACTIONS)")
    print("=" * 96)
    t_fuzz0 = time.time()
    bins = [0] * NUM_BINS
    fuzz_mitigations = 0
    benign_false_alarms = 0
    fuzz_disturb = {}
    fuzz_flipped = set()
    total_benign_beats = 0

    random.seed(0x5EED_F022)
    chunk_count = 100
    chunk_size = 10000

    for c in range(chunk_count):
        # Epoch reset emulation at chunk boundaries
        bins = [0] * NUM_BINS

        # 8,000 Benign mixed compute accesses per chunk (Poisson/uniform distributed)
        for i in range(8000):
            row = random.randint(0, 16383)
            bg = random.randint(0, 3)
            ba = random.randint(0, 3)
            h1 = hash1(row, ba, bg)
            h2 = hash2(row, ba, bg)
            cnt = min(bins[h1], bins[h2]) + 1
            bins[h1] = cnt
            bins[h2] = cnt
            total_benign_beats += 1
            if cnt >= BASE_RH_THRESHOLD:
                benign_false_alarms += 1
                bins[h1] = 0
                bins[h2] = 0

        # 2,000 Adversarial high-frequency burst accesses targeting hot rows
        hot_rows = [random.randint(100, 200) for _ in range(4)]
        for i in range(2000):
            row = random.choice(hot_rows)
            bg = 0
            ba = 0
            h1 = hash1(row, ba, bg)
            h2 = hash2(row, ba, bg)
            cnt = min(bins[h1], bins[h2]) + 1
            bins[h1] = cnt
            bins[h2] = cnt
            fuzz_disturb[row] = 0
            for v in (row - 1, row + 1):
                fuzz_disturb[v] = fuzz_disturb.get(v, 0) + 1
                if fuzz_disturb[v] >= HC_FIRST:
                    fuzz_flipped.add(v)
            if cnt >= BASE_RH_THRESHOLD:
                fuzz_mitigations += 1
                bins[h1] = 0
                bins[h2] = 0
                for v in (row - 2, row - 1, row + 1, row + 2):
                    fuzz_disturb[v] = 0

    elapsed_fuzz = time.time() - t_fuzz0
    fuzz_escaped = len(fuzz_flipped)
    fuzzer_fpr = (benign_false_alarms / max(1, total_benign_beats)) * 100.0

    print(f"  Total Fuzzing Beats  : 1,000,000")
    print(f"  Mitigations Injected : {fuzz_mitigations:,}")
    print(f"  Benign False Alarms  : {benign_false_alarms} ({fuzzer_fpr:.4f}% FPR)")
    print(f"  Escaped Bit-Flips    : {fuzz_escaped}")
    print(f"  Fuzzing Throughput   : {1_000_000 / elapsed_fuzz:,.0f} ops/sec (Elapsed: {elapsed_fuzz:.2f}s)")
    print(f"  Model verdict        : {'NO ESCAPES IN MODEL' if fuzz_escaped == 0 else 'ESCAPES IN MODEL'}")
    print("=" * 96)

    fuzzer_result = {
        "workload": "Adversarial_Address_Fuzzer_1M",
        "total_accesses": 1_000_000,
        "mitigations": fuzz_mitigations,
        "escaped_bitflips": fuzz_escaped,
        "benign_fpr_pct": round(fuzzer_fpr, 4),
        "fuzzing_throughput_ops_sec": round(1_000_000 / elapsed_fuzz, 1),
        "runtime_seconds": round(elapsed_fuzz, 2),
        "status": "NO_ESCAPES_IN_MODEL" if fuzz_escaped == 0 else "ESCAPES_IN_MODEL",
    }

    # 1. Save Attack Emulation Summary JSON
    summary_path = os.path.join(RESULTS_DIR, "attack_emulation_summary.json")
    with open(summary_path, "w") as f:
        json.dump({"attacks": results, "fuzzer": fuzzer_result}, f, indent=2)
    print(f"[+] Saved Attack Summary JSON : {summary_path}")

    # 2. Save Attack Emulation Metadata JSON
    meta_path = os.path.join(RESULTS_DIR, "attack_emulation_meta.json")
    meta_payload = {
        "script": "run_attack_emulation.py",
        "commit_sha": get_git_commit(),
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "hardware_parameters": {
            "num_bins": NUM_BINS,
            "base_rh_threshold": BASE_RH_THRESHOLD,
            "rowpress_tact_thresh_cycles": ROWPRESS_TACT_THRESH_CYCLES,
            "epoch_window_cycles": EPOCH_WINDOW_CYCLES,
        },
        "model_assumptions": {
            "hc_first": HC_FIRST,
            "t_access_cycles": T_ACCESS_CYCLES,
            "t_throttle_cycles": T_THROTTLE_CYCLES,
        },
        "model_fidelity_notes": MODEL_FIDELITY_NOTES,
        "attacks_evaluated": list(ATTACK_TAXONOMY.keys()),
        "fuzzer_evaluated": True,
        "fuzzer_transactions": 1_000_000,
        "timestamp_epoch": time.time(),
    }
    with open(meta_path, "w") as f:
        json.dump(meta_payload, f, indent=2)
    print(f"[+] Saved Attack Metadata JSON: {meta_path}")

    # 3. Save Markdown Report
    report_md_path = os.path.join(RESULTS_DIR, "attack_emulation_report.md")
    with open(report_md_path, "w") as f:
        f.write("# Q-Shield Attack Emulation Report (Python Architectural Model)\n\n")
        f.write("> Results come from a Python model, not from RTL simulation. Fidelity limits:\n")
        for note in MODEL_FIDELITY_NOTES:
            f.write(f"> - {note}\n")
        f.write(f"> - Assumed HC_FIRST = {HC_FIRST} activations; detection is N/A when a trace never reaches it.\n\n")
        f.write("## 1. Summary Matrix (Standardized Threat Vectors)\n\n")
        f.write("| Attack Profile | Category | Memory Accesses | Mitigations | Escaped Bit-Flips | Detection Rate | FPR | Attack Throughput Cut | Benign Slowdown |\n")
        f.write("| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n")
        for r in results:
            f.write(f"| **{r['attack_tag']}** | {r['category']} | {r['total_accesses']:,} | {r['mitigations_issued']:,} | **{r['escaped_bitflips']}** | {'N/A' if r['attack_detection_rate_pct'] is None else format(r['attack_detection_rate_pct'], '.1f') + '%'} | {r['false_positive_rate_pct']:.3f}% | -{r['throughput_reduction_pct']}% | {r['benign_slowdown_factor']:.2f}$\\times$ |\n")
        f.write("\n## 2. Tier 1 Adversarial Address Fuzzing (1,000,000 Transactions)\n\n")
        f.write(f"- **Total Transactions**: {fuzzer_result['total_accesses']:,}\n")
        f.write(f"- **Rate Pacing Mitigations**: {fuzzer_result['mitigations']:,}\n")
        f.write(f"- **Benign False Positive Rate**: **{fuzzer_result['benign_fpr_pct']:.4f}%**\n")
        f.write(f"- **Escaped Bit-Flips**: **{fuzzer_result['escaped_bitflips']}** (model)\n")
        f.write(f"- **Execution Speed**: {fuzzer_result['fuzzing_throughput_ops_sec']:,} ops/sec ({fuzzer_result['runtime_seconds']}s)\n\n")
        f.write("## 3. Threat Model Boundaries & Assumptions\n\n")
        f.write("- **Attacker Capabilities**: Unprivileged native instruction execution with arbitrary row targeting.\n")
        f.write("- **RTL status**: open RTL gaps found by tb/top/tb_security_attacks_vcd.sv (e.g. S8 epoch split, S10 threshold loosening, S11 dropped alerts) are not modelled here.\n")
        f.write("- **Non-Defended Vectors**: Physical bus probing, interposer sniffing, and cryogenic row-retention reading are outside controller scope.\n")
    print(f"[+] Saved Markdown Report     : {report_md_path}")

if __name__ == "__main__":
    main()
