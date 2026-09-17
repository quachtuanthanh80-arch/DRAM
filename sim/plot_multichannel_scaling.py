#!/usr/bin/env python3
"""
===============================================================================
Script: plot_multichannel_scaling.py
Description: Generates publication-quality figures (PDF & PNG) for IEEE Transactions:
             1. Bandwidth Scaling vs Number of Channels (1-CH to 8-CH)
             2. Read Latency Reduction across Multi-Channel Configurations
             3. Scaling Efficiency (%) compared to Ideal Linear Speedup
===============================================================================
"""

import os
import json
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_JSON = os.path.join(BASE_DIR, "sim", "results", "multichannel_scaling_full.json")
FIG_DIR = os.path.join(BASE_DIR, "paper", "figures")
os.makedirs(FIG_DIR, exist_ok=True)

if not os.path.exists(RESULTS_JSON):
    print(f"[ERROR] Results file not found: {RESULTS_JSON}")
    exit(1)

with open(RESULTS_JSON, "r") as f:
    data = json.load(f)

# IEEE Publication Style Configuration
plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 10,
    'axes.labelsize': 11,
    'axes.titlesize': 12,
    'xtick.labelsize': 9,
    'ytick.labelsize': 9,
    'legend.fontsize': 9,
    'figure.titlesize': 13,
    'figure.dpi': 300,
    'axes.grid': True,
    'grid.alpha': 0.3,
    'grid.linestyle': '--',
})

# Filter data for Benign and Mixed on DDR4-3200 and DDR5-4800
channels = [1, 2, 4, 8]

ddr4_benign_bw = [next(r["throughput_mbps"] for r in data if r["dram"] == "DDR4-3200" and r["workload"] == "Benign" and r["channels"] == ch) for ch in channels]
ddr5_benign_bw = [next(r["throughput_mbps"] for r in data if r["dram"] == "DDR5-4800" and r["workload"] == "Benign" and r["channels"] == ch) for ch in channels]

ddr4_benign_lat = [next(r["read_latency_ns"] for r in data if r["dram"] == "DDR4-3200" and r["workload"] == "Benign" and r["channels"] == ch) for ch in channels]
ddr5_benign_lat = [next(r["read_latency_ns"] for r in data if r["dram"] == "DDR5-4800" and r["workload"] == "Benign" and r["channels"] == ch) for ch in channels]

ddr4_mixed_bw = [next(r["throughput_mbps"] for r in data if r["dram"] == "DDR4-3200" and r["workload"] == "Mixed" and r["channels"] == ch) for ch in channels]
ddr5_mixed_bw = [next(r["throughput_mbps"] for r in data if r["dram"] == "DDR5-4800" and r["workload"] == "Mixed" and r["channels"] == ch) for ch in channels]

#------------------------------------------------------------------------------
# Figure 1: Multi-Channel Bandwidth Scaling (GB/s)
#------------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(6.5, 4.0))

x = np.arange(len(channels))
width = 0.20

rects1 = ax.bar(x - 1.5*width, [bw/1000.0 for bw in ddr4_benign_bw], width, label='DDR4-3200 (Benign)', color='#1f77b4', edgecolor='black', linewidth=0.8)
rects2 = ax.bar(x - 0.5*width, [bw/1000.0 for bw in ddr4_mixed_bw], width, label='DDR4-3200 (Mixed)', color='#aec7e8', edgecolor='black', linewidth=0.8, hatch='//')
rects3 = ax.bar(x + 0.5*width, [bw/1000.0 for bw in ddr5_benign_bw], width, label='DDR5-4800 (Benign)', color='#2ca02c', edgecolor='black', linewidth=0.8)
rects4 = ax.bar(x + 1.5*width, [bw/1000.0 for bw in ddr5_mixed_bw], width, label='DDR5-4800 (Mixed)', color='#98df8a', edgecolor='black', linewidth=0.8, hatch='\\\\')

ax.set_xlabel('Memory Channel Configuration')
ax.set_ylabel('Aggregated Throughput (GB/s)')
ax.set_title('Throughput Scaling: 1-CH, 2-CH, 4-CH, and 8-CH')
ax.set_xticks(x)
ax.set_xticklabels(['1-CH (Single)', '2-CH (Dual)', '4-CH (Quad)', '8-CH (Octa)'])
ax.legend(frameon=True, loc='upper left')

# Add value labels on top of bars
for rect in rects3 + rects4:
    h = rect.get_height()
    ax.annotate(f'{h:.1f}',
                xy=(rect.get_x() + rect.get_width() / 2, h),
                xytext=(0, 3), textcoords="offset points",
                ha='center', va='bottom', fontsize=7.5, fontweight='bold')

plt.tight_layout()
fig1_path_pdf = os.path.join(FIG_DIR, "bandwidth_scaling_multichannel.pdf")
fig1_path_png = os.path.join(FIG_DIR, "bandwidth_scaling_multichannel.png")
plt.savefig(fig1_path_pdf)
plt.savefig(fig1_path_png)
plt.close()
print(f"[+] Saved Figure 1: {fig1_path_pdf}")

#------------------------------------------------------------------------------
# Figure 2: Average Read Latency Reduction (ns)
#------------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(6.0, 3.8))

ax.plot(channels, ddr4_benign_lat, marker='o', linewidth=2.0, markersize=6, color='#1f77b4', label='DDR4-3200 (Benign)')
ax.plot(channels, ddr5_benign_lat, marker='s', linewidth=2.0, markersize=6, color='#2ca02c', label='DDR5-4800 (Benign)')

# Mixed Latency
ddr4_mixed_lat = [next(r["read_latency_ns"] for r in data if r["dram"] == "DDR4-3200" and r["workload"] == "Mixed" and r["channels"] == ch) for ch in channels]
ddr5_mixed_lat = [next(r["read_latency_ns"] for r in data if r["dram"] == "DDR5-4800" and r["workload"] == "Mixed" and r["channels"] == ch) for ch in channels]
ax.plot(channels, ddr4_mixed_lat, marker='^', linestyle='--', linewidth=1.8, markersize=6, color='#ff7f0e', label='DDR4-3200 (Mixed)')
ax.plot(channels, ddr5_mixed_lat, marker='d', linestyle='--', linewidth=1.8, markersize=6, color='#d62728', label='DDR5-4800 (Mixed)')

ax.set_xlabel('Number of Channels')
ax.set_ylabel('Average Read Latency (ns)')
ax.set_title('Queueing Contention Mitigation vs Channel Count')
ax.set_xticks(channels)
ax.set_xticklabels(['1-CH', '2-CH', '4-CH', '8-CH'])
ax.legend(frameon=True, loc='upper right')

for x_val, y_val in zip(channels, ddr5_benign_lat):
    ax.annotate(f'{y_val:.1f} ns', xy=(x_val, y_val), xytext=(0, 6), textcoords="offset points", ha='center', fontsize=8)

plt.tight_layout()
fig2_path_pdf = os.path.join(FIG_DIR, "latency_scaling_multichannel.pdf")
fig2_path_png = os.path.join(FIG_DIR, "latency_scaling_multichannel.png")
plt.savefig(fig2_path_pdf)
plt.savefig(fig2_path_png)
plt.close()
print(f"[+] Saved Figure 2: {fig2_path_pdf}")

print("[*] All publication figures generated successfully in paper/figures/")
