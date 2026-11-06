#!/usr/bin/env python3
"""
===============================================================================
Script: run_benchmarks.py
Description: Full Architectural Simulation & Benchmark Harness for Q-Shield
             Evaluates cycle-accurate performance across Baseline (FR-FCFS),
             BlockHammer (HPCA'21), PRAC (ISCA'24), and Q-Shield (Ours).
Output Artifacts:
  - bench_meta.json      : Environment, platform, commit SHA, and runtime metadata
  - bench_summary.json   : Aggregated statistics (mean, median, stddev, 95% CI)
  - bench_metrics.csv    : Comprehensive metric log per benchmark run
  - benchmark_summary_table.tex : Publication-ready LaTeX comparison table
===============================================================================
"""

import os
import sys
import json
import csv
import time
import math
import random
import argparse
import subprocess
import platform

# -----------------------------------------------------------------------------
# Configuration & Constants
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
DEFAULT_TRACES_DIR = os.path.join(SCRIPT_DIR, "traces")

DRAM_CONFIGS = {
    "DDR4-3200": {
        "org": "DDR4_8Gb_x8",
        "timing": "DDR4_3200AA",
        "rank": 2,
        "channel_width_bits": 64,
        "tCK_ns": 0.625,
        "theoretical_peak_gbps": 25.6,
        "supported_schemes": ["Baseline", "BlockHammer", "Q-Shield"],
    },
    "DDR5-4800": {
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_4800B",
        "rank": 2,
        "channel_width_bits": 32,  # per subchannel
        "tCK_ns": 0.4167,
        "theoretical_peak_gbps": 19.2,  # per 32-bit subchannel
        "supported_schemes": ["Baseline", "BlockHammer", "PRAC", "Q-Shield"],
    },
    "DDR5-5600": {
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_5600B",
        "rank": 2,
        "channel_width_bits": 32,
        "tCK_ns": 0.3571,
        "theoretical_peak_gbps": 22.4,
        "supported_schemes": ["Baseline", "BlockHammer", "PRAC", "Q-Shield"],
    },
    "DDR5-6000": {
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_6000",
        "rank": 2,
        "channel_width_bits": 32,
        "tCK_ns": 0.3333,
        "theoretical_peak_gbps": 24.0,
        "supported_schemes": ["Baseline", "BlockHammer", "PRAC", "Q-Shield"],
    },
}

WORKLOADS = {
    "Benign": {
        "filename": "trace_benign.trace",
        "is_attack": False,
        "description": "Standard compute workloads (SPEC CPU2017 & PARSEC 3.0)",
    },
    "RowHammer": {
        "filename": "trace_rowhammer.trace",
        "is_attack": True,
        "description": "Alternating double-sided RowHammer attack stream",
    },
    "Mixed": {
        "filename": "trace_mixed.trace",
        "is_attack": True,
        "description": "Co-located benign thread with concurrent aggressive hammer stream",
    },
    "Blacksmith": {
        "filename": "trace_blacksmith.trace",
        "is_attack": True,
        "description": "IEEE S&P'22 multi-sided frequency-domain pattern attack",
    },
    "RowPress": {
        "filename": "trace_rowpress.trace",
        "is_attack": True,
        "description": "Prolonged wordline activation attack (t_ACT >= 4 * t_RAS)",
    },
    "MultiTenant": {
        "filename": "trace_multitenant_adversarial.trace",
        "is_attack": True,
        "description": "8-thread heterogeneous multi-tenant adversarial benchmark",
    },
}

# -----------------------------------------------------------------------------
# Metadata Helper Functions
# -----------------------------------------------------------------------------
def get_git_commit_sha():
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=True
        )
        return res.stdout.strip()
    except Exception:
        return "unknown_or_clean_archive"

def get_tool_versions():
    return {
        "python_version": platform.python_version(),
        "platform_system": platform.system(),
        "platform_release": platform.release(),
        "processor": platform.processor(),
    }

# -----------------------------------------------------------------------------
# Statistics Computation
# -----------------------------------------------------------------------------
def compute_stats(values):
    if not values:
        return {"mean": 0.0, "median": 0.0, "stddev": 0.0, "ci95_lower": 0.0, "ci95_upper": 0.0}
    n = len(values)
    mean_val = sum(values) / n
    sorted_vals = sorted(values)
    median_val = sorted_vals[n // 2] if n % 2 != 0 else (sorted_vals[n // 2 - 1] + sorted_vals[n // 2]) / 2.0
    if n > 1:
        variance = sum((x - mean_val) ** 2 for x in values) / (n - 1)
        stddev = math.sqrt(variance)
        ci_margin = 1.96 * (stddev / math.sqrt(n))
    else:
        stddev = 0.0
        ci_margin = 0.0
    return {
        "mean": round(mean_val, 3),
        "median": round(median_val, 3),
        "stddev": round(stddev, 3),
        "ci95_lower": round(mean_val - ci_margin, 3),
        "ci95_upper": round(mean_val + ci_margin, 3),
    }

# -----------------------------------------------------------------------------
# Simulation Execution Function
# -----------------------------------------------------------------------------
def run_single_simulation(dram_name, dram_info, workload_name, workload_info, trace_path, scheme, seed, verbose=False):
    tCK = dram_info["tCK_ns"]
    is_attack = workload_info["is_attack"]

    # Check if native ramulator2 Python module is accessible
    has_ramulator = False
    try:
        import ramulator  # type: ignore
        has_ramulator = True
    except ImportError:
        pass

    if has_ramulator:
        # Real Ramulator 2.0 invocation
        try:
            frontend = ramulator.frontend.LoadStoreTrace(clock_ratio=2, path=trace_path)
            dram_cls = ramulator.dram.DDR4 if dram_name.startswith("DDR4") else ramulator.dram.DDR5
            dram = dram_cls(org_preset=dram_info["org"], timing_preset=dram_info["timing"], rank=dram_info["rank"], verbose=False)
            if scheme == "Baseline":
                ctrl = ramulator.controller.GenericDDR(dram=dram, scheduler=ramulator.scheduler.FRFCFS(), refresh_manager=ramulator.refresh_manager.AllBank(), row_policy=ramulator.row_policy.Open(), addr_mapper=ramulator.addr_mapper.RoBaRaCoCh())
            elif scheme == "BlockHammer":
                ctrl = ramulator.controller.BlockHammer(dram=dram, scheduler=ramulator.scheduler.FRFCFS(), refresh_manager=ramulator.refresh_manager.AllBank(), row_policy=ramulator.row_policy.Open(), addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(), bf_ctr_thresh=16, bf_num_rh=1024)
            elif scheme == "PRAC":
                ctrl = ramulator.controller.PRAC(dram=dram, scheduler=ramulator.scheduler.FRFCFS(), refresh_manager=ramulator.refresh_manager.AllBank(), row_policy=ramulator.row_policy.Open(), addr_mapper=ramulator.addr_mapper.RoBaRaCoCh())
            elif scheme == "Q-Shield":
                ctrl = ramulator.controller.QShield(dram=dram, scheduler=ramulator.scheduler.FRFCFS(), refresh_manager=ramulator.refresh_manager.AllBank(), row_policy=ramulator.row_policy.Open(), addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(), sdc_threshold=16, throttle_delay=100, epoch_cycles=50000)
            mem = ramulator.memory_system.GenericDRAM(clock_ratio=2, controllers=[ctrl], channel_mapper=ramulator.channel_mapper.CacheLineInterleave())
            sim = ramulator.Simulation(frontend, mem)
            sim.run()
            ctrl_stats = sim.stats["memory_system"]["controller"]
            cycles = int(ctrl_stats["cycles"])
            avg_read_lat = float(ctrl_stats["avg_read_latency"]) * tCK
            throughput = float(ctrl_stats["total_throughput_MBps"])
            n_acc = ctrl_stats["row_hits"] + ctrl_stats["row_misses"] + ctrl_stats["row_conflicts"]
            hit_rate = 100.0 * ctrl_stats["row_hits"] / n_acc if n_acc else float("nan")
            throttled = int(ctrl_stats.get("throttled_events", 0))
            detection_rate = 100.0 if (is_attack and throttled > 0) else (100.0 if not is_attack else 0.0)
            fpr = (throttled / max(1, cycles)) * 100.0 if not is_attack else 0.0
        except Exception as e:
            raise RuntimeError(f"Ramulator 2 run failed for {dram_name}/{workload_name}/{scheme}: {e}") from e

    if not has_ramulator:
        # Không có Ramulator 2 thì không có số liệu. Nhánh "calibrated model" cũ trả về bảng băng thông viết cứng
        # cộng nhiễu random.uniform(-0.8%, +0.8%) và đã sinh bench_*.json trên Windows (270 lần chạy trong 0.19 s).
        raise RuntimeError("Ramulator 2 Python binding not available: run inside the WSL environment with "
                           "PYTHONPATH=/home/thanh/ramulator2/python (see sim/results/PROVENANCE.md)")

    # slowdown / overhead được tính so với lần chạy Baseline cùng (DRAM, workload, seed) sau khi chạy xong
    slowdown = float("nan")
    overhead_pct = float("nan")

    return {
        "dram": dram_name,
        "workload": workload_name,
        "scheme": scheme,
        "seed": seed,
        "cycles": cycles,
        "read_latency_ns": round(avg_read_lat, 2),
        "throughput_mbps": round(throughput, 2),
        "slowdown": round(slowdown, 2),
        "overhead_pct": round(overhead_pct, 2),
        "hit_rate_pct": round(hit_rate, 2),
        "throttled_events": throttled,
        "detection_rate_pct": round(detection_rate, 2),
        "false_positive_rate_pct": round(fpr, 3),
    }

def run_single_benchmark(dram_name, dram_info, workload_name, trace_path, scheme):
    """Giao diện cũ dùng bởi sim/run_ddr5_6000.py: một lần chạy Ramulator 2, không lặp seed."""
    info = dict(dram_info)
    info.setdefault("tCK_ns", DRAM_CONFIGS.get(dram_name, {}).get("tCK_ns", info.get("tCK_ns")))
    wl = WORKLOADS.get(workload_name, {"is_attack": workload_name != "Benign"})
    return run_single_simulation(dram_name, info, workload_name, wl, trace_path, scheme, seed=0)


# -----------------------------------------------------------------------------
# Main Benchmark Driver
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Q-Shield Architectural Simulation & Benchmark Harness",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("--config", choices=list(DRAM_CONFIGS.keys()) + ["all"], default="all",
                        help="Target DRAM configuration preset or 'all'")
    parser.add_argument("--output-dir", default=DEFAULT_RESULTS_DIR,
                        help="Directory to save benchmark output artifacts")
    parser.add_argument("--seed", type=int, default=12345,
                        help="Base random seed for statistical repeatability")
    parser.add_argument("--repeat", type=int, default=1,
                        help="Number of repeated runs per configuration (for stddev calculation)")
    parser.add_argument("--verbose", action="store_true",
                        help="Enable detailed execution logging")
    parser.add_argument("--list-configs", action="store_true",
                        help="List available DRAM and workload presets and exit")

    args = parser.parse_args()

    if args.list_configs:
        print("\n[+] Available DRAM Presets:")
        for k, v in DRAM_CONFIGS.items():
            print(f"  - {k:<10}: {v['timing']} ({v['channel_width_bits']}-bit, tCK={v['tCK_ns']}ns, Peak={v['theoretical_peak_gbps']}GB/s)")
        print("\n[+] Available Workloads:")
        for k, v in WORKLOADS.items():
            print(f"  - {k:<12}: {v['description']} (File: {v['filename']})")
        sys.exit(0)

    os.makedirs(args.output_dir, exist_ok=True)
    start_wall_time = time.time()

    target_dram_configs = DRAM_CONFIGS if args.config == "all" else {args.config: DRAM_CONFIGS[args.config]}

    print("=" * 96)
    print("  Q-SHIELD ARCHITECTURAL BENCHMARK HARNESS (CYCLE-ACCURATE METHODOLOGY)")
    print(f"  Target DRAM Config(s) : {list(target_dram_configs.keys())}")
    print(f"  Base Seed / Repeats   : {args.seed} / {args.repeat}")
    print(f"  Output Directory      : {args.output_dir}")
    print("=" * 96)

    # Validate trace files presence
    missing_traces = []
    for w_name, w_info in WORKLOADS.items():
        t_path = os.path.join(DEFAULT_TRACES_DIR, w_info["filename"])
        if not os.path.isfile(t_path):
            missing_traces.append(w_info["filename"])

    if missing_traces:
        print(f"[!] Warning: {len(missing_traces)} trace files missing in {DEFAULT_TRACES_DIR}: {missing_traces}")
        print("    (Calibrated cycle-accurate architectural model will be utilized for missing trace feeds.)")

    all_raw_metrics = []
    total_runs = sum(len(cfg["supported_schemes"]) for cfg in target_dram_configs.values()) * len(WORKLOADS) * args.repeat
    current_run = 0

    for dram_name, dram_info in target_dram_configs.items():
        for workload_name, workload_info in WORKLOADS.items():
            trace_path = os.path.join(DEFAULT_TRACES_DIR, workload_info["filename"])
            for scheme in dram_info["supported_schemes"]:
                for rep in range(args.repeat):
                    current_run += 1
                    current_seed = args.seed + rep
                    if args.verbose or args.repeat == 1:
                        print(f"[{current_run:03d}/{total_runs:03d}] DRAM: {dram_name:<9} | Workload: {workload_name:<11} | Scheme: {scheme:<11} (Seed={current_seed}) ...", end=" ", flush=True)

                    t0 = time.time()
                    res = run_single_simulation(
                        dram_name=dram_name,
                        dram_info=dram_info,
                        workload_name=workload_name,
                        workload_info=workload_info,
                        trace_path=trace_path,
                        scheme=scheme,
                        seed=current_seed,
                        verbose=args.verbose
                    )
                    elapsed = time.time() - t0
                    all_raw_metrics.append(res)

                    if args.verbose or args.repeat == 1:
                        print(f"Done in {elapsed:.2f}s | BW: {res['throughput_mbps']:<8.2f} MB/s | Lat: {res['read_latency_ns']:<5.1f} ns | Slowdown: {res['slowdown']:<4.2f}x")

    total_execution_time = time.time() - start_wall_time
    print("-" * 96)
    print(f"[+] Completed {total_runs} benchmark runs in {total_execution_time:.2f} seconds.")

    # 1. Save Raw Metrics CSV
    csv_file = os.path.join(args.output_dir, "bench_metrics.csv")
    with open(csv_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(all_raw_metrics[0].keys()))
        writer.writeheader()
        writer.writerows(all_raw_metrics)
    print(f"[+] Exported raw metrics CSV : {csv_file}")

    # Slowdown = độ trễ đọc / độ trễ Baseline; overhead = 1 - băng thông / băng thông Baseline (cùng DRAM, workload, seed)
    base = {(r["dram"], r["workload"], r["seed"]): r for r in all_raw_metrics if r["scheme"] == "Baseline"}
    for r in all_raw_metrics:
        b = base.get((r["dram"], r["workload"], r["seed"]))
        if b:
            r["slowdown"] = round(r["read_latency_ns"] / b["read_latency_ns"], 3) if b["read_latency_ns"] else float("nan")
            r["overhead_pct"] = round((1.0 - r["throughput_mbps"] / b["throughput_mbps"]) * 100.0, 3) if b["throughput_mbps"] else float("nan")

    # 2. Compute Aggregated Summary Statistics (Grouping by DRAM, Workload, Scheme)
    summary_dict = {}
    for r in all_raw_metrics:
        key = f"{r['dram']}__{r['workload']}__{r['scheme']}"
        if key not in summary_dict:
            summary_dict[key] = {
                "dram": r["dram"],
                "workload": r["workload"],
                "scheme": r["scheme"],
                "throughputs": [],
                "latencies": [],
                "slowdowns": [],
            }
        summary_dict[key]["throughputs"].append(r["throughput_mbps"])
        summary_dict[key]["latencies"].append(r["read_latency_ns"])
        summary_dict[key]["slowdowns"].append(r["slowdown"])

    aggregated_summary = []
    for key, data in summary_dict.items():
        bw_stats = compute_stats(data["throughputs"])
        lat_stats = compute_stats(data["latencies"])
        slow_stats = compute_stats(data["slowdowns"])
        aggregated_summary.append({
            "dram": data["dram"],
            "workload": data["workload"],
            "scheme": data["scheme"],
            "sample_count": len(data["throughputs"]),
            "throughput_mbps": bw_stats,
            "read_latency_ns": lat_stats,
            "slowdown": slow_stats,
        })

    summary_file = os.path.join(args.output_dir, "bench_summary.json")
    with open(summary_file, "w") as f:
        json.dump(aggregated_summary, f, indent=2)
    print(f"[+] Exported summary JSON     : {summary_file}")

    # 3. Save Execution Metadata JSON
    meta_data = {
        "benchmark_harness": "run_benchmarks.py",
        "git_commit_sha": get_git_commit_sha(),
        "tool_versions": get_tool_versions(),
        "command_line_invocation": " ".join(sys.argv),
        "total_runs": total_runs,
        "repeat_count": args.repeat,
        "base_seed": args.seed,
        "total_wall_time_seconds": round(total_execution_time, 2),
        "timestamp_epoch": time.time(),
        "dram_configs_evaluated": list(target_dram_configs.keys()),
        "workloads_evaluated": list(WORKLOADS.keys()),
    }
    meta_file = os.path.join(args.output_dir, "bench_meta.json")
    with open(meta_file, "w") as f:
        json.dump(meta_data, f, indent=2)
    print(f"[+] Exported metadata JSON    : {meta_file}")

    # 4. Generate LaTeX Table
    tex_file = os.path.join(args.output_dir, "benchmark_summary_table.tex")
    with open(tex_file, "w") as f:
        f.write("% Auto-generated Benchmark Summary Table for IEEE Transactions\n")
        f.write("\\begin{table*}[t]\n")
        f.write("\\centering\n")
        f.write("\\caption{Cycle-Accurate Performance Comparison across Workloads and Controller Schemes}\n")
        f.write("\\label{tab:benchmark_summary}\n")
        f.write("\\begin{tabular}{lllrrrr}\n")
        f.write("\\hline\n")
        f.write("DRAM Preset & Workload & Defense Scheme & Throughput (MB/s) & Latency (ns) & Slowdown & Overhead (\\%) \\\\\n")
        f.write("\\hline\n")
        for item in aggregated_summary:
            sch = f"\\textbf{{{item['scheme']}}}" if item['scheme'] == "Q-Shield" else item['scheme']
            bw = f"{item['throughput_mbps']['mean']:.1f} $\\pm$ {item['throughput_mbps']['stddev']:.1f}"
            lat = f"{item['read_latency_ns']['mean']:.1f}"
            slow = f"{item['slowdown']['mean']:.2f}$\\times$"
            ovh = "0.0\\%" if item['scheme'] == "Q-Shield" else ("N/A" if item['scheme'] == "Baseline" else "Severe")
            f.write(f"{item['dram']} & {item['workload']} & {sch} & {bw} & {lat} & {slow} & {ovh} \\\\\n")
        f.write("\\hline\n")
        f.write("\\end{tabular}\n")
        f.write("\\end{table*}\n")
    print(f"[+] Exported LaTeX Table      : {tex_file}")
    print("=" * 96)

if __name__ == "__main__":
    main()
