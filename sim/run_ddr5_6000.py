import sys
import os
import json

sys.path.insert(0, os.environ.get('RAMULATOR2_PYTHON', os.path.expanduser('~/ramulator2/python')))
SIM_DIR = os.path.dirname(os.path.abspath(__file__))
if SIM_DIR not in sys.path:
    sys.path.insert(0, SIM_DIR)
from run_benchmarks import run_single_benchmark
import ramulator

dram_info = {
    'cls': ramulator.dram.DDR5,
    'org': 'DDR5_16Gb_x8',
    'timing': 'DDR5_6000B',
    'rank': 2,
    'tCK_ns': 0.333333,
}

trace_mixed = os.path.join(SIM_DIR, 'traces', 'trace_mixed.trace')
trace_benign = os.path.join(SIM_DIR, 'traces', 'trace_benign.trace')
trace_rh = os.path.join(SIM_DIR, 'traces', 'trace_rowhammer.trace')
trace_bs = os.path.join(SIM_DIR, 'traces', 'trace_blacksmith.trace')

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

out_file = os.path.join(SIM_DIR, 'results', 'ddr5_6000_results.json')
with open(out_file, 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2)
print(f"\nSaved to {out_file}")
