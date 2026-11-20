# Q-Shield Architectural Limitations, Threat Boundaries & Trade-Offs

> **Provenance note (2026-10-30).** Ramulator-based throughput/overhead figures (SPEC CPU2017/PARSEC, ±σ), the "apples-to-apples" table and the Nangate 45 nm gate counts were not reproducible from this repository and are withdrawn. See `sim/results/PROVENANCE.md` for what each result file is, and the README section "What has been measured" for the numbers that are backed by runs.

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
  While no attacks are missed, the accumulated false-positive rate ($FPR$) rises. This forces innocent victim rows sharing those hash bins into conservative rate pacing, inducing a localized denial-of-service (QoS degradation) for the targeted bank group.

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
- **Worst-Case Stalling**: Under pathological multi-bank hammering across all 32 banks, total memory bus throughput is reduced by mandatory refresh command injection; the size of the reduction has not been measured.

---

## 3. Configuration Trade-Offs (not yet quantified)

The SDC filter size, the mitigation threshold and the rate-pacing parameters trade area against false-positive rate,
detection latency and throughput loss under attack. An earlier version of this section tabulated numbers for three
configurations (area in gate equivalents, false-positive rate, detection latency, throughput loss). Those numbers were
withdrawn because no run in this repository produced them. Quantifying this trade-off is part of the planned
evaluation in [`EVALUATION.md`](EVALUATION.md).

---

## 4. Hardware Implementation Limits

### 4.1 FPGA timing and area

Measured results (Xilinx `xczu7ev`, Vivado 2026.1) are in [`DESIGN.md`](DESIGN.md) section 3:

- The core controller closes timing at 3.8 ns (about 263 MHz) after place and route and **does not close at 2.5 ns
  (400 MHz)**: WNS is -1.273 ns at the 2.5 ns target.
- The encryption and integrity layer adds a large amount of logic: the secure top uses 164,062 LUTs (71.2 % of the
  device) after place and route, and closes timing at 4.15 ns (about 241 MHz), not at 2.5 ns (WNS -1.595 ns).
- Large storage arrays (for example the metadata cache) are mapped to block RAM. Using block RAM adds a cycle of read
  latency, and the surrounding logic is written for it.

### 4.2 Power and energy

Power was estimated for the core controller at 263.16 MHz by Vivado in vectorless mode (1.618 W total). That is a
rough estimate and not a measurement. ASIC power and energy per operation were not measured, and earlier figures for
them were withdrawn.

---

## 5. Model Validation Status & Silicon Realization Boundaries

To ensure complete experimental transparency regarding the boundaries between simulation models and physical hardware:

### 5.1 What Has Been Verified

- **Functional behaviour in simulation**: the testbenches listed in [`README.md`](README.md) pass; the coverage and mutation limits are in section 9.
- **Command timing**: a JEDEC DDR5 timing checker runs in every top-level testbench and reports no violations in those runs.
- **FPGA timing after place and route (core controller)**: closes at 3.8 ns (about 263 MHz), **does not close at 2.5 ns (400 MHz)**; see [`DESIGN.md`](DESIGN.md) section 3.

### 5.2 Unverified Physical Dimensions (Open Research Questions)
- **Post-P&R Gate-Level Netlist Timing**: Evaluated through pre-layout synthesis; full physical place-and-route clock tree synthesis (CTS) and parasitic RC back-annotation remain future work.
- **Physical Layout Parasitics**: On-chip IR drop, power delivery network (PDN) inductive bounce, and high-speed inter-wire crosstalk are not modeled in digital RTL.
- **Silicon Measurement Data**: No physical test-chip tape-out has been manufactured to date; physical silicon validation remains an open goal.
- **Temperature & Process Corner Extremes**: PPA evaluations assume nominal operating conditions ($25^\circ\text{C}, 1.1\,\text{V}$, typical-typical process corner); thermal runaway corners are uncharacterized.
- **Long-Term Device Reliability**: Electromigration, Time-Dependent Dielectric Breakdown (TDDB), and Negative Bias Temperature Instability (NBTI) aging are not modeled.

### 5.3 Security Validation Boundaries
- **Proven Defenses**: RowHammer bit-flip prevention (single, double, many-sided), RowPress hold-time capping, adaptive rate pacing, and autonomous single-bit SEC-DED soft-error scrubbing.
- **Mitigation-timing channels (LeakyHammer / PRACLeak)**: A tenant can no longer observe another tenant's mitigation activity across banks. Victim refreshes occupy only the aggressor's bank (bank-parallel engine), and queue capacity is split per bank: each bank has one reserved slot in its bank-group queue, and the remaining slots form a shared pool. As a result, commands stalled behind a pending victim refresh cannot exhaust the queue entries of a different bank. `tb_security_attacks_vcd` V19 measures 39 vs 40 cycles for the two symbols, and the receiver decodes 7/16 bits (chance level). A receiver in the *same* physical bank still sees the refresh, because the bank itself is the shared resource. Bank coloring (V23) separates tenants at bank granularity.
- **Explicit Non-Goals**: Side-channel resistance beyond the scheduling channels above (power analysis, electromagnetic emission), transient speculative execution, and physical bus tampering.

---

## 6. Crypto-Integration Demo Top (`sec_ddr5_controller_top.sv`) Scope & Known Open Limitations

**`axi_ddr5_mc_top`** (`rtl/top/axi_ddr5_mc_top.sv`) is the **canonical production top-level module** of Q-Shield used for end-to-end verification, formal proofs, and synthesis evaluation.

By contrast, **`sec_ddr5_controller_top`** (`rtl/top/sec_ddr5_controller_top.sv`) is retained strictly as a **crypto-integration demonstration top** (illustrating the dual-lane AES-256-XTS write pipeline, dual-clock Gray-code CDC FIFOs, and dual-subchannel scheduler). It is **not part of the canonical controller hierarchy (`axi_ddr5_mc_top`)** and **must not be used for any area, timing ($F_{max}$/WNS), LUT/FF utilization, or throughput claims**.

The following findings on `sec_ddr5_controller_top` are closed by scope (documented as known demo limitations without modifying demo RTL logic) and tracked in `tb/findings/known_open_demo.txt`:

### 6.1 [C-3] Subchannel Scheduler Row/Column Address Driven from Ciphertext Slice
- **Location**: `rtl/top/sec_ddr5_controller_top.sv` (`u_sched_a` lines 443–446, `u_sched_b` lines 485–488).
- **Root Cause & Impact**: `axi4_slave_adapter` forwards only a 16-bit metadata vector (`{1'b1, awaddr[16:15], awaddr[14:12], awid, 2'b00}`) alongside the 128-bit encrypted data beat (`enc_a_data` / `enc_b_data`) across the 144-bit CDC FIFOs (`u_cdc_fifo_a`, `u_cdc_fifo_b`). On the `clk_ddr` domain, `u_sched_a` and `u_sched_b` wire `req_row` to `fifo_*_rdata[127:112]` and `req_col` to `fifo_*_rdata[105:96]`, which are bits of the AES-XTS ciphertext (`enc_*_data[127:96]`) rather than the host AXI physical row and column address. Consequently, the DFI row/column address emitted by the demo top depends on encrypted payload data instead of `s_axi_awaddr`.
- **Reproduction**:
  ```bash
  python tb/findings/run_findings.py
  # Or run check_c3 directly with Icarus Verilog:
  # check_c3 (tb/findings/checks/check_c3.sv) writes two distinct plaintexts to the same
  # AXI address with enc_enable=1 and observes two different DFI ACT row addresses ([FAIL] C-3).
  ```

### 6.2 [C-4] Write-Only Demo Datapath & Read Channel Stub
- **Location**: `rtl/bus/axi4_slave_adapter.sv` (lines 274–279) and `rtl/top/sec_ddr5_controller_top.sv` (`u_sched_a` line 442, `u_sched_b` line 484, `u_dfi_a`/`u_dfi_b` lines 522–524, 567–569).
- **Root Cause & Impact**: In `axi4_slave_adapter.sv`, the AXI4 read channels (`AR` and `R`) are stubbed (`assign s_axi_arready = 1'b1;` and `assign s_axi_rvalid = 1'b0;`). In `sec_ddr5_controller_top.sv`, both subchannel schedulers tie `.req_is_write(1'b1)` high and leave the `dfi_phy_adapter` read response ports (`rd_resp_valid`, `rd_resp_data`, `rd_resp_tag`) unconnected. Any AXI4 read request (`s_axi_arvalid = 1'b1`) accepted on `AR` never produces a read response beat (`s_axi_rvalid` remains `0` indefinitely).
- **Reproduction**:
  ```bash
  python tb/findings/run_findings.py
  # check_c4 (tb/findings/checks/check_c4.sv) issues an AXI4 write followed by an AXI4 read
  # on sec_ddr5_controller_top and times out waiting for s_axi_rvalid ([FAIL] C-4).
  ```

### 6.3 [H-1] Asynchronous CDC FIFO Partial Reset Desynchronization on `soft_reset`
- **Location**: `rtl/top/sec_ddr5_controller_top.sv` (`u_cdc_fifo_a` line 378, `u_cdc_fifo_b` line 404).
- **Root Cause & Impact**: The write-domain asynchronous reset input of `async_fifo_cdc` is driven combinationally by `.wrst_n(rst_axi_n && !soft_reset)`, whereas the read-domain reset input is driven solely by `.rrst_n(rst_ddr_n)`. Triggering a software reset (`soft_reset = 1'b1` via APB CSR `0x000[2]`) after traffic has advanced the FIFO pointers resets only the write pointers (`wptr_bin`, `wptr_gray` → `0`) while leaving the read pointers (`rptr_bin`, `rptr_gray`) at their old non-zero values. Once `soft_reset` deasserts, `rptr_gray_Next != rq2_wptr_gray` causes `rempty` to deassert falsely on the `clk_ddr` side, draining phantom entries from stale FIFO memory and corrupting subsequent write stream alignment.
- **Reproduction**:
  ```bash
  python tb/findings/run_findings.py
  # check_h1 (tb/findings/checks/check_h1.sv) writes 2 beats through sec_ddr5_controller_top,
  # pulses soft_reset via APB CSR, and detects phantom subchannel scheduler requests while idle ([FAIL] H-1).
  ```

*(Note: In addition to C-3, C-4, and H-1, `u_qshield_crypto` inside `sec_ddr5_controller_top.sv` lines 618–651 has its datapath valid inputs `i_precomp_valid`, `i_wr_valid`, and `i_rd_valid` tied to `1'b0` — tracked as demo finding **[C-1]** and reproduced by `check_c1` in `tb/findings/run_findings.py`.)*

---

## 7. Unwired / Standalone ECC & Chipkill Extensions (`M-7`, `M-8`)

### 7.1 [M-7] ZEM Fault-Masking Cache Disconnected on Canonical Read Path (`axi_ddr5_mc_top.sv`)
- **Location**: `rtl/top/axi_ddr5_mc_top.sv` (`u_ecc_scrubber` instantiation, lines 1752–1758) and `rtl/backend/ecc_scrubber.sv`.
- **Current RTL State**: `ecc_scrubber.sv` implements ZEM fault masking (`COL_WIDTH = 13`, 16 entries) hardened with a 2-scan confirmation learn policy (`i_cfg_zem_auto_learn`, transient switching guard `o_zem_learn_blocked_cnt`, manual override `i_cfg_zem_manual_load`) and automatic row-level ZEM entry invalidation on ECC check-bit errors or 2-bit uncorrectable errors (`checks=18 fails=0` in `tb_eccfail_zem_scrubber`). However, on the canonical controller read path in `axi_ddr5_mc_top.sv`, ZEM lookup inputs remain tied off (`.i_zem_lookup_valid(1'b0)`, `.o_zem_hit()`, `.o_zem_mask()`, `.o_zem_hit_cnt()`).
- **Root Cause & Decision (ZEM read-path decision)**: Connecting ZEM CAM lookup and pre-decode masking onto the critical DFI read path in `axi_ddr5_mc_top.sv` initially degraded 400 MHz (`2.500 ns`) Vivado OOC timing to `WNS = -1.432 ns` (`t39_zem`). Across 3 optimization rounds (`t39_r1` `-0.575 ns` -> `t39_r2` `-0.469 ns` -> `t39_r3` `-0.077 ns`, failing arbiter path `u_qos_queue/o_cand_starved_reg[1]/C -> u_arbiter/last_served_bg_reg[0]/CE`), core WNS remained `0.055 ns` worse than the preceding baseline (`-0.022 ns`), exceeding the `0.050 ns` regression budget we set. As a result, read-path ZEM wiring was rolled back (`t39_fallback`: `WNS = -0.022 ns`, `TNS = -0.429 ns`), leaving canonical read beats protected solely by Hamming SEC-DED (72,64).
- **Reproduction**:
  ```bash
  # Standalone 2-scan ZEM & anti-poisoning verification (18/18 checks):
  python run_iverilog_regression.py --only tb_eccfail_zem_scrubber
  # Canonical core read integrity & top-level regression without read-path ZEM:
  python run_iverilog_regression.py --only tb_rt03_rd_integrity,tb_axi_ddr5_mc_top
  ```

### 7.2 [M-8] Reed-Solomon Chipkill `RS(18,16)` Standalone Over `GF(2^8)` — Not Wired Into Controller Top
- **Location**: `rtl/backend/gf256_arith_pkg.sv`, `rtl/backend/rs_chipkill_encoder.sv`, `rtl/backend/rs_chipkill_decoder.sv`; `rtl/top/axi_ddr5_mc_top.sv` lines 1241, 1750 (`ecc_chipkill_fallback_req`).
- **Scope & Integration Gap**: `rs_chipkill_encoder.sv` and `rs_chipkill_decoder.sv` are standalone IP blocks that are **not instantiated** in `axi_ddr5_mc_top.sv` or `axi_ddr5_mc_secure_top.sv`. Inside `axi_ddr5_mc_top.sv`, `u_ecc_scrubber.o_chipkill_fallback_req` (`o_ecc_miscorrect_alert || o_double_err`) drives only an unread local wire `ecc_chipkill_fallback_req`; there is **no** closed-loop `"ECC trial -> MAC -> Chipkill"` failover pipeline in the memory controller.
- **Mathematical Field & Distance Limit (`GF(2^8)`, `d = 3`)**:
  - The standalone RS codec operates on **`RS(18,16)` over `GF(2^8)`** (`gf256_arith_pkg.sv`, polynomial $x^8 + x^4 + x^3 + x^2 + 1$, $\alpha = 2$; 16 data symbols + 2 parity symbols = 18 8-bit symbols = two x4 DRAM beats). A `GF(2^4)` field (`gf16_arith_pkg.sv` in older drafts, which does not exist in the repository) is mathematically infeasible for `RS(18,16)` because `GF(2^4)` has only 15 nonzero elements for 18 symbol locators.
  - Because `rs_chipkill_decoder.sv` computes only two syndromes (`s0, s1`; minimum distance `d = 3`, with no third syndrome `S_2` or $\Delta = S_0 S_2 \oplus S_1^2$ and no `o_double_detected` port), it guarantees single-symbol (1 x4 chip) correction and accurate parity-chip (`p16`, `p17`) identification, but does **not** provide 100% Double-Symbol Detection (DSD): two-chip errors are flagged on `o_uncorrectable` only when the syndrome misses the 18 valid locators (~93.5%–93.7% detection probability; full DSD requires 3 parity symbols, `d = 4`).
- **Reproduction**:
  ```bash
  # Standalone GF(2^8) RS(18,16) unit verification (not top-level controller integration):
  python run_iverilog_regression.py --only tb_rs_parity_chip
  iverilog -g2012 -o test_rs.vvp rtl/backend/gf256_arith_pkg.sv rtl/backend/rs_chipkill_encoder.sv rtl/backend/rs_chipkill_decoder.sv tb/backend/tb_rs_parity_chip.sv && vvp test_rs.vvp
  ```

---

## 8. Side-Channel, Parity Enable & ABO Timing Boundaries (`L-1`, `L-2`, `L-3`)

### 8.1 [L-1] Unmasked LUT S-Box, Unused `aes_sbox_composite`, & SCARF Seed Width
- **Scope & Design Choice**:
  - **AES S-Box LUT & Side-Channel Non-Goal**: Q-Shield's symmetric cipher datapaths prioritize single-cycle/pipelined 400 MHz FPGA/ASIC timing closure and functional DRAM security (RowHammer/RowPress mitigation, SEC-DED, bus scrambling) over physical power/EM side-channel masking (`Section 5.3`). Active AES instances use unmasked LUT S-boxes (`aes_sbox.sv`), which are vulnerable to first-order DPA/CPA power analysis if exposed to physical power probing.
  - **`aes_sbox_composite.sv` Unused Reference**: `rtl/crypto/aes_sbox_composite.sv` provides an uninstantiated composite-field $\text{GF}(((2^2)^2)^2)$ S-box implementation kept intact for structural reference and future masked-S-box extensions without modifying active datapaths.
  - **SCARF Randomizer Seed Width ($\le 62$ bits)**: `rtl/core/scarf_dram_randomizer.sv` restricts the internal hardware SCARF tweakable block permutation seed/key width to $\le 62$ bits for single-cycle 400 MHz combinational address translation. This provides fast hardware address isolation against physical RowHammer hammering patterns, not full 128-bit cryptographic brute-force resistance.

### 8.2 [L-2] `cfg_parity_check_en` External Top-Level Port vs. APB CSR (`apb_csr_regs.sv`)
- **Location**: `rtl/top/axi_ddr5_mc_top.sv` (`cfg_parity_check_en` port), `rtl/top/axi_ddr5_mc_secure_top.sv` (`cfg_parity_check_en` port), `rtl/frontend/axi_slave_frontend.sv`, and `rtl/bus/apb_csr_regs.sv` (`reg_ext_config[12]`).
- **Scope & Integration Model**:
  - The canonical controller top (`axi_ddr5_mc_top.sv`) and secure wrapper (`axi_ddr5_mc_secure_top.sv`) intentionally expose `cfg_parity_check_en` as an **external top-level input port** directly wired into `u_frontend.cfg_parity_check_en` and contain **no internal APB CSR register block** for this flag (preserving the canonical datapath and 400 MHz timing closure). System integrators using canonical top must drive `cfg_parity_check_en` from SoC-level strap pins or an external APB/CSR subsystem.
  - For standalone / crypto-demo SoC configurations integrating `rtl/bus/apb_csr_regs.sv`, `cfg_parity_check_en` is mapped to `reg_ext_config[12]` at `AddrExtConfig = 12'h100` (reset `0`, write-protected when `sec_locked` is asserted).
  - Inside `rtl/frontend/axi_slave_frontend.sv`, when `cfg_parity_check_en = 1'b1`, ASIL-D odd-parity checking runs across all enabled `s_axi_wstrb` bytes on valid W beats **regardless of whether `s_axi_wchk` is zero or non-zero**, asserts `o_parity_err`, and masks the outgoing write strobes (`o_wr_strb = '0`) to block corrupted bytes from updating DRAM while preserving AXI4 beat framing.

### 8.3 [L-3] ABO RFM Priority & `tABO` Deadline Timer (`ddr5_cmd_engine.sv`)
- **Location**: `rtl/backend/ddr5_cmd_engine.sv` (`ko_glob`, `K_REF`, `abo_rfm_req`, `abo_critical`), vs. `rtl/backend/directed_refresh_manager.sv`.
- **Scope & Timing-Driven Revert**:
  - **Implemented**: Victim row `±1..3` boundary clamping in `rtl/backend/directed_refresh_manager.sv` eliminates uint32 underflow/wraparound near row `0` and `ROW_MAX` across both FSM enqueue paths and legacy PROQ matching.
  - **Open Limitation (Reverted for 400 MHz Timing Closure)**: Candidate fixes in `rtl/backend/ddr5_cmd_engine.sv` to prioritize `abo_rfm_req` over postponed periodic refresh (`K_REF` when `ref_owed >= MAX_POSTPONE`) and enforce a countdown `tABO` deadline timer (`abo_timer`) regressed Vivado post-synthesis WNS from baseline `-0.022 ns` (`t52_before`) to `-0.261 ns` (`t52_after`, `TNS = -6.869 ns` vs. the `-0.072 ns` `0.05 ns` regression budget; critical path `u_cmd_engine/ref_mode_reg/Q -> ko_glob -> pre_rdy -> any_pre -> decoy_c -> pk_oh_reg[*]/D`). Following the same timing-regression rule, the `ddr5_cmd_engine.sv` ABO/`tABO` modification was reverted to preserve 400 MHz closure; periodic refresh starvation relief still takes precedence over PRAC ABO RFM when `ref_owed >= MAX_POSTPONE`, and no hardware `tABO` deadline timer is enforced inside `ddr5_cmd_engine.sv`.

---

## 9. Tiêu chuẩn và kiểm chứng (Standards & Verification Boundaries)

Phần này nêu rõ phạm vi những gì đã được kiểm chứng và những gì chưa:

### 9.1 Trạng thái chứng nhận tiêu chuẩn bảo mật (FIPS 140-3, CC, ISO/IEC 17825)
- **FIPS 140-3**: Q-Shield chỉ sử dụng FIPS 140-3 như một **khung tham chiếu kỹ thuật** đối chiếu các yêu cầu quản lý khóa bí mật (write-only sau khi `sec_locked`), cơ chế zeroization trên reset và cảnh báo bảo mật, và kiểm tra TMR cho thanh ghi bảo mật. Thiết kế **chưa được chứng nhận FIPS 140-3** bởi bất kỳ phòng kiểm chuẩn mật mã (CST lab) hay cơ quan quản lý (CMVP) nào; tuyệt đối không tuyên bố "đạt chứng nhận FIPS 140-3".
- **Common Criteria (ISO/IEC 15408)**: Chỉ được sử dụng làm **khung mô hình đe dọa** (Byzantine hash collision, RowHammer rate pacing, chống SEU và bus snooping); thiết kế **không nhận và không tuyên bố bất kỳ cấp độ bảo đảm EAL nào** (EAL1–EAL7).
- **ISO/IEC 17825**: Chưa triển khai đo lường TVLA (Test Vector Leakage Assessment) trên chip vật lý; S-Box hiện tại trong active datapath là dạng LUT chưa che mặt nạ (unmasked) để tối ưu timing 400 MHz; trạng thái đối với ISO/IEC 17825 là **CHƯA LÀM** (chỉ có thể tự chạy đánh giá rò rỉ kiểu TVLA trong tương lai, không phải chứng nhận phòng lab).

### 9.2 Giới hạn kiểm chứng hình thức BMC
- Các bằng chứng kiểm chứng hình thức SymbiYosys trong `formal/` được thực thi bằng phương pháp **Bounded Model Checking (BMC) với giới hạn độ sâu hữu hạn (depth 12 đến 15 chu kỳ)** và temporal induction cục bộ, **không phải là chứng minh toán học trên độ sâu vô hạn** ($\infty$).
- **Mô hình trừu tượng độc lập của toàn vẹn**: File `formal/integrity_formal.sv` là một **mô hình trừu tượng độc lập** (sử dụng tham số thu nhỏ, không gọi hay instantiate các module RTL thực tế như `qshield_bmt_engine`, `qshield_meta_cache` hay `qshield_axi_crypto_bridge`). Do đó, các bất biến toàn vẹn Bonsai Merkle Tree được chứng minh trên mô hình toán học trừu tượng, **chưa được chứng minh hình thức trực tiếp trên toàn bộ netlist RTL thực tế**. Tuyệt đối không viết "RTL được kiểm chứng hình thức cho phần toàn vẹn".

### 9.3 Giới hạn kiểm thử đột biến (mutation testing)
- Engine kiểm thử đột biến RTL (`tools/mutate_rtl.py`) được đánh giá trên tập **20 mutant** phân bổ qua 4 khối: scheduler, ROB, adapter và CSR.
- **Tỷ lệ diệt đột biến**: Đạt **90.0% (18/20 mutant bị diệt)**, đúng bằng ngưỡng tối thiểu (>= 90%).
- **Mutant sống sót**: Có 2 mutant trong khối ROB (`MUT-ROB-01` và `MUT-ROB-05` liên quan đến điều kiện phát hiện RAW hazard) sống sót qua testbench ngẫu nhiên; dù được giải thích là có cơ chế formal bảo vệ, 2 mutant này **chưa được chạy kiểm tra lại trực tiếp bằng công cụ formal**.
- **Phạm vi hạn chế**: Mutation testing **chưa bao phủ các khối đóng góp trọng tâm mới** bao gồm: bridge mã hóa (`qshield_axi_crypto_bridge`), Bonsai Merkle Tree engine (`qshield_bmt_engine`), bộ đệm metadata (`qshield_meta_cache`) và đường ống mã hóa XTS (`subchannel_aes_xts_pipe`).

### 9.4 Giới hạn độ phủ UVM pyuvm
- Môi trường kiểm thử UVM chuẩn công nghiệp pyuvm 5.0.0 (`tb/uvm/run_uvm.py`) báo cáo độ phủ chức năng 100% (`hit=23/23`).
- **Bản chất độ phủ**: Con số 100% này **chỉ phản ánh độ phủ của 23 bin chức năng tự định nghĩa** (16 bin trong `mc_env` và 7 bin trong `csr_env`), **không đại diện cho độ phủ mã nguồn (line/branch/toggle code coverage) hay độ phủ chức năng toàn diện chuẩn ngành EDA**.
- Số lượng seed ngẫu nhiên hiện tại còn hạn chế (mặc định 2 đến 5 seeds).

### 9.5 Cocotb + Verilator suites
- The repository also contains cocotb suites that run on Verilator (`python run_all_tests.py --skip-gate --skip-findings --skip-corner-matrix`).
  They had fallen behind the RTL: with Verilator 5.032, 14 of 24 stages failed. Each failure was classified and
  the suites were repaired: 23 of 24 stages now pass locally with Verilator 5.032. Thirteen failures were out-of-date tests
  (RTL changed on purpose earlier, tests kept the old expectations) and none was a regression; four Verilator lint
  warnings in the RTL (width, missing pin, combinational loop) were fixed without changing behaviour. `tools/check_cocotb_triage.py`
  prints the per-stage result and fails on any unexplained failure.
- The remaining stage is the PyUVM random/corner stage, which needs the `pyuvm` package that was not installed in the local
  Linux environment (it passes where the package is installed: 23 of 23 checks).
- The SDC-filter counters are reset to zero when a row reaches the threshold, so rows that share a counter bin can
  under-count each other. The many-sided test needed 8 rounds instead of 6 to throttle all 8 aggressors at threshold 4. How much of that
  is the old test's counting and how much is real under-counting from bin collisions has not been separated yet; it is part of the planned
  RowHammer evaluation, so do not quote an effective threshold of 2T as proven.
- The continuous-integration workflow still runs these suites as a non-blocking job, because the workflow has not yet been
  run with the newer Verilator it installs.
- The regression that is maintained with the RTL uses Icarus Verilog: `python run_iverilog_regression.py` and
  `python tb/findings/run_findings.py`.

