# Q-Shield Architectural Design Specification

> **Provenance note (2026-10-30).** Ramulator-based throughput/overhead figures (SPEC CPU2017/PARSEC, ±σ), the "apples-to-apples" table and the Nangate 45 nm gate counts were not reproducible from this repository and are withdrawn. See `sim/results/PROVENANCE.md` for what each result file is, and the README section "What has been measured" for the numbers that are backed by runs.

This document provides the microarchitectural specification, operational mechanisms, module decompositions, and physical implementation trade-offs of **Q-Shield: A High-Throughput, Zero-Bubble & SDC-Resilient DDR5/DDR4 Secure Memory Controller**.

---

## 1. Architectural Overview

Q-Shield integrates RowHammer mitigation, Silent Data Corruption (SDC) resilience, and JEDEC DDR5/DDR4 command scheduling into a unified, pure-memory-controller pipeline. The architecture operates entirely at the memory controller side without requiring custom DRAM in-die modifications or external hypervisor coordination.

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
   │ - 1,024-Bin Counter  │ │ - 16-Entry Table   │ │ - (72,64) Hamming  │
   │ - Orthogonal Hashes  │ │ - In-Order Retire  │ │ - Patrol Scrubber  │
   │ - Single-Cycle Reset │ │ - RAW Hazard Check │ │ - Single-Cycle Corr│
   └──────────┬───────────┘ └────────┬───────────┘ └────────┬───────────┘
              │                      │                      │
              │     ┌────────────────▼────────────────┐     │
              │     │  Adaptive Threshold Engine(ATE) │     │
              │     │  - EWMA Aggressor Smoothing     │     │
              │     │  - Saturation Limits [16, 512]  │     │
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
                     │  - DDR5 / DDR4 Dual Mode      │
                     │  - tRCD, tRP, tRAS, tCCD Timers│
                     └───────────────┬───────────────┘
                                     │
                          DFI 5.0 PHY Interface
```

---

## 2. Microarchitectural Modules

### 2.1 AMBA AXI4 Frontend & Skid Buffering
- **Source Module**: [`rtl/frontend/axi_slave_frontend.sv`](rtl/frontend/axi_slave_frontend.sv), [`rtl/bus/axi4_skid_buffer.sv`](rtl/bus/axi4_skid_buffer.sv)
- **Mechanism**: Implements full AMBA AXI4 protocol with independent address/data channels (`AW`, `W`, `B`, `AR`, `R`).
- **Skid Buffering**: Decouples the ready/valid handshake intended to avoid register-induced bubbles (sustained throughput has not been measured separately). When downstream pipelines assert backpressure, incoming requests are temporarily buffered in a single-depth latch stage without dropping back-to-back transfer beats.
- **Boundary Detection**: Decomposes bursts crossing 4KB memory boundaries into compliant transactions per AMBA AXI specification section A3.4.1.

### 2.2 Dual-Hash SDC-Resilient Filter
- **Source Module**: [`rtl/core/sdc_resilient_filter.sv`](rtl/core/sdc_resilient_filter.sv)
- **Algorithm**: A 2-way associative Count-Min sketch with 1,024 physical bins per table. Uses orthogonal polynomials:
  $$\text{Hash}_1(\text{Row}) = \text{CRC16-CCITT}(x^{16} + x^{12} + x^5 + 1)$$
  $$\text{Hash}_2(\text{Row}) = \text{Jenkins-32 Bit Permutation}$$
- **O(1) Epoch Reset**: Traditional multi-entry counters require $O(N)$ clock cycles to zeroize upon refresh window expiration ($t_{REFW} = 64\text{ ms}$ or $32\text{ ms}$). Q-Shield uses an epoch-tag generation register: counter invalidation occurs in a **single clock cycle** ($O(1)$) by incrementing the active epoch identifier, preventing pipeline stalls during refresh boundaries.

### 2.3 Adaptive Threshold Engine (ATE)
- **Source Module**: [`rtl/core/adaptive_threshold_engine.sv`](rtl/core/adaptive_threshold_engine.sv)
- **Operational Rationale**: Static threshold defenses fail against non-uniform or phase-shifted RowHammer attacks (e.g., RowPress or alternating many-sided hammer).
- **Control Law**: Continuously monitors activation density $\lambda_{act}$ and modulates mitigation threshold $T_{thresh}$ via Exponentially Weighted Moving Average (EWMA):
  $$T_{k+1} = \text{clamp}\left( \alpha \cdot T_k + (1-\alpha) \cdot \frac{N_{bank\_act}}{\Delta t}, \; T_{min}, \; T_{max} \right)$$
  Where $\alpha = 0.875$, $T_{min} = 16$, and $T_{max} = 512$.

### 2.4 Dynamic Rate Limiter (DRM) & Backpressure
- **Source Module**: [`rtl/backend/directed_refresh_manager.sv`](rtl/backend/directed_refresh_manager.sv)
- **Mechanism**: Leaky-bucket rate pacing that throttles suspected aggressor rows rather than hard-killing memory channels.
- **Non-blocking Behavior**: If an aggressor bank is throttled, non-conflicting bank groups bypass the stalled queue through the Slack-Aware Arbiter, maintaining high memory bus utilization for benign threads.

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
- **Mathematical Structure**: 10-round Tweaked-Feistel permutation cipher with non-linear 4-bit S-Boxes.
- **Security Guarantee**: Bijective pseudo-random permutation mapping logical row/bank addresses to scrambled physical rows per epoch/bank tweak. Defeats spatial adjacency RowHammer patterns (ZenHammer on DDR5, Phoenix USENIX '24) with zero pipeline bubbles ($IPC = 1.0$).

### 2.8 Universal PXOR-Hash Engine
- **Source Module**: [`rtl/core/pxor_hash_engine.sv`](rtl/core/pxor_hash_engine.sv)
- **Algorithm**: Parallel XOR universal reduction tree over dynamic Toeplitz binary matrix parameterized by a 64-bit seed.
- **Purpose**: A seeded Toeplitz-style XOR reduction used to spread row addresses over Count-Min sketch bins so that an attacker cannot easily choose addresses that collide. No collision probability bound has been proven or measured for this implementation.

### 2.9 AMD SEV-SNP Style Multi-ASID Confidential Key Table
- **Source Module**: [`rtl/crypto/multi_vm_key_table.sv`](rtl/crypto/multi_vm_key_table.sv)
- **Architecture**: 16-VM hardware key storage table indexing 256-bit AES data keys and 128-bit XTS tweak keys by 4-bit Address Space ID (ASID).
- **Access Control**: APB4 supervisor-only write protection (`pprot[1] == 1'b1`) preventing unprivileged guest VMs or corrupted OS threads from modifying neighbor encryption keys. Hardware C-bit detection provides transparent zero-latency unencrypted DMA bypass.

### 2.10 Fault-Hardened CSR with TMR Glitch Watchdog
- **Source Module**: [`rtl/core/fault_hardened_csr.sv`](rtl/core/fault_hardened_csr.sv)
- **Redundancy Model**: Triple Modular Redundancy (TMR) across 3 physically isolated register rails with 2-out-of-3 bitwise majority voting.
- **Watchdog Protection**: Continuous rail comparison network triggering a real-time `o_glitch_alert` pulse and latching a permanent `o_security_locked` signal upon detecting clock or voltage glitch fault injection (HOST 2020 standard).

### 2.11 Two-Tier Decoupled Cryptographic Subsystem (0-Cycle AES-CTR Pre-computation)
- **Source Modules**: [`rtl/crypto/qshield_crypto_top.sv`](rtl/crypto/qshield_crypto_top.sv), [`rtl/crypto/split_counter_table.sv`](rtl/crypto/split_counter_table.sv), [`rtl/crypto/aes_ctr_keystream.sv`](rtl/crypto/aes_ctr_keystream.sv), [`rtl/crypto/integrity_mac_gen.sv`](rtl/crypto/integrity_mac_gen.sv)
- **Mechanism**: Decouples cryptographic execution from the critical data return path by overlapping a 14-stage AES-256-CTR keystream generation with physical DRAM row activation and read latency ($t_{RCD} + t_{CL} = 14\text{--}22$ cycles).
- **Split-Counter Table (SCT)**: Hierarchical Major (64-bit per page) and Minor (7-bit per line) counters limiting counter storage overhead to 1.56%.
- **Keystream Tag Buffer**: 16-entry CAM matching returning DRAM read tags to decrypt in 0 static cycles via combinational XOR.
- **Dynamic Security Profiles**: Profile 0 (Bypass), Profile 1 (Legacy inline XTS), Profile 2 (High-throughput decoupled CTR), and Profile 3 (Enterprise TEE with 64-bit MAC and ASIL-D fault poisoning).

### 2.12 Intended Deployment Scenarios (not evaluated)
The scenarios below describe where the controller could be used. They have not been implemented or evaluated in this repository.

- **Form Factor A (CXL 3.0 Type-3 Memory Expansion)**: Standard PCIe Gen5/Gen6 Add-In Card (AIC) or EDSFF E3.S module for cloud memory pooling and disaggregation, bridging CXL.mem subchannels to dual DDR5 RDIMMs with smooth SDC rate-pacing.
- **Form Factor B (Heterogeneous Chiplet IOD via UCIe 1.1)**: Dedicated I/O Die (IOD) connecting to host compute tiles via Universal Chiplet Interconnect Express (UCIe 1.1), governed by the packaging scaling law $\tau = \alpha \cdot \sqrt{\text{Area}} + \beta \cdot d_{\text{die}}$ to guarantee sub-nanosecond handshakes.

---

## 3. Hardware Implementation Results

All figures in this section come from Vivado 2026.1 reports for the Xilinx `xczu7ev-ffvc1156-2-e` device, run out of
context, and are stored in [`syn/reports/evidence/`](syn/reports/evidence/). ASIC area, power and energy figures that
appeared in earlier versions of this document were removed: no synthesis run in this repository produced them.

### 3.1 Core controller (`axi_ddr5_mc_top`) after place and route

| Target period | WNS | TNS (failing / total endpoints) | CLB LUTs | CLB registers | BRAM / DSP |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 2.500 ns (400 MHz) | -1.273 ns | -27,881 ns (61,510 / 107,309) | 65,170 (28.3 %) | 44,293 | 0 / 0 |
| 3.800 ns (263.16 MHz) | +0.024 ns | 0 ns (0 / 107,193) | 63,785 (27.7 %) | 44,243 | 0 / 0 |

The core closes timing at 3.8 ns and does not close at 2.5 ns. The worst path at 2.5 ns runs from the SDC filter
output (`u_sdc_filter/out_bg_reg`) to the QoS queue dependency register (`u_qos_queue/q_dep_reg`); routing accounts for
about 75 % of that path's delay. Synthesis-only slack for the same design was -0.022 ns at 2.5 ns, so synthesis
results alone are not a reliable predictor of the routed result.

### 3.2 Area by block (routed, 3.8 ns run)

Ten largest instances by LUT count ([`core_confirmed_route_util_hier.rpt`](syn/reports/evidence/core_confirmed_route_util_hier.rpt)):

| Instance | Module | Total LUTs | FFs |
| :--- | :--- | ---: | ---: |
| `u_qos_queue` | `qos_scheduler_queue` | 15,771 | 5,312 |
| `u_wds` | `wr_data_store` | 13,174 | 9,444 |
| `u_sdc_filter` | `sdc_resilient_filter` | 12,062 | 9,236 |
| `u_cmd_engine` | `ddr5_cmd_engine` | 10,146 | 4,395 |
| `u_rob` | `reorder_buffer_rob` | 4,533 | 9,211 |
| `u_drm` | `directed_refresh_manager` | 2,425 | 2,354 |
| `u_rd_iq` | `rd_issue_queue` | 1,317 | 503 |
| `u_bank_credit` | `bank_credit_ctrl` | 954 | 204 |
| `u_addr_mapper` | `addr_mapper_ddr5` | 472 | 153 |
| `u_wr_ks` | `scrambler_ks_pipe` | 446 | 450 |

### 3.3 Power

Vivado's vectorless estimate at 263.16 MHz is 1.618 W total (1.021 W dynamic, 0.597 W static)
([`core_confirmed_route_power.rpt`](syn/reports/evidence/core_confirmed_route_power.rpt)). No switching-activity file was
used, so this is a rough estimate and not a measurement.

### 3.4 Secure top (`axi_ddr5_mc_secure_top`)

Place and route on `xczu7ev`:

| Target period | WNS | TNS (failing / total endpoints) | CLB LUTs | CLB registers | BRAM |
|---|---|---|---|---|---|
| 2.500 ns (400 MHz) | -1.595 ns | -61,801.969 ns (124,925 / 243,888) | 165,587 | 110,298 | 7.5 |
| 4.100 ns (243.90 MHz) | -0.005 ns | -0.010 ns (3 / 243,659) | 164,064 | 110,185 | 7.5 |
| 4.150 ns (240.96 MHz) | **+0.021 ns** | 0 ns (0 / 243,670) | 164,062 (71.2 %) | 110,190 | 7.5 |

The highest clock that closed timing for the secure top is about **241 MHz**. The 4.1 ns run missed by 0.005 ns and is
kept in the table. Vivado's vectorless power estimate at 4.15 ns is 4.437 W (rough estimate, not a measurement). Reports:
[2.5 ns timing](syn/reports/evidence/sec_2500ps_route_timing.rpt), [4.1 ns timing](syn/reports/evidence/sec_confirmed_route_timing.rpt),
[4.15 ns timing](syn/reports/evidence/sec_confirmed_r2_route_timing.rpt), [4.15 ns utilization](syn/reports/evidence/sec_confirmed_r2_route_util.rpt),
[4.15 ns power](syn/reports/evidence/sec_confirmed_r2_route_power.rpt). Synthesis-only result at 2.5 ns after the multi-driver fix: WNS -0.385 ns,
169,365 LUTs ([report](syn/reports/evidence/secure_top_synth_T44_timing.rpt)).

The metadata cache alone reaches +0.037 ns at 2.5 ns in synthesis
([report](syn/reports/evidence/meta_cache_synth_timing.rpt)). The secure top is therefore about 22 MHz slower than the
core; this is the frequency cost of the encryption and integrity layer.

### 3.5 Not yet measured

ASIC (Nangate45 or other PDK) area, power and timing; energy per operation; multi-foundry portability. These will be
added only with a run and a report.

---

## 4. Signal Handshaking & Timing Constraints

1. **AXI4 Slave Latency**: Minimum read latency through the skid buffer is 2 clock cycles (registered request + registered response).
2. **SDC Invalidation**: Single-cycle epoch pulse invalidates the active table by toggling `epoch_gen[0] ^ epoch_gen[1]`.
3. **Command Issue Timing**: The DDR5 Command FSM strictly enforces JEDEC timings:
   - $t_{RCD} = 13.75\text{ ns}$ (14 cycles @ 1 GHz DDR5 core)
   - $t_{RP} = 13.75\text{ ns}$ (14 cycles)
   - $t_{RAS} = 32.00\text{ ns}$ (32 cycles)
   - $t_{CCD\_L} = 5.00\text{ ns}$ (same bank group access spacing)
   - $t_{CCD\_S} = 2.50\text{ ns}$ (different bank group access spacing)
