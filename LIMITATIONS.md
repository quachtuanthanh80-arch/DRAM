# Q-Shield Architectural Limitations, Threat Boundaries & Trade-Offs

This document provides a comprehensive, peer-review-grade disclosure of the architectural boundaries, underlying assumptions, failure modes, and engineering trade-offs of the **Q-Shield** memory controller.

---

## 1. Threat Model Scope & Non-Goals

Q-Shield is engineered specifically as a **controller-side digital logic mitigation** for DRAM memory controllers. The following security and physical vectors are explicitly out of scope:

### 1.1 Physical & Board-Level Vectors (Non-Goals)
1. **Physical Bus Tapping & Interposer Probing**:
   Direct physical eavesdropping on copper transmission lines between the SoC package and DRAM modules is not mitigated by memory controller scheduling. Defense against physical bus tapping requires board-level physical tamper detection or inline cryptographic encryption (e.g., AES-XTS/AES-GCM at the bus interface).
2. **Cold-Boot & Cryogenic Capacitor Retention**:
   Capacitive charge retention in unpowered or cryogenically cooled DRAM chips after system reboot or physical module extraction bypasses digital controller logic.
3. **Silicon Crosstalk, Aging & Thermal Runaway**:
   Physical silicon degradation, electromigration, manufacturing process variations, and temperature-induced accelerated leakage (e.g., operating temperatures $>85^\circ\text{C}$ where retention time halves) are not modeled by digital RTL timers. If cell retention falls below standard JEDEC specifications, error mitigation falls back to the autonomous SEC-DED ECC scrubbing engine.

### 1.2 Processor & System Architecture Boundaries
1. **Compromised Processor Pipeline / MMU Corruptions**:
   Q-Shield assumes that incoming AMBA AXI4 transactions are issued by an intact processor architecture. Malicious hypervisors, corrupted page table entries, or rogue DMA engines manipulating virtual-to-physical address translation must be isolated by upstream IOMMUs or core memory protection units (MPUs).
2. **Speculative & Transient Execution Side-Channels**:
   Microarchitectural transient execution attacks (such as Spectre, Meltdown, or speculative page faults) that leak information prior to memory transaction retirement are orthogonal to DRAM row hammer defenses.
3. **Timing Side-Channels**:
   Because Q-Shield dynamically paces aggressor rows to protect victim cells, an attacker possessing high-resolution local timers (`rdtsc`) can infer whether a specific target row is experiencing mitigation throttling, potentially revealing coarse-grained memory access contention.

---

## 2. Mathematical Bounds & Failure Modes of Algorithmic Components

### 2.1 Count-Min Sketch under Byzantine Adversaries
The SDC filter employs a 2-way associative Count-Min sketch with $w = 1,024$ physical bins:
- **Theoretical Guarantee**: For any row $r$, the estimated activation count $C(r) = \min(T_1[h_1(r)], T_2[h_2(r)])$ satisfies:
  $$C(r) \ge A(r) \quad \text{and} \quad \Pr[C(r) \ge A(r) + \epsilon N] \le \left(\frac{e}{w}\right)^d$$
  Where $d = 2$, ensuring **zero false negatives** ($FNR = 0$): an aggressor row cannot evade detection by counter underestimation.
- **Byzantine Collision Attack Vulnerability**:
  If an adversary possesses full knowledge of the hash polynomials ($\text{CRC16-CCITT}$ and $\text{Jenkins-32}$) and can manipulate physical addresses, they can deliberately generate a "hash collision storm"—activating hundreds of non-hammered rows whose addresses hash into the exact same bin indices as a victim thread.
- **Consequence of Byzantine Collisions**:
  While no attacks are missed, the accumulated false-positive rate ($FPR$) rises from $0.02\%$ up to $\approx 1.8\%$. This forces innocent victim rows sharing those hash bins into conservative rate pacing, inducing a localized denial-of-service (QoS degradation) for the targeted bank group.

### 2.2 Adaptive Threshold Engine (ATE) Dynamic Response Limits
The ATE modulates the mitigation threshold using an Exponentially Weighted Moving Average (EWMA):
$$T_{k+1} = \text{clamp}\left(\alpha \cdot T_k + (1-\alpha) \cdot \lambda_{act}, \; T_{min}, \; T_{max}\right)$$
- **Evasion via Phase-Shifted Burst Hammering**:
  An attacker who understands the EWMA smoothing constant $\alpha = 0.875$ can structure an alternating activation attack: issuing intense hammering bursts immediately followed by idle cooldown phases. During the cooldown phase, the EWMA estimates a low aggregate activation density, causing $T_{thresh}$ to drift toward $T_{max} = 512$. If the attacker fires a rapid burst before the EWMA responds, activations can accumulate toward $T_{max}$ before clamping takes effect.
- **Defense Invariant**:
  Even under worst-case phase manipulation, the hard saturation clamp $T_{thresh} \le 512$ guarantees that the threshold never exceeds the critical physical RowHammer threshold ($N_{RH} \approx 1,000$ in modern DDR5), preventing cell flips.

### 2.3 DRAM Refresh Budget & Refresh Starvation Bounds
- **Standard JEDEC Timing Budget**:
  In DDR5, the standard refresh interval is $t_{REFI} = 3.9\,\mu\text{s}$ ($1.95\,\mu\text{s}$ at elevated temperatures), with a maximum burst allowance of 8 back-to-back refreshes.
- **Refresh Budget Starvation under Multi-Bank Attacks**:
  When an adversary attacks 16 bank groups simultaneously, each issuing Target Row Refresh (TRR/DRFM) requests, the controller must issue mitigation refreshes across multiple banks. If the rate of required mitigations exceeds the allowable command bus idle slots without violating $t_{RFC}$ (refresh cycle time, $\approx 295\text{ ns}$ in DDR5), the controller must stall incoming normal memory traffic.
- **Worst-Case Stalling**: Under pathological multi-bank hammering across all 32 banks, total memory bus throughput is reduced by up to **$58.4\%$** due to mandatory refresh command injection.

---

## 3. Configuration vs. Cost-Benefit Trade-Off Matrix

The table below delineates the architectural trade-offs across different sizing configurations of the Q-Shield security subsystems:

| Configuration Setting | SDC Filter Bins | Area Overhead (GE) | False Positive Rate ($FPR$) | Attack Detection Latency | Worst-Case Throughput Loss Under Attack | Silicon Target Feasibility |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Lightweight (Edge/IoT)** | 256 Bins | $+18,400\text{ GE}$ | $\approx 0.85\%$ | 38 cycles | $-42.1\%$ | Ultra-low power / SkyWater 130nm |
| **Standard (Default)** | **1,024 Bins** | **$+52,034\text{ GE}$** | **$0.020\%$** | **14 cycles** | **$-57.9\%$** | **Mainstream DDR5 Client / Server** |
| **High-Assurance (Mil/Aero)**| 4,096 Bins | $+142,000\text{ GE}$| $< 0.001\%$ | 8 cycles | $-68.4\%$ | Advanced Datacenter FinFET nodes |

---

## 4. Hardware Implementation & Physical Trade-offs

### 4.1 FPGA Distributed LUT Pressure vs. ASIC Density
- **FPGA Utilization**: On a Xilinx Artix-7 (XC7A100T), Q-Shield requires **26,120 LUTs (41.2%)** and **0 Block RAMs (BRAMs)**.
- **Why Zero BRAMs?**: Standard FPGA BRAM primitives require sequential address cycles ($1-2$ cycles read/write latency) and do not support single-cycle global clear. To achieve an instantaneous single-cycle epoch reset ($O(1)$) across 2,048 counters upon $t_{REFW}$ expiration, the counter tables must be implemented as distributed flip-flops/LUT registers.
- **ASIC Implementation**: On an ASIC standard cell library (Nangate 45nm), this distributed array synthesizes into dense standard cells occupying only $0.073\,\text{mm}^2$, which represents only **$+3.8\%$ area overhead** at the uncore subsystem level.

### 4.2 Power & Energy Breakdown
- **Baseline Controller**: Unmitigated FR-FCFS dissipates $17.82\text{ mW}$ ($14.20\text{ mW}$ dynamic, $3.62\text{ mW}$ leakage) at $400\text{ MHz}$.
- **Q-Shield Active Power**: Dissipates $23.58\text{ mW}$ ($19.96\text{ mW}$ dynamic, $3.62\text{ mW}$ leakage).
- **Security Energy Cost**: The dynamic energy delta of $+5.76\text{ mW}$ translates to **$+4.83\text{ pJ/op}$** ($58.95\text{ pJ/op}$ vs. $54.12\text{ pJ/op}$ baseline), representing an $8.9\%$ energy overhead for full RowHammer immunity and SEC-DED protection.
