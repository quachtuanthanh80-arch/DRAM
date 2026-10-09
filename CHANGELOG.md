# Q-Shield Changelog & Revision History

All notable changes, methodological improvements, and architectural updates to the **Q-Shield** memory controller repository are documented in this file.

---

## [3.0.0] - 2026-10-09

### Major Cryptographic & Microarchitectural Upgrades
- **SCARF 1-Cycle Low-Latency DRAM Address Randomizer (`rtl/core/scarf_dram_randomizer.sv`)**:
  - Implemented a 10-round Tweaked-Feistel cipher with non-linear 4-bit S-Boxes and per-bank row permutation.
  - Sub-cycle combinational mapping ($IPC = 1.0$) prevents spatial physical adjacency exploitation (ZenHammer, Phoenix, and half-double RowHammer patterns).
- **Universal PXOR-Hash Engine (`rtl/core/pxor_hash_engine.sv`)**:
  - Designed a parallel XOR reduction tree over a dynamic Toeplitz binary matrix parameterized by randomized seed.
  - Provable collision probability bound $\le 2^{-8}$, sub-nanosecond evaluation delay, eliminating algorithmic adversarial collisions against Count-Min sketches (Crystalor CCS '24).
- **AMD SEV-SNP Style Multi-ASID Confidential Key Table (`rtl/crypto/multi_vm_key_table.sv`)**:
  - Integrated 16-VM hardware key table indexing 256-bit AES data keys and 128-bit XTS tweak keys by 4-bit ASID.
  - Enforced APB4 supervisor-only write protection (`pprot[1] == 1'b1`) preventing unprivileged guest tampering, with hardware C-bit unencrypted DMA bypass.
- **HOST '20 Fault-Hardened CSR with TMR Glitch Watchdog (`rtl/core/fault_hardened_csr.sv`)**:
  - Implemented Triple Modular Redundancy (TMR) across 3 independent register rails with 2-out-of-3 bitwise majority voting for all threshold/configuration registers.
  - Real-time rail mismatch detector triggering continuous `o_glitch_alert` and security lockdown latch (`o_security_locked`) against EM/voltage fault injection.
- **Top-Level Integration & Full 18-Test Regression Suite**:
  - Integrated into `addr_mapper_ddr5.sv`, `sdc_resilient_filter.sv`, and `axi_ddr5_mc_top.sv`.
  - Achieved 100% pass rate (18/18 tests passed) across master Icarus Verilog regression suite (`run_iverilog_regression.py`).

---

## [2.1.0] - 2026-10-08

### Major Methodological & Peer-Review Upgrades
- **Transition from Promotional to Objective Academic Style**:
  - Eliminated unqualified marketing terminology (e.g., "0% overhead", "100% pass", "flawless SOTA", "zero weaknesses") across `README.md`, `sim/`, and `formal/`.
  - Added operational contexts and conditional bounds to all performance claims (e.g., *"< 0.05% overhead under non-congested SPEC CPU2017 workloads due to physical t_RCD / t_RP pipeline latency shadowing"*).
  - Replaced promotional badges with objective, informative status indicators.
- **Three-Tier Comparative Architecture Matrix**:
  - Partitioned evaluations into (1) Apples-to-Apples cycle-accurate comparisons on Ramulator 2.0, (2) Literature-reported values with platform discrepancy caveats, and (3) Qualitative architectural taxonomy.
- **Structured Artifact Mapping**:
  - Established a 1-to-1 mapping table linking all 10 manuscript figures and 4 tables directly to generating scripts and raw data outputs.
- **Extended Limitations & Trade-offs Disclosure**:
  - Detailed the Count-Min sketch probabilistic upper bound, false positive trade-offs (0.08% → 1.38%), FPGA distributed LUT utilization (86.8%), deliberate attacker throughput throttling (-57.9%), and pure-controller boundaries.
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
