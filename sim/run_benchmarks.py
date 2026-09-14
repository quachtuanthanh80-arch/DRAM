import sys
import os
import json
import csv
import time

sys.path.insert(0, '/home/thanh/ramulator2/python')
import ramulator

# Results directory
RESULTS_DIR = "/mnt/d/RAM/sim/results"
os.makedirs(RESULTS_DIR, exist_ok=True)

# DRAM Configurations
DRAM_CONFIGS = {
    "DDR4-3200": {
        "cls": ramulator.dram.DDR4,
        "org": "DDR4_8Gb_x8",
        "timing": "DDR4_3200AA",
        "rank": 2,
        "tCK_ns": 0.625, # 1/1600 MHz
    },
    "DDR5-4800": {
        "cls": ramulator.dram.DDR5,
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_4800B",
        "rank": 2,
        "tCK_ns": 0.4167, # 1/2400 MHz
    },
    "DDR5-5600": {
        "cls": ramulator.dram.DDR5,
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_5600B",
        "rank": 2,
        "tCK_ns": 0.3571, # 1/2800 MHz
    },
}

# Workloads
WORKLOADS = {
    "Benign": "/mnt/d/RAM/sim/traces/trace_benign.trace",
    "RowHammer": "/mnt/d/RAM/sim/traces/trace_rowhammer.trace",
    "Mixed": "/mnt/d/RAM/sim/traces/trace_mixed.trace",
}

# Controller Schemes
SCHEMES = ["Baseline", "BlockHammer", "Q-Shield"]

def run_single_benchmark(dram_name, dram_info, workload_name, trace_path, scheme):
    # 1. Frontend
    frontend = ramulator.frontend.LoadStoreTrace(
        clock_ratio=2,
        path=trace_path,
    )

    # 2. DRAM
    dram = dram_info["cls"](
        org_preset=dram_info["org"],
        timing_preset=dram_info["timing"],
        rank=dram_info["rank"],
        verbose=False,
    )

    # 3. Controller
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

    # 4. Memory System
    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=2,
        controllers=[ctrl],
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )

    # 5. Execute Simulation
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

def main():
    print("=" * 80)
    print("  Q-SHIELD DDR5/DDR4 FULL BENCHMARK MATRIX (RAMULATOR2 SIMULATION)")
    print("=" * 80)

    all_results = []
    total_runs = len(DRAM_CONFIGS) * len(WORKLOADS) * len(SCHEMES)
    current_run = 0
    start_time = time.time()

    for dram_name, dram_info in DRAM_CONFIGS.items():
        for workload_name, trace_path in WORKLOADS.items():
            for scheme in SCHEMES:
                current_run += 1
                print(f"[{current_run}/{total_runs}] Running {dram_name} | {workload_name:<10} | {scheme:<12} ...", end=" ", flush=True)
                t0 = time.time()
                res = run_single_benchmark(dram_name, dram_info, workload_name, trace_path, scheme)
                elapsed = time.time() - t0
                all_results.append(res)
                print(f"Done in {elapsed:.2f}s | Cycles: {res['cycles']:<8} Lat: {res['read_latency_ns']:<7.2f} ns  BW: {res['throughput_mbps']:<8.2f} MB/s")

    total_elapsed = time.time() - start_time
    print("-" * 80)
    print(f"All {total_runs} benchmark runs completed in {total_elapsed:.2f} seconds.")

    # Save to JSON
    json_path = os.path.join(RESULTS_DIR, "benchmark_results.json")
    with open(json_path, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"Saved JSON results to {json_path}")

    # Save to CSV
    csv_path = os.path.join(RESULTS_DIR, "benchmark_results.csv")
    fieldnames = list(all_results[0].keys())
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_results)
    print(f"Saved CSV results to {csv_path}")

    # Print Summary Table
    print("\n" + "=" * 95)
    print(f"{'DRAM':<11} | {'Workload':<10} | {'Scheme':<12} | {'Cycles':<9} | {'Lat (ns)':<9} | {'BW (MB/s)':<10} | {'Hit Rate':<9} | {'Throttled':<9}")
    print("-" * 95)
    for r in all_results:
        print(f"{r['dram']:<11} | {r['workload']:<10} | {r['scheme']:<12} | {r['cycles']:<9} | {r['read_latency_ns']:<9.2f} | {r['throughput_mbps']:<10.2f} | {r['hit_rate_pct']:<8.1f}% | {r['throttled_events']:<9}")
    print("=" * 95)

if __name__ == "__main__":
    main()
