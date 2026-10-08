# Q-Shield Experimental Reproducibility Guide

This guide provides instructions to reproduce all empirical findings, simulation figures, synthesis metrics, and formal verification proofs presented in the **Q-Shield** evaluation.

---

## 🚀 1. Quick Start: One-Command Validation

To execute the core hardware regression, attack emulation, and metric compilation:

```bash
# Clone and enter workspace
git clone https://github.com/quachtuanthanh80-arch/DRAM.git
cd DRAM

# 1. Install Python prerequisites
pip install -r requirements.txt

# 2. Run Master Hardware Regression Suite (14 testbenches)
python run_iverilog_regression.py

# 3. Run Attack Emulation & Defense Verification
python sim/run_attack_emulation.py

# 4. Generate Multi-Tier Benchmark Comparison Matrices
python sim/generate_sota_comparison.py
```

---

## 📦 2. Toolchain Requirements & Installation

| Tool / Framework | Minimum Version | Tested Version | Purpose in Evaluation |
| :--- | :---: | :---: | :--- |
| **Python** | 3.10 | 3.12 / 3.13 | Test automation, statistical processing, trace generation |
| **Icarus Verilog** | 12.0 | 12.0 | SystemVerilog unit and integration testbenches |
| **Verilator** | 5.020 | 5.032 | Cocotb E2E cycle-accurate C++ model compilation |
| **Cocotb** | 2.0.0 | 2.1.0 | Co-simulation verification test harness |
| **SymbiYosys (SBY)**| 0.38 | 0.69 | SVA formal property checking |
| **Z3 SMT Solver** | 4.8.12 | 4.12.2 | Formal verification constraint solving |
| **Yosys** | 0.38 | 0.52 | Open-source logic synthesis and tech mapping |
| **Ramulator 2.0** | 2.0 | 2.0 | Cycle-accurate architectural DRAM simulation |

---

## 🗺️ 3. Artifact Mapping: Paper Figures & Tables to Source Scripts

Every figure and table in the manuscript maps 1-to-1 to an execution script and output artifact:

| Paper Item | Description | Generating Script | Output Artifact |
| :--- | :--- | :--- | :--- |
| **Figure 1** | Microarchitectural Block Pipeline | `paper/figures/fig_arch_overview.tex` | `paper/figures/fig_arch_overview.pdf` |
| **Figure 2** | Inter-BG Timing Slack Matrix | `paper/figures/fig2_inter_bg_slack_matrix.tex` | `paper/figures/fig2_inter_bg_slack_matrix.pdf` |
| **Figure 3** | RowPress FPR and Resilience | `paper/figures/fig7_rowpress_fpr_resilience.tex` | `paper/figures/fig7_rowpress_fpr_resilience.pdf` |
| **Figure 4** | SEC-DED SDC Bit-Flip Recovery | `paper/figures/fig5_secded_sdc_resilience.tex` | `paper/figures/fig5_secded_sdc_resilience.pdf` |
| **Figure 5** | Double-Bit Detection Matrix | `paper/figures/plot_template_figures.py` | `paper/figures/plot2_double_bit_matrix.pdf` |
| **Figure 6** | Multi-PDK PPA Scaling | `paper/figures/fig6_multi_pdk_ppa_scaling.tex` | `paper/figures/fig6_multi_pdk_ppa_scaling.pdf` |
| **Figure 7** | Multi-Tenant Throughput under Attack | `paper/figures/fig1_multitenant_throughput.tex` | `paper/figures/fig1_multitenant_throughput.pdf` |
| **Figure 8** | Multi-Channel Bandwidth Scaling | `paper/figures/fig3_multichannel_scaling.tex` | `paper/figures/fig3_multichannel_scaling.pdf` |
| **Figure 9** | Gate Count Comparison | `paper/figures/fig4_related_work_comparison.tex` | `paper/figures/fig4_related_work_comparison.pdf` |
| **Figure 10**| Formal BMC & Induction Convergence | `paper/figures/fig8_formal_bmc_convergence.tex` | `paper/figures/fig8_formal_bmc_convergence.pdf` |
| **Table I** | Multi-PDK ASIC PPA Comparison | [`synth/asic/scripts/generate_multi_pdk_ppa_report.py`](synth/asic/scripts/generate_multi_pdk_ppa_report.py) | `synth/asic/reports/multi_pdk_ppa_comparison.md` |
| **Table II** | Subsystem Gate Breakdown | [`synth/asic/reports/`](synth/asic/reports/) | `synth/asic/reports/axi_ddr5_mc_top_asic_ppa_summary.json` |
| **Table III**| Cycle-Accurate Ramulator2 Matrix | [`sim/run_benchmarks.py`](sim/run_benchmarks.py) | `sim/results/bench_summary.json` |
| **Table IV** | Qualitative Taxonomy Comparison | [`sim/generate_sota_comparison.py`](sim/generate_sota_comparison.py) | `sim/results/qualitative_taxonomy.json` |

---

## 🔍 4. Step-by-Step Reproduction Instructions

### Step 1: Hardware Unit & Integration Regression
```bash
python run_iverilog_regression.py
```
- **Expected Outcome**: 14/14 testbenches pass with zero fatal assertion errors.
- **Verification Log**: Inspect `regression_summary.json` and `regression_logs/`.

### Step 2: Full End-to-End Cocotb Verification
```bash
python run_all_tests.py
```
- **Expected Outcome**: All 20 Cocotb test suites complete successfully.
- **Verification Log**: Inspect `ci_test_summary.json`.

### Step 3: Formal Mathematical Invariant Proofs
```bash
cd formal
bash run_all_formal.sh
```
- **Expected Outcome**: 11 formal properties proved with zero counter-examples.
- **Verification Log**: Inspect `formal/reports/summary.json`.

### Step 4: Architectural Benchmark Sweep
```bash
python sim/run_benchmarks.py --config all --repeat 10 --seed 12345
```
- **Expected Outcome**: Produces `sim/results/bench_metrics.csv` and `sim/results/bench_summary.json`.

---

## ⏱️ 5. Runtime Expectations & Machine Hardware Profiles

### Minimal Example (`run_minimal_example.py`)
- **Expected Runtime**: **~8 seconds** (Wall-clock time on reference machine).
- **Reference Host**: Intel Core i7-10700K / AMD Ryzen 7 5800X, 16 GB DDR4/DDR5 RAM, NVMe SSD, Ubuntu 22.04 LTS.
- **Docker Footprint**: ~2.5 GB (fresh container build with pinned compiler toolchains).

#### Detailed Timing Breakdown:
| Sub-Stage | Description | Reference Host | Older CPU / HDD | GitHub Actions Runner |
| :--- | :--- | :---: | :---: | :---: |
| **Formal Quick Proof** | SymbiYosys Single Property (P2) | 1.8 s | 4.5 s | 2.5 s |
| **RTL Unit Sanity** | Icarus Verilog FSM & Skid Buffer | 2.7 s | 6.2 s | 3.5 s |
| **Benchmark Trace** | Single-Channel DDR5 1M-Command Run | 2.1 s | 5.8 s | 2.8 s |
| **Golden Output Diff** | Numerical & Checksum Tolerance Check | 0.8 s | 1.5 s | 1.0 s |
| **Total Wall-Clock** | Complete Environment Sanity Gate | **~7.4 s** | **~18.0 s** | **~9.8 s** |

*Note*: Full 20-suite regression (`python run_all_tests.py`) runs in ~1.5–2.0 minutes; complete multi-workload benchmark sweep (`python sim/run_benchmarks.py --config all`) runs in ~8–12 minutes.
