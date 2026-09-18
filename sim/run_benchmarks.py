#!/usr/bin/env python3
"""
===============================================================================
Script: run_benchmarks.py
Description: Full Benchmark Matrix Evaluation comparing Baseline, BlockHammer (HPCA'21),
             PRAC (ISCA'24 / JEDEC DDR5), and Q-Shield (Ours) across DDR4 and DDR5.
Workloads: Benign, RowHammer, Mixed, and Blacksmith (IEEE S&P'22 Multi-Sided).
===============================================================================
"""

import sys
import os
import json
import csv
import time

sys.path.insert(0, '/home/thanh/ramulator2/python')
import ramulator

RESULTS_DIR = "/mnt/d/RAM/sim/results"
TRACES_DIR = "/mnt/d/RAM/sim/traces"
os.makedirs(RESULTS_DIR, exist_ok=True)

DRAM_CONFIGS = {
    "DDR4-3200": {
        "cls": ramulator.dram.DDR4,
        "org": "DDR4_8Gb_x8",
        "timing": "DDR4_3200AA",
        "rank": 2,
        "tCK_ns": 0.625,
        "supported_schemes": ["Baseline", "BlockHammer", "Q-Shield"],
    },
    "DDR5-4800": {
        "cls": ramulator.dram.DDR5,
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_4800B",
        "rank": 2,
        "tCK_ns": 0.4167,
        "supported_schemes": ["Baseline", "BlockHammer", "PRAC", "Q-Shield"],
    },
    "DDR5-5600": {
        "cls": ramulator.dram.DDR5,
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_5600B",
        "rank": 2,
        "tCK_ns": 0.3571,
        "supported_schemes": ["Baseline", "BlockHammer", "PRAC", "Q-Shield"],
    },
}

WORKLOADS = {
    "Benign": os.path.join(TRACES_DIR, "trace_benign.trace"),
    "RowHammer": os.path.join(TRACES_DIR, "trace_rowhammer.trace"),
    "Mixed": os.path.join(TRACES_DIR, "trace_mixed.trace"),
    "Blacksmith": os.path.join(TRACES_DIR, "trace_blacksmith.trace"),
    "RowPress": os.path.join(TRACES_DIR, "trace_rowpress.trace"),
    "MultiTenant": os.path.join(TRACES_DIR, "trace_multitenant_adversarial.trace"),
}

def run_single_benchmark(dram_name, dram_info, workload_name, trace_path, scheme):
    frontend = ramulator.frontend.LoadStoreTrace(
        clock_ratio=2,
        path=trace_path,
    )

    dram = dram_info["cls"](
        org_preset=dram_info["org"],
        timing_preset=dram_info["timing"],
        rank=dram_info["rank"],
        verbose=False,
    )

    if scheme == "Baseline":
        ctrl = ramulator.controller.GenericDDR(
            dram=dram,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
        )
    elif scheme == "BlockHammer":
        ctrl = ramulator.controller.BlockHammer(
            dram=dram,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
            bf_ctr_thresh=16,
            bf_num_rh=1024,
        )
    elif scheme == "PRAC":
        ctrl = ramulator.controller.PRAC(
            dram=dram,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
        )
    elif scheme == "Q-Shield":
        ctrl = ramulator.controller.QShield(
            dram=dram,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
            sdc_threshold=16,
            throttle_delay=100,
            epoch_cycles=50000,
        )
    else:
        raise ValueError(f"Unknown scheme: {scheme}")

    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=2,
        controllers=[ctrl],
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )

    sim = ramulator.Simulation(frontend, mem)
    sim.run()

    ctrl_stats = sim.stats["memory_system"]["controller"]
    cycles = ctrl_stats["cycles"]
    read_latency_cycles = ctrl_stats["avg_read_latency"]
    tCK = dram_info["tCK_ns"]
    read_latency_ns = read_latency_cycles * tCK
    throughput_mbps = ctrl_stats["total_throughput_MBps"]
    row_hits = ctrl_stats["row_hits"]
    row_misses = ctrl_stats["row_misses"]
    row_conflicts = ctrl_stats["row_conflicts"]
    total_row_accesses = row_hits + row_misses + row_conflicts
    hit_rate = (row_hits / total_row_accesses * 100.0) if total_row_accesses > 0 else 0.0

    throttled_events = ctrl_stats.get("throttled_events", 0)
    blocked_acts = ctrl_stats.get("attack_acts_blocked", 0)
    bypassed_benign = ctrl_stats.get("bypassed_benign_reqs", 0)

    result = {
        "dram": dram_name,
        "workload": workload_name,
        "scheme": scheme,
        "cycles": cycles,
        "read_latency_cycles": round(read_latency_cycles, 2),
        "read_latency_ns": round(read_latency_ns, 2),
        "throughput_mbps": round(throughput_mbps, 2),
        "row_hits": row_hits,
        "row_misses": row_misses,
        "row_conflicts": row_conflicts,
        "hit_rate_pct": round(hit_rate, 2),
        "throttled_events": throttled_events,
        "attack_acts_blocked": blocked_acts,
        "bypassed_benign_reqs": bypassed_benign,
    }
    return result

def export_latex_table(results, file_path):
    with open(file_path, "w") as f:
        f.write("% Auto-generated Benchmark Summary Table for IEEE Transactions\n")
        f.write("\\begin{table*}[t]\n")
        f.write("\\centering\n")
        f.write("\\caption{Comprehensive Performance & Resilience Comparison across Architectures and Baselines}\n")
        f.write("\\label{tab:benchmark_summary}\n")
        f.write("\\begin{tabular}{lllrrrrr}\n")
        f.write("\\hline\n")
        f.write("DRAM Preset & Workload & Scheme & Cycles & Latency (ns) & Throughput (MB/s) & Hit Rate (\\%) & Throttled \\\\\n")
        f.write("\\hline\n")
        for r in results:
            scheme_fmt = f"\\textbf{{{r['scheme']}}}" if r['scheme'] == "Q-Shield" else r['scheme']
            f.write(f"{r['dram']} & {r['workload']} & {scheme_fmt} & {r['cycles']} & {r['read_latency_ns']:.2f} & {r['throughput_mbps']:.2f} & {r['hit_rate_pct']:.1f}\\% & {r['throttled_events']} \\\\\n")
        f.write("\\hline\n")
        f.write("\\end{tabular}\n")
        f.write("\\end{table*}\n")

def main():
    print("=" * 95)
    print("  Q-SHIELD SOTA BENCHMARK MATRIX (RAMULATOR2): BASELINE, BLOCKHAMMER, PRAC, Q-SHIELD")
    print("=" * 95)

    all_results = []
    total_runs = sum(len(cfg["supported_schemes"]) for cfg in DRAM_CONFIGS.values()) * len(WORKLOADS)
    current_run = 0
    start_time = time.time()

    for dram_name, dram_info in DRAM_CONFIGS.items():
        for workload_name, trace_path in WORKLOADS.items():
            for scheme in dram_info["supported_schemes"]:
                current_run += 1
                print(f"[{current_run}/{total_runs}] Running {dram_name} | {workload_name:<11} | {scheme:<12} ...", end=" ", flush=True)
                t0 = time.time()
                res = run_single_benchmark(dram_name, dram_info, workload_name, trace_path, scheme)
                elapsed = time.time() - t0
                all_results.append(res)
                print(f"Done in {elapsed:.2f}s | Cycles: {res['cycles']:<7} Lat: {res['read_latency_ns']:<6.2f} ns  BW: {res['throughput_mbps']:<8.2f} MB/s")

    total_elapsed = time.time() - start_time
    print("-" * 95)
    print(f"All {total_runs} benchmark runs completed in {total_elapsed:.2f} seconds.")

    # Save to JSON & CSV
    json_path = os.path.join(RESULTS_DIR, "benchmark_results_expanded.json")
    with open(json_path, "w") as f:
        json.dump(all_results, f, indent=2)

    csv_path = os.path.join(RESULTS_DIR, "benchmark_results_expanded.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(all_results[0].keys()))
        writer.writeheader()
        writer.writerows(all_results)

    # Save LaTeX Table
    tex_path = os.path.join(RESULTS_DIR, "benchmark_summary_table.tex")
    export_latex_table(all_results, tex_path)

    print(f"[+] Saved JSON: {json_path}")
    print(f"[+] Saved CSV:  {csv_path}")
    print(f"[+] Saved TeX:  {tex_path}")

if __name__ == "__main__":
    main()
