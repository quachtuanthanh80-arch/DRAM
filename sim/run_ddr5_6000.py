import sys
import os
import json

sys.path.insert(0, '/home/thanh/ramulator2/python')
sys.path.insert(0, '/mnt/d/RAM/sim')
from run_benchmarks import run_single_benchmark
import ramulator

dram_info = {
    'cls': ramulator.dram.DDR5,
    'org': 'DDR5_16Gb_x8',
    'timing': 'DDR5_6000B',
    'rank': 2,
    'tCK_ns': 0.333333,
}

trace_mixed = '/mnt/d/RAM/sim/traces/trace_mixed.trace'
trace_benign = '/mnt/d/RAM/sim/traces/trace_benign.trace'
trace_rh = '/mnt/d/RAM/sim/traces/trace_rowhammer.trace'
trace_bs = '/mnt/d/RAM/sim/traces/trace_blacksmith.trace'

results = []
for wl_name, tr_path in [('Benign', trace_benign), ('RowHammer', trace_rh), ('Mixed', trace_mixed), ('Blacksmith', trace_bs)]:
    for scheme in ['Baseline', 'BlockHammer', 'PRAC', 'Q-Shield']:
        print(f"[*] Running DDR5-6000 {wl_name} with {scheme}...")
        r = run_single_benchmark('DDR5-6000', dram_info, wl_name, tr_path, scheme)
        results.append(r)

print("\n=== SUMMARY DDR5-6000 BENCHMARK RESULTS ===")
for r in results:
    w = r['workload']
    s = r['scheme']
    c = r['cycles']
    lat = r['read_latency_ns']
    bw = r['throughput_mbps']
    print(f"{w:12} | {s:12} | Cycles: {c:8} | Latency: {lat:7.2f} ns | BW: {bw:8.1f} MB/s")

with open('/mnt/d/RAM/sim/results/ddr5_6000_results.json', 'w') as f:
    json.dump(results, f, indent=2)
print("\nSaved to /mnt/d/RAM/sim/results/ddr5_6000_results.json")
