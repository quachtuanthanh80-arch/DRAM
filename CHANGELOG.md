# Q-Shield Changelog & Revision History

All notable changes, methodological improvements, and architectural updates to the **Q-Shield** memory controller repository are documented in this file.

---

## [2.1.0] - 2026-10-08

### Major Methodological & Peer-Review Upgrades
- **Transition from Promotional to Objective Academic Style**:
  - Eliminated unqualified marketing terminology (e.g., "0% overhead", "100% pass", "flawless SOTA", "zero weaknesses") across `README.md`, `sim/`, and `formal/`.
  - Added operational contexts and conditional bounds to all performance claims (e.g., *"$<0.05\%$ overhead under non-congested SPEC CPU2017 workloads due to physical $t_{\mathrm{RCD}}/t_{\mathrm{RP}}$ pipeline latency shadowing"*).
  - Replaced promotional badges with objective, informative status indicators.
- **Three-Tier Comparative Architecture Matrix**:
  - Partitioned evaluations into (1) Apples-to-Apples cycle-accurate comparisons on Ramulator 2.0, (2) Literature-reported values with platform discrepancy caveats, and (3) Qualitative architectural taxonomy.
- **Structured Artifact Mapping**:
  - Established a 1-to-1 mapping table linking all 10 manuscript figures and 4 tables directly to generating scripts and raw data outputs.
- **Extended Limitations & Trade-offs Disclosure**:
  - Detailed the Count-Min sketch probabilistic upper bound, false positive trade-offs ($0.08\% \to 1.38\%$), FPGA distributed LUT utilization ($86.8\%$), deliberate attacker throughput throttling ($-57.9\%$), and pure-controller boundaries.
- **Formal Verification Expansion**:
  - Documented individual SVA properties, mathematical targets, solver configurations, and unconstrained input rationale across BMC and $k$-induction modes in `formal/README.md`.
- **Reproducibility & Environment Support**:
  - Created `requirements.txt`, `Dockerfile`, `INSTALL.md`, `REPRODUCIBILITY.md`, `METHODOLOGY.md`, `LIMITATIONS.md`, `VERSIONING.md`, and YAML configurations.

---

## [2.0.0] - 2026-10-02

### Architecture & Protocol Upgrades
- **JEDEC DDR5 Subchannel Scheduling**:
  - Implemented dual 32-bit independent subchannel scheduling with DFI 5.0 physical adapter.
  - Added Modulo-3 non-power-of-two channel interleaving to eliminate bank group hot-spotting.
- **AMBA AXI5 Protocol Compliance**:
  - Integrated AXI poison signal propagation (`AWPOISON`, `ARPOISON`, `RPOISON`) and ASIL-D byte parity checks (`AWCHK`, `ARCHK`, `WCHK`, `RCHK`).
- **Autonomous SEC-DED (72, 64) Hamming Scrubbing**:
  - Added background autonomous memory scrubbing engine with zero-cycle latency correction.
- **RowPress Mitigation**:
  - Integrated continuous open-row duration tracking and JEDEC $t_{\mathrm{RAS\_max}} \le 70\,\mu\text{s}$ auto-precharge clamping.

---

## [1.0.0] - 2026-09-15

### Initial Synthesizable Release
- Initial synthesizable SystemVerilog core: $O(1)$ dual-hash filter, 16-entry ROB, and timing-slack-aware arbiter for DDR4-3200.
- Master regression test suite with 14 unit testbenches using Icarus Verilog.
