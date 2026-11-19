# Q-Shield Evaluation: Status and Protocol

This document separates **what has been measured** from **what is planned**. Earlier versions of this file contained
throughput-overhead tables, a security-efficacy table ("0 escaped bit-flips") and a comparison against published
defenses. Those tables were **withdrawn**: the repository does not contain the runs, configurations or traces that
would reproduce them, so they cannot be cited. Nothing in this file should be read as a cycle-accurate performance or
RowHammer-security result until the planned evaluation below has been run and its outputs added to the repository.

## 1. What has been measured

| Quantity | Result | Where |
| :--- | :--- | :--- |
| Core timing, FPGA, after place and route | 2.5 ns: WNS -1.273 ns (fails). 3.8 ns: WNS +0.024 ns (met). | [`README.md`](README.md), [`DESIGN.md`](DESIGN.md) section 3, [`syn/reports/evidence/`](syn/reports/evidence/) |
| Core area, FPGA | 63,785 LUTs and 44,243 registers at 3.8 ns | [`DESIGN.md`](DESIGN.md) section 3 |
| Secure top, FPGA, after place and route | 2.5 ns: WNS -1.595 ns (fails). 4.1 ns: WNS -0.005 ns (fails). 4.15 ns: WNS +0.021 ns (met), 164,062 LUTs (71.2 %) | [`DESIGN.md`](DESIGN.md) section 3.4 |
| Functional verification | See the verification table | [`README.md`](README.md) |

## 2. What has not been measured

- Throughput and latency overhead of the mitigation and of the encryption and integrity layer under realistic workloads.
- The number of bit-flips that a RowHammer or RowPress attacker can cause with and without the mitigation.
- Comparison against other defenses (for example PARA, Graphene, Hydra, BlockHammer, PRAC, RFM) on the same simulator.
- ASIC area, power and timing.
- Side-channel leakage (not claimed; see [`LIMITATIONS.md`](LIMITATIONS.md)).

## 3. Planned evaluation protocol

The protocol is recorded here so that results, once produced, can be checked against it.

### 3.1 Simulator and model

- Cycle-accurate DRAM simulator Ramulator2, an unmodified upstream commit (`72427a1`), with a Q-Shield model written
  to match the RTL parameters (activation tracker thresholds and table sizes, victim refresh, RFM, row-open clamp,
  integrity-metadata traffic). Each model parameter is traced to a line in the RTL.
- A cross-check of the model against the RTL on short traces: bandwidth and latency within 10 %, event counts within 5 %.
- DRAM: DDR5-4800 with the timing bins used by the RTL.

### 3.2 Workloads

- Memory traces derived from SPEC CPU benchmarks, taken from the public ChampSim trace set of the Data Prefetching
  Championship 3 (24 traces spanning low, medium and high memory intensity). Traces are streamed and truncated by
  instruction count; truncation parameters are recorded with each result.
- Attack traces: double-sided, many-sided, half-double, and row-hold (RowPress-style) patterns.
- Multi-programmed mixes with a fixed random seed, and one attacker plus benign co-runners.

### 3.3 Baselines and thresholds

- No mitigation, and the existing Ramulator2 implementations of PARA, Graphene, Hydra, BlockHammer, PRAC and RFM.
- RowHammer thresholds N_RH in {1024, 512, 256, 128}, with the same threshold for every defense.

### 3.4 Metrics and statistics

- Weighted speedup, harmonic speedup, maximum slowdown, number of preventive refreshes, DRAM energy if available.
- Randomized configurations are run with at least three seeds and reported as mean with a 95 % confidence interval.

### 3.5 Validity gate

A security result is accepted only if (a) the no-mitigation configuration shows rows exceeding N_RH under the attack,
so the attack is effective, and (b) the Q-Shield configuration differs from the baseline. A run that fails either
condition is reported as invalid, not as a success.

## 4. Reporting rules

- Every number in a paper or README must link to a report or log file in this repository.
- Synthesis-only timing is not reported as achievable frequency; post-route timing is.
- Results from other publications are quoted only with their own simulator, configuration and trace, and are never
  placed in the same table as our measurements without that context.
