# Architectural Simulation & Benchmark Suite for Q-Shield

This directory contains 87 cycle-accurate command traces and simulation infrastructure for evaluating **Q-Shield** under benign and adversarial workloads on **Ramulator 2.0**.

Traces are generated from **SPEC CPU2017**, **PARSEC 3.0**, and synthetic attack patterns. Measurement protocol: $n=10$ runs per configuration, fixed seed 12345, 1M-cycle warmup, 10M-cycle measurement window.

---

## 📂 1. Directory Structure & Trace Metadata

```
sim/
├── traces/
│   ├── benign/         # 25 traces (SPEC CPU2017, PARSEC 3.0, YCSB)
│   ├── rowhammer/      # 20 traces (Double-sided, single-sided, many-sided)
│   ├── rowpress/       # 14 traces (tRAS holding stress)
│   ├── evasion/        # 10 traces (Frequency-domain & Blacksmith)
│   └── metadata.json   # Per-trace configuration and hash
├── results/            # Benchmark outputs and LaTeX tables
├── run_attack_emulation.py
├── run_benchmarks.py
└── generate_sota_comparison.py
```

### Trace Metadata Schema (`metadata.json`)
```json
{
  "name": "trace_benign_spec_mcf_ddr5_4800.txt",
  "workload_source": "SPEC CPU2017 mcf (ref run)",
  "attack_type": "benign",
  "dram_config": "DDR5-4800B",
  "num_commands": 47892154,
  "generation_seed": 12345,
  "verification_hash": "sha256:a1b2c3d4e5f6..."
}
```

---

## 🚀 2. How to Run Simulations

### Recommended Execution Order
1. **Quick Security Sanity Check (~2 minutes)**:
   ```bash
   python sim/run_attack_emulation.py
   ```
2. **Full Benchmark Suite (~45 minutes, n=10 runs)**:
   ```bash
   python sim/run_benchmarks.py --config config/benchmark_config.yaml --repeat 10
   ```
3. **Generate Multi-Tier Comparison Tables (~5 minutes)**:
   ```bash
   python sim/generate_sota_comparison.py
   ```

### Output Files Explanation
- `results/bench_metrics.csv`: Mean throughput, latency, and overhead ($n=10$ runs with 95% CI).
- `results/bench_metrics_detailed.csv`: Per-run raw measurements.
- `results/apples_to_apples_cycle_accurate.json` & `.tex`: Tier 1 direct comparisons on Ramulator2.
- `results/literature_reported_values.json` & `.tex`: Tier 2 contextual comparison (with disclaimers).
- `results/qualitative_taxonomy.json` & `.tex`: Tier 3 architectural feature matrix.

---

## 🔬 3. How Traces Were Generated

### Benign Traces (25 total)
- **SPEC CPU2017**: `mcf`, `lbm`, `cactuBSSN`, `gcc` (4 workloads, 3 runs each = 12 traces).
- **PARSEC 3.0**: `canneal`, `dedup`, `facesim` (3 workloads, 1 run each = 3 traces).
- **YCSB**: `uniform`, `zipfian` (2 workloads, 5 runs each = 10 traces).

```bash
python sim/traces/generate_benign_traces.py \
  --workloads mcf,lbm,canneal \
  --num_copies 3 \
  --seed 12345 \
  --output_dir sim/traces/benign/
```

### RowHammer Traces (20 total)
- Double-sided hammering: 8 traces.
- Single-sided hammering: 6 traces.
- Many-sided hammering (10+ aggressors): 6 traces.

```bash
python sim/traces/generate_rowhammer_traces.py \
  --attack_pattern double_sided \
  --hammer_frequency 8000 \
  --num_traces 20 \
  --seed 12345 \
  --output_dir sim/traces/rowhammer/
```

---

## ⚖️ 4. Benchmark Fairness & Comparison Methodology

### Apples-to-Apples Criteria (Tier 1)
- Same simulator: **Ramulator 2.0 (v2.0.1)**.
- Same DRAM configuration: **DDR5-4800B** (32 GB, 2 rank, 8 BG × 4 banks).
- Same memory traces: `trace_rowhammer_double_sided_ddr5_4800.txt`.
- Same measurement protocol: $n=10$ runs, fixed seed 12345.

*Only Tier 1 results are used for direct performance and speedup claims.*

### Why Tier 2 (Literature-Reported Values) is NOT Directly Comparable
- **BlockHammer (HPCA'21)** uses the USIMM simulator with a different timing model.
- **PRAC (ISCA'24)** includes in-DRAM die modifications ($+4.5\%$ die area), fundamentally altering the threat model.
- **PrISM (ISCA'26)** uses probabilistic sampling with non-zero false-negative rates.

*Tier 2 values are provided for architectural context only, not numerical claims.*
