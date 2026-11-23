# Formal Verification Suite for Q-Shield DDR5 Memory Controller

This directory contains the formal property harnesses, SystemVerilog assertions, and SymbiYosys (`sby`) configurations for the **Q-Shield** DDR5 secure memory controller. Verified runs use **SymbiYosys (SBY)** with **Yosys 0.52** and the **Z3 SMT solver** (`smtbmc z3`).

---

## 1. Verified Formal Suite Summary (BMC + Cover)

Only the **five suites** listed below have been executed and confirmed PASS on the current repository revision (logged in `reports/remediation/T61.log`). All five use **Bounded Model Checking (BMC)** and **Cover** — they confirm no counter-example exists within the stated depth (`depth 15`), and are **not** unbounded $k$-induction proofs.

| # | SBY Specification | Harness / Target | Mode | Solver | Depth | Status | Checked Properties |
|:---:|:---|:---|:---:|:---:|:---:|:---:|:---|
| F1 | [`formal_integrity.sby`](formal_integrity.sby) | `integrity_formal.sv` (**abstract model**, no RTL instantiation) | BMC + Cover | Z3 | BMC `15` / Cover `12` (4 traces) | PASS | Counter tuple uniqueness `(major, minor, addr)` and `(L, major, minor)`, MAC fail SLVERR, metadata cache unpinned way, BMT root update consistency. |
| F2 | [`formal_sec_lock.sby`](formal_sec_lock.sby) | `sec_lock_formal.sv`, `apb_csr_regs.sv`, `fault_hardened_csr.sv` | BMC + Cover | Z3 | BMC `15` / Cover `8` (2 traces) | PASS | `sec_locked` stability over `enc_enable`, `!keys_valid` gating `pipe_in_valid`, non-secure APB write rejection (`pslverr`). |
| F3 | [`formal_scheduler_bank.sby`](formal_scheduler_bank.sby) | `scheduler_bank_formal.sv`, `ddr5_subchannel_scheduler.sv` | BMC + Cover | Z3 | BMC `15` / Cover `15` (4 traces) | PASS | `ACT` precedes `RD`/`WR` per `{bg, bank}` (`bank_state[{cmd_bg, cmd_ba}] == BANK_ACTIVE`). |
| F4 | [`formal_axi_protocol.sby`](formal_axi_protocol.sby) | `axi_protocol_formal.sv` | BMC + Cover | Z3 | BMC `15` / Cover `15` (3 traces) | PASS | AMBA AXI4 `VALID` stability under backpressure and handshake progress. |
| F5 | [`formal_rob_retire.sby`](formal_rob_retire.sby) | `rob_retire_formal.sv` | BMC + Cover | Z3 | BMC `15` / Cover `15` (4 traces) | PASS | ROB beat conservation and no duplicate `R` beat emission when `RREADY = 0`. |

### Legacy SBY Files (Not Re-Verified / Known Open)

Earlier `.sby` files (`formal_sdc_filter.sby`, `formal_ate.sby`, `formal_drm.sby`, `formal_cmd_engine.sby`, `formal_cmd_engine_v2.sby`, `formal_skid_buffer.sby`, `formal_ecc_scrubber.sby`, `formal_scrambler.sby`, `formal_async_fifo.sby`, `formal_qos_queue.sby`, `formal_slack_arbiter.sby`, `formal_rob.sby`, `formal_axi_frontend.sby`) were written for earlier RTL revisions and have **not** been re-verified as passing or unbounded proofs on the current RTL. Two legacy failures are documented in [`known_open.txt`](known_open.txt) (`formal_rob.sby` and `formal_axi_frontend.sby`).

---

## 2. Formal Methodology & Known Limitations

- **Bounded Horizon Only**: BMC at `depth 15` verifies all reachable states within 15 cycles from reset; it does not prove unbounded correctness ($\forall t \ge 0$).
- **Abstract Integrity Model**: `integrity_formal.sv` models the integrity protocol with reduced parameters and does **not** instantiate `qshield_bmt_engine.sv`, `qshield_meta_cache.sv`, or `qshield_axi_crypto_bridge.sv`. Do not cite `formal_integrity.sby` as a formal proof of the integrity RTL.
- **Yosys 0.52 Syntax**: Because open-source Yosys 0.52 lacks full concurrent `property ... endproperty` support, SBY harnesses use immediate `always_ff` assertions; concurrent SVA versions for commercial tools are kept in `../tb/sv_props/`.
- **Abstraction Scope**: Formal checks operate on synchronous digital models and do not cover analog PHY timing, power/EM side channels, or DRAM cell disturbance physics.

---

## 3. How to Run the Verified Suites

Run inside WSL Ubuntu (where `sby`, `yosys`, and `z3` are installed):

```bash
sby -f formal/formal_integrity.sby
sby -f formal/formal_sec_lock.sby
sby -f formal/formal_scheduler_bank.sby
sby -f formal/formal_axi_protocol.sby
sby -f formal/formal_rob_retire.sby
```
