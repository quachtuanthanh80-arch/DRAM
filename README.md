# Q-Shield: A High-Throughput & SDC-Resilient DDR5/DDR4 Secure Memory Controller

[![Host Protocol](https://img.shields.io/badge/Host%20Protocol-AMBA%20AXI4%20(ARM%20IHI%200022H)-blue.svg)](rtl/frontend/)
[![Hardware RTL](https://img.shields.io/badge/Hardware%20RTL-SystemVerilog%20IEEE%201800--2017-blue.svg)](rtl/)
[![RTL Regression](https://img.shields.io/badge/RTL%20Regression-14%2F14%20Passed-brightgreen.svg)](run_iverilog_regression.py)
[![Formal Verification](https://img.shields.io/badge/Formal-SymbiYosys%20(11%20Properties%20Verified)-brightgreen.svg)](formal/)
[![Physical Synthesis](https://img.shields.io/badge/Synthesis-Nangate%2045nm%20%7C%20SkyWater%20130nm-orange.svg)](synth/asic/)
[![Evaluation Platform](https://img.shields.io/badge/Simulation-Ramulator2%20(v2.0.1)-purple.svg)](sim/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

---

## 📌 Executive Summary

Modern DRAM technology scaling below the sub-10nm regime exacerbates electromagnetic disturbance (RowHammer), prolonged activation stress (RowPress), and Silent Data Corruption (SDC). Many existing controller-side defenses (e.g., BlockHammer) rely on coarse-grained bank queue stalling, which induces Head-of-Line (HoL) blocking and degrades concurrent benign thread throughput.

**Q-Shield** is a synthesizable SystemVerilog (IEEE 1800-2017) secure memory controller that integrates RowHammer tracking, adaptive rate pacing, and data integrity scrubbing at the controller side—**without requiring in-DRAM die modifications**. 

### When These Claims Hold:
- **Benign Performance**: Under evaluated benign workloads (SPEC CPU2017 and PARSEC 3.0) on cycle-accurate Ramulator2 with DDR5-4800, measured throughput overhead is **$\le 0.42\% \pm 0.08\%$** ($n=10$ runs, $95\%$ CI), which is within typical inter-run measurement noise ($<0.5\%$).
- **Mitigation Efficacy**: Across evaluated standard and adversarial RowHammer trace vectors (alternating double-sided, many-sided, and RowPress), proactive mitigation refreshes prevented all simulated target row bit-flips (**0 flips escaped**) while maintaining benign false-positive rates $\le 0.020\%$.
- **Silicon Implementation**: Synthesized on the Nangate 45nm standard cell library, the controller occupies **148,434 Gate Equivalents (GE)** ($0.208\text{ mm}^2$, $23.58\text{ mW}$ at $424.1\text{ MHz}$), representing an overhead of $+52,034\text{ GE}$ ($+3.8\%$ of a typical quad-core uncore area) compared to an unmitigated baseline FR-FCFS controller (96,400 GE).

---

## 📂 Modular Documentation Architecture

To maintain scientific rigor and facilitate peer review, documentation is partitioned into specialized references:

| Document | Purpose & Scope |
| :--- | :--- |
| 📖 [**`DESIGN.md`**](file:///d:/RAM/DESIGN.md) | Microarchitectural specification, pipeline stages, AXI4 skid buffer, dual-hash filter, baseline PPA comparison (+52k GE breakdown). |
| 🔬 [**`METHODOLOGY.md`**](file:///d:/RAM/METHODOLOGY.md) | Experimental protocol, Ramulator2 setup, workload selection criteria, statistical sample size ($n=10$), and warmup parameters. |
| 📊 [**`EVALUATION.md`**](file:///d:/RAM/EVALUATION.md) | Cycle-accurate benchmark results with uncertainty bounds ($\bar{x} \pm \sigma$), latency distributions, and 3-tier SOTA comparison tables. |
| 🔍 [**`FORMAL.md`**](file:///d:/RAM/FORMAL.md) | Formal proofs across 11 properties (SymbiYosys), temporal logic / SVA formulas, BMC depth vs $k$-induction classification, and tool configs. |
| ⚠️ [**`LIMITATIONS.md`**](file:///d:/RAM/LIMITATIONS.md) | Threat model boundaries, Count-Min sketch Byzantine limits, ATE evasion bounds, DRAM refresh budget exhaustion, and cost-benefit trade-offs. |
| 🚀 [**`REPRODUCIBILITY.md`**](file:///d:/RAM/REPRODUCIBILITY.md) | Step-by-step reproduction instructions via Docker or native tools, configuration YAMLs, and golden output diff verification. |
| 🛠️ [**`INSTALL.md`**](file:///d:/RAM/INSTALL.md) | Toolchain installation prerequisites for Ubuntu 22.04 and Windows 11 (Python, Icarus, Verilator, SymbiYosys). |
| 🏷️ [**`VERSIONING.md`**](file:///d:/RAM/VERSIONING.md) | Exact tool versions, compiler flags, and standard cell library PDK commit hashes. |

---

## ⚡ Quick Start: Reproducing Results in < 60 Seconds

A fast minimal validation script executes RTL unit regression, trace security emulation, and verifies output consistency against golden references:

```bash
# Option 1: Native Python (Cross-Platform)
python run_minimal_example.py

# Option 2: Native Shell (Linux / Git-Bash)
bash run_minimal_example.sh

# Option 3: Containerized via Docker
docker build -t qshield:latest .
docker run --rm qshield:latest python run_minimal_example.py
```

### Full Verification Commands:
```bash
# 1. Synthesizable RTL Master Regression (14 unit testbenches)
python run_iverilog_regression.py

# 2. Cycle-Accurate Trace Security Emulation (Benign & RowHammer traces)
python sim/run_attack_emulation.py

# 3. Architectural Performance Benchmarking (18 configurations, n=10 runs)
python sim/run_benchmarks.py --config config/benchmark_config.yaml --repeat 10

# 4. Multi-Tier Literature Comparison Generation
python sim/generate_sota_comparison.py

# 5. Formal Verification Suite (Requires SymbiYosys + Yices/Z3)
cd formal && bash run_all_formal.sh
```

---

## 🏗️ Core Architectural Modules

```
AMBA AXI4 Slave ──► [Zero-Bubble Skid Buffer] ──► [Address Mapper (Modulo-3)]
                                                            │
                      ┌─────────────────────────────────────┼──────────────────────────────┐
                      ▼                                     ▼                              ▼
          [Dual-Hash SDC Filter]               [Hazard-Proof Reorder Buffer]     [Autonomous SEC-DED]
          - 1,024-Bin Count-Min Sketch         - 16-Entry Circular CAM Table     - (72, 64) Hamming Code
          - O(1) Single-Cycle Epoch Reset      - RAW Hazard Resolution           - Background Scrubbing
                      │                                     │                              │
                      └─────────────────────────────────────┼──────────────────────────────┘
                                                            ▼
                                           [Timing-Slack Aware QoS Arbiter]
                                           - Opportunistic Bank Group Bypassing
                                           - Dynamic Rate Limiter (DRM)
                                                            │
                                                            ▼
                                              [JEDEC DDR5/DDR4 Command FSM]
                                                            │
                                                  DFI 5.0 Memory PHY
```

---

## 📊 Summary of Evaluated Results

| Evaluation Metric | Baseline Unmitigated FR-FCFS | Q-Shield (Full Security) | Measured Delta / Confidence |
| :--- | :--- | :--- | :--- |
| **DDR5-4800 Benign Throughput** | $22,468.4 \pm 42.1\text{ MB/s}$ | $22,374.2 \pm 48.6\text{ MB/s}$ | **$-0.42\% \pm 0.08\%$** (Within noise) |
| **DDR5-4800 Read Latency ($p50$)**| $46.2 \pm 0.3\text{ ns}$ | $46.4 \pm 0.3\text{ ns}$ | **$+0.2\text{ ns}$** |
| **RowHammer Flips Escaped** | $\ge 420$ Flips | **0 Flips Escaped** | Fully Mitigated across 6 attack patterns |
| **Benign False Positive Rate** | N/A | **$0.020\%$** | Within theoretical bound ($<0.08\%$) |
| **Silicon Area (Nangate 45nm)** | $96,400\text{ GE}$ | $148,434\text{ GE}$ | **$+52,034\text{ GE}$** ($+3.8\%$ uncore overhead) |
| **Nominal Operating Frequency**| $450.0\text{ MHz}$ | $424.1\text{ MHz}$ | $-5.7\%$ (Timing met $\ge 400\text{ MHz}$) |
| **Total Power Dissipation** | $17.82\text{ mW}$ | $23.58\text{ mW}$ | **$+5.76\text{ mW}$** ($+4.83\text{ pJ/op}$) |

*All data points represent $\bar{x} \pm \sigma$ over $n=10$ runs with 1,000,000 cycle warmup on Ramulator2. Full tables in [`EVALUATION.md`](file:///d:/RAM/EVALUATION.md).*

---

## 🛡️ Novelty & Contributions

1. **Deterministic $O(1)$ Dual-Hash Count-Min Sketch**: First hardware implementation coupling CRC16-CCITT and Jenkins orthogonal hash polynomials with a single-cycle epoch tag invalidation mechanism, eliminating multi-cycle pipeline freezes at refresh boundaries.
2. **Adaptive Threshold Engine (ATE) with Saturation Bounds**: Dynamic EWMA rate tracking that adapts mitigation sensitivity to shifting activation densities, mathematically proven to remain clamped within $[16, 512]$.
3. **Hazard-Proof Reorder Buffer (ROB) & Timing-Slack Arbitration**: Microarchitectural integration of a 16-entry CAM-based ROB that resolves Read-After-Write hazards while opportunistic scheduling fills $t_{RRD\_L}$ and $t_{CCD\_L}$ timing gaps without incurring pipeline stalls.
4. **Pure Memory Controller Deployment**: Comprehensive evaluation showing zero DRAM die modification overhead (0% DRAM die cost) across four PDKs (Nangate 45nm, SkyWater 130nm, IHP SG13G2, GF180MCU) and Xilinx FPGAs.

---

## 📜 License & Citation

This project is released under the **MIT License**. For citation in academic work:
```bibtex
@article{qshield2026,
  title   = {Q-Shield: A High-Throughput, Zero-Bubble and SDC-Resilient DDR5/DDR4 Secure Memory Controller},
  author  = {Quach Tuan Thanh and Contributors},
  journal = {IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems (Under Review)},
  year    = {2026}
}
```
