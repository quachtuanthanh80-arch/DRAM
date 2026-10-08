# Golden Reference Outputs & Validation Dataset

This directory contains deterministic, verified golden reference outputs generated from the Q-Shield verification, architectural simulation, and synthesis regression pipelines. Reviewers and researchers can compare their local run outputs directly against these baseline artifacts.

---

## 1. Golden Artifact Inventory

| File | Source Stage | Description |
| :--- | :--- | :--- |
| [`regression_summary.json`](regression_summary.json) | RTL Simulation (Icarus / Verilator) | 14 synthesizable SystemVerilog unit tests across DDR4/DDR5 FSMs, skid buffers, SEC-DED, and dual-hash filter. |
| [`attack_emulation_summary.json`](attack_emulation_summary.json) | Trace Security Emulation | Defense mitigation metrics across 6 attack and benign traces (bit-flips prevented, false positive rate). |
| [`bench_summary.json`](bench_summary.json) | Architectural Benchmarking | Statistical performance (mean ± σ, n = 10 runs) across 18 memory configurations and workload classes. |
| [`bench_metrics.csv`](bench_metrics.csv) | Architectural Benchmarking | Raw sample-by-sample run data (180 data points) including throughput, latency, and stall rates. |
| [`apples_to_apples_cycle_accurate.json`](apples_to_apples_cycle_accurate.json) | SOTA Comparison Tier 1 | Direct cycle-accurate Ramulator2 comparison against baseline FR-FCFS under identical DDR5-4800 parameters. |
| [`literature_reported_values.json`](literature_reported_values.json) | SOTA Comparison Tier 2 | Cross-study comparison against published metrics (BlockHammer, AQUA, PRAC, PrISM) with explicit methodology caveats. |
| [`qualitative_taxonomy.json`](qualitative_taxonomy.json) | SOTA Comparison Tier 3 | Architectural defense mechanisms, threat model boundaries, and silicon overhead trade-offs. |
| [`lifecycle_validation_summary.json`](lifecycle_validation_summary.json) | Lifecycle Pipeline | End-to-end verification summary verifying RTL, security emulation, benchmarks, and SOTA generation. |

---

## 2. Automated Golden Verification

To verify that local execution matches the golden references within numerical tolerance:

```bash
# Verify using the automated verification utility (numerical tolerance <= 1%)
python tools/verify_golden_outputs.py

# Verify SHA256 integrity of golden files
sha256sum -c GOLDEN_OUTPUTS/checksums.sha256
```

