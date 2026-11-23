# Q-Shield Evaluation Methodology & Experimental Rigor

> **Provenance note.** Earlier unbacked Ramulator throughput/overhead figures (SPEC CPU2017/PARSEC, ±σ), the legacy "apples-to-apples" table, and the Nangate 45 nm gate counts were withdrawn. See `sim/results/PROVENANCE.md` for legacy files, `reports/paper/perf/` for measured Ramulator2 DDR5 evaluations, `reports/paper/security/` for RTL RowHammer/RowPress runs, and `reports/paper/fpga/` for post-route FPGA PPA.

This document details the evaluation methodology, DDR5 configurations, workload suites, fairness criteria, and repeatability protocol governing the empirical validation of the **Q-Shield** DDR5 memory controller.

---

## 1. Architectural Simulation & RTL Evaluation Environment

1. **Cycle-Accurate Architectural Simulation (Ramulator 2.0)**:
   - Built from upstream Ramulator 2.0 commit `72427a1bba3771564c4fb0e494ba02242fd1eaa7` with the in-tree `QShield` / `QShield_Integ` controller models and commercial-DRAM `*_ACT` mitigation variants (`sim/ramulator2_qshield/`).
   - Models DDR5 scheduling and disturbance tracking (`DDR5_VRR`, `DDR5_16Gb_x4`, `DDR5_3200C`) referencing JEDEC JESD79-5 timing parameters.
2. **RTL Functional, Security & Cross-Validation Simulation (Icarus Verilog 12 / Verilator 5.032)**:
   - Canonical single-clock RTL (`axi_ddr5_mc_top.sv` and `axi_ddr5_mc_secure_top.sv`) targeting `400 MHz` (`2.500 ns` cycle time; `clk_ddr`/`aresetn_ddr` are unused compatibility ports since clock-domain unification).
   - Post-route FPGA frequency on Xilinx `xczu7ev-ffvc1156-2-e` (Vivado 2026.1) reaches `256.41 MHz` (`3.900 ns`, confirmed upper bound not swept below `3.900 ns`) for the core and `240.96 MHz` (`4.150 ns`) for the secure top (`reports/paper/fpga/t89/`, `reports/paper/fpga/t92/`).

---

## 2. DRAM Physical Configurations (DDR5-Only)

All current evaluations target **DDR5** exclusively (referencing JEDEC JESD79-5):

| Parameter | Ramulator2 Evaluation Preset (`DDR5_VRR` / `DDR5_3200C`) | RTL Command Engine (`ddr5_cmd_engine.sv` @ `2.500 ns` target) |
| :--- | :---: | :---: |
| **DRAM Organization** | `DDR5_16Gb_x4` (32 banks: 8 Bank Groups × 4 Banks) | 8 Bank Groups × 4 Banks (32 banks total) |
| **Bus / Controller Cycle** | `tCK = 0.625 ns` (`DDR5_3200C`) | `2.500 ns` target clock (`400 MHz`) |
| **Row Timing (`nRAS`, `nRP`, `nRC` / `T_RCD`, `T_RP`, `T_RAS`)** | `nRAS = 52 nCK (32.5 ns)`, `nRP = 28 nCK (17.5 ns)`, `nRC = 80 nCK (50.0 ns)` | `T_RCD = 7`, `T_RP = 7`, `T_RAS = 13`, `T_FAW = 10` cycles |
| **Refresh Interval (`tREFI` / `tREFW`)** | `tREFI = 3.9 us`, `tREFW = 32 ms` | `T_REFI = 1560` cycles (`3.9 us`) |
| **Refresh Cycle Time (`tRFC`)** | Per JEDEC DDR5-16Gb (`295 ns`) | `T_RFC = 118` cycles (`295.0 ns`) |
| **Victim Refresh Cost (`VRR` vs `ACT+PREpb`)** | `nVRR = 448 nCK (280.0 ns)` vs `4 × nRC = 320 nCK (200.0 ns)` | Standard `ACT -> tRAS -> PRE` per victim + `RFMab` |

---

## 3. Workload Suite & Trace Provenance

1. **Ramulator2 Trace Suite (`reports/paper/perf/`)**:
   - Uses the Chronus benchmark trace collection (`57` traces characterized for LLC/DRAM MPKI).
   - **Short-window matrix (`perf_report_v2.md`, `2,883` runs)**: `21` single-core workloads (`num_expected_insts = 2,000,000`; median window `0.2364 ms`), `20` 4-core mixes (median `0.7283 ms`), and `4` attack scenarios (`double_sided`, `half_double`, `many_sided`, `rowpress_hold` with 3 benign co-runners `434.zeusmp`, `401.bzip2`, `458.sjeng`; median `3.125 ms`) across $N_{RH} \in \{1024, 512, 256, 128\}$.
   - **Long-window matrix (`perf_report_long.md`, `321` runs at `33.6 ms >= 1 tREFW`)**: `6` single-core workloads (2 per MPKI tier: `429.mcf`, `tpch6`, `tpch17`, `401.bzip2`, `511.povray`, `458.sjeng`) plus the `4` attack scenarios at $N_{RH} \in \{1024, 128\}$, fixed simulation window `num_max_cycles = 134,400,000` (`ctrl_cycles = 53,760,000`, `sim_time_ms = 33.6000 ms`). Short traces wrap around in `BHO3`/`SimpleO3`; wrap counts are reported explicitly per workload in `perf_report_long.md`.
2. **RTL RowHammer / RowPress Security Matrix (`reports/paper/security/security_eval_report.md`)**:
   - `56` directed RTL test cases covering single-sided, double-sided, many-sided (`4/8/16/32`), half-double, decoy-feinting, RowPress (`rowpress_long_hold` up to $t_{\mathrm{RAS\_max}}$, `rowpress_subthresh`), unknown-seed and known-seed PXOR hash collisions across $N_{RH} \in \{1024, 512, 256, 128\}$ and blast radii $R \in \{2, 3\}$.
   - Attack classes reflect published DRAM disturbance mechanisms including Blacksmith (Jattke et al., IEEE S&P '22), Half-Double (Kogler et al., USENIX Security '22), and RowPress (Luo et al., ISCA '23).
3. **RTL-to-Ramulator2 Cross-Validation (`reports/paper/crossval/crossval_report_v2.md`)**:
   - `14` synthetic traces (`8` in-sample calibration traces + `6` frozen holdout traces, `seed = 902026`) executed on both live RTL and Ramulator2 across `base` and `secure` configurations (`28` runs), plus exact metadata counter verification against `tb_secure_top_integrity` (`meta_rd_cnt=83`, `meta_wr_cnt=131`, `mc_hit_rate=78.5%`, `reencrypt_events=1`).

---

## 4. Performance & Security Metrics

1. **Weighted Speedup (Normalized WS), Mean IPC, Harmonic Speedup, and Maximum Slowdown**: computed across single-core, 4-core mix, and attack+co-runner runs relative to the unmitigated `Baseline` under the identical simulation window.
2. **Preventive Refreshes (`Prev Ref`)**: count of preventive victim refresh operations (`ACT+PREpb` or `VRR` / `RFMab`).
3. **Maximum Victim Disturbance (`Worst R1`, `Worst R2`, `D_max`)**: peak activation disturbance recorded by the passive `RowHammerObserver` (Ramulator2) or behavioral DRAM tracker (RTL), reported against $N_{RH}$ and the structural bound $B_1$.
4. **Cross-Validation Error**: bandwidth and average read latency percentage deltas between Ramulator2 and live RTL (`+5.42% ± 3.52%` BW and `-4.09% ± 7.35%` latency on holdout traces, showing ~4–5 % systematic model optimism; uncalibrated defaults are used in `perf_report_v2.md` and `perf_report_long.md`).

---

## 5. Statistical Rigor & Repeatability

- **Deterministic Schemes**: executed with fixed configuration and verified bit-exact repeatable across reruns (`determinism_ok = true` on `tpch6`, `33.6 ms` in `perf_report_long.md`).
- **Probabilistic Schemes (`PARA`, `PARA_ACT`)**: executed across `3` independent seeds per workload and threshold, reporting the mean and 95 % confidence interval (`Seed 95% CI`) in `perf_report_v2.md` and `perf_report_long.md`.
- **DRAM Energy**: reported as `N/A` where not provided by upstream Ramulator 2.0 commit `72427a1`.

---

## 6. Fairness Criteria & Comparison Taxonomy

To ensure fair comparison with prior RowHammer mitigations targeting commodity DDR5:

- **Group A — Commercial DRAM (`dram_support = none`, no DRAM die modification and no non-JEDEC commands)**: `Baseline`, `BlockHammer` (Yağlıkçı et al., HPCA '21), commercial `ACT+PREpb` equivalents `PARA_ACT`, `Graphene_ACT`, `Hydra_ACT`, `QShield`, and `QShield_Integ`. All schemes in Group A are simulated on the identical Ramulator 2.0 binary, traces, and timing configuration.
- **Group B — Non-JEDEC Command or In-DRAM Hardware (`dram_support = vrr_non_jedec` or `in_dram`)**: `PARA`, `Graphene` (Park et al., MICRO '20), `Hydra` (Qureshi et al., ISCA '22) using the non-JEDEC `VRR` command, and `PRAC` (JEDEC DDR5 / Canpolat et al., HPCA '25) / `RFM` requiring in-DRAM counters or target selection. Group B is tabulated separately from Group A and is not ranked on the same axis.
- **Literature Context**: Other published mitigations such as `AQUA` (Saxena et al., MICRO '22), `Rubix` (Saxena et al., ASPLOS '24), `DREAM` (Taneja & Qureshi, ISCA '25), `QPRAC` (Woo et al., HPCA '25), and `PrISM` (Woo et al., ISCA '26) use different simulators, memory technologies, or hardware assumptions and are discussed only qualitatively with explicit platform caveats.
