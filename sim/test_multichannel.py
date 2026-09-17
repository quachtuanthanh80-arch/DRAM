#!/usr/bin/env python3
"""
===============================================================================
Script: test_multichannel.py
Description: Full-Scale Multi-Channel Memory Evaluation (1-CH, 2-CH, 3-CH, 4-CH, 8-CH)
             across DDR4-3200 and DDR5-4800 for Benign, RowHammer, and Mixed workloads.
Features:
- Standard CacheLineInterleave for power-of-two channels (1, 2, 4, 8).
- Specialized Modulo-3 Trace Partitioning for Triple-Channel (3-CH).
- Metrics: Throughput (MB/s), Cycles, Read Latency (ns), Scaling Efficiency (%).
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
    },
    "DDR5-4800": {
        "cls": ramulator.dram.DDR5,
        "org": "DDR5_16Gb_x8",
        "timing": "DDR5_4800B",
        "rank": 2,
        "tCK_ns": 0.4167,
    },
}

WORKLOADS = {
    "Benign": os.path.join(TRACES_DIR, "trace_benign.trace"),
    "RowHammer": os.path.join(TRACES_DIR, "trace_rowhammer.trace"),
    "Mixed": os.path.join(TRACES_DIR, "trace_mixed.trace"),
}

def partition_trace_modulo3(input_trace_path):
    """Partitions a 64-byte aligned trace into 3 distinct trace files based on (addr >> 6) % 3."""
    base_name = os.path.splitext(os.path.basename(input_trace_path))[0]
    out_paths = [os.path.join(TRACES_DIR, f"{base_name}_ch{i}.trace") for i in range(3)]
    
    files = [open(p, "w") for p in out_paths]
    try:
        with open(input_trace_path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        addr_str = parts[1] if parts[0] in ["LD", "ST", "R", "W"] else parts[0]
                        addr = int(addr_str, 0)
                        ch_idx = (addr >> 6) % 3
                        files[ch_idx].write(line)
                    except ValueError:
                        files[0].write(line)
    finally:
        for f in files:
            f.close()
            
    return out_paths

def run_standard_multichannel(dram_name, dram_info, num_channels, trace_path, scheme="Baseline"):
    frontend = ramulator.frontend.LoadStoreTrace(
        clock_ratio=2,
        path=trace_path,
    )

    controllers = []
    for ch_idx in range(num_channels):
        dram_inst = dram_info["cls"](
            org_preset=dram_info["org"],
            timing_preset=dram_info["timing"],
            rank=dram_info["rank"],
            verbose=False,
        )
        ctrl = ramulator.controller.GenericDDR(
            dram=dram_inst,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
        )
        controllers.append(ctrl)

    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=2,
        controllers=controllers,
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )

    sim = ramulator.Simulation(frontend, mem)
    sim.run()

    c_stats = sim.stats["memory_system"]["controller"]
    tCK = dram_info["tCK_ns"]

    if isinstance(c_stats, list):
        total_bw = sum(c["total_throughput_MBps"] for c in c_stats)
        max_cycles = max(c["cycles"] for c in c_stats)
        avg_lat_cyc = sum(c["avg_read_latency"] for c in c_stats) / len(c_stats)
    else:
        total_bw = c_stats["total_throughput_MBps"]
        max_cycles = c_stats["cycles"]
        avg_lat_cyc = c_stats["avg_read_latency"]

    return {
        "cycles": max_cycles,
        "read_latency_ns": round(avg_lat_cyc * tCK, 2),
        "throughput_mbps": round(total_bw, 2),
    }

def run_modulo3_triple_channel(dram_name, dram_info, trace_path, scheme="Baseline"):
    """Simulates 3 independent channels processing partitioned streams."""
    sub_traces = partition_trace_modulo3(trace_path)
    tCK = dram_info["tCK_ns"]
    
    total_bw = 0.0
    max_cycles = 0
    total_lat_weighted = 0.0
    total_reads = 0

    for ch_idx, sub_path in enumerate(sub_traces):
        if not os.path.exists(sub_path) or os.path.getsize(sub_path) == 0:
            continue
            
        frontend = ramulator.frontend.LoadStoreTrace(clock_ratio=2, path=sub_path)
        dram_inst = dram_info["cls"](
            org_preset=dram_info["org"],
            timing_preset=dram_info["timing"],
            rank=dram_info["rank"],
            verbose=False,
        )
        ctrl = ramulator.controller.GenericDDR(
            dram=dram_inst,
            scheduler=ramulator.scheduler.FRFCFS(),
            refresh_manager=ramulator.refresh_manager.AllBank(),
            row_policy=ramulator.row_policy.Open(),
            addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
        )
        mem = ramulator.memory_system.GenericDRAM(
            clock_ratio=2,
            controllers=[ctrl],
            channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
        )
        sim = ramulator.Simulation(frontend, mem)
        sim.run()

        c_stats = sim.stats["memory_system"]["controller"]
        bw = c_stats["total_throughput_MBps"]
        cyc = c_stats["cycles"]
        lat = c_stats["avg_read_latency"]
        n_reads = c_stats["num_read_reqs"]

        total_bw += bw
        if cyc > max_cycles:
            max_cycles = cyc
        total_lat_weighted += (lat * n_reads)
        total_reads += n_reads

    avg_lat_cyc = (total_lat_weighted / total_reads) if total_reads > 0 else 0.0

    return {
        "cycles": max_cycles,
        "read_latency_ns": round(avg_lat_cyc * tCK, 2),
        "throughput_mbps": round(total_bw, 2),
    }

def main():
    print("=" * 105)
    print("  Q-SHIELD MULTI-CHANNEL SCALING BENCHMARK (1-CH, 2-CH, 3-CH MODULO-3, 4-CH, 8-CH)")
    print("=" * 105)

    test_channels = [1, 2, 3, 4, 8]
    all_results = []

    for dram_name in ["DDR4-3200", "DDR5-4800"]:
        dram_info = DRAM_CONFIGS[dram_name]

        for wl_name, wl_path in WORKLOADS.items():
            print(f"\n--- Architecture: {dram_name} | Workload: {wl_name} ---")
            base_bw = None

            for ch in test_channels:
                print(f"  Testing {ch}-Channel ...", end=" ", flush=True)
                t0 = time.time()
                
                if ch == 3:
                    res = run_modulo3_triple_channel(dram_name, dram_info, wl_path)
                    res["note"] = "Modulo-3 Interleaved"
                else:
                    res = run_standard_multichannel(dram_name, dram_info, ch, wl_path)
                    res["note"] = "CacheLine Interleaved"

                elapsed = time.time() - t0
                res["dram"] = dram_name
                res["workload"] = wl_name
                res["channels"] = ch

                if ch == 1:
                    base_bw = res["throughput_mbps"]
                    res["speedup"] = 1.00
                    res["efficiency_pct"] = 100.0
                else:
                    speedup = res["throughput_mbps"] / base_bw if base_bw > 0 else 1.0
                    res["speedup"] = round(speedup, 2)
                    res["efficiency_pct"] = round((speedup / ch) * 100.0, 1)

                print(f"Done in {elapsed:.2f}s | Cycles: {res['cycles']:<6} Lat: {res['read_latency_ns']:<6.2f} ns  BW: {res['throughput_mbps']:<8.2f} MB/s  Speedup: {res['speedup']}x ({res['efficiency_pct']}%)")
                all_results.append(res)

    # Save to JSON
    json_path = os.path.join(RESULTS_DIR, "multichannel_scaling_full.json")
    with open(json_path, "w") as f:
        json.dump(all_results, f, indent=2)

    # Save to CSV
    csv_path = os.path.join(RESULTS_DIR, "multichannel_scaling_full.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(all_results[0].keys()))
        writer.writeheader()
        writer.writerows(all_results)

    print("\n" + "=" * 115)
    print(f"{'DRAM':<11} | {'Workload':<10} | {'Channels':<9} | {'Cycles':<8} | {'Lat (ns)':<9} | {'BW (MB/s)':<11} | {'Speedup':<8} | {'Efficiency':<11} | {'Method'}")
    print("-" * 115)
    for r in all_results:
        print(f"{r['dram']:<11} | {r['workload']:<10} | {r['channels']:<9} | {r['cycles']:<8} | {r['read_latency_ns']:<9.2f} | {r['throughput_mbps']:<11.2f} | {r['speedup']:<6.2f}x | {r['efficiency_pct']:<9.1f}% | {r['note']}")
    print("=" * 115)
    print(f"Full results archived to: {json_path} and {csv_path}")

if __name__ == "__main__":
    main()
