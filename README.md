# Q-Shield: A DDR5/DDR4 Secure Memory Controller (Research Prototype)

[![Host Protocol](https://img.shields.io/badge/Host%20Protocol-AMBA%20AXI4-blue.svg)](rtl/frontend/)
[![Hardware RTL](https://img.shields.io/badge/Hardware%20RTL-SystemVerilog%20IEEE%201800--2017-blue.svg)](rtl/)
[![Status](https://img.shields.io/badge/Status-research%20prototype-orange.svg)](#status-read-this-first)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

Q-Shield is a synthesizable SystemVerilog (IEEE 1800-2017) DDR5/DDR4 memory controller that combines
controller-side RowHammer/RowPress mitigation and error correction with an optional **memory encryption and
integrity layer** (AES-256-XTS, a 64-bit Carter-Wegman MAC, and an 8-ary Bonsai Merkle tree with a trusted metadata
cache) placed outside the controller core. It does not require in-DRAM modifications.

## Status (read this first)

This repository is an **academic research prototype under active verification**. Numbers below are limited to what
has a report or a test log in this repository. Anything not listed as measured is **not yet measured**.

| Area | Status |
| :--- | :--- |
| Functional verification (simulation) | Done for the items listed in [Verification evidence](#verification-evidence). |
| Timing on FPGA (Xilinx `xczu7ev`, Vivado 2026.1) | **Measured. The design does not meet 400 MHz after place and route** (see below). |
| ASIC area, power and timing (Nangate45) | **Not measured yet.** Earlier gate-equivalent and milliwatt figures were removed because no run in this repository produced them. |
| Cycle-accurate performance and RowHammer security evaluation (Ramulator2) | **Not measured yet.** Earlier overhead and "0 bit-flips" tables were withdrawn for the same reason. See [`EVALUATION.md`](EVALUATION.md). |
| Formal verification | Partial. Bounded model checking only for the properties listed in [`FORMAL.md`](FORMAL.md); see its status section. |

### Measured timing and area (FPGA, out-of-context, `xczu7ev-ffvc1156-2-e`)

Core controller `axi_ddr5_mc_top`, after place and route (reports in [`syn/reports/evidence/`](syn/reports/evidence/)):

| Target period | WNS | TNS (failing / total endpoints) | CLB LUTs | CLB registers | BRAM / DSP |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 2.500 ns (400 MHz) | **-1.273 ns** | -27,881 ns (61,510 / 107,309) | 65,170 (28.3 %) | 44,293 | 0 / 0 |
| 3.800 ns (263.16 MHz) | **+0.024 ns** | 0 ns (0 / 107,193) | 63,785 (27.7 %) | 44,243 | 0 / 0 |

The highest clock that closed timing in our runs is therefore about **263 MHz**, not 400 MHz. Power at 263 MHz is
estimated at 1.618 W (1.021 W dynamic, 0.597 W static) by Vivado in vectorless mode, which is a rough estimate and not
a measurement.

Secure top `axi_ddr5_mc_secure_top` (core + encryption and integrity layer), synthesis only, 2.500 ns target:
**WNS -0.385 ns**, 169,365 CLB LUTs (73.5 %), 111,834 registers, 7.5 BRAM tiles, no multi-driven nets
([`secure_top_synth_T44_timing.rpt`](syn/reports/evidence/secure_top_synth_T44_timing.rpt)). Place and route of the
secure top is not complete yet.

Metadata cache `qshield_meta_cache` alone: synthesis WNS is positive at 2.5 ns
([`meta_cache_synth_timing.rpt`](syn/reports/evidence/meta_cache_synth_timing.rpt)).

> Synthesis-only slack is optimistic: for the core, synthesis reported -0.022 ns at 2.5 ns while the routed result
> was -1.273 ns. Use post-route numbers when comparing.

## Verification evidence

All counts below come from testbenches in this repository; run commands are in [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md).

| What | Result |
| :--- | :--- |
| Integrity and encryption layer, end to end (`tb_secure_top_integrity`) | 273 checks, 0 failures. Covers random traffic, data/MAC/counter/tree-node bit flips, splicing, full replay and data+MAC replay, minor-counter overflow re-encryption, root flush against a Python reference, cache pressure, and integrity-off mode. |
| AES-256-XTS (IEEE Std 1619) | 2,048 known-answer vectors checked against the RTL. |
| Metadata cache and Merkle engine | 50,000 random cache operations and at least 20,000 engine operations compared with a Python model. |
| Core and secure-top testbenches | `tb_axi_ddr5_mc_top` 19 checks; `tb_axi_ddr5_mc_secure_top` 15 checks; 0 failures. |
| Known-defect reproduction suite (`tb/findings`) | 15 checks; open defects are reproduced and fixed ones are guarded. |
| Python UVM-style environment (`tb/uvm`, pyuvm 5.0.0) | 23/23 checks over the controller and CSR environments with independent Python golden models. Coverage is measured on bins defined in the environment; it is not code coverage. |
| Corner-case matrix | 26 documented corner cases, each mapped to an executing test (`tools/check_corner_matrix.py`). |
| Mutation testing | 18 of 20 injected faults detected (90 %) in four blocks (scheduler, reorder buffer, AXI adapter, CSR). The encryption and integrity blocks are **not** covered by mutation testing yet. |
| Formal (SymbiYosys) | Bounded model checking to depth 12 to 15 for lock and key-valid rules, scheduler bank timing, AXI4 handshake stability and reorder-buffer beat conservation. The integrity invariants are proven on an **abstract model** (`formal/integrity_formal.sv`) that does not instantiate the RTL. |

A static check (`tools/check_multidriver.py`) rejects registers driven from more than one process. It was added after
synthesis exposed such a defect that simulation had hidden: a read-path integrity-failure flag was forced to zero in
the synthesized netlist.

## Architecture overview

```
AXI4 slave -> [skid buffer] -> [SCARF address mapper] -> [PXOR SDC filter] / [reorder buffer] / [SEC-DED + scrubber]
                                                   -> [timing-slack aware QoS arbiter + directed refresh]
                                                   -> [JEDEC DDR5/DDR4 command FSM] -> DFI

Secure top (optional): AXI4 -> [AES-256-XTS + MAC + Bonsai Merkle tree + metadata cache] -> controller core
```

### RTL map

| Component | Source | Notes | Test |
| :--- | :--- | :--- | :--- |
| SDC filter | [`sdc_resilient_filter.sv`](rtl/core/sdc_resilient_filter.sv) | Dual-hash count-min sketch with epoch tags; configure the threshold at most half the RowHammer threshold. | `test_sdc_filter.py`, `tb_security_attacks_vcd` |
| PXOR hash | [`pxor_hash_engine.sv`](rtl/core/pxor_hash_engine.sv) | Parallel XOR reduction for filter bins. | `tb_pxor_sdc_filter` |
| SCARF randomizer | [`scarf_dram_randomizer.sv`](rtl/core/scarf_dram_randomizer.sv) | Row-address Feistel, bijective. | `tb_scarf_randomizer` |
| Key table | [`multi_vm_key_table.sv`](rtl/crypto/multi_vm_key_table.sv) | Per-ASID keys, write-only, secure-privileged writes. | `tb_multi_vm_key_table` |
| Fault-hardened CSR | [`fault_hardened_csr.sv`](rtl/core/fault_hardened_csr.sv) | Triple-redundant registers, 2-of-3 vote, glitch latch. | `tb_fault_hardened_csr` |
| Adaptive threshold | [`adaptive_threshold_engine.sv`](rtl/core/adaptive_threshold_engine.sv) | EWMA, clamped. | `tb_adaptive_threshold_engine` |
| Reorder buffer | [`reorder_buffer_rob.sv`](rtl/core/reorder_buffer_rob.sv) | In-order retire per AXI ID. | `tb_reorder_buffer_rob` |
| QoS queue | [`qos_scheduler_queue.sv`](rtl/core/qos_scheduler_queue.sv) | Same-address dependency masks. | `tb_qos_scheduler_queue` |
| Command engine | [`ddr5_cmd_engine.sv`](rtl/backend/ddr5_cmd_engine.sv) | JEDEC timing FSM, refresh, RFM, victim refresh. | `tb_ddr5_cmd_engine`, JEDEC checker in every top-level TB |
| SEC-DED ECC | [`secded_72_64_pkg.sv`](rtl/backend/secded_72_64_pkg.sv), [`ecc_scrubber.sv`](rtl/backend/ecc_scrubber.sv) | Hamming (72,64), inverted check bits. The scrubber also implements zero-cycle fault masking (ZEM); **ZEM is not connected to the core read path** because it exceeded the timing budget (see [`LIMITATIONS.md`](LIMITATIONS.md)). | `tb_eccfail_zem_scrubber`, `tb_rt03_rd_integrity` |
| Chipkill RS(18,16) | [`rs_chipkill_decoder.sv`](rtl/backend/rs_chipkill_decoder.sv) | Standalone module, **not** wired into the top. | `tb_rs_chipkill_selfcheck` |
| Bus scrambler | [`bus_scrambler.sv`](rtl/memory/bus_scrambler.sv) | Pattern obfuscation, not encryption. | `tb_e2e_scoreboard` |
| Encryption/integrity bridge | [`qshield_axi_crypto_bridge.sv`](rtl/crypto/qshield_axi_crypto_bridge.sv) | AES-256-XTS, MAC, tree and cache around the core. Partial-strobe writes and non-16-byte-aligned bursts are rejected with SLVERR. | `tb_secure_top_integrity` |
| Integrity engines | [`qshield_bmt_engine.sv`](rtl/crypto/qshield_bmt_engine.sv), [`qshield_meta_cache.sv`](rtl/crypto/qshield_meta_cache.sv), [`qshield_mac_unit.sv`](rtl/crypto/qshield_mac_unit.sv), [`qshield_counter_unit.sv`](rtl/crypto/qshield_counter_unit.sv) | Bonsai Merkle tree, trusted cache, MAC, split counters. | `tb_qshield_bmt_engine`, `tb_qshield_meta_cache` |
| Canonical top | [`axi_ddr5_mc_top.sv`](rtl/top/axi_ddr5_mc_top.sv) | Controller core used for verification and synthesis. | `tb_axi_ddr5_mc_top` |
| Secure top | [`axi_ddr5_mc_secure_top.sv`](rtl/top/axi_ddr5_mc_secure_top.sv) | Core plus encryption and integrity layer. | `tb_axi_ddr5_mc_secure_top` |
| Demo top | [`sec_ddr5_controller_top.sv`](rtl/top/sec_ddr5_controller_top.sv) | Early integration demo. Do not use for results. | `tb_sec_ddr5_controller_top` |

## Known limitations (summary)

The full list is in [`LIMITATIONS.md`](LIMITATIONS.md). The most important ones:

- The controller core misses 400 MHz after place and route on the target FPGA (about 263 MHz achieved).
- Side-channel resistance is not claimed. The AES S-box is a lookup table.
- Chipkill is a standalone module and ZEM is not on the core read path.
- Formal results are bounded, and the integrity invariants are proven on an abstract model, not on the RTL.
- Performance and RowHammer-security results under cycle-accurate simulation are pending.
- No third-party certification (for example FIPS 140-3 or Common Criteria) is claimed. These are used only as
  reference frameworks; see [`docs/standards_matrix.md`](docs/standards_matrix.md).

## Documentation

| Document | Purpose |
| :--- | :--- |
| [`DESIGN.md`](DESIGN.md) | Microarchitecture and implementation results. |
| [`EVALUATION.md`](EVALUATION.md) | Evaluation protocol, what has been measured, and what is pending. |
| [`METHODOLOGY.md`](METHODOLOGY.md) | Experimental protocol. |
| [`FORMAL.md`](FORMAL.md) | Formal verification setup and status. |
| [`LIMITATIONS.md`](LIMITATIONS.md) | Threat model boundaries and known gaps. |
| [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) | How to rerun the tests. |
| [`INSTALL.md`](INSTALL.md), [`VERSIONING.md`](VERSIONING.md) | Toolchain and versions. |
| [`docs/standards_matrix.md`](docs/standards_matrix.md), [`docs/finding_cwe_map.md`](docs/finding_cwe_map.md) | Mapping to external standards and weakness classes. |

## Quick start

```bash
# Native (Ubuntu 22.04+ / WSL2), Icarus Verilog and Python 3.13
python3 -m pip install -r requirements.txt
python run_iverilog_regression.py --only tb_axi_ddr5_mc_top
python tools/check_multidriver.py
```

For the full regression and container setup see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md).

## License

MIT, see [`LICENSE`](LICENSE).
