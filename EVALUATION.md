# Q-Shield Evaluation: Status and Protocol

This document separates **what has been measured** from **what has not**. Earlier versions of this file contained
throughput-overhead tables, a security-efficacy table ("0 escaped bit-flips") and a comparison against published
defenses. Those tables were **withdrawn** because the repository did not contain the runs that produce them. The
evaluation has since been re-run from scratch (tasks T80 to T92); the results below replace the withdrawn tables.
Every number links to a report file in this repository. Results are **model and simulation results**, not
measurements on a fabricated chip or on real DRAM.

## 1. What has been measured

| Quantity | Result | Where |
| :--- | :--- | :--- |
| Core timing, FPGA, after place and route (`xczu7ev`) | 2.5 ns (400 MHz): WNS -1.673 ns, fails. Timing is met at 3.900 ns (256.41 MHz): WNS +0.014 ns, 0 failing endpoints, 62,699 LUTs, 44,485 registers. This is an upper bound: the sweep (4.150 to 3.900 ns, six points, all met) stopped at 3.900 ns and 3.850 ns was not run. | [`reports/paper/fpga/t92/fpga_ppa_summary.md`](reports/paper/fpga/t92/fpga_ppa_summary.md), [`reports/paper/fpga/t89/fpga_ppa_summary.md`](reports/paper/fpga/t89/fpga_ppa_summary.md) |
| Secure top, FPGA, after place and route | 2.5 ns: WNS -1.648 ns, fails. 4.150 ns (240.96 MHz): WNS +0.018 ns, met; 165,776 LUTs (71.95 %), 110,405 registers, 7.5 BRAM tiles | [`reports/paper/fpga/t89/fpga_ppa_summary.md`](reports/paper/fpga/t89/fpga_ppa_summary.md) |
| Performance under attack and benign load (Ramulator2 model) | 1,983 runs (21 single-core workloads, 20 four-core mixes, attack runs), `N_RH` in {1024, 512, 256, 128}; commodity-DRAM comparison and metadata-traffic audit; 321 long-window runs of 33.6 ms (more than one `tREFW`) | [`reports/paper/perf/perf_report.md`](reports/paper/perf/perf_report.md), [`perf_report_v2.md`](reports/paper/perf/perf_report_v2.md), [`perf_report_long.md`](reports/paper/perf/perf_report_long.md) |
| Agreement between the Ramulator2 Q-Shield model and the RTL | On the 13 clean rows of the first cross-check, bandwidth and latency agree within 10 % (13 of 13) and activation traffic within 5 % (9 of 13). The hold-out cross-check of T90, in the same report, did not trigger its stop condition (3 of 12 rows outside 10 %; the condition is more than one third). | [`reports/paper/crossval/crossval_report_v2.md`](reports/paper/crossval/crossval_report_v2.md) |
| RowHammer bound in RTL simulation | 56 attack cases on the RTL with a behavioural DRAM model: no case in the `B1` group and no unknown-seed case exceeds the bound `B1` for victim rows within the refresh radius `R`, at the attack lengths that were run; no JEDEC timing violation. Some cases where the attacker knows the hash seed exceed `N_RH`. | [`reports/paper/security/security_eval_report.md`](reports/paper/security/security_eval_report.md) |
| Functional verification | See the verification table | [`README.md`](README.md) |

Known limits of these results are listed in [`LIMITATIONS.md`](LIMITATIONS.md). Three of them matter most:

- The bound `B1` is defined only for victim rows within distance `R` of the aggressor. A long single-sided attack in
  the RTL simulation raised the disturbance counter of a row at distance 3 to 136 (above `N_RH` = 128) after 1,100
  attack rounds, because the refreshes issued as mitigation are not counted by the tracker (see
  [`LIMITATIONS.md`](LIMITATIONS.md) section 2.3). This is one case, one configuration, and the
  DRAM model counts activation-induced disturbance, not real bit flips. The fix is planned and not yet verified.
- The Ramulator2 numbers come from a Q-Shield model that was written to match the RTL; the cross-check above bounds the
  mismatch only on the rows that were compared.
- The long-window runs show rows exceeding `N_RH` for several schemes, including Q-Shield, through the same mechanism
  as above ([`perf_report_long.md`](reports/paper/perf/perf_report_long.md)).

## 2. What has not been measured

- The number of bit-flips that a RowHammer or RowPress attacker causes on real DRAM, with and without the mitigation.
- ASIC area, power and timing.
- DRAM energy (the upstream Ramulator2 commit used here does not provide it).
- Side-channel leakage (not claimed; see [`LIMITATIONS.md`](LIMITATIONS.md)).
- Any DRAM generation other than DDR5. The scope of this project is DDR5.

## 3. Evaluation protocol (as executed)

### 3.1 Simulator and model

- Cycle-accurate DRAM simulator Ramulator2, upstream commit `72427a1`, with a Q-Shield model written to match the RTL
  parameters (activation tracker thresholds and table sizes, victim refresh, RFM, row-open clamp, integrity-metadata
  traffic). Model parameters are traced to RTL lines in [`sim/ramulator2_qshield/PARAMS.md`](sim/ramulator2_qshield/PARAMS.md).
- DRAM: DDR5-3200C, 16 Gb x4 devices, one channel and one rank, with the timing used by the RTL controller.
- A cross-check of the model against the RTL on short traces (section 1).

### 3.2 Workloads

- CPU traces from the Chronus trace set (Zenodo DOI 10.5281/zenodo.14281771, CC-BY-4.0), grouped by measured LLC MPKI;
  the selected workloads, hashes and measured MPKI are in [`sim/paper_perf/WORKLOADS.md`](sim/paper_perf/WORKLOADS.md).
- Attack runs: double-sided, many-sided, half-double and row-hold (RowPress-style) patterns, one attacker with benign
  co-runners.
- Multi-programmed mixes with a fixed random seed.

### 3.3 Baselines and thresholds

- No mitigation, and the Ramulator2 implementations of PARA, Graphene, Hydra, BlockHammer, PRAC and RFM. Schemes that
  need a refresh command that commodity DRAM does not provide are reported in a separate table, together with variants
  that use ordinary activate and precharge commands ([`perf_report_v2.md`](reports/paper/perf/perf_report_v2.md)).
- RowHammer thresholds `N_RH` in {1024, 512, 256, 128}, with the same threshold for every defense.

### 3.4 Metrics and statistics

- Weighted speedup, harmonic speedup, maximum slowdown, number of preventive refreshes, and the largest disturbance
  counter reached by any row.
- Randomized configurations are run with three seeds and reported as mean with a 95 % confidence interval.

### 3.5 Validity gate

A security result is accepted only if (a) the no-mitigation configuration shows rows exceeding `N_RH` under the attack,
so the attack is effective, and (b) the Q-Shield configuration differs from the baseline. A run that fails either
condition is reported as invalid, not as a success.

## 4. Reporting rules

- Every number in a paper or README must link to a report or log file in this repository.
- Synthesis-only timing is not reported as achievable frequency; post-route timing is.
- Results from other publications are quoted only with their own simulator, configuration and trace, and are never
  placed in the same table as our measurements without that context
  ([`sim/results/tab_literature_reported_comparison.tex`](sim/results/tab_literature_reported_comparison.tex)).
