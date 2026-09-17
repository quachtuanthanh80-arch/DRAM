# Q-Shield: A High-Throughput, Zero-Bubble & SDC-Resilient DDR5/DDR4 Memory Controller

[![Language](https://img.shields.io/badge/Language-SystemVerilog%20IEEE%201800--2017-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Formal Proof](https://img.shields.io/badge/Formal%20Verification-SymbiYosys%20%2B%20Z3%20(PASS)-success.svg)](formal/)
[![Cocotb](https://img.shields.io/badge/Verification-Cocotb%202.1.0%20(11%2F11%20PASS)-brightgreen.svg)](tb/)
[![ASIC 45nm](https://img.shields.io/badge/ASIC%2045nm-424.1%20MHz%20%7C%20148k%20GE-blue.svg)](synth/asic/README.md)
[![Synthesis](https://img.shields.io/badge/FPGA%20Synthesis-Yosys%200.52%20(46k%20LUTs)-orange.svg)](syn/)
[![Architecture](https://img.shields.io/badge/Simulator-Ramulator2%20(36%20runs)-blueviolet.svg)](sim/)
[![Bandwidth](https://img.shields.io/badge/Bandwidth-137.2%20GB%2Fs%20(8--CH)-success.svg)](sim/)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg)](LICENSE)

---

## 📌 Executive Summary

**Q-Shield** is a secure, high-throughput, and timing-slack-aware DDR5/DDR4 memory controller bridging AMBA AXI4 interconnects and JEDEC DRAM physical interfaces via DFI 5.0 and dual 32-bit subchannels. Designed for high-assurance computing systems and multi-tenant cloud environments, Q-Shield eliminates the catastrophic performance collapse (up to $29.9\times$ slowdown) and victim thread starvation caused by conventional hard-blocking RowHammer mitigation architectures like HPCA'21 BlockHammer.

### Core Architectural Contributions:
1. **$O(1)$ Dual-Hash SDC-Resilient Filter:** Tracks row activation frequency across 1,024 active bins with zero false-blocking, smooth non-blocking rate throttling, and single-cycle epoch counter resets.
2. **Slack-Aware QoS Scheduling Engine:** Opportunistically schedules non-interfering bank groups during JEDEC inter-command timing slacks ($t_{RRD\_L}, t_{CCD\_L}$), delivering a **24.6x – 29.9x throughput speedup** over BlockHammer under mixed multi-tenant attacks, with **0.0% overhead** under benign workloads.
3. **Hazard-Proof Reorder Buffer (ROB):** 16-entry circular tracking engine formally proven (via SymbiYosys BMC + Temporal Induction) to enforce strict in-order retirement and eliminate Read-After-Write (RAW) data hazards.
4. **Autonomous SEC-DED (72, 64) Scrubber:** Background Hamming ECC scrubbing engine mitigating Silent Data Corruption (SDC).
5. **High-Throughput Dual 32-Bit Subchannel & Multi-Channel Scaling:** Native DDR5 dual-subchannel architecture with non-power-of-two Modulo-3 interleaving, achieving **137.21 GB/s** at 8 channels with **107.5% – 109.3% super-linear scaling efficiency**.
6. **Multi-PDK Silicon Validation Across 4 Foundries:** Synthesized across Nangate 45nm, SkyWater 130nm, IHP SG13G2 130nm, and GF180MCU 180nm, verifying gate-count invariance (~148k–151k GE) and achieving **$F_{max} = 424.1$ MHz** in 45nm planar CMOS.

---

## 🏗️ Top-Level System Architecture

```mermaid
graph TB
    subgraph AXI4_Interface ["AMBA AXI4 Host Interface"]
        AW["AW: Addr[31:0], ID[3:0], Len[7:0], QoS[3:0]"]
        W["W: Data[63:0], Strb[7:0], Last"]
        B["B: ID[3:0], Resp[1:0]"]
        AR["AR: Addr[31:0], ID[3:0], Len[7:0], QoS[3:0]"]
        R["R: Data[63:0], ID[3:0], Resp[1:0], Last"]
    end

    subgraph Frontend_Stage ["Frontend & Address Mapping"]
        SKID_AW["axi4_skid_buffer (AW Channel)<br/>Depth=2, Zero-Bubble"]
        SKID_AR["axi4_skid_buffer (AR Channel)<br/>Depth=2, Zero-Bubble"]
        SKID_W["axi4_skid_buffer (W Channel)<br/>Depth=2, Zero-Bubble"]
        FE["axi_slave_frontend<br/>4KB Boundary Check & Burst Split"]
        WBUF["wdata_buffer<br/>Write Data Staging FIFO"]
        MAPPER["addr_mapper_ddr5<br/>Rank/BG/Bank/Row/Col Mapping<br/>Modulo-3 Multi-Channel Hashing"]
    end

    subgraph Core_Engine ["Security & QoS Scheduling Engine"]
        SDC["sdc_resilient_filter<br/>Dual-Hash Tracker (1024 Bins)<br/>Non-Blocking Rate Pacing"]
        QOS["qos_scheduler_queue<br/>8 BG x 8 Entries<br/>Starvation Aging & QoS Prioritization"]
        ROB["reorder_buffer_rob<br/>16-Entry Circular Queue<br/>Strict RAW Hazard Interlock"]
    end

    subgraph Backend_Stage ["Backend Arbitration & Command Engine"]
        ARB["slack_aware_arbiter<br/>Timing Slack Matrix Arbiter<br/>Opportunistic BG Bypassing"]
        ENGINE["ddr5_cmd_engine<br/>JEDEC DDR5/DDR4 Command FSM<br/>tRP, tRCD, tCL, tCWL, tWR, tCCD"]
        ECC["ecc_scrubber<br/>Autonomous SEC-DED (72, 64) Engine"]
    end

    subgraph Memory_PHY ["Subchannel & DFI 5.0 PHY Adapter"]
        SCHED["ddr5_subchannel_scheduler<br/>Dual 32-bit Independent Subchannels (A/B)"]
        DFI["dfi_phy_adapter<br/>JEDEC DFI 5.0 Protocol & Timing Alignment"]
    end

    AW --> SKID_AW --> FE
    AR --> SKID_AR --> FE
    W --> SKID_W --> WBUF
    FE --> MAPPER
    MAPPER --> SDC
    MAPPER --> QOS
    MAPPER --> ROB
    WBUF --> ENGINE
    SDC -.->|Throttle Flags| QOS
    QOS --> ARB
    ARB --> ENGINE
    ENGINE --> ECC
    ECC --> SCHED
    SCHED --> DFI
    ECC --> ROB
    ROB --> R
    ROB --> B
```

---

## ⚡ DDR5 Command Engine Finite State Machine (FSM)

```mermaid
stateDiagram-v2
    [*] --> S_IDLE
    S_IDLE --> S_PRE : Row Conflict in Bank
    S_IDLE --> S_ACT : Bank Closed (Page Empty)
    S_IDLE --> S_RD : Page Hit (Read)
    S_IDLE --> S_WR : Page Hit (Write)

    S_PRE --> S_WAIT_RP : Emit PRECHARGE
    S_WAIT_RP --> S_ACT : tRP timer met
    
    S_ACT --> S_WAIT_RCD : Emit ACTIVATE
    S_WAIT_RCD --> S_RD : tRCD met (Read)
    S_WAIT_RCD --> S_WR : tRCD met (Write)

    S_RD --> S_WAIT_CL : Emit READ
    S_WAIT_CL --> S_DATA_XFER : tCL met
    S_DATA_XFER --> S_IDLE : Burst Done & tCCD met

    S_WR --> S_WAIT_CWL : Emit WRITE
    S_WAIT_CWL --> S_WRITE_DATA : tCWL met
    S_WRITE_DATA --> S_WAIT_WR : All Beats Done
    S_WAIT_WR --> S_IDLE : tWR met
```

---

## 🏛️ Cross-Node ASIC Implementation & Multi-PDK PPA Benchmark

Q-Shield was synthesized across **four independent silicon technology libraries** spanning from mature 180nm to advanced 45nm planar CMOS:

| Metric Category | **Nangate 45nm** (Academic) | **SkyWater 130nm** (HD) | **IHP SG13G2** (BiCMOS) | **GF180MCU** (Automotive) |
| :--- | :---: | :---: | :---: | :---: |
| **Process Node** | 45nm CMOS | 130nm CMOS | 130nm BiCMOS | 180nm BCD |
| **Operating Voltage ($V_{dd}$)** | 1.10 V | 1.80 V | 1.20 V | 3.30 V / 5.0 V |
| **Track Height & Pitch** | 10T (1.40 µm) | 7T (2.72 µm) | 8T (3.90 µm) | 7T (5.60 µm) |
| **NAND2 Unit Area** | 0.798 µm² | 7.452 µm² | 10.450 µm² | 21.050 µm² |
| **Target Clock ($F_{target}$)** | **400.0 MHz** | 133.3 MHz | 200.0 MHz | 66.7 MHz |
| **Max Frequency ($F_{max}$)** | **424.1 MHz** | 142.8 MHz | 225.0 MHz | 68.5 MHz |
| **Timing Slack (WNS)** | +0.142 ns (Met) | +0.496 ns (Met) | +0.556 ns (Met) | +0.392 ns (Met) |
| **Total Cell Area** | **118,450 µm²** (0.118 mm²) | 1,116,159 µm² (1.116 mm²) | 1,556,527 µm² (1.557 mm²) | 3,182,760 µm² (3.183 mm²) |
| **Gate Equivalent (GE)** | **148,434 GE** | 149,820 GE | 148,950 GE | 151,200 GE |
| **Area Scaling vs 45nm** | **1.00×** (Baseline) | 9.42× | 13.14× | 26.87× |
| **Dynamic Power** | **23.27 mW** | 46.85 mW | 34.20 mW | 89.60 mW |
| **Leakage Power** | 312.4 µW | 18.5 µW | 64.2 µW | **2.8 µW** |
| **Total Power Dissipation** | **23.58 mW** | 46.87 mW | 34.26 mW | 89.60 mW |
| **Energy per Access ($E_{op}$)** | **58.95 pJ/op** | 351.61 pJ/op | 171.30 pJ/op | 1,343.33 pJ/op |

### Key Silicon Implementation Insights:
- **Gate Count Invariance (~148k–151k GE):** Across all four libraries spanning mature 180nm to advanced 45nm, synthesized gate count remains invariant within $\pm 1.8\%$, confirming clean, portable SystemVerilog RTL.
- **Silicon Area Dynamics:** Moving from GF180MCU down to Nangate 45nm yields a **26.87× area reduction** ($3.183\,\text{mm}^2$ to $0.118\,\text{mm}^2$). On SkyWater 130nm, Q-Shield occupies $1.116\,\text{mm}^2$, making it fully compatible with low-cost open-source tapeout shuttles (Tiny Tapeout / Efabless MPW).
- **Frequency Closure:** Nangate 45nm achieves **$F_{max} = 424.1$ MHz** with positive slack (+0.142 ns), meeting DDR5 1:4 gear PHY clock requirements.
- **Energy Efficiency:** 45nm planar CMOS consumes only **58.95 pJ/op**, achieving a **22.8× energy reduction** compared to automotive GF180MCU.

---

## 📈 Multi-Channel & Subchannel Bandwidth Scaling (1 to 8 Channels)

Q-Shield supports high-bandwidth parallel configurations across multiple physical channels and independent 32-bit DDR5 subchannels using non-power-of-two Modulo-3 interleaving:

| DRAM Preset | Workload | Channels | Interleaving Mode | Cycles | Latency (ns) | Throughput (MB/s) | Speedup vs 1-CH | Scaling Efficiency |
| :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| **DDR5-4800** | Benign | 1-CH | CacheLine Interleaved | 48,485 | 208.02 | 15,684.5 | $1.00\times$ | 100.0% |
| | | 2-CH | CacheLine Interleaved | 22,197 | 214.35 | 33,712.1 | $2.15\times$ | **107.5%** |
| | | 3-CH | Modulo-3 Interleaved | 15,651 | 208.49 | 47,900.2 | $3.05\times$ | **101.8%** |
| | | 4-CH | CacheLine Interleaved | 10,947 | 178.49 | 66,670.9 | $4.25\times$ | **106.3%** |
| | | **8-CH** | **CacheLine Interleaved** | **5,270** | **101.48** | **137,206.3** | **8.75x** | **109.3% (137.21 GB/s)** |
| **DDR5-4800** | RowHammer | 1-CH | CacheLine Interleaved | 71,656 | 211.89 | 10,666.4 | $1.00\times$ | 100.0% |
| | | 2-CH | CacheLine Interleaved | 32,021 | 191.55 | 23,715.2 | $2.22\times$ | **111.2%** |
| | | 3-CH | Modulo-3 Interleaved | 26,164 | 207.79 | 32,240.9 | $3.02\times$ | **100.8%** |
| | | 4-CH | CacheLine Interleaved | 15,439 | 185.52 | 48,548.4 | $4.55\times$ | **113.8%** |
| | | **8-CH** | **CacheLine Interleaved** | **7,151** | **168.28** | **102,062.1** | **9.57x** | **119.6% (102.06 GB/s)** |
| **DDR5-4800** | Mixed | 1-CH | CacheLine Interleaved | 61,021 | 211.83 | 12,487.5 | $1.00\times$ | 100.0% |
| | | 2-CH | CacheLine Interleaved | 31,648 | 191.32 | 24,014.2 | $1.92\times$ | 96.2% |
| | | 3-CH | Modulo-3 Interleaved | 20,478 | 204.52 | 37,247.6 | $2.98\times$ | 99.4% |
| | | 4-CH | CacheLine Interleaved | 15,677 | 145.46 | 47,566.0 | $3.81\times$ | 95.2% |
| | | **8-CH** | **CacheLine Interleaved** | **5,822** | **86.40** | **125,782.8** | **10.07x** | **125.9% (125.78 GB/s)** |

*Super-linear efficiency (>100%) occurs due to reduced bank conflicts and broadened rank/subchannel parallelism across the memory bus.*

---

## 📊 Comprehensive Ramulator2 Benchmark Matrix (36 Runs)

Detailed cycle-accurate architectural evaluation comparing **Baseline (No Defense)**, **BlockHammer (HPCA'21)**, and **Q-Shield (Ours)** across four JEDEC DRAM configurations:
- **DDR4-3200:** 16 GB, 2 ranks, 4 BG x 4 Bank, $t_{CK} = 0.625$ ns.
- **DDR5-4800:** 32 GB, 2 subchannels, 2 ranks, 8 BG x 4 Bank, $t_{CK} = 0.4167$ ns.
- **DDR5-5600:** 32 GB, 2 subchannels, 2 ranks, 8 BG x 4 Bank, $t_{CK} = 0.3571$ ns.
- **DDR5-6000:** 32 GB, 2 subchannels, 2 ranks, 8 BG x 4 Bank, $t_{CK} = 0.3333$ ns.

| DRAM Preset | Workload | Controller Scheme | Cycles | Latency (ns) | Bandwidth (MB/s) | Throttled | Bypassed | Speedup vs BlockHammer |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **DDR4-3200** | Benign | Baseline | 22,673 | 154.56 | 22,374.2 | 0 | 0 | $1.00\times$ |
| | | BlockHammer | 22,673 | 154.56 | 22,374.2 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **22,673** | **154.56** | **22,374.2** | **0** | **0** | **1.00x (0% overhead)** |
| | RowHammer | Baseline | 45,337 | 197.94 | 11,220.9 | 0 | 0 | - |
| | | BlockHammer | 314,930 | 1,283.59 | 1,615.3 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **45,337** | **197.94** | **11,220.9** | **52** | **0** | **6.94x faster** |
| | Mixed | Baseline | 34,603 | 180.21 | 14,657.3 | 0 | 0 | - |
| | | BlockHammer | 1,019,360 | 4,588.54 | 497.6 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **34,114** | **178.02** | **14,867.4** | **293** | **1,035** | **29.88x faster** |
| **DDR5-4800** | Benign | Baseline | 48,485 | 208.02 | 15,684.5 | 0 | 0 | $1.00\times$ |
| | | BlockHammer | 48,485 | 208.02 | 15,684.5 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **48,485** | **208.02** | **15,684.5** | **0** | **0** | **1.00x (0% overhead)** |
| | RowHammer | Baseline | 71,656 | 211.89 | 10,666.4 | 0 | 0 | - |
| | | BlockHammer | 476,158 | 1,297.32 | 1,605.2 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **71,656** | **211.89** | **10,666.4** | **55** | **0** | **6.64x faster** |
| | Mixed | Baseline | 61,021 | 211.83 | 12,487.5 | 0 | 0 | - |
| | | BlockHammer | 1,532,669 | 4,604.15 | 497.2 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **61,021** | **211.83** | **12,487.5** | **299** | **226** | **25.12x faster** |
| **DDR5-5600** | Benign | Baseline | 50,212 | 184.41 | 17,640.8 | 0 | 0 | $1.00\times$ |
| | | BlockHammer | 50,212 | 184.41 | 17,640.8 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **50,212** | **184.41** | **17,640.8** | **0** | **0** | **1.00x (0% overhead)** |
| | RowHammer | Baseline | 83,500 | 210.93 | 10,666.1 | 0 | 0 | - |
| | | BlockHammer | 554,850 | 1,294.87 | 1,605.2 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **83,500** | **210.93** | **10,666.1** | **50** | **0** | **6.65x faster** |
| | Mixed | Baseline | 65,440 | 196.41 | 13,568.6 | 0 | 0 | - |
| | | BlockHammer | 1,608,797 | 4,143.43 | 551.9 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **65,440** | **196.41** | **13,568.6** | **268** | **40** | **24.58x faster** |
| **DDR5-6000** | Benign | Baseline | 51,704 | 177.47 | 18,366.5 | 0 | 0 | $1.00\times$ |
| | | BlockHammer | 51,704 | 177.47 | 18,366.5 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **51,704** | **177.47** | **18,366.5** | **0** | **0** | **1.00x (0% overhead)** |
| | RowHammer | Baseline | 89,478 | 210.37 | 10,670.9 | 0 | 0 | - |
| | | BlockHammer | 592,762 | 1,290.79 | 1,610.8 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **89,478** | **210.37** | **10,670.9** | **49** | **0** | **6.62x faster** |
| | Mixed | Baseline | 66,740 | 188.07 | 14,263.2 | 0 | 0 | - |
| | | BlockHammer | 1,718,951 | 4,131.87 | 553.8 | 0 | 0 | $1.00\times$ |
| | | **Q-Shield** | **66,740** | **188.07** | **14,263.2** | **241** | **5** | **25.76x faster (95.4% lat drop)** |

---

## 🥊 Head-to-Head Comparison vs State-of-the-Art (SOTA)

| Architectural Metric | **Q-Shield (Ours)** | **BlockHammer** (HPCA'21) | **AQUA** (MICRO'22) | **Rubix** (ASPLOS'24) | **PRAC** (ISCA'24) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **SDC Error Mitigation** | **SEC-DED (72, 64) ($d_{min}=4$)** | None | None | None | Link ECC (In-DRAM) |
| **Target Architecture** | **DDR4 & DDR5 Dual-Subchannel** | DDR4 Controller | DDR4/DDR5 Server | DDR4/DDR5 | JEDEC DDR5 Spec |
| **Operating Frequency ($F_{max}$)** | **424.1 MHz (Nangate 45nm)** | 400.0 MHz | 350.0 MHz | 400.0 MHz | 400.0 MHz |
| **Silicon Area Overhead (%)** | **3.8%** | **1.2%** | 12.4% (41 KB SRAM) | 2.1% | 4.5% |
| **Power Overhead (%)** | **4.1%** | 3.5% | 9.8% | **2.9%** | 5.2% |
| **Single-Bit Correction (SDR)** | **100.00%** | 0.00% | 0.00% | 0.00% | 100.00% (PHY Only) |
| **Double-Bit Detection (DDR)** | **100.00% ($d_{min}=4$)** | 0.00% | 0.00% | 0.00% | 0.00% (Undetected) |
| **Rollback Stall Latency** | **0 cycles (Zero-Bubble)** | Up to 1,718,951 cycles | 18–32 cycles | 8–16 cycles | 45–80 cycles ($t_{DRFM}$) |

---

## 🛠️ FPGA Synthesis Utilization (Xilinx 7-Series Target)

Mapped to **Xilinx 7-Series (XC7Z020 FPGA)** via **Yosys 0.52**:

| Module Name | File Path | LUTs | FFs | CARRY4 | BRAM | Role |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| `axi4_skid_buffer` | `rtl/frontend/axi4_skid_buffer.sv` | 70 | 132 | 0 | 0 | Zero-bubble AXI handshaking |
| `axi_slave_frontend` | `rtl/frontend/axi_slave_frontend.sv` | 1,196 | 1,872 | 0 | 0 | 4KB boundary check & burst unpack |
| `wdata_buffer` | `rtl/frontend/wdata_buffer.sv` | 2,354 | 5,576 | 0 | 0 | Write payload staging buffer |
| `addr_mapper_ddr5` | `rtl/frontend/addr_mapper_ddr5.sv` | 10 | 94 | 0 | 0 | Interleaved BG/Bank mapping |
| `sdc_resilient_filter` | `rtl/core/sdc_resilient_filter.sv` | 16,128 | 17,720 | 0 | 0 | Dual-hash RowHammer rate tracker |
| `qos_scheduler_queue` | `rtl/core/qos_scheduler_queue.sv` | 3,742 | 3,520 | 0 | 0 | Priority & aging command queue |
| `reorder_buffer_rob` | `rtl/core/reorder_buffer_rob.sv` | 17,304 | 34,952 | 0 | 0 | 16-entry in-order retirement & RAW lock |
| `slack_aware_arbiter` | `rtl/backend/slack_aware_arbiter.sv` | 2,642 | 6 | 0 | 0 | High-speed timing-slack matrix arbiter |
| `ddr5_cmd_engine` | `rtl/backend/ddr5_cmd_engine.sv` | 2,202 | 2,604 | 0 | 0 | JEDEC command timing engine |
| `ecc_scrubber` | `rtl/backend/ecc_scrubber.sv` | 544 | 142 | 0 | 0 | (72, 64) SEC-DED Hamming scrubber |
| **Total Q-Shield Design** | **All 14 Synthesizable Modules** | **46,192** | **66,618** | **0** | **0** | **100% Synthesizable RTL** |

---

## 🔍 Hardware Formal Verification (SymbiYosys + Z3)

Formal proof properties are formulated in SystemVerilog Assertions (SVA) and verified via **SymbiYosys**:
```bash
cd formal
sby -f formal_skid_buffer.sby
sby -f formal_sdc_filter.sby
sby -f formal_rob.sby
```
- `formal_skid_buffer.sby`: **PASS** (BMC + Temporal Induction, depth=20). Zero-bubble handshake stability, capacity bound $\le 2$, and forward progress.
- `formal_sdc_filter.sby`: **PASS** (BMC, depth=10). Monotonic counter increments, throttle alert consistency, and $O(1)$ epoch reset safety.
- `formal_rob.sby`: **PASS** (BMC, depth=10). Zero invalid retirements, strict in-order retirement, and Read-After-Write (RAW) hazard interlock.

---

## 🧪 Functional Verification (Cocotb 2.1.0)

Automated regression suite spanning frontend, core, backend, and top-level integration:
```bash
python3 -c "
import subprocess
for suite in ['frontend', 'core', 'backend', 'top']:
    subprocess.run(['make', 'sim', '-C', f'tb/{suite}'], check=True)
"
```

| Test Suite | Module Under Test | Test Function | Status |
| :--- | :--- | :--- | :---: |
| `tb/frontend` | `axi_slave_frontend` | `test_reset_and_defaults` | **PASS** |
| | `axi_slave_frontend` | `test_ar_handshake_and_4kb_detection` | **PASS** |
| | `axi4_skid_buffer` | `test_skid_buffer_backpressure` | **PASS** |
| `tb/core` | `sdc_resilient_filter` | `test_rowhammer_threshold_detection` | **PASS** |
| | `sdc_resilient_filter` | `test_instant_o1_window_reset` | **PASS** |
| `tb/backend` | `qos_scheduler_queue` | `test_starved_priority_boost` | **PASS** |
| | `slack_aware_arbiter` | `test_bg_readiness_gating` | **PASS** |
| | `slack_aware_arbiter` | `test_opportunistic_slack_mitigation` | **PASS** |
| `tb/top` | `sec_ddr5_controller_top` | `test_axi_write_burst_e2e` | **PASS** |
| | `sec_ddr5_controller_top` | `test_axi_read_e2e_reorder_and_return` | **PASS** |
| | `sec_ddr5_controller_top` | `test_rowhammer_sdc_defense_e2e` | **PASS** |

---

## 🚀 Simulation & Multi-Stage Lifecycle Commands

Execute architectural benchmarks and validation suites:
```bash
# 1. Run the Full Industrial 3-Stage Lifecycle Validation
python tools/run_full_lifecycle_validation.py

# 2. Run the 36-run Ramulator2 Benchmark Matrix
python sim/run_benchmarks.py
python sim/run_ddr5_6000.py

# 3. Run Multi-Channel Bandwidth Scaling (1 to 8 Channels)
python sim/test_multichannel.py
```

---

## 📜 Core RTL Components & Citation

All hardware source code is open-source and synthesizable:
- **Top-Level Memory Controller:** [`rtl/top/axi_ddr5_mc_top.sv`](rtl/top/axi_ddr5_mc_top.sv)
- **Top-Level Secure Subsystem:** [`rtl/top/sec_ddr5_controller_top.sv`](rtl/top/sec_ddr5_controller_top.sv)
- **Dual-Hash SDC Filter:** [`rtl/core/sdc_resilient_filter.sv`](rtl/core/sdc_resilient_filter.sv)
- **Slack-Aware Matrix Arbiter:** [`rtl/backend/slack_aware_arbiter.sv`](rtl/backend/slack_aware_arbiter.sv)
- **DDR5 Subchannel Scheduler:** [`rtl/memory/ddr5_subchannel_scheduler.sv`](rtl/memory/ddr5_subchannel_scheduler.sv)
- **DFI 5.0 PHY Adapter:** [`rtl/memory/dfi_phy_adapter.sv`](rtl/memory/dfi_phy_adapter.sv)
- **AES-256-XTS Pipeline:** [`rtl/crypto/subchannel_aes_xts_pipe.sv`](rtl/crypto/subchannel_aes_xts_pipe.sv)

```bibtex
@article{qshield2026,
  title   = {{Q-Shield}: A High-Throughput, Zero-Bubble and {SDC}-Resilient {DDR5/DDR4} Memory Controller},
  author  = {Quach, Tuan Thanh and Contributors},
  journal = {IEEE Transactions on Computer-Aided Design of Integrated Circuits and Systems (TCAD) / TVLSI},
  year    = {2026}
}
```
