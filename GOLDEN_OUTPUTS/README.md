# Golden Reference Outputs & Validation Dataset

This directory contains deterministic, verified golden reference outputs generated from the Q-Shield verification, architectural simulation, and synthesis regression pipelines. Reviewers and researchers can compare their local run outputs directly against these baseline artifacts.

---

## 1. Golden Artifact Inventory

| File | Source Stage | Description |
| :--- | :--- | :--- |
| [`regression_summary.json`](regression_summary.json) | RTL Simulation (Icarus / Verilator) | 14 synthesizable SystemVerilog unit tests across DDR4/DDR5 FSMs, skid buffers, SEC-DED, and dual-hash filter. |
| [`attack_emulation_summary.json`](attack_emulation_summary.json) | Trace Security Emulation | Defense mitigation metrics across 6 attack and benign traces (bit-flips prevented, false positive rate). |
| [`literature_reported_values.json`](literature_reported_values.json) | SOTA Comparison Tier 2 | Cross-study comparison against published metrics (BlockHammer, AQUA, PRAC, PrISM) with explicit methodology caveats. |
| [`qualitative_taxonomy.json`](qualitative_taxonomy.json) | SOTA Comparison Tier 3 | Architectural defense mechanisms, threat model boundaries, and silicon overhead trade-offs. |
| [`lifecycle_validation_summary.json`](lifecycle_validation_summary.json) | Lifecycle Pipeline | End-to-end verification summary verifying RTL, security emulation, benchmarks, and SOTA generation. |

> Removed 2026-10-30: `bench_summary.json`, `bench_metrics.csv` and `apples_to_apples_cycle_accurate.json`. The first two
> came from the "calibrated model" branch of `sim/run_benchmarks.py` (hard-coded bandwidth tables plus ±0.8% random
> noise, generated on Windows without Ramulator); the third was a hard-coded table labelled as a Ramulator 2 run.
> See `sim/results/PROVENANCE.md`.

---

## 2. Automated Golden Verification

To verify that local execution matches the golden references within numerical tolerance:

```bash
# Verify using the automated verification utility (numerical tolerance <= 1%)
python tools/verify_golden_outputs.py

# Verify SHA256 integrity of golden files
sha256sum -c GOLDEN_OUTPUTS/checksums.sha256
```

