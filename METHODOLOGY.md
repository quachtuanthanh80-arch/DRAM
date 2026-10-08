# Q-Shield Evaluation Methodology & Experimental Rigor

This document details the scientific evaluation methodology, benchmark suites, fairness criteria, and statistical models governing the empirical validation of the **Q-Shield** memory controller.

---

## 1. Architectural Simulation Environment

Cycle-accurate hardware performance is evaluated using **Ramulator 2.0**, extended with dual 32-bit subchannel DDR5 scheduling models conforming to JEDEC JESD79-5.

### Clock Distribution & Synchronization
- **Processor / AXI Interconnect Domain**: $250\,\text{MHz}$ ($4.0\,\text{ns}$ cycle time).
- **Memory Controller & DRAM Core Domain**: $400\,\text{MHz}$ ($2.5\,\text{ns}$ cycle time).
- **Clock Domain Crossing (CDC)**: Modeled cycle-accurately via dual-clock Gray-code asynchronous FIFOs (`async_fifo_cdc.sv`) introducing a 2-stage synchronizer flip-flop latency ($8.0\,\text{ns}$ crossing penalty).

---

## 2. DRAM Physical Configurations

Simulations model standardized JEDEC memory timings to eliminate arbitrary configuration bias:

| Parameter | JEDEC DDR5-4800B (Primary Target) | JEDEC DDR5-5600B | JEDEC DDR4-3200AA (Baseline) |
| :--- | :---: | :---: | :---: |
| **Channel Organization** | 2 $\times$ 32-bit Subchannels | 2 $\times$ 32-bit Subchannels | 1 $\times$ 64-bit Channel |
| **Ranks per Channel** | 1 Rank | 1 Rank | 1 Rank |
| **Bank Groups (BG)** | 8 Bank Groups | 8 Bank Groups | 4 Bank Groups |
| **Banks per Group** | 4 Banks / BG (32 Total) | 4 Banks / BG (32 Total) | 4 Banks / BG (16 Total) |
| **Bus Cycle ($t_{\mathrm{CK}}$)** | $0.416\,\text{ns}$ | $0.357\,\text{ns}$ | $0.625\,\text{ns}$ |
| **Core Timing ($t_{\mathrm{CL}}-t_{\mathrm{RCD}}-t_{\mathrm{RP}}$)** | $40-40-40$ | $46-46-46$ | $22-22-22$ |
| **Row Active Time ($t_{\mathrm{RAS}}$)** | 64 cycles ($26.6\,\text{ns}$) | 72 cycles ($25.7\,\text{ns}$) | 52 cycles ($32.5\,\text{ns}$) |
| **Refresh Interval ($t_{\mathrm{REFI}}$)** | $3.9\,\mu\text{s}$ | $3.9\,\mu\text{s}$ | $7.8\,\mu\text{s}$ |
| **Refresh Cycle Time ($t_{\mathrm{RFC}}$)** | $295\,\text{ns}$ | $295\,\text{ns}$ | $350\,\text{ns}$ |

---

## 3. Workload Suite & Trace Provenance

To reflect realistic compute demands, benchmarks employ 87 cycle-accurate memory access traces spanning three distinct operational regimes:

1. **Benign Scientific & Standard Workloads**:
   - Traces extracted from **SPEC CPU2017** (`mcf`, `lbm`, `omnetpp`, `gcc`) and **PARSEC 3.0** (`streamcluster`, `canneal`).
   - Selected for diverse memory access characteristics: `mcf` exhibits a high row-miss rate ($78.4\%$), whereas `lbm` produces heavy streaming bus saturation ($99.9\%$).
2. **Cloud Database Workloads**:
   - **YCSB** Workload A (50% Read / 50% Write) and Workload B (95% Read / 5% Write) representing transactional cloud database behavior.
3. **Adversarial Disturbance Patterns**:
   - *Alternating Double-Sided RowHammer*: Pounding adjacent wordlines ($Row_{k-1}, Row_{k+1}$) at wire speed.
   - *Blacksmith Frequency-Domain Hammer*: Non-uniform multi-sided frequency toggling across multiple aggressor rows (IEEE S&P'22).
   - *RowPress*: Holding rows active for prolonged durations up to JEDEC $t_{\mathrm{RAS\_max}}$ ($70\,\mu\text{s}$) to accelerate charge leakage.

---

## 4. Performance Metrics & Mathematical Definitions

1. **Effective Throughput ($\text{MB/s}$)**:
   $$\text{Throughput} = \frac{\text{Total Serviced Bytes}}{\text{Simulated Time (s)}}$$
2. **Average Read Latency ($\text{ns}$)**:
   Elapsed time from transaction acceptance at AXI `AR` channel to beat reception at `R` channel.
3. **Relative Slowdown**:
   $$\text{Slowdown} = \frac{\text{Latency under Multi-Tenant Attack}}{\text{Latency in Isolation}}$$
4. **False Positive Rate (FPR)**:
   $$\text{FPR} = \frac{\text{Benign Requests Throttled}}{\text{Total Benign Requests}} \times 100\%$$

---

## 5. Statistical Rigor & Repeatability

- **Warmup Phase**: Each simulation executes $100,000$ memory cycles of warmup to prime cache lines, open page states, and queuing structures before logging metrics.
- **Monte Carlo Repetitions**: Stochastic experiments are evaluated across **10 independent runs** initialized with fixed pseudo-random seeds (`seed = 12345` through `12354`).
- **Confidence Intervals**: Numerical results report the empirical mean with standard deviations ($\sigma$) and 95% confidence intervals ($\text{CI}_{95} = \bar{x} \pm 1.96 \frac{\sigma}{\sqrt{N}}$), yielding $\sigma < 1.2\%$ across all primary benchmark indicators.

---

## 6. Fairness Criteria & Comparison Taxonomy

To ensure objective comparison with existing state-of-the-art defenses:
- **Apples-to-Apples Comparisons**: Direct comparisons (Baseline FR-FCFS, BlockHammer HPCA'21, Q-Shield) are performed on the **identical simulator binary** (Ramulator 2.0) with identical trace files, timing constants, and channel structures.
- **Literature-Reported Comparisons**: Numerical values from prior works (Graphene MICRO'20, AQUA MICRO'22, Rubix ASPLOS'24, PRAC ISCA'24, DREAM ISCA'25) are cited with explicit disclaimers regarding architectural and platform disparities.
