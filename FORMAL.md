# Q-Shield Formal Verification Report & SVA Specification

This document details the formal verification methodology, temporal logic specifications, SystemVerilog Assertions (SVA), solver assumptions, and proof guarantees for the **Q-Shield** secure memory controller.

---

## 1. Formal Verification Architecture & Solver Setup

- **Toolchain**: SymbiYosys (SBY) v0.38+ with Yosys 0.38+
- **SMT Solvers**: Yices 2.6.4 (primary for bit-level arithmetic and BMC), Z3 4.12.2 (secondary for $k$-induction)
- **Clock Domain**: Synchronous controller core domain (`clk`, active-high synchronous `rst_n`)
- **Execution Script**: [`formal/run_all_formal.sh`](formal/run_all_formal.sh)

---

## 2. Classification of Formal Properties: BMC vs. Induction

Formal methods distinguish between **Bounded Model Checking (BMC)** (which verifies that no safety property is violated within the first $k$ cycles from reset) and **$k$-Induction (Prove Mode)** (which mathematically proves unbounded correctness for all future time steps).

| # | Property Target | SBY Configuration File | Mode | Depth ($k$) | Solver | Verified Guarantee |
| :- | :--- | :--- | :--- | :-: | :--- | :--- |
| **P1** | SDC Counter Monotonicity | [`formal_sdc_filter.sby`](formal/formal_sdc_filter.sby) | **Prove ($k$-Ind)** | **30** | Yices + Z3 | Unbounded: Counters monotonically increment upon activation; never decrement or wrap illegally. |
| **P2** | SDC Single-Cycle Reset | [`formal_sdc_filter.sby`](formal/formal_sdc_filter.sby) | **Prove ($k$-Ind)** | **30** | Yices + Z3 | Unbounded: On epoch trigger, all counter outputs evaluate to 0 within exactly 1 clock cycle. |
| **P3** | SDC False-Negative Immunity | [`formal_sdc_filter.sby`](formal/formal_sdc_filter.sby) | **Prove ($k$-Ind)** | **30** | Yices + Z3 | Unbounded: If true row activations exceed threshold $T$, filter output never reports $< T$. |
| **P4** | ATE Clamping Safety | [`formal_ate.sby`](formal/formal_ate.sby) | **BMC** | **20** | Yices | Bounded: Threshold $T_{thresh}$ is strictly bounded within $[T_{min}, T_{max}] = [16, 512]$ across all arbitrary inputs. |
| **P5** | ATE Saturation Invariance | [`formal_ate.sby`](formal/formal_ate.sby) | **BMC** | **20** | Yices | Bounded: EWMA multiplier arithmetic does not experience arithmetic overflow or sign bit corruption. |
| **P6** | DRM Rate Pacing Safety | [`formal_drm.sby`](formal/formal_drm.sby) | **BMC** | **20** | Yices | Bounded: Throttled aggressor rows cannot exceed target dispatch rate $R_{max}$. |
| **P7** | DRM Queue Non-Starvation | [`formal_drm.sby`](formal/formal_drm.sby) | **BMC** | **20** | Yices | Bounded: Benign bank queues never experience indefinite backpressure due to aggressor stalls. |
| **P8** | CMD $t_{RCD}$ Timing Compliance | [`formal_cmd_engine.sby`](formal/formal_cmd_engine.sby) | **BMC** | **25** | Yices | Bounded: `READ`/`WRITE` commands are strictly separated from prior `ACT` by $\ge t_{RCD}$ cycles. |
| **P9** | CMD $t_{RP}$ Precharge Compliance | [`formal_cmd_engine.sby`](formal/formal_cmd_engine.sby) | **BMC** | **25** | Yices | Bounded: Subsequent `ACT` to same bank is strictly separated from `PRE` by $\ge t_{RP}$ cycles. |
| **P10** | CMD $t_{CCD\_L}$ Bank Group Spacing | [`formal_cmd_engine.sby`](formal/formal_cmd_engine.sby) | **BMC** | **25** | Yices | Bounded: Back-to-back column commands to same bank group respect $t_{CCD\_L}$ timing gap. |
| **P11** | Skid Buffer Zero-Drop Liveness | [`formal_skid_buffer.sby`](formal/formal_skid_buffer.sby) | **Prove ($k$-Ind)** | **20** | Yices + Z3 | Unbounded: No valid transaction beats are dropped during backpressure handshake transitions. |

---

## 3. Temporal Logic & SystemVerilog Assertion (SVA) Specifications

### 3.1 P2: Single-Cycle Epoch Reset
$$\mathbf{G} \left( \text{epoch\_reset\_pulse} \implies \mathbf{X} (\forall i \in [0, N-1], \; \text{filter\_count}[i] == 0) \right)$$
```systemverilog
property p_single_cycle_epoch_reset;
    @(posedge clk) disable iff (!rst_n)
    epoch_reset_pulse |=> (filter_effective_count == '0);
endproperty
assert property (p_single_cycle_epoch_reset);
```

### 3.2 P3: SDC False-Negative Boundedness
Let $A(r)$ be the true activation count of row $r$ within the current epoch, and $C(r) = \min(\text{Table}_1[h_1(r)], \text{Table}_2[h_2(r)])$ be the Count-Min estimate:
$$\mathbf{G} \left( C(r) \ge A(r) \right)$$
```systemverilog
property p_sdc_no_false_negatives;
    @(posedge clk) disable iff (!rst_n)
    (true_row_activations >= threshold) |-> (filter_alert_flag == 1'b1);
endproperty
assert property (p_sdc_no_false_negatives);
```

### 3.3 P4: Adaptive Threshold Range Invariant
$$\mathbf{G} \left( T_{min} \le T_{thresh} \le T_{max} \right)$$
```systemverilog
property p_ate_threshold_bounded;
    @(posedge clk) disable iff (!rst_n)
    (adaptive_threshold >= 16'd16) && (adaptive_threshold <= 16'd512);
endproperty
assert property (p_ate_threshold_bounded);
```

### 3.4 P8: JEDEC $t_{RCD}$ Timing Invariant
$$\mathbf{G} \left( \text{cmd\_act}[b] \implies \neg \left( \bigvee_{i=1}^{t_{RCD}-1} \mathbf{X}^i (\text{cmd\_read}[b] \lor \text{cmd\_write}[b]) \right) \right)$$
```systemverilog
property p_jedec_trcd_compliance;
    @(posedge clk) disable iff (!rst_n)
    (cmd_valid && cmd_type == CMD_ACT) |-> 
        not (##[1:PARAM_TRCD-1] (cmd_valid && (cmd_type == CMD_RD || cmd_type == CMD_WR) && cmd_bank == $past(cmd_bank)));
endproperty
assert property (p_jedec_trcd_compliance);
```

---

## 4. Verification Assumptions & Unconstrained Inputs

To prove correctness without masking real failure modes, the formal harness applies only necessary protocol preconditions:
1. **Reset Precondition**: Active-low reset `rst_n` remains asserted low for $\ge 2$ clock cycles before deassertion.
2. **Valid Command Precondition**: Incoming AXI4 command requests adhere to valid address ranges (no undefined `1'bx` or `1'bz` control bits).
3. **Unconstrained Attack Streams**: Row activation addresses and request frequencies are left **completely unconstrained** by the solver, allowing the formal engine to synthesize worst-case adversarial access sequences to expose safety violations.

---

## 5. Formal Verification Limitations & Boundaries

1. **Finite Depth of BMC Properties**: Properties P4–P10 are verified via Bounded Model Checking up to depth $k \in [20, 25]$. While sufficient to check command transitions and timer wrapping, BMC does not constitute an unbounded proof over arbitrary operating lifespans.
2. **Synchronous Behavioral Abstraction**: Verification targets synthesizable register-transfer level (RTL) SystemVerilog. It abstracts analog PHY signaling, board-level impedance mismatches, clock jitter, and DRAM silicon crosstalk.
3. **Non-Targeted Threat Classes**: Formal assertions do not model physical side-channel leakage (DPA/EM), speculative transient execution attacks, or thermal RowPress degradation beyond digital threshold models.
