# Q-Shield Architectural Design Specification

> **Provenance note.** Earlier unbacked Ramulator throughput/overhead tables (SPEC CPU2017/PARSEC, ±σ), the legacy "apples-to-apples" table, and the Nangate 45 nm gate counts were withdrawn. See `sim/results/PROVENANCE.md` for legacy files, `reports/paper/fpga/` for post-route FPGA PPA, and `reports/paper/perf/` for measured Ramulator2 DDR5 evaluations.

This document provides the microarchitectural specification, operational mechanisms, module decompositions, and physical implementation trade-offs of **Q-Shield: A High-Throughput, Zero-Bubble & SDC-Resilient DDR5 Secure Memory Controller**.

---

## 1. Architectural Overview

Q-Shield integrates RowHammer mitigation, Silent Data Corruption (SDC) resilience, and JEDEC DDR5 command scheduling into a unified, pure-memory-controller pipeline. The architecture operates entirely at the memory controller side without requiring custom DRAM in-die modifications or external hypervisor coordination.

```
                          AMBA AXI4 Slave Interface
                                     │
                     ┌───────────────▼───────────────┐
                     │ Zero-Bubble Skid Buffer Engine│
                     │  - 4KB Boundary Decomposer    │
                     │  - Non-blocking Forward Path  │
                     └───────────────┬───────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
   ┌──────────▼───────────┐ ┌────────▼───────────┐ ┌────────▼───────────┐
   │ Dual-Hash SDC Filter │ │  Hazard-Proof ROB  │ │ Autonomous SEC-DED │
   │ - 256-Bin/Table (x2) │ │ - 16-Entry Table   │ │ - (72,64) Hamming  │
   │ - PXOR / Mod+CRC-8   │ │ - In-Order Retire  │ │ - Patrol Scrubber  │
   │ - Single-Cycle Reset │ │ - RAW Hazard Check │ │ - Single-Cycle Corr│
   └──────────┬───────────┘ └────────┬───────────┘ └────────┬───────────┘
              │                      │                      │
              │     ┌────────────────▼────────────────┐     │
              │     │  Adaptive Threshold Engine(ATE) │     │
              │     │  - EWMA Aggressor Smoothing     │     │
              │     │  - CSR Clamp [base, max]        │     │
              │     └────────────────┬────────────────┘     │
              │                      │                      │
              └──────────────────────┼──────────────────────┘
                                     │
                     ┌───────────────▼───────────────┐
                     │ Timing-Slack Aware QoS Arbiter│
                     │  - Opportunistic BG Bypassing │
                     │  - Dynamic Rate Limiter (DRM) │
                     └───────────────┬───────────────┘
                                     │
                     ┌───────────────▼───────────────┐
                     │ JEDEC Command Generation FSM  │
                     │  - DDR5 Subchannel Mode       │
                     │  - tRCD, tRP, tRAS, tCCD Timers│
                     └───────────────┬───────────────┘
                                     │
                          DFI 5.0 PHY Interface
```

---

## 2. Microarchitectural Modules

### 2.1 AMBA AXI4 Frontend & Skid Buffering
- **Source Module**: [`rtl/frontend/axi_slave_frontend.sv`](rtl/frontend/axi_slave_frontend.sv), [`rtl/bus/axi4_skid_buffer.sv`](rtl/bus/axi4_skid_buffer.sv)
- **Mechanism**: Implements AMBA AXI4 slave channels (`AW`, `W`, `B`, `AR`, `R`).
- **Skid Buffering**: Decouples the ready/valid handshake intended to avoid register-induced bubbles (sustained throughput has not been measured separately). When downstream pipelines assert backpressure, incoming requests are temporarily buffered in a single-depth latch stage without dropping back-to-back transfer beats.
- **Boundary Detection**: Decomposes bursts crossing 4KB memory boundaries into transactions designed according to AMBA AXI4 specification section A3.4.1.

### 2.2 Dual-Hash SDC-Resilient Filter
- **Source Module**: [`rtl/core/sdc_resilient_filter.sv`](rtl/core/sdc_resilient_filter.sv)
- **Algorithm**: A 2-table Count-Min sketch parameterized with `TABLE_ENTRIES = 256` physical bins per table (512 bins total, 16-bit saturating counters per bin). Selects via `cfg_pxor_mode` between seeded PXOR universal hashing (adapted from the incremental universal hash construction of Crystalor, Ueno et al., CCS '24, using 64-bit `cfg_pxor_seed`) and Modulo/CRC-8 indexing, with Subtract-$T$ counter decrement on mitigation trigger (`T86`) and 32-bank `{bg, bank}` coordinated throttling (`cfg_multibank_thresh`).
- **O(1) Epoch Reset**: Traditional multi-entry counters require $O(N)$ clock cycles to zeroize upon refresh window expiration ($t_{REFW} = 32\text{ ms}$ in DDR5, fixed at `REFW_REFS = 8192` periodic `REFab` ticks). Q-Shield uses an epoch-tag generation register: counter invalidation occurs in a **single clock cycle** ($O(1)$) by incrementing the active epoch identifier, preventing pipeline stalls during refresh boundaries.

### 2.3 Adaptive Threshold Engine (ATE)
- **Source Module**: [`rtl/core/adaptive_threshold_engine.sv`](rtl/core/adaptive_threshold_engine.sv)
- **Operational Rationale**: Static threshold defenses face varying activation densities across workloads and attack patterns (e.g., RowPress or alternating many-sided hammer).
- **Control Law**: Samples access and throttle telemetry every `WINDOW_CYCLES = 1024` cycles and updates the dynamic threshold via a 3-stage pipelined EWMA with saturating arithmetic (`COUNT_WIDTH + 1` bit, `T88`):
  - Default smoothing factor `ALPHA_SHIFT_DEF = 4` ($\alpha = 1/16$, runtime-configurable via `cfg_alpha_shift`).
  - Default bounds `base_thresh = 2048` and `max_thresh = 8192` (runtime-configurable via `cfg_base_thresh` and `cfg_max_thresh`, with `cfg_max_thresh` wired to `voted_rh_threshold` in `axi_ddr5_mc_top.sv`).

### 2.4 Dynamic Rate Limiter (DRM) & Backpressure
- **Source Module**: [`rtl/backend/directed_refresh_manager.sv`](rtl/backend/directed_refresh_manager.sv)
- **Mechanism**: Leaky-bucket rate pacing that throttles suspected aggressor rows rather than hard-blocking all memory channels.
- **Non-blocking Behavior**: If an aggressor bank is throttled, non-conflicting bank groups bypass the stalled queue through the Slack-Aware Arbiter, preserving memory bus utilization for benign threads.

### 2.5 Hazard-Proof Reorder Buffer (ROB)
- **Source Module**: [`rtl/core/reorder_buffer_rob.sv`](rtl/core/reorder_buffer_rob.sv)
- **Structure**: 16-entry circular FIFO with content-addressable memory (CAM) lookup.
- **Hazard Resolution**: Eliminates Read-After-Write (RAW) data hazards by tracking in-flight write addresses. If a read targets a pending write address, it either forwards data directly from the write buffer or stalls until the write retires, ensuring strict in-order memory consistency at retirement.

### 2.6 SEC-DED (72, 64) Hamming Engine & Autonomous Scrubber
- **Source Module**: [`rtl/backend/ecc_scrubber.sv`](rtl/backend/ecc_scrubber.sv)
- **Coding Scheme**: Extended Hamming (72, 64) SEC-DED (masks equal to OpenTitan `prim_secded_hamming_72_64`) providing single-error correction and double-error detection. Check bits are stored inverted (XOR `0xAA`, OpenTitan `prim_secded_inv` style) so all-zero / all-one words are never valid codewords.
- **Patrol Scrubbing**: An autonomous hardware engine steps through physical memory addresses during idle command slots, correcting single-bit soft errors before accumulation into uncorrectable multi-bit errors.

### 2.7 SCARF 1-Cycle Low-Latency DRAM Address Randomizer
- **Source Module**: [`rtl/core/scarf_dram_randomizer.sv`](rtl/core/scarf_dram_randomizer.sv)
- **Mathematical Structure**: 10-round Tweaked-Feistel permutation cipher with non-linear 4-bit S-Boxes (adapted from SCARF, Canale et al., USENIX Security '23, originally proposed for cache randomization).
- **Design Objective**: Bijective pseudo-random permutation mapping logical row/bank addresses to scrambled physical rows per epoch/bank tweak, intended to disrupt spatial adjacency RowHammer patterns (such as ZenHammer, USENIX Security '24, and Phoenix, IEEE S&P '26) within a single combinational mapping stage (standalone IPC overhead has not been isolated separately).

### 2.8 Universal PXOR-Hash Engine
- **Source Module**: [`rtl/core/pxor_hash_engine.sv`](rtl/core/pxor_hash_engine.sv)
- **Algorithm**: Parallel XOR universal reduction tree over dynamic Toeplitz binary matrix parameterized by a 64-bit seed.
- **Purpose**: A seeded Toeplitz-style XOR reduction used to spread row addresses over Count-Min sketch bins so that an attacker without the seed cannot easily choose addresses that collide. No collision probability bound has been formally proven for this implementation; known-seed collisions are documented as a threat-model boundary in [`LIMITATIONS.md`](LIMITATIONS.md).

### 2.9 Multi-ASID Confidential Key Table
- **Source Module**: [`rtl/crypto/multi_vm_key_table.sv`](rtl/crypto/multi_vm_key_table.sv)
- **Architecture**: 16-VM hardware key storage table indexing 256-bit AES data keys and 128-bit XTS tweak keys by 4-bit Address Space ID (ASID), modeled after confidential-computing key isolation.
- **Access Control**: APB4 supervisor-only write protection (`pprot[1] == 1'b1`) preventing unprivileged guest VMs or corrupted OS threads from modifying neighbor encryption keys. Hardware C-bit detection provides unencrypted DMA bypass.

### 2.10 Fault-Hardened CSR with TMR Glitch Watchdog
- **Source Module**: [`rtl/core/fault_hardened_csr.sv`](rtl/core/fault_hardened_csr.sv)
- **Redundancy Model**: Triple Modular Redundancy (TMR) across 3 register rails with 2-out-of-3 bitwise majority voting.
- **Watchdog Protection**: Continuous rail comparison network triggering a real-time `o_glitch_alert` pulse and latching a permanent `o_security_locked` signal upon detecting single-rail fault upsets (motivated by hardware fault-injection attacks such as Nashimoto et al., 2020).

### 2.11 Encryption & Integrity Bridge (Secure Top) and Standalone Crypto Modules
- **Integrated Secure Wrapper**: [`rtl/top/axi_ddr5_mc_secure_top.sv`](rtl/top/axi_ddr5_mc_secure_top.sv) wraps the canonical core with [`rtl/crypto/qshield_axi_crypto_bridge.sv`](rtl/crypto/qshield_axi_crypto_bridge.sv), [`rtl/crypto/qshield_bmt_engine.sv`](rtl/crypto/qshield_bmt_engine.sv), [`rtl/crypto/qshield_meta_cache.sv`](rtl/crypto/qshield_meta_cache.sv), [`rtl/crypto/qshield_mac_unit.sv`](rtl/crypto/qshield_mac_unit.sv), [`rtl/crypto/qshield_counter_unit.sv`](rtl/crypto/qshield_counter_unit.sv), and [`rtl/crypto/qshield_xts_tweak_unit.sv`](rtl/crypto/qshield_xts_tweak_unit.sv) (AES-256-XTS per IEEE Std 1619, 64-bit Carter-Wegman MAC over $\mathrm{GF}(2^{128})$, 8-ary Bonsai Merkle Tree, and 4 KB 64-entry trusted metadata cache).
- **Standalone / Demo Modules**: [`rtl/crypto/qshield_crypto_top.sv`](rtl/crypto/qshield_crypto_top.sv), [`rtl/crypto/split_counter_table.sv`](rtl/crypto/split_counter_table.sv), [`rtl/crypto/aes_ctr_keystream.sv`](rtl/crypto/aes_ctr_keystream.sv), and [`rtl/crypto/integrity_mac_gen.sv`](rtl/crypto/integrity_mac_gen.sv) are retained as standalone/demo components and are **not** wired into the canonical `axi_ddr5_mc_top` or `axi_ddr5_mc_secure_top` datapath.

### 2.12 Intended Deployment Scenarios (not evaluated)
The scenarios below describe where the controller could be used. They have not been implemented or evaluated in this repository.

- **Form Factor A (CXL 3.0 Type-3 Memory Expansion)**: PCIe Gen5/Gen6 Add-In Card (AIC) or EDSFF E3.S module for cloud memory pooling and disaggregation, bridging CXL.mem subchannels to dual DDR5 RDIMMs with smooth SDC rate-pacing.
- **Form Factor B (Heterogeneous Chiplet IOD via UCIe 1.1)**: Dedicated I/O Die (IOD) connecting to host compute tiles via Universal Chiplet Interconnect Express (UCIe 1.1), targeting low-latency die-to-die handshakes (not implemented or evaluated).

---

## 3. Hardware Implementation Results

All figures in this section come from Vivado 2026.1 post-route reports for the Xilinx `xczu7ev-ffvc1156-2-e` device, run out of
context on the post-T86/T88 RTL, and are stored in [`reports/paper/fpga/t89/`](reports/paper/fpga/t89/) and [`reports/paper/fpga/t92/`](reports/paper/fpga/t92/). ASIC area, power and energy figures that
appeared in earlier versions of this document were removed: no synthesis run in this repository produced them.

### 3.1 Core controller (`axi_ddr5_mc_top`) after place and route

| Target period | WNS | TNS (failing / total endpoints) | CLB LUTs | CLB registers | BRAM / DSP |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 2.500 ns (400 MHz, T89) | -1.673 ns | -40,375.344 ns (70,632 / 107,881) | 64,147 | 44,574 | 0 / 0 |
| 4.200 ns (238.10 MHz, T89) | +0.076 ns | 0.000 ns (0 / 107,895) | 62,623 (27.18 %) | 44,581 | 0 / 0 |
| 3.900 ns (256.41 MHz, T92) | +0.014 ns | 0.000 ns (0 / 107,704) | 62,699 (27.21 %) | 44,485 | 0 / 0 |

The core closes timing at `3.900 ns` (`256.41 MHz`, **confirmed upper bound; periods below `3.900 ns` have not yet been swept**) and does not close at `2.500 ns`. The worst routed path at `2.500 ns` runs inside the command engine from `u_cmd_engine/s_mit_reg[22]` to `u_cmd_engine/pk_oh_reg[31]` (`4.154 ns` data path delay; routing accounts for `78.308 %` of that path's delay; [`core_2500ps_route_timing.rpt`](reports/paper/fpga/t89/core_2500ps_route_timing.rpt)). Synthesis-only slack for the same RTL was `-0.508 ns` at `2.500 ns` (`t88_after`), confirming that synthesis results alone are not a reliable predictor of the routed result.

### 3.2 Area by block (routed, `3.900 ns` T92 run)

Ten largest instances by LUT count ([`core_3900ps_route_util_hier.rpt`](reports/paper/fpga/t92/core_3900ps_route_util_hier.rpt)):

| Instance | Module | Total LUTs | FFs |
| :--- | :--- | ---: | ---: |
| `u_qos_queue` | `qos_scheduler_queue` | 13,929 | 5,374 |
| `u_wds` | `wr_data_store` | 13,165 | 9,444 |
| `u_sdc_filter` | `sdc_resilient_filter` | 11,692 | 9,327 |
| `u_cmd_engine` | `ddr5_cmd_engine` | 9,925 | 4,408 |
| `u_rob` | `reorder_buffer_rob` | 4,503 | 9,211 |
| `u_drm` | `directed_refresh_manager` | 3,870 | 2,432 |
| `u_rd_iq` | `rd_issue_queue` | 1,309 | 503 |
| `u_bank_credit` | `bank_credit_ctrl` | 944 | 204 |
| `u_addr_mapper` | `addr_mapper_ddr5` | 449 | 153 |
| `u_wr_ks` | `scrambler_ks_pipe` | 446 | 449 |

### 3.3 Power

Vivado's vectorless estimate at `256.41 MHz` (`3.900 ns`) is `1.645 W` total (`1.048 W` dynamic, `0.597 W` static;
[`core_3900ps_route_power.rpt`](reports/paper/fpga/t92/core_3900ps_route_power.rpt)), and `1.572 W` (`0.975 W` dynamic, `0.597 W` static) at `238.10 MHz` (`4.200 ns`; [`core_confirmed_route_power.rpt`](reports/paper/fpga/t89/core_confirmed_route_power.rpt)). No switching-activity file was used, so these are rough estimates and not measurements.

### 3.4 Secure top (`axi_ddr5_mc_secure_top`)

Place and route on `xczu7ev` on post-T86/T88 RTL ([`reports/paper/fpga/t89/`](reports/paper/fpga/t89/)):

| Target period | WNS | TNS (failing / total endpoints) | CLB LUTs | CLB registers | BRAM |
|---|---|---|---|---|---|
| 2.500 ns (400 MHz, T89) | -1.648 ns | -81,083.195 ns (132,736 / 244,412) | 167,139 | 110,454 | 7.5 |
| 4.150 ns (240.96 MHz, T89) | **+0.018 ns** | 0.000 ns (0 / 244,317) | 165,776 (71.95 %) | 110,405 | 7.5 |

The highest clock that closed timing for the secure top is **240.96 MHz** (`4.150 ns`). An earlier pre-T86/T88 run at `4.100 ns` (`243.90 MHz`) missed by `-0.005 ns` (`3 / 243,659` failing endpoints; [`sec_confirmed_route_timing.rpt`](syn/reports/evidence/sec_confirmed_route_timing.rpt)). Vivado's vectorless power estimate at `4.150 ns` is `4.301 W` (`3.689 W` dynamic, `0.612 W` static; rough estimate, not a measurement). Reports:
[`fpga_ppa_summary.md` (T89)](reports/paper/fpga/t89/fpga_ppa_summary.md), [`2.5 ns timing`](reports/paper/fpga/t89/sec_2500ps_route_timing.rpt),
[`4.15 ns timing`](reports/paper/fpga/t89/sec_confirmed_route_timing.rpt), [`4.15 ns utilization`](reports/paper/fpga/t89/sec_confirmed_route_util.rpt),
[`4.15 ns power`](reports/paper/fpga/t89/sec_confirmed_route_power.rpt).

The metadata cache alone reaches `+0.037 ns` at `2.500 ns` in synthesis
([report](syn/reports/evidence/meta_cache_synth_timing.rpt)). Compared against the confirmed `256.41 MHz` core upper bound, the encryption and integrity layer reduces post-route frequency by about `15.45 MHz` (`256.41 MHz` vs `240.96 MHz`).

### 3.5 Not yet measured

ASIC (Nangate45 or other PDK) area, power and timing; energy per operation; multi-foundry portability. These will be
added only with a run and a report.

---

## 4. Signal Handshaking & Timing Constraints

1. **AXI4 Slave Latency**: Minimum read latency through the skid buffer is 2 clock cycles (registered request + registered response).
2. **SDC Invalidation**: Single-cycle epoch pulse invalidates the active table by toggling `epoch_gen[0] ^ epoch_gen[1]`.
3. **Command Issue Timing**: The DDR5 Command FSM (`rtl/backend/ddr5_cmd_engine.sv`) is parameterized against JEDEC JESD79-5 DDR5-16Gb timing intervals at the `2.500 ns` (`400 MHz`) controller target clock:
   - `T_RCD = 7` cycles (`17.5 ns`)
   - `T_RP = 7` cycles (`17.5 ns`)
   - `T_RAS = 13` cycles (`32.5 ns`)
   - `T_RFC = 118` cycles (`295.0 ns`)
   - `T_REFI = 1560` cycles (`3.9 us`)
   - `T_FAW = 10` cycles (`25.0 ns`)
