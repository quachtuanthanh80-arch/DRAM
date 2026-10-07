# Architectural Simulation & Benchmark Suite for Q-Shield
# Cycle-accurate workload evaluation, attack emulation, and SOTA comparison matrix.

## Overview

This directory provides the simulation infrastructure and 87 formatted command traces evaluating Q-Shield under benign and hostile memory workloads.

## Directory Structure

- `traces/`: 87 cycle-accurate address/command traces:
  - 28 Benign traces (SPEC CPU2017 `mcf`, `lbm`, `omnetpp`, `gcc`, and YCSB workloads across 1 to 8 channels).
  - 28 RowHammer adversarial traces (Single-sided, double-sided alternating patterns).
  - 28 Mixed multi-tenant traces (co-located benign and attacking tenants).
  - 3 Synthetic calibration traces (`cmd_trace.txt.ch0`, `trace_ddr5_6000.txt`, `trace_synthetic_mixed.txt`).
- `results/`: 21 benchmark data outputs in CSV, JSON, and LaTeX formats.

## How to Run Simulations

### 1. Hardware Security & Attack Emulation Audit
Runs Q-Shield's dual-hash SDC filter, ATE rate pacing, and DRM against Blacksmith, RowPress, and RowHammer:
```bash
python sim/run_attack_emulation.py
```
Outputs: `results/attack_emulation_summary.json`, `results/attack_emulation_report.md`.

### 2. SOTA Matrix Generation (Literature vs Cycle-Accurate)
Generates the comparison tables across 10 architectures (Baseline, BlockHammer, Graphene, AQUA, Rubix, PRAC, DREAM, QPRAC, PrISM, Q-Shield):
```bash
python sim/generate_sota_comparison.py
```
Outputs: `results/tab_sota_architectural_taxonomy.tex`, `results/tab_ramulator2_apples_to_apples.tex`, `results/tab_literature_reported_comparison.tex`.

### 3. Ramulator2 End-to-End Benchmark Suite
Requires local Ramulator2 installation (`/home/thanh/ramulator2` or environment path):
```bash
python sim/run_benchmarks.py
```
Outputs: `results/benchmark_results.csv`, `results/ramulator2_apples_to_apples.json`.
