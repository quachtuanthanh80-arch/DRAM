# Q-Shield SystemVerilog RTL Hierarchy (`rtl/`)

This directory contains the synthesizable SystemVerilog (IEEE 1800-2017) source files for the Q-Shield DDR5 memory controller.

---

## 1. Canonical Production Top vs. Crypto-Integration Demo Top (Decision D1)

| Top Module | File | Role & Scope | Used for Claims / Metrics? |
| :--- | :--- | :--- | :---: |
| **`axi_ddr5_mc_top`** | [`rtl/top/axi_ddr5_mc_top.sv`](top/axi_ddr5_mc_top.sv) | **Canonical production top-level module.** Integrates the full AXI4/AXI5 slave frontend, burst splitter, read/write issue queues, SCARF row randomizer, PXOR dual-hash SDC filter, Adaptive Threshold Engine (ATE), Directed Refresh Manager (DRM), per-BG QoS scheduler queues, bank credit controller, Reorder Buffer (ROB), timing-slack aware arbiter, JEDEC DDR5 command engine, SEC-DED (72,64) ECC scrubber, bus scrambler, fault-hardened TMR CSRs, and Multi-VM ASID key table. | **Yes (Canonical)** |
| **`sec_ddr5_controller_top`** | [`rtl/top/sec_ddr5_controller_top.sv`](top/sec_ddr5_controller_top.sv) | **Demo tích hợp crypto, chưa dùng cho số liệu/claim.** Standalone integration demonstration of the dual-lane AES-256-XTS pipeline (`subchannel_aes_xts_pipe`), dual-clock Gray-code CDC FIFOs (`async_fifo_cdc`), and dual subchannel schedulers (`ddr5_subchannel_scheduler`). Contains known open demo limitations **C-1**, **C-3**, **C-4**, and **H-1** documented in [`../LIMITATIONS.md`](../LIMITATIONS.md) §6. Never instantiated by `axi_ddr5_mc_top`. | **No (Demo Only)** |

---

## 2. Canonical Top (`axi_ddr5_mc_top`) Instance Tree

`axi_ddr5_mc_top` (`rtl/top/axi_ddr5_mc_top.sv`) instantiates only the following verified production modules:

- **Clock & Reset (`rtl/cdc/`)**:
  - `rst_sync.sv` — Dual-rank asynchronous reset assertion / synchronous deassertion synchronizers (`u_rst_axi_sync`, `u_rst_ddr_sync`).
  - `async_fifo_cdc.sv` — Parameterized Gray-code dual-clock FIFO for `clk_axi` ↔ `clk_ddr` domain crossing when `ASYNC_CDC=1`.
- **Host Bus & Frontend (`rtl/bus/`, `rtl/frontend/`)**:
  - `axi4_skid_buffer.sv` — Zero-bubble 2-entry AXI channel register slice.
  - `axi_slave_frontend.sv` — AMBA AXI4/AXI5 slave interface, 4KB boundary check, ASIL-D parity check, and APB4 CSR port.
  - `wdata_buffer.sv`, `wr_data_store.sv` — Write data buffering and sub-word write strobe handling.
  - `axi_burst_splitter.sv` — Splits multi-beat AXI bursts into beat-level memory requests.
  - `rd_issue_queue.sv` — Read request issue queue tracking per-bank-group pending reads.
  - `domain_bank_coloring.sv` — Multi-tenant security domain bank coloring.
  - `addr_mapper_ddr5.sv` — Physical-to-DRAM address mapper (Rank, BG, Bank, Row, Col) with Modulo-3 / XOR bank hashing.
  - `perf_monitor_unit.sv` — Hardware telemetry and performance counter unit.
- **Core Security & Scheduling (`rtl/core/`, `rtl/crypto/`, `rtl/top/`)**:
  - `scarf_dram_randomizer.sv` — Bijective unbalanced Feistel row address randomizer.
  - `pxor_hash_engine.sv`, `sdc_resilient_filter.sv` — Dual-hash Count-Min sketch row activation tracker with single-cycle epoch reset.
  - `adaptive_threshold_engine.sv` — EWMA dynamic activation threshold engine (ATE).
  - `qos_scheduler_queue.sv` — Per-bank-group QoS command queues (8 instances) with same-address RAW/WAR/WAW hazard tracking.
  - `bank_credit_ctrl.sv` — Per-physical-bank queue slot reservation and shared credit pool controller.
  - `reorder_buffer_rob.sv` — 16-entry circular CAM Reorder Buffer enforcing per-AXI-ID in-order read retirement.
  - `fault_hardened_csr.sv` — Triple Modular Redundancy (TMR) 2-out-of-3 majority-voted security control registers.
  - `multi_vm_key_table.sv` — 16-ASID isolated key table with APB4 `PPROT` supervisor access control.
- **DRAM Backend & Data Integrity (`rtl/backend/`, `rtl/memory/`)**:
  - `slack_aware_arbiter.sv` — Timing-slack aware cross-bank-group command arbiter and write-drain hysteresis controller.
  - `directed_refresh_manager.sv` — Proactive victim refresh (`Row ± 1`, `Row ± 2`) queue and blast-radius dispatcher.
  - `ddr5_cmd_engine.sv` — JEDEC JESD79-5 bank-parallel command FSM (`tRCD`, `tRP`, `tRAS`, `tRFC`, `tREFI`, `tFAW`, `tCCD_L/S`, `tWR`, `tRTP`, PRAC ABO, autonomous RFM, `tRAS_max` RowPress clamp, partial-write RMW).
  - `secded_72_64_pkg.sv`, `ecc_scrubber.sv` — Autonomous Hsiao (72,64) SEC-DED encoder/decoder with `0xAA` check-bit inversion and background patrol scrubber.
  - `bus_scrambler.sv`, `scrambler_ks_pipe.sv` — Data bus scrambler and pipelined keystream generator.

---

## 3. Demo & Standalone Subsystems (Not Instantiated in `axi_ddr5_mc_top`)

- **Crypto-Integration Demo Top (`rtl/top/sec_ddr5_controller_top.sv`)**:
  - Uses `rtl/bus/axi4_slave_adapter.sv`, `rtl/bus/apb_csr_regs.sv`, `rtl/crypto/subchannel_aes_xts_pipe.sv`, `rtl/cdc/async_fifo_cdc.sv`, `rtl/memory/ddr5_subchannel_scheduler.sv`, `rtl/memory/dfi_phy_adapter.sv`, and `rtl/crypto/qshield_crypto_top.sv`.
  - Exercised by demo testbench `tb/top/tb_sec_ddr5_controller_top.sv`; open demo findings `C-1`, `C-3`, `C-4`, and `H-1` are reproduced by `python tb/findings/run_findings.py` (`tb/findings/known_open_demo.txt`).
- **Standalone Cryptographic Engines (`rtl/crypto/`)**:
  - `aes_pkg.sv`, `aes_sbox.sv`, `aes_sbox_composite.sv`, `aes_tweak_gen.sv`, `aes_round_pipe.sv`, `subchannel_aes_xts_pipe.sv`, `aes256_key_expand.sv`, `aes128_enc_iter.sv`, `aes_ctr_keystream.sv`, `split_counter_table.sv`, `integrity_mac_gen.sv`, `qshield_crypto_top.sv` — verified at unit/subsystem level (`tb_aes_sbox_test`, `tb_aes_xts_pipe`, `tb_aes256_key_expand`, `tb_aes128_enc_iter`, `tb_qshield_crypto_top`, `tb_integrity_mac_attack`).
- **Standalone Chipkill Reed-Solomon ECC (`rtl/backend/`)**:
  - `gf256_arith_pkg.sv`, `rs_chipkill_encoder.sv`, `rs_chipkill_decoder.sv` — RS(18,16) over $GF(2^8)$ verified by `tb_rs_chipkill_selfcheck` and `tb_rs_parity_chip`.
- **Form-Factor Interconnect Shims (`rtl/interfaces/`)**:
  - `pcie_cxl_io_apb_shim.sv`, `cxl_mem_axi_shim.sv`, `ucie_fdi_axi_shim.sv` — verified by `tb_pcie_cxl_io_shim`, `tb_cxl_mem_axi_shim`, and `tb_ucie_fdi_axi_shim`.
