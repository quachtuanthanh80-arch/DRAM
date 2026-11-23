# Q-Shield Formal Verification Report & SVA Specification

This document details the formal verification methodology, SystemVerilog Assertions (SVA), solver setup, verified bounded checks, and known limitations for the **Q-Shield** DDR5 secure memory controller.

---

> **Status of this document.** The verified formal evidence in this repository consists of **five SymbiYosys Bounded Model Checking (BMC) + Cover suites** executed with Z3. Bounded model checking confirms that no assertion violation occurs within the stated cycle depth (`depth 15`); it is **not** an unbounded proof. In addition, the integrity suite (`formal/formal_integrity.sby`) verifies an **abstract model** (`formal/integrity_formal.sv`) with reduced parameters that does not instantiate the RTL (`qshield_bmt_engine`, `qshield_meta_cache`, `qshield_axi_crypto_bridge`). Earlier legacy `.sby` tables claiming unbounded $k$-induction (`k = 20..30`) have not been re-verified on the current RTL and are listed separately below.

## 1. Formal Verification Architecture & Solver Setup

- **Toolchain**: SymbiYosys (SBY) with Yosys 0.52 (executed in WSL Ubuntu)
- **SMT Solver**: Z3 (`smtbmc z3`)
- **Clock Domain**: Single synchronous controller core domain (`clk`, active-low `rst_n`)
- **Concurrent SVA Library (for commercial simulators)**: [`tb/sv_props/`](tb/sv_props/) (`integrity_invariants_sva.sv`, `security_lock_sva.sv`, `scheduler_sva.sv`, `axi_protocol_sva.sv`, `rob_sva.sv`)
- **Known Open Legacy Assertions**: [`formal/known_open.txt`](formal/known_open.txt)

---

## 2. Verified Formal Suites (BMC + Cover)

All five suites below were executed with SymbiYosys + Z3 and returned `PASS` (`rc = 0`, 17 cover traces total; logged in [`formal/evidence/bmc_cover_run.log`](formal/evidence/bmc_cover_run.log)):

| # | Target Scope | SBY Configuration File | Model / Source | BMC Mode & Depth | Cover Mode & Traces | Checked Safety Invariants (Bounded) |
| :- | :--- | :--- | :--- | :-: | :-: | :--- |
| **F1** | Integrity & BMT Invariants | [`formal_integrity.sby`](formal/formal_integrity.sby) | **Abstract model** (`formal/integrity_formal.sv`, no RTL instantiation) | BMC `depth 15` PASS | Cover `depth 12` (4 traces) PASS | Uniqueness of `(major, minor, addr)` and `(L, major, minor)`, MAC failure returning SLVERR, metadata cache unpinned way rule, BMT root update consistency. |
| **F2** | Security Lock & Key-Valid Gating | [`formal_sec_lock.sby`](formal/formal_sec_lock.sby) | `formal/sec_lock_formal.sv`, `formal/apb_csr_regs.sv`, `formal/fault_hardened_csr.sv` | BMC `depth 15` PASS | Cover `depth 8` (2 traces) PASS | Once `sec_locked` is asserted, `enc_enable` remains stable; `!keys_valid` gates `pipe_in_valid`; non-secure APB writes return `pslverr`. |
| **F3** | Scheduler Bank Timing | [`formal_scheduler_bank.sby`](formal/formal_scheduler_bank.sby) | `formal/scheduler_bank_formal.sv`, `formal/ddr5_subchannel_scheduler.sv` | BMC `depth 15` PASS | Cover `depth 15` (4 traces) PASS | `RD`/`WR` commands require the targeted `{bg, bank}` to be in `BANK_ACTIVE` state after `ACT` (covering `ACT`, `RD`, `WR`, `PRE`). |
| **F4** | AMBA AXI4 Handshake Stability | [`formal_axi_protocol.sby`](formal/formal_axi_protocol.sby) | `formal/axi_protocol_formal.sv` | BMC `depth 15` PASS | Cover `depth 15` (3 traces) PASS | Channel `VALID` and payload stability under backpressure (`!READY`) and bounded handshake progress. |
| **F5** | ROB Beat Conservation | [`formal_rob_retire.sby`](formal/formal_rob_retire.sby) | `formal/rob_retire_formal.sv` | BMC `depth 15` PASS | Cover `depth 15` (4 traces) PASS | Read beat conservation across retirement and no duplicate `R` beat emission when `RREADY = 0`. |

---

## 3. Legacy Formal Targets (Not Re-Verified on Current RTL)

Older `.sby` configurations remain in `formal/` from earlier repository revisions (`formal_sdc_filter.sby`, `formal_ate.sby`, `formal_drm.sby`, `formal_cmd_engine.sby`, `formal_cmd_engine_v2.sby`, `formal_skid_buffer.sby`, `formal_ecc_scrubber.sby`, `formal_scrambler.sby`, `formal_async_fifo.sby`, `formal_qos_queue.sby`, `formal_slack_arbiter.sby`, `formal_rob.sby`, `formal_axi_frontend.sby`). They are **not** claimed as passing or unbounded $k$-induction proofs on the current RTL. Specifically, two legacy assertions are tracked as **known open** in [`formal/known_open.txt`](formal/known_open.txt):

1. `formal_rob.sby` (`reorder_buffer_rob.sv`): legacy assertion `o_alloc_ready == !o_rob_full` does not account for `o_raw_hazard` gating `o_alloc_ready`.
2. `formal_axi_frontend.sby` (`axi_slave_frontend.sv`): legacy `$past` assertion on `s_axi_rpoison` does not synchronize with the registered `u_r_skid` output stage under backpressure.

---

## 4. Verification Assumptions & Formal Boundaries

1. **Reset Precondition**: Active-low reset `rst_n` is asserted during the initial cycles so sequential state starts in a well-defined reset state.
2. **Protocol Assumptions**: Formal harnesses constrain incoming bus transactions to legal AXI4 / APB4 handshake sequences where required by the property under test.
3. **Finite BMC Horizon**: All five verified suites use Bounded Model Checking (`depth 15`). Multi-epoch behaviors, long-horizon counter overflows, and refresh-window dynamics (`32 ms`) are outside the BMC horizon and are evaluated via RTL simulation and Ramulator2 rather than unbounded formal proofs.
4. **Abstract Integrity Model**: `formal/integrity_formal.sv` models the BMT/MAC/counter protocol invariants with reduced parameters and does **not** instantiate the synthesizable RTL modules (`qshield_bmt_engine.sv`, `qshield_meta_cache.sv`, `qshield_axi_crypto_bridge.sv`). Functional equivalence on the RTL is checked via `tb_secure_top_integrity`, `tb_qshield_bmt_engine`, and `tb_qshield_meta_cache`.
5. **Non-Targeted Threat Classes**: Formal assertions operate at the synchronous RTL / abstract model level and do not model analog PHY signaling, power/EM side channels, or physical DRAM cell crosstalk.
