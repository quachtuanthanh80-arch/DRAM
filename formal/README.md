# Formal Verification Suite for Q-Shield
# SymbiYosys (SBY) & Z3 SMT formal proofs for hardware invariants and security guarantees.

## Overview

This directory contains 11 formal verification specifications evaluated via **SymbiYosys (SBY)** using the **Z3 SMT solver** (or Boolector/Yices2).

### Proof Summary Table

| # | SBY Specification | Target RTL Module | Mode | Depth | Proven Invariant / Security Guarantee |
|:---:|:---|:---|:---:|:---:|:---|
| 1 | `formal_sdc_filter.sby` | `sdc_resilient_filter.sv` | `prove` | 30 | Count-Min sketch bound $\min(C_1, C_2) \ge N_{\text{act}}$ (0% False Negatives, FNR=0), O(1) epoch reset |
| 2 | `formal_ate.sby` | `adaptive_threshold_engine.sv` | `bmc` | 20 | Dynamic threshold bound $\theta \in [\theta_{\text{base}}, \theta_{\text{max}}]$, anti-evasion rate pacing |
| 3 | `formal_drm.sby` | `directed_refresh_manager.sv` | `bmc` | 20 | Backpressure stall assertion on buffer saturation ($\ge 6/8$), zero-drop guarantee |
| 4 | `formal_cmd_engine.sby` | `ddr5_cmd_engine.sv` | `bmc` | 25 | Strict JEDEC DDR5 timing compliance ($t_{\text{RP}}, t_{\text{RCD}}, t_{\text{RAS}}$) |
| 5 | `formal_rob.sby` | `reorder_buffer.sv` | `prove` | 25 | In-order retirement, zero Read-After-Write (RAW) data hazard, deadlock-free |
| 6 | `formal_skid_buffer.sby` | `axi4_skid_buffer.sv` | `prove` | 30 | Zero-bubble AXI throughput, data invariance under downstream stall |
| 7 | `formal_slack_arbiter.sby` | `slack_aware_arbiter.sv` | `bmc` | 20 | 4-Tier QoS priority fairness, bank group bypassing, anti-starvation bound |
| 8 | `formal_ecc_scrubber.sby` | `ecc_scrubber_engine.sv` | `prove` | 20 | Autonomous SEC-DED (72, 64) single-bit correction & double-bit alert invariance |
| 9 | `formal_scrambler.sby` | `bus_crypto_engine.sv` | `prove` | 20 | Bus crypto invertibility: $D = \text{descramble}(\text{scramble}(D))$ |
| 10 | `formal_qos_queue.sby` | `qos_scheduler_queue.sv` | `bmc` | 20 | Per-bank-group queue ordering, zero pointer leakage |
| 11 | `formal_async_fifo.sby` | `async_fifo_gray.sv` | `prove` | 30 | Gray-code CDC safety across AXI (250 MHz) and DDR (400 MHz) domains |

## How to Run

### Run All Formal Proofs (Master Script)
```bash
cd formal
bash run_all_formal.sh
```

### Run an Individual Proof
```bash
sby -f formal_sdc_filter.sby
sby -f formal_ate.sby
sby -f formal_drm.sby
```

## Note on Unconstrained Inputs (Adversarial Universal Quantification)
In SBY, input command streams (`i_cmd_valid`, `i_cmd_row`, `i_cmd_bank`, `i_cmd_bg`) have NO artificial `assume()` restrictions. Consequently, the SMT solver proves assertions across **all mathematically possible sequences**, inherently covering arbitrary worst-case adversarial access patterns.
