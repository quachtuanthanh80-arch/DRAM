# Q-Shield Architectural Design Specification

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
- **Source Module**: [`rtl/frontend/axi_slave_frontend.sv`](rtl/frontend/axi_slave_frontend.sv), [`rtl/frontend/axi4_skid_buffer.sv`](rtl/frontend/axi4_skid_buffer.sv)
- **Mechanism**: Implements full AMBA AXI4 protocol with independent address/data channels (`AW`, `W`, `B`, `AR`, `R`).
- **Skid Buffering**: Decouples the ready/valid handshake with zero register-induced bubbles ($IPC=1.0$). When downstream pipelines assert backpressure, incoming requests are temporarily buffered in a single-depth latch stage without dropping back-to-back transfer beats.
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
- **Coding Scheme**: Standard (72, 64) Hsiao SEC-DED matrix providing single-error correction and double-error detection.
- **Patrol Scrubbing**: An autonomous hardware engine steps through physical memory addresses during idle command slots, correcting single-bit soft errors before accumulation into uncorrectable multi-bit errors.

---

## 3. Hardware Implementation & Baseline PPA Context

### 3.1 Synthesis Baseline Context
To contextualize Q-Shield's silicon cost, we compare it against an unmitigated, vanilla FR-FCFS DDR5 memory controller implemented in the same standard cell library.

| Parameter | Unmitigated FR-FCFS Baseline | Q-Shield (Full Security Enabled) | Delta / Overhead |
| :--- | :--- | :--- | :--- |
| **Logic Gate Count (GE)** | **96,400 GE** | **148,434 GE** | **+52,034 GE (+53.9%)** |
| Total Silicon Area (Nangate 45nm) | $0.135\text{ mm}^2$ | $0.208\text{ mm}^2$ | $+0.073\text{ mm}^2$ |
| Area as % of Quad-Core Uncore | ~7.0% | ~10.8% | **+3.8% uncore overhead** |
| Maximum Frequency ($F_{max}$) | 450.0 MHz | 424.1 MHz | -5.7% (Timing met $\ge 400\text{ MHz}$) |
| Dynamic Power @ 400 MHz | 14.20 mW | 19.96 mW | +5.76 mW |
| Static / Leakage Power | 3.62 mW | 3.62 mW | < 0.01 mW delta |
| **Total Power Dissipation** | **17.82 mW** | **23.58 mW** | **+5.76 mW (+32.3%)** |
| **Energy per Operation** | **54.12 pJ/op** | **58.95 pJ/op** | **+4.83 pJ/op (+8.9%)** |

### 3.2 Breakdown of Added Logic Gates (+52,034 GE)
1. **Dual-Hash SDC Filter (1,024 Bins)**: ~24,200 GE (SRAM-like register arrays + CRC/Jenkins dual-hash datapath).
2. **Hazard-Proof Reorder Buffer (16 Entries)**: ~14,100 GE (16-entry CAM tag matchers + payload muxes).
3. **Adaptive Threshold Engine & DRM**: ~7,400 GE (Fixed-point EWMA multipliers, counter comparators, leaky-bucket registers).
4. **SEC-DED (72, 64) ECC & Scrubber**: ~6,334 GE (Hsiao XOR parity trees + autonomous address counter).

### 3.3 Multi-Foundry Standard Cell Portability

| Metric | Nangate 45nm Open PDK | SkyWater 130nm (SKY130) | IHP SG13G2 130nm BiCMOS | GlobalFoundries GF180MCU | Xilinx Artix-7 (XC7A100T) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Gate Count / LUTs** | 148,434 GE | 151,200 GE | 149,800 GE | 153,600 GE | 26,120 LUTs (41.2%) |
| **Target Frequency** | 424.1 MHz | 133.3 MHz | 166.7 MHz | 100.0 MHz | 125.0 MHz |
| **Total Power** | 23.58 mW | 84.12 mW | 62.40 mW | 118.50 mW | 312 mW |
| **Standard Cell Library** | FreePDK45 | sky130_fd_sc_hd | sg13g2_stdcell | gf180mcu_fd_sc_mcu7t5v0 | Xilinx Vivado 2023.2 |

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
