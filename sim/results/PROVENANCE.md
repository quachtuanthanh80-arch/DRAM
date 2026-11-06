# Provenance of the files in `sim/results/`

Audit date: 2026-10-30. Before you cite a number from this directory, check its class here.

## Class A: produced by a simulation in this repository (you can reproduce it)

| File | Generator | What actually runs |
|---|---|---|
| `rtl_bench/rtl_bench.{csv,json}` | `tools/run_rtl_bench.py` | Icarus RTL simulation of `axi_ddr5_mc_top` with the behavioural `tb/common/dram_model.sv` and the JEDEC checker. Traces come from `tools/gen_bench_traces.py` (seeded, synthetic access patterns). |
| `security_attack_results.json`, `security_attack_audit_report.md` | `tools/run_security_attack_suite.py` | Icarus RTL testbench `tb_security_attacks_vcd` plus the Python attack emulation. |
| `attack_emulation_{meta,summary}.json`, `attack_emulation_report.md` | `sim/run_attack_emulation.py` | Python behavioural model of the defenses, not the RTL. Report these as model results. |

## Class B: Ramulator 2 outputs, with a generator in the repository

| File | Generator | Notes |
|---|---|---|
| `ddr5_6000_results.json` | `sim/run_ddr5_6000.py` | Imports Ramulator 2 from `/home/thanh/ramulator2/python`, so it must run inside WSL. `QShield` there is a separate C++ controller model, not this RTL. |
| `multichannel_scaling_full.{csv,json}` | `sim/test_multichannel.py` | Same WSL requirement. |

`sim/run_benchmarks.py` also belongs here. Until 2026-10-30, if Ramulator 2 was not importable it fell back to a "calibrated model": hard-coded bandwidth tables plus ±0.8 % `random.uniform` noise. That branch has been removed, and the script now stops with an error instead. The outputs that branch produced on Windows were deleted from here and from `GOLDEN_OUTPUTS/`: `bench_meta.json`, `bench_metrics.csv`, `bench_summary.json` and `benchmark_summary_table.tex` (270 "runs" in 0.19 s).

### Finding: the Ramulator 2 Q-Shield model does not mitigate anything (2026-10-30)

`sim/run_benchmarks.py --config DDR5-4800` was run in WSL against the real Ramulator 2 build. The Q-Shield and PRAC rows matched the Baseline rows to every digit in all 6 workloads, for both bandwidth and latency. Only `throttled_events` differed: 55–652 for Q-Shield.

The cause is in `~/ramulator2/src/ramulator/controller/impl/qshield_controller.cpp`, which is outside this repository:
- It defers an ACT only when the same row was activated less than `throttle_delay` = 100 cycles earlier. Two ACTs to one row are already at least tRC apart (about 115 cycles at DDR5-4800), so the deferral never fires.
- It issues no victim refresh at all.
- The "RowHammer" trace has a 98 % row-hit rate, so it produces almost no activations.

Any Ramulator 2 claim of the form "Q-Shield keeps full throughput under attack" is therefore an artifact of a model that does nothing. It says nothing about the RTL, which really does throttle and refresh victims. The model needs victim refresh (ACT→tRAS→PRE per neighbour), throttling driven by the count, and hammer traces that force activations before its numbers mean anything.

## Class C: no generator in the repository (unverified; regenerate before citing)

`benchmark_results.{csv,json}`, `benchmark_results_expanded.{csv,json}`, `multichannel_benchmark_results.json`, `fpga_synthesis_results.json`.

The first three look like Ramulator 2 statistics (integer row-hit and row-conflict counts), but no script in the repository writes them. `fpga_synthesis_results.json` has no synthesis log behind it. Current Vivado out-of-context numbers are in `.harness/qshield_review/vivado/` (local).

## Class D: hard-coded tables (not simulation results)

| File | Content |
|---|---|
| `ramulator2_apples_to_apples.json`, `tab_ramulator2_apples_to_apples.tex` | Labelled as Ramulator 2, but they repeat the hard-coded "29.46× vs BlockHammer" figures. Do not cite them as measured. |
| `sota_comprehensive_matrix.{csv,json,tex}` | Hand-entered area and throughput values. |
| `literature_reported*.{json,tex}`, `tab_literature_reported_comparison.tex` | Values quoted from other papers. Check each one against its source before use. |
| `qualitative_taxonomy.{json,tex}`, `architectural_taxonomy.json`, `tab_sota_architectural_taxonomy.tex` | Qualitative classification (opinion, not measurement). |

`apples_to_apples_cycle_accurate.{json,tex}` was a hard-coded table labelled "Ramulator 2.0, identical SPEC CPU2017 traces". It has been removed, and `sim/generate_sota_comparison.py` no longer exports it.
