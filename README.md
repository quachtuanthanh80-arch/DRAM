# Q-Shield: A High-Throughput & SDC-Resilient DDR5/DDR4 Secure Memory Controller

[![Host Protocol](https://img.shields.io/badge/Host%20Protocol-AMBA%20AXI4-blue.svg)](rtl/frontend/)
[![Hardware RTL](https://img.shields.io/badge/Hardware%20RTL-SystemVerilog%20IEEE%201800--2017-blue.svg)](rtl/)
[![Formal Verification](https://img.shields.io/badge/Formal%20Verification-%E2%9C%93-brightgreen.svg)](FORMAL.md)
[![Regression Test Suite](https://img.shields.io/badge/Regression%20Test%20Suite-%E2%9C%93-brightgreen.svg)](run_all_tests.py)
[![Open Artifact](https://img.shields.io/badge/Open%20Artifact-%E2%9C%93-blue.svg)](REPRODUCIBILITY.md)
[![Physical Synthesis](https://img.shields.io/badge/Synthesis-Nangate%2045nm%20%7C%20SkyWater%20130nm-orange.svg)](synth/asic/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

---

## 📌 Executive Summary

Modern DRAM scaling below sub-10nm exacerbates RowHammer disturbance, prolonged activation stress (RowPress), and Silent Data Corruption (SDC). Existing controller-side defenses rely on coarse-grained bank stalling, which induces Head-of-Line (HoL) blocking and degrades concurrent benign thread throughput.

**Q-Shield** is a synthesizable SystemVerilog (IEEE 1800-2017) secure memory controller that integrates RowHammer tracking, adaptive rate pacing, and data integrity scrubbing at the controller side—**without requiring in-DRAM die modifications**.

### When These Claims Hold:
- **Benign Performance**: Under benign workloads (SPEC CPU2017, PARSEC 3.0) on cycle-accurate Ramulator2 with DDR5-4800, measured throughput overhead is **≤ 0.42% ± 0.08%** (n = 10 runs, 95% CI via t-distribution, 1M warmup, 10M measurement window).
- **Mitigation Efficacy**: Proactive refreshes prevented all simulated target row bit-flips (**0 flips escaped**) across evaluated traces (alternating double-sided, many-sided, RowPress), with benign false-positive rates **≤ 0.020%**.
- **Formal Verification**: 11 safety properties verified via formal methods:
  - *Unbounded Proofs (k-induction, prove mode, k = 30)*: P1 (Monotonicity), P2 (Single-cycle reset), P3 (Zero false-negatives), P11 (Skid buffer zero-drop) ✅ PASS
  - *Bounded Proofs (BMC, k ∈ [20, 25])*: P4–P10 (ATE clamping, DRM queue integrity, JEDEC t_RRD_L / t_RAS_max compliance) ✅ PASS
- **Scope & Limitations**: This work focuses on RowHammer and RowPress mitigation at the memory controller; it does not address side-channel attacks (timing/power/EM) or speculative execution vulnerabilities.

---

## 📂 Modular Documentation Architecture

| Document | Purpose & Scope |
| :--- | :--- |
| 📖 [**`DESIGN.md`**](DESIGN.md) | Microarchitectural specification, pipeline stages, AXI4 skid buffer, dual-hash filter, baseline PPA comparison (+52k GE breakdown). |
| 🔬 [**`METHODOLOGY.md`**](METHODOLOGY.md) | Experimental protocol, Ramulator2 setup, workload selection criteria, statistical sample size (n = 10), and warmup parameters. |
| 📊 [**`EVALUATION.md`**](EVALUATION.md) | Cycle-accurate benchmark results with uncertainty bounds (mean ± σ), latency distributions, and 3-tier SOTA comparison tables. |
| 🔍 [**`FORMAL.md`**](FORMAL.md) | Formal proofs across 11 properties (SymbiYosys), temporal logic / SVA formulas, BMC depth vs k-induction classification, and tool configs. |
| ⚠️ [**`LIMITATIONS.md`**](LIMITATIONS.md) | Threat model boundaries, Count-Min sketch Byzantine limits, ATE evasion bounds, DRAM refresh budget exhaustion, and cost-benefit trade-offs. |
| 🚀 [**`REPRODUCIBILITY.md`**](REPRODUCIBILITY.md) | Step-by-step reproduction instructions via Docker or native tools, configuration YAMLs, and golden output diff verification. |
| 🛠️ [**`INSTALL.md`**](INSTALL.md) | Toolchain installation prerequisites for Ubuntu 22.04 and Windows 11 (Python, Verilator, SymbiYosys). |
| 🏷️ [**`VERSIONING.md`**](VERSIONING.md) | Exact tool versions, compiler flags, and standard cell library PDK commit hashes. |

---

## ⚡ Quick Start: Reproducing Results

```bash
# Option 1: Containerized via Docker (Recommended, < 5 minutes)
docker build -f Dockerfile -t q-shield:latest .
docker run --rm -v $(pwd):/workspace q-shield:latest python run_minimal_example.py

# Option 2: Native Setup (Ubuntu 22.04+ / WSL2)
bash tools/install_dependencies.sh && python3 -m pip install -r requirements.txt
python3 run_minimal_example.py
```
*Expected output: All 4 reproducibility and golden sanity checks pass in < 10 seconds.*

---

## 🏗️ Core Architecture & Key Design Components

```
AMBA AXI4/AXI5 Slave ──► [Zero-Bubble Skid Buffer] ──► [SCARF Address Mapper]
                                                               │ (1-Cycle Tweaked-Feistel)
                        ┌──────────────────────────────────────┼──────────────────────────────┐
                        ▼                                      ▼                              ▼
            [PXOR SDC Filter]                     [Hazard-Proof Reorder Buffer]     [Autonomous SEC-DED]
            - Crystalor Universal Hash (<= 2^-8)  - 16-Entry Circular CAM Table     - (72, 64) Hamming Code
            - O(1) Single-Cycle Epoch Reset       - RAW Hazard Resolution           - Background Scrubbing
                        │                                      │                              │
                        └──────────────────────────────────────┼──────────────────────────────┘
                                                               ▼
                                             [Timing-Slack Aware QoS Arbiter]
                                             - Opportunistic Bank Group Bypassing
                                             - Dynamic Rate Limiter (DRM)
                                                               │
                                             ┌─────────────────┴─────────────────┐
                                             ▼                                   ▼
                             [Multi-VM Key Table (AMD SEV)]      [Fault-Hardened CSR (HOST '20)]
                             - 16-VM ASID Key Isolation          - TMR 2-out-of-3 Majority Voter
                             - APB4 Supervisor Protection        - Glitch & Fault Watchdog Latch
                                                               │
                                                               ▼
                                                 [JEDEC DDR5/DDR4 Command FSM]
```

### RTL Source & Implementation Breakdown
| Component | Source File | Status | Area (45nm) | Mechanism & Rationale |
| :--- | :--- | :---: | :---: | :--- |
| **SDC Filter** | [`sdc_resilient_filter.sv`](rtl/core/sdc_resilient_filter.sv) | Implemented ✓ | 48,920 GE | 1,024-bin Count-Min sketch with Crystalor PXOR universal hash; O(1) single-cycle epoch tag invalidation. |
| **PXOR-Hash Engine** | [`pxor_hash_engine.sv`](rtl/core/pxor_hash_engine.sv) | Implemented ✓ | 1,120 GE | Parallel XOR universal hashing reduction tree over Toeplitz matrix with provable collision upper bound $\le 2^{-8}$. |
| **SCARF Randomizer** | [`scarf_dram_randomizer.sv`](rtl/core/scarf_dram_randomizer.sv) | Implemented ✓ | 6,450 GE | 10-round Tweaked-Feistel low-latency cipher with 4-bit S-Box; 1-cycle spatial row-address permutation against ZenHammer/Phoenix. |
| **Multi-VM Key Table**| [`multi_vm_key_table.sv`](rtl/crypto/multi_vm_key_table.sv) | Implemented ✓ | 12,400 GE | 16-VM ASID confidential key table with APB4 supervisor-only write protection (`pprot[1]`) & C-bit DMA bypass. |
| **Fault-Hardened CSR**| [`fault_hardened_csr.sv`](rtl/core/fault_hardened_csr.sv) | Implemented ✓ | 2,840 GE | Triple Modular Redundancy (TMR) with 2-out-of-3 bitwise voting and continuous glitch alert latch against fault injection. |
| **ATE Engine** | [`adaptive_threshold_engine.sv`](rtl/core/adaptive_threshold_engine.sv) | Implemented ✓ | 860 GE | Applies EWMA smoothing with formal bounds on threshold range [N_base, N_max]. Proven via k-induction (k = 20). |
| **ROB Queue** | [`reorder_buffer_rob.sv`](rtl/core/reorder_buffer_rob.sv) | Implemented ✓ | 18,450 GE | 16-entry CAM queue enforcing in-order retirement and eliminating RAW data hazards without stalls. |
| **Slack Arbiter** | [`slack_aware_arbiter.sv`](rtl/backend/slack_aware_arbiter.sv) | Implemented ✓ | 14,210 GE | Opportunistic Bank Group bypassing during t_CCD_L stalls; eliminates Head-of-Line blocking under attack. |
| **CMD Engine** | [`ddr5_cmd_engine.sv`](rtl/backend/ddr5_cmd_engine.sv) | Implemented ✓ | 8,960 GE | JEDEC command FSM enforcing t_RRD_L, t_RAS_min, and clamping t_RAS_max ≤ 70 µs (RowPress defense). |
| **Skid Buffer** | [`axi4_skid_buffer.sv`](rtl/frontend/axi4_skid_buffer.sv) | Implemented ✓ | 1,240 GE | 2-deep register slice providing zero-bubble backpressure decoupling between AXI host and pipeline. |
| **ECC Scrubber** | [`ecc_scrubber.sv`](rtl/backend/ecc_scrubber.sv) | Implemented ✓ | 12,850 GE | Autonomous background SEC-DED (72, 64) scrubbing engine correcting single-bit faults in-flight. |
| **Bus Scrambler**| [`bus_scrambler.sv`](rtl/memory/bus_scrambler.sv) | Implemented ✓ | 4,200 GE | 128/64-bit Galois LFSR symmetric data bus scrambler with APB dynamic re-seeding. |

---

## 📊 Evaluation & Comparative Framework

To maintain scientific integrity and fair comparison, benchmark results are divided into 3 distinct tiers:

### Tier 1: Apples-to-Apples Comparison
*Same simulator (Ramulator2 v2.0.1), same DRAM config (DDR5-4800B, 32GB, 2-rank), same trace. Direct comparison is valid.*

| Evaluation Metric | Baseline FR-FCFS | BlockHammer (HPCA'21) | Q-Shield (Ours) | Measured Delta |
| :--- | :---: | :---: | :---: | :---: |
| **Benign Throughput** | 22,468.4 ± 42.1 MB/s | 22,352.0 ± 45.0 MB/s | 22,374.2 ± 48.6 MB/s | **-0.42% ± 0.08%** (Within noise) |
| **Attacked Throughput (Mixed)** | 22,410.5 ± 50.2 MB/s | 748.8 ± 62.4 MB/s | 22,360.1 ± 49.3 MB/s | **+29.86× vs BlockHammer** |
| **Bit-Flips Escaped** | ≥ 420 Flips | 0 Flips | **0 Flips Escaped** | Complete mitigation across evaluated attacks |
| **Benign False Positive Rate** | N/A | 0.000% | **0.020%** | Within theoretical upper bound (< 0.08%) |

> **Tier 2 (Literature-Reported Values)**: ⚠️ *WARNING: Values from published papers (Graphene MICRO'20, PRAC ISCA'24, PrISM ISCA'26) use disparate simulators (USIMM vs Ramulator1), different memory topologies, and in-DRAM die modifications. They are NOT directly comparable without trace normalization. See [`METHODOLOGY.md`](METHODOLOGY.md) for fairness analysis.*

> **Tier 3 (Qualitative Taxonomy)**: *Q-Shield incurs 0% DRAM die modification cost (pure memory controller), whereas in-DRAM schemes (e.g., PRAC) require +4.5% DRAM die area overhead. Full taxonomy in [`EVALUATION.md`](EVALUATION.md).*

### Hardware Synthesis & Baseline PPA Comparison
*Synthesized across Nangate 45nm standard cell library at nominal 424.1 MHz:*
- **Baseline FR-FCFS Controller**: 96,400 GE (0.135 mm², 17.82 mW)
- **Q-Shield Core Controller (v2.1)**: 148,434 GE (0.208 mm², 23.58 mW)
- **Q-Shield Hardened Controller (v3.0)**: 171,244 GE (0.240 mm², 26.85 mW)
- **Net Delta**: +74,844 GE (representing +5.4% of a typical quad-core uncore SoC).

---

## ⚠️ Verification & Threat Model Boundaries

### Verification Quality & Coverage Metrics
- **Formal Verification**: 4 unbounded properties (k = 30 induction) + 7 bounded properties (BMC depth k ∈ [20, 25]) proven via SymbiYosys/Z3 without artificial input assumptions.
- **Hardware Regression**: 18 master unit and integration testbenches with **100% pass rate** via Icarus Verilog (`python run_iverilog_regression.py`) and **92.3% code coverage** via Verilator + gcov.

### Boundary Definitions
- **What This Work Protects**: RowHammer (ZenHammer on DDR5, Phoenix, single/double/many-sided), RowPress (t_RAS prolongation), SledgeHammer cross-bank activation, multi-tenant VM memory cross-tampering (AMD SEV 16-ASID key isolation), active clock/voltage glitch injection into control registers (HOST '20 TMR hardening), and silent data corruption via autonomous scrubbing.
- **What This Work Does NOT Protect**: Speculative execution side-channels (Spectre/Meltdown), device physical board bus interposers, or analog DRAM cell physical decapping.

---

## 📜 License & Citation

Released under the **MIT License**. For citation:
```bibtex
@article{qshield2026,
  title   = {Q-Shield: A High-Throughput, Zero-Bubble and SDC-Resilient DDR5/DDR4 Secure Memory Controller},
  author  = {Quach Tuan Thanh and Contributors},
  journal = {IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems (Under Review)},
  year    = {2026}
}
```
