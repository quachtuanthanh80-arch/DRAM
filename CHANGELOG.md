# Q-Shield Changelog & Revision History

All notable changes, methodological improvements, and architectural updates to the **Q-Shield** memory controller repository are documented in this file.

---

## Revision: accuracy pass & DDR5-only scope (2026-11)

- **Withdrawn**: the unbacked ASIC gate-equivalent/power/energy tables (`synth/asic/reports/multi_pdk_ppa_comparison.md`), the 424.1 MHz and +0.142 ns timing claim, legacy unbacked Ramulator2 throughput-overhead and zero-disturbance tables, and unverified literature GE/overhead rows.
- **Added measured FPGA post-route results** (`reports/paper/fpga/t89/`, `reports/paper/fpga/t92/`): on `xczu7ev` with post-T86/T88 RTL, neither top closes at 400 MHz (`2.500 ns`); core `axi_ddr5_mc_top` closes at `3.900 ns` (`256.41 MHz`, confirmed upper bound not yet swept below `3.900 ns`, `WNS +0.014 ns`, `62,699` LUTs, `1.645 W` vectorless) and `4.200 ns` (`238.10 MHz`, `WNS +0.076 ns`); secure top `axi_ddr5_mc_secure_top` closes at `4.150 ns` (`240.96 MHz`, `WNS +0.018 ns`, `165,776` LUTs, `7.5` BRAM, `4.301 W` vectorless).
- **Added** the encryption and integrity layer (AES-256-XTS, MAC, Bonsai Merkle tree, 4 KB trusted metadata cache) and its verification (`tb_secure_top_integrity`: `279` FAST / `405` full checks, `0` failures, 1:1 AXI metadata accounting `meta_rd_cnt=83`, `meta_wr_cnt=131`; `2,048` XTS known-answer vectors; cache and tree model checks).
- **Added** a static multi-driver check (`tools/check_multidriver.py`) after synthesis revealed registers driven from two processes in the encryption bridge; the defect is fixed.
- **Added** measured DDR5 Ramulator2 evaluations separating commercial-DRAM (`dram_support=none`) from non-JEDEC VRR and in-DRAM schemes (`2,883` short-window runs in `reports/paper/perf/perf_report_v2.md`; `321` long-window runs at `33.6 ms >= 1 tREFW` in `reports/paper/perf/perf_report_long.md`), RTL RowHammer/RowPress matrix (`56/56` cases in `reports/paper/security/security_eval_report.md`), and RTL-to-Ramulator2 cross-validation (`14` synthetic traces in `reports/paper/crossval/crossval_report_v2.md`).
- **Added** a Python UVM-style environment (`pyuvm 5.0.0`, `23/23` checks with independent Python golden models), a 26-case corner-case matrix, mutation testing (`18/20` = `90 %` on four core/CSR blocks), and five bounded SymbiYosys BMC/Cover checks (`depth 15`, integrity on an abstract model).
- **Scoped documentation and benchmark scripts to DDR5-only**: removed legacy unbacked non-DDR5 benchmark rows and hard-coded throughput tables, and verified external paper citations directly against source PDFs.

> **Historical release notes below (2026-09 to 2026-10).** Entries from `[3.0.0]` through `[1.0.0]` are retained for repository history. Claims in those historical entries regarding unproven collision bounds, unbacked overhead figures, older test counts, or unbounded formal proofs are superseded by the 2026-11 accuracy pass above.

## [3.0.0] - 2026-10-09

### Major Cryptographic & Microarchitectural Upgrades
- **SCARF 1-Cycle Low-Latency DRAM Address Randomizer (`rtl/core/scarf_dram_randomizer.sv`)**:
  - Implemented a 10-round Tweaked-Feistel cipher with non-linear 4-bit S-Boxes and per-bank row permutation (adapted from Canale et al., USENIX Security '23).
  - Single-cycle combinational mapping intended to disrupt spatial physical adjacency patterns (such as ZenHammer, USENIX Security '24; Phoenix, IEEE S&P '26; and Half-Double, USENIX Security '22).
- **Universal PXOR-Hash Engine (`rtl/core/pxor_hash_engine.sv`)**:
  - Designed a parallel XOR reduction tree over a dynamic Toeplitz binary matrix parameterized by a 64-bit seed.
  - *(Withdrawn in 2026-11: an earlier note claimed a $\le 2^{-8}$ collision bound attributed to Crystalor CCS '24; Crystalor proposes PXOR-Hash for recoverable memory encryption metadata, not Count-Min sketch RowHammer bounds, and no collision probability bound is proven for this RTL implementation.)*
- **Multi-ASID Confidential Key Table (`rtl/crypto/multi_vm_key_table.sv`)**:
  - Integrated 16-VM hardware key table indexing 256-bit AES data keys and 128-bit XTS tweak keys by 4-bit ASID.
  - Enforced APB4 supervisor-only write protection (`pprot[1] == 1'b1`) preventing unprivileged guest tampering, with hardware C-bit unencrypted DMA bypass.
- **Fault-Hardened CSR with TMR Glitch Watchdog (`rtl/core/fault_hardened_csr.sv`)**:
  - Implemented Triple Modular Redundancy (TMR) across 3 independent register rails with 2-out-of-3 bitwise majority voting for threshold/configuration registers.
  - Real-time rail mismatch detector triggering continuous `o_glitch_alert` and security lockdown latch (`o_security_locked`) against single-rail fault upsets.
- **Top-Level Integration & Historical Regression Suite**:
  - Integrated into `addr_mapper_ddr5.sv`, `sdc_resilient_filter.sv`, and `axi_ddr5_mc_top.sv`.
  - Historical 18-test Icarus Verilog suite (`run_iverilog_regression.py`); superseded by the expanded canonical regression suite in 2026-11.

---

## [2.1.0] - 2026-10-08

### Major Methodological & Peer-Review Upgrades
- **Transition from Promotional to Objective Academic Style**:
  - Removed unqualified marketing terminology across `README.md`, `sim/`, and `formal/`.
  - *(Historical performance context notes from this revision were later withdrawn in 2026-11 in favor of measured Ramulator2 reports in `reports/paper/perf/`.)*
  - Replaced promotional badges with objective, informative status indicators.
- **Three-Tier Comparative Architecture Matrix**:
  - Separated simulation comparisons from literature context and qualitative taxonomy.
- **Structured Artifact Mapping**:
  - Mapped manuscript figures and tables to generating scripts and raw data outputs.
- **Extended Limitations & Trade-offs Disclosure**:
  - Documented Count-Min sketch trade-offs and pure-controller threat-model boundaries *(earlier unbacked numerical percentages from this draft were withdrawn in 2026-11)*.
- **Formal Verification Documentation**:
  - Documented SVA assertions and solver configurations in `formal/README.md` *(superseded by the five verified BMC/Cover suites in 2026-11)*.
- **Reproducibility & Environment Support**:
  - Created `requirements.txt`, `Dockerfile`, `INSTALL.md`, `REPRODUCIBILITY.md`, `METHODOLOGY.md`, `LIMITATIONS.md`, `VERSIONING.md`, and YAML configurations.

---

## [2.0.0] - 2026-10-02

### Architecture & Protocol Upgrades
- **JEDEC DDR5 Subchannel Scheduling**:
  - Implemented dual 32-bit independent subchannel scheduling with DFI 5.0 physical adapter.
  - Added Modulo-3 non-power-of-two channel interleaving.
- **AMBA AXI5 Poisoning & Parity Support**:
  - Integrated AXI poison signal propagation (`AWPOISON`, `ARPOISON`, `RPOISON`) and byte parity checks (`AWCHK`, `ARCHK`, `WCHK`, `RCHK`).
- **Autonomous SEC-DED (72, 64) Hamming Scrubbing**:
  - Added background autonomous memory scrubbing engine.
- **RowPress Mitigation**:
  - Integrated open-row duration tracking and JEDEC $t_{\mathrm{RAS\_max}} \le 70\,\mu\text{s}$ auto-precharge clamping.

---

## [1.0.0] - 2026-09-15

### Initial Synthesizable Release
- Initial synthesizable SystemVerilog core: $O(1)$ dual-hash filter, 16-entry ROB, and timing-slack-aware arbiter for DDR4-3200.
- Master regression test suite with 14 unit testbenches using Icarus Verilog.
