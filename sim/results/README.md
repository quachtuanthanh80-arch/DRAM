# Results in this directory

Only the files below are produced by a generator that is part of this repository and can be reproduced.

| File | Generator | What it is |
| :--- | :--- | :--- |
| `rtl_bench/rtl_bench.{csv,json}` | `tools/run_rtl_bench.py` | Icarus RTL simulation of `axi_ddr5_mc_top` with the behavioural DRAM model and the JEDEC checker. |
| `security_attack_results.json`, `security_attack_audit_report.md` | `tools/run_security_attack_suite.py` | RTL attack testbench plus a Python attack emulation. |
| `attack_emulation_{meta,summary}.json`, `attack_emulation_report.md` | `sim/run_attack_emulation.py` | Python behavioural model of the defenses, not the RTL. Report these as model results. |

Earlier versions of this directory also held throughput tables, "apples-to-apples" comparisons, a hand-entered
comparison matrix, values quoted from other papers, and an FPGA table. They were withdrawn: there was no generator or
log behind them, or the simulator model they used did not mitigate anything. Cycle-accurate performance and security
evaluation is planned; see [`EVALUATION.md`](../../EVALUATION.md).
