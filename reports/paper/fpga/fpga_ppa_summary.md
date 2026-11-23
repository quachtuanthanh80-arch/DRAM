# Q-Shield FPGA Post-Route PPA Evaluation Summary
- Ngày đo: 2026-11-19T22:40:08.428882
- Chip mục tiêu: `xczu7ev-ffvc1156-2-e` (Xilinx Zynq UltraScale+)
- Vivado: `unknown` | Threads: `default` | Reuse session presynth DCP: `True`
- Git commit: `1c38d8b27d40f42a83ba73b0e88c93a596fab52c` (dirty (chưa commit))
- Phương pháp đo công suất: vectorless report_power (Vivado default toggle rate 12.5%, no Simulation Activity File)

## 1. Bảng tổng hợp hiệu năng định thời và tài nguyên sau Place & Route

| Module | Initial @ 400 MHz (2.500 ns) WNS / TNS / WHS | Confirmed Period (ns) | Confirmed Fmax (MHz) | Confirmed WNS / TNS / WHS | LUTs (%) | FFs (%) | BRAM Tiles | DSPs | Total Power (W) [Dyn / Static] |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_top` | `-1.273` / `-27880.857` / `0.019` | `3.800` | **`263.16`** | `0.024` / `0.000` / `0.020` | `63785` (`27.68%`) | `44243` (`9.60%`) | `0.0` | `0` | `1.618` (`1.021` / `0.597`) |
| `axi_ddr5_mc_secure_top` | `-1.595` / `-61801.969` / `0.019` | `4.150` | **`240.96`** | `0.021` / `0.000` / `0.011` | `164062` (`71.21%`) | `110190` (`23.91%`) | `7.5` | `0` | `4.437` (`3.824` / `0.613`) |

## 2. Toàn bộ các điểm đo đã chạy (trung thực mọi lần thử)

| Top | Tag | Period (ns) | Fmax (MHz) | WNS (ns) | TNS (ns) | WHS (ns) | Failing EP | LUTs | FFs | Total Power (W) | Elapsed (s) | Log |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `axi_ddr5_mc_top` | `core_2500ps` | `2.500` | `400.00` | `-1.273` | `-27880.857` | `0.019` | `61510` | `65170` | `44293` | `2.190` | — | — |
| `axi_ddr5_mc_top` | `core_confirmed` | `3.800` | `263.16` | `0.024` | `0.000` | `0.020` | `0` | `63785` | `44243` | `1.618` | — | — |
| `axi_ddr5_mc_secure_top` | `sec_2500ps` | `2.500` | `400.00` | `-1.595` | `-61801.969` | `0.019` | `124925` | `165587` | `110298` | `7.259` | — | — |
| `axi_ddr5_mc_secure_top` | `sec_confirmed` | `4.100` | `243.90` | `-0.005` | `-0.010` | `0.020` | `3` | `164064` | `110185` | `4.347` | — | — |
| `axi_ddr5_mc_secure_top` | `sec_confirmed_r2` | `4.150` | `240.96` | `0.021` | `0.000` | `0.011` | `0` | `164062` | `110190` | `4.437` | — | — |

## 3. Phân rã tài nguyên và công suất theo khối (Post-Route Confirmed)

### axi_ddr5_mc_top (`core_confirmed` @ `3.800 ns` / `263.16 MHz`)
| Hierarchical Path | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM Tiles | DSP | Dynamic Power (W) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_top` | `(top)` | 63785 | 63634 | 108 | 44243 | 0.0 | 0 | 1.021 |
| `axi_ddr5_mc_top/(axi_ddr5_mc_top)` | `(top)` | 210 | 158 | 52 | 761 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_addr_mapper` | `addr_mapper_ddr5` | 472 | 441 | 0 | 153 | 0.0 | 0 | 0.032 |
| `axi_ddr5_mc_top/u_addr_mapper/u_scarf_randomizer` | `scarf_dram_randomizer_2` | 435 | 425 | 0 | 111 | 0.0 | 0 | 0.031 |
| `axi_ddr5_mc_top/u_ar_split` | `axi_burst_splitter` | 168 | 168 | 0 | 112 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_top/u_arbiter` | `slack_aware_arbiter` | 252 | 252 | 0 | 11 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_ate` | `adaptive_threshold_engine` | 286 | 286 | 0 | 246 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_top/u_aw_split` | `axi_burst_splitter_0` | 208 | 208 | 0 | 112 | 0.0 | 0 | 0.007 |
| `axi_ddr5_mc_top/u_bank_credit` | `bank_credit_ctrl` | 954 | 954 | 0 | 204 | 0.0 | 0 | 0.022 |
| `axi_ddr5_mc_top/u_cmd_engine` | `ddr5_cmd_engine` | 10146 | 10134 | 12 | 4395 | 0.0 | 0 | 0.107 |
| `axi_ddr5_mc_top/u_decoy_prf` | `scarf_dram_randomizer` | 171 | 171 | 0 | 95 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_top/u_drm` | `directed_refresh_manager` | 2425 | 2425 | 0 | 2354 | 0.0 | 0 | 0.051 |
| `axi_ddr5_mc_top/u_ecc_scrubber` | `ecc_scrubber` | 74 | 74 | 0 | 87 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_top/u_frontend` | `axi_slave_frontend` | 193 | 193 | 0 | 517 | 0.0 | 0 | 0.007 |
| `axi_ddr5_mc_top/u_frontend/u_w_skid` | `axi4_skid_buffer__parameterized0` | 63 | 63 | 0 | 148 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_top/u_frontend/u_ar_skid` | `axi4_skid_buffer` | 39 | 39 | 0 | 108 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_frontend/u_aw_skid` | `axi4_skid_buffer_1` | 32 | 32 | 0 | 108 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_frontend/u_r_skid` | `axi4_skid_buffer__parameterized2` | 54 | 54 | 0 | 142 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_top/u_pmu` | `perf_monitor_unit` | 328 | 328 | 0 | 263 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_top/u_qos_queue` | `qos_scheduler_queue` | 15771 | 15771 | 0 | 5312 | 0.0 | 0 | 0.056 |
| `axi_ddr5_mc_top/u_rd_iq` | `rd_issue_queue` | 1317 | 1317 | 0 | 503 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_top/u_rd_ks` | `scrambler_ks_pipe__parameterized0` | 400 | 399 | 0 | 391 | 0.0 | 0 | 0.018 |
| `axi_ddr5_mc_top/u_rob` | `reorder_buffer_rob` | 4533 | 4533 | 0 | 9211 | 0.0 | 0 | 0.064 |
| `axi_ddr5_mc_top/u_sdc_filter` | `sdc_resilient_filter` | 12062 | 12062 | 0 | 9236 | 0.0 | 0 | 0.279 |
| `axi_ddr5_mc_top/u_wdata_buffer` | `wdata_buffer` | 290 | 246 | 44 | 364 | 0.0 | 0 | 0.024 |
| `axi_ddr5_mc_top/u_wds` | `wr_data_store` | 13174 | 13174 | 0 | 9444 | 0.0 | 0 | 0.212 |
| `axi_ddr5_mc_top/u_wr_ks` | `scrambler_ks_pipe` | 446 | 435 | 0 | 450 | 0.0 | 0 | 0.021 |

### axi_ddr5_mc_secure_top (`sec_confirmed_r2` @ `4.150 ns` / `240.96 MHz`)
| Hierarchical Path | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM Tiles | DSP | Dynamic Power (W) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_secure_top` | `(top)` | 164062 | 162539 | 1478 | 110190 | 7.5 | 0 | 3.824 |
| `axi_ddr5_mc_secure_top/(axi_ddr5_mc_secure_top)` | `(top)` | 1 | 1 | 0 | 0 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge` | `qshield_axi_crypto_bridge` | 101121 | 99749 | 1370 | 65864 | 7.5 | 0 | 2.782 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/(u_crypto_bridge)` | `qshield_axi_crypto_bridge` | 35706 | 34336 | 1370 | 20301 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[10].u_mask_rnd` | `aes_round_pipe` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[10].u_mask_rnd/(gen_mask_aes_round[10].u_mask_rnd)` | `aes_round_pipe` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[11].u_mask_rnd` | `aes_round_pipe_3` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[11].u_mask_rnd/(gen_mask_aes_round[11].u_mask_rnd)` | `aes_round_pipe_3` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[12].u_mask_rnd` | `aes_round_pipe_4` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[12].u_mask_rnd/(gen_mask_aes_round[12].u_mask_rnd)` | `aes_round_pipe_4` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[13].u_mask_rnd` | `aes_round_pipe_5` | 0 | 0 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[13].u_mask_rnd/(gen_mask_aes_round[13].u_mask_rnd)` | `aes_round_pipe_5` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[14].u_mask_rnd` | `aes_round_pipe_6` | 197 | 197 | 0 | 129 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[14].u_mask_rnd/(gen_mask_aes_round[14].u_mask_rnd)` | `aes_round_pipe_6` | 197 | 197 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[1].u_mask_rnd` | `aes_round_pipe_7` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.015 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[1].u_mask_rnd/(gen_mask_aes_round[1].u_mask_rnd)` | `aes_round_pipe_7` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[2].u_mask_rnd` | `aes_round_pipe_8` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[2].u_mask_rnd/(gen_mask_aes_round[2].u_mask_rnd)` | `aes_round_pipe_8` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[3].u_mask_rnd` | `aes_round_pipe_9` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[3].u_mask_rnd/(gen_mask_aes_round[3].u_mask_rnd)` | `aes_round_pipe_9` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[4].u_mask_rnd` | `aes_round_pipe_10` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[4].u_mask_rnd/(gen_mask_aes_round[4].u_mask_rnd)` | `aes_round_pipe_10` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[5].u_mask_rnd` | `aes_round_pipe_11` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[5].u_mask_rnd/(gen_mask_aes_round[5].u_mask_rnd)` | `aes_round_pipe_11` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[6].u_mask_rnd` | `aes_round_pipe_12` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[6].u_mask_rnd/(gen_mask_aes_round[6].u_mask_rnd)` | `aes_round_pipe_12` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[7].u_mask_rnd` | `aes_round_pipe_13` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[7].u_mask_rnd/(gen_mask_aes_round[7].u_mask_rnd)` | `aes_round_pipe_13` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[8].u_mask_rnd` | `aes_round_pipe_14` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[8].u_mask_rnd/(gen_mask_aes_round[8].u_mask_rnd)` | `aes_round_pipe_14` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[9].u_mask_rnd` | `aes_round_pipe_15` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[9].u_mask_rnd/(gen_mask_aes_round[9].u_mask_rnd)` | `aes_round_pipe_15` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine` | `qshield_bmt_engine` | 30463 | 30462 | 0 | 21654 | 7.5 | 0 | 0.702 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/(u_bmt_engine)` | `qshield_bmt_engine` | 13228 | 13228 | 0 | 11849 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[10].u_rnd` | `aes_round_pipe_744` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[10].u_rnd/(gen_aes_round[10].u_rnd)` | `aes_round_pipe_744` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[11].u_rnd` | `aes_round_pipe_745` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[11].u_rnd/(gen_aes_round[11].u_rnd)` | `aes_round_pipe_745` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[12].u_rnd` | `aes_round_pipe_746` | 79 | 79 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[12].u_rnd/(gen_aes_round[12].u_rnd)` | `aes_round_pipe_746` | 79 | 79 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[13].u_rnd` | `aes_round_pipe_747` | 0 | 0 | 0 | 65 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[13].u_rnd/(gen_aes_round[13].u_rnd)` | `aes_round_pipe_747` | 0 | 0 | 0 | 65 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[14].u_rnd` | `aes_round_pipe_748` | 68 | 68 | 0 | 65 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[14].u_rnd/(gen_aes_round[14].u_rnd)` | `aes_round_pipe_748` | 68 | 68 | 0 | 65 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[1].u_rnd` | `aes_round_pipe_749` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[1].u_rnd/(gen_aes_round[1].u_rnd)` | `aes_round_pipe_749` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[2].u_rnd` | `aes_round_pipe_750` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[2].u_rnd/(gen_aes_round[2].u_rnd)` | `aes_round_pipe_750` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[3].u_rnd` | `aes_round_pipe_751` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[3].u_rnd/(gen_aes_round[3].u_rnd)` | `aes_round_pipe_751` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[4].u_rnd` | `aes_round_pipe_752` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[4].u_rnd/(gen_aes_round[4].u_rnd)` | `aes_round_pipe_752` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[5].u_rnd` | `aes_round_pipe_753` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[5].u_rnd/(gen_aes_round[5].u_rnd)` | `aes_round_pipe_753` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[6].u_rnd` | `aes_round_pipe_754` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[6].u_rnd/(gen_aes_round[6].u_rnd)` | `aes_round_pipe_754` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[7].u_rnd` | `aes_round_pipe_755` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[7].u_rnd/(gen_aes_round[7].u_rnd)` | `aes_round_pipe_755` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[8].u_rnd` | `aes_round_pipe_756` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[8].u_rnd/(gen_aes_round[8].u_rnd)` | `aes_round_pipe_756` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[9].u_rnd` | `aes_round_pipe_757` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[9].u_rnd/(gen_aes_round[9].u_rnd)` | `aes_round_pipe_757` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_key_expand` | `aes256_key_expand_758` | 684 | 684 | 0 | 2312 | 0.0 | 0 | 0.054 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_key_expand/(u_key_expand)` | `aes256_key_expand_758` | 684 | 684 | 0 | 2312 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit` | `qshield_mac_unit_759` | 8127 | 8126 | 0 | 2252 | 0.0 | 0 | 0.264 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit/(u_mac_unit)` | `qshield_mac_unit_759` | 608 | 608 | 0 | 1159 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit/u_gf128_mul` | `gf128_mul_pipe_760` | 7519 | 7518 | 0 | 1093 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_meta_cache` | `qshield_meta_cache` | 6716 | 6716 | 0 | 3563 | 7.5 | 0 | 0.153 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_data_mac` | `qshield_mac_unit` | 7874 | 7873 | 0 | 2314 | 0.0 | 0 | 0.273 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_data_mac/u_gf128_mul` | `gf128_mul_pipe` | 7562 | 7561 | 0 | 1090 | 0.0 | 0 | 0.247 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe` | `aes_inv_cipher_pipe` | 15011 | 15011 | 0 | 5304 | 0.0 | 0 | 0.710 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/(u_dec_pipe)` | `aes_inv_cipher_pipe` | 7168 | 7168 | 0 | 1904 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[10].u_inv_round` | `aes_inv_round_pipe` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.049 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[10].u_inv_round/(gen_inv_rounds[10].u_inv_round)` | `aes_inv_round_pipe` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[11].u_inv_round` | `aes_inv_round_pipe_506` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.041 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[11].u_inv_round/(gen_inv_rounds[11].u_inv_round)` | `aes_inv_round_pipe_506` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[12].u_inv_round` | `aes_inv_round_pipe_507` | 449 | 449 | 0 | 129 | 0.0 | 0 | 0.044 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[12].u_inv_round/(gen_inv_rounds[12].u_inv_round)` | `aes_inv_round_pipe_507` | 449 | 449 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[13].u_inv_round` | `aes_inv_round_pipe_508` | 2 | 2 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[13].u_inv_round/(gen_inv_rounds[13].u_inv_round)` | `aes_inv_round_pipe_508` | 2 | 2 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[14].u_inv_round` | `aes_inv_round_pipe_509` | 129 | 129 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[14].u_inv_round/(gen_inv_rounds[14].u_inv_round)` | `aes_inv_round_pipe_509` | 129 | 129 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[1].u_inv_round` | `aes_inv_round_pipe_510` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[1].u_inv_round/(gen_inv_rounds[1].u_inv_round)` | `aes_inv_round_pipe_510` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[2].u_inv_round` | `aes_inv_round_pipe_511` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[2].u_inv_round/(gen_inv_rounds[2].u_inv_round)` | `aes_inv_round_pipe_511` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[3].u_inv_round` | `aes_inv_round_pipe_512` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.050 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[3].u_inv_round/(gen_inv_rounds[3].u_inv_round)` | `aes_inv_round_pipe_512` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[4].u_inv_round` | `aes_inv_round_pipe_513` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.057 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[4].u_inv_round/(gen_inv_rounds[4].u_inv_round)` | `aes_inv_round_pipe_513` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[5].u_inv_round` | `aes_inv_round_pipe_514` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.061 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[5].u_inv_round/(gen_inv_rounds[5].u_inv_round)` | `aes_inv_round_pipe_514` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[6].u_inv_round` | `aes_inv_round_pipe_515` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.064 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[6].u_inv_round/(gen_inv_rounds[6].u_inv_round)` | `aes_inv_round_pipe_515` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[7].u_inv_round` | `aes_inv_round_pipe_516` | 0 | 0 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[7].u_inv_round/(gen_inv_rounds[7].u_inv_round)` | `aes_inv_round_pipe_516` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[8].u_inv_round` | `aes_inv_round_pipe_517` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.049 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[8].u_inv_round/(gen_inv_rounds[8].u_inv_round)` | `aes_inv_round_pipe_517` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[9].u_inv_round` | `aes_inv_round_pipe_518` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.050 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[9].u_inv_round/(gen_inv_rounds[9].u_inv_round)` | `aes_inv_round_pipe_518` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_mid_skid` | `aes_inv_skid_stage` | 592 | 592 | 0 | 531 | 0.0 | 0 | 0.051 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_out_skid` | `aes_inv_skid_stage_519` | 951 | 951 | 0 | 533 | 0.0 | 0 | 0.016 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_s0_skid` | `aes_inv_skid_stage_520` | 1258 | 1258 | 0 | 530 | 0.0 | 0 | 0.016 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane` | `aes_xts_lane` | 3952 | 3952 | 0 | 4907 | 0.0 | 0 | 0.310 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/(u_enc_lane)` | `aes_xts_lane` | 127 | 127 | 0 | 1806 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[10].u_round` | `aes_round_pipe_267` | 143 | 143 | 0 | 129 | 0.0 | 0 | 0.021 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[10].u_round/(gen_rounds[10].u_round)` | `aes_round_pipe_267` | 143 | 143 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[11].u_round` | `aes_round_pipe_268` | 146 | 146 | 0 | 129 | 0.0 | 0 | 0.022 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[11].u_round/(gen_rounds[11].u_round)` | `aes_round_pipe_268` | 146 | 146 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[12].u_round` | `aes_round_pipe_269` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[12].u_round/(gen_rounds[12].u_round)` | `aes_round_pipe_269` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[13].u_round` | `aes_round_pipe_270` | 6 | 6 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[13].u_round/(gen_rounds[13].u_round)` | `aes_round_pipe_270` | 6 | 6 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[14].u_round` | `aes_round_pipe_271` | 129 | 129 | 0 | 129 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[14].u_round/(gen_rounds[14].u_round)` | `aes_round_pipe_271` | 129 | 129 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[1].u_round` | `aes_round_pipe_272` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[1].u_round/(gen_rounds[1].u_round)` | `aes_round_pipe_272` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[2].u_round` | `aes_round_pipe_273` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[2].u_round/(gen_rounds[2].u_round)` | `aes_round_pipe_273` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[3].u_round` | `aes_round_pipe_274` | 143 | 143 | 0 | 129 | 0.0 | 0 | 0.020 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[3].u_round/(gen_rounds[3].u_round)` | `aes_round_pipe_274` | 143 | 143 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[4].u_round` | `aes_round_pipe_275` | 146 | 146 | 0 | 129 | 0.0 | 0 | 0.024 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[4].u_round/(gen_rounds[4].u_round)` | `aes_round_pipe_275` | 146 | 146 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[5].u_round` | `aes_round_pipe_276` | 145 | 145 | 0 | 129 | 0.0 | 0 | 0.029 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[5].u_round/(gen_rounds[5].u_round)` | `aes_round_pipe_276` | 145 | 145 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[6].u_round` | `aes_round_pipe_277` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.024 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[6].u_round/(gen_rounds[6].u_round)` | `aes_round_pipe_277` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[7].u_round` | `aes_round_pipe_278` | 1 | 1 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[7].u_round/(gen_rounds[7].u_round)` | `aes_round_pipe_278` | 1 | 1 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[8].u_round` | `aes_round_pipe_279` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.024 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[8].u_round/(gen_rounds[8].u_round)` | `aes_round_pipe_279` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[9].u_round` | `aes_round_pipe_280` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.023 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[9].u_round/(gen_rounds[9].u_round)` | `aes_round_pipe_280` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_mid_skid` | `aes_xts_skid_stage` | 280 | 280 | 0 | 519 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_out_skid` | `aes_xts_skid_stage__parameterized0` | 476 | 476 | 0 | 260 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_s0_skid` | `aes_xts_skid_stage_281` | 1347 | 1347 | 0 | 516 | 0.0 | 0 | 0.013 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_integ_csr` | `qshield_integrity_csr` | 1361 | 1361 | 0 | 337 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k1_expand` | `aes256_key_expand` | 806 | 806 | 0 | 2441 | 0.0 | 0 | 0.062 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k1_expand/(u_k1_expand)` | `aes256_key_expand` | 806 | 806 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k2_expand` | `aes256_key_expand_16` | 731 | 731 | 0 | 2441 | 0.0 | 0 | 0.058 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k2_expand/(u_k2_expand)` | `aes256_key_expand_16` | 731 | 731 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k3_expand` | `aes256_key_expand_17` | 1201 | 1201 | 0 | 2441 | 0.0 | 0 | 0.058 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k3_expand/(u_k3_expand)` | `aes256_key_expand_17` | 1201 | 1201 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit` | `qshield_xts_tweak_unit` | 2119 | 2119 | 0 | 1918 | 0.0 | 0 | 0.118 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[10].u_round` | `aes_round_pipe_18` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[10].u_round/(gen_tweak_rounds[10].u_round)` | `aes_round_pipe_18` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[11].u_round` | `aes_round_pipe_19` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[11].u_round/(gen_tweak_rounds[11].u_round)` | `aes_round_pipe_19` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[12].u_round` | `aes_round_pipe_20` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[12].u_round/(gen_tweak_rounds[12].u_round)` | `aes_round_pipe_20` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[13].u_round` | `aes_round_pipe_21` | 0 | 0 | 0 | 129 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[13].u_round/(gen_tweak_rounds[13].u_round)` | `aes_round_pipe_21` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[14].u_round` | `aes_round_pipe_22` | 288 | 288 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[14].u_round/(gen_tweak_rounds[14].u_round)` | `aes_round_pipe_22` | 288 | 288 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[1].u_round` | `aes_round_pipe_23` | 244 | 244 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[1].u_round/(gen_tweak_rounds[1].u_round)` | `aes_round_pipe_23` | 244 | 244 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[2].u_round` | `aes_round_pipe_24` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[2].u_round/(gen_tweak_rounds[2].u_round)` | `aes_round_pipe_24` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[3].u_round` | `aes_round_pipe_25` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[3].u_round/(gen_tweak_rounds[3].u_round)` | `aes_round_pipe_25` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[4].u_round` | `aes_round_pipe_26` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[4].u_round/(gen_tweak_rounds[4].u_round)` | `aes_round_pipe_26` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[5].u_round` | `aes_round_pipe_27` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[5].u_round/(gen_tweak_rounds[5].u_round)` | `aes_round_pipe_27` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[6].u_round` | `aes_round_pipe_28` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[6].u_round/(gen_tweak_rounds[6].u_round)` | `aes_round_pipe_28` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[7].u_round` | `aes_round_pipe_29` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[7].u_round/(gen_tweak_rounds[7].u_round)` | `aes_round_pipe_29` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[8].u_round` | `aes_round_pipe_30` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[8].u_round/(gen_tweak_rounds[8].u_round)` | `aes_round_pipe_30` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[9].u_round` | `aes_round_pipe_31` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[9].u_round/(gen_tweak_rounds[9].u_round)` | `aes_round_pipe_31` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core` | `axi_ddr5_mc_top` | 62943 | 62792 | 108 | 44326 | 0.0 | 0 | 1.042 |
| `axi_ddr5_mc_secure_top/u_mc_core/(u_mc_core)` | `axi_ddr5_mc_top` | 235 | 183 | 52 | 764 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core/u_addr_mapper` | `addr_mapper_ddr5` | 470 | 439 | 0 | 153 | 0.0 | 0 | 0.028 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ar_split` | `axi_burst_splitter` | 169 | 169 | 0 | 112 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_arbiter` | `slack_aware_arbiter` | 216 | 216 | 0 | 11 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ate` | `adaptive_threshold_engine` | 288 | 288 | 0 | 246 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_aw_split` | `axi_burst_splitter_0` | 208 | 208 | 0 | 112 | 0.0 | 0 | 0.007 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_bank_credit` | `bank_credit_ctrl` | 949 | 949 | 0 | 204 | 0.0 | 0 | 0.021 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_cmd_engine` | `ddr5_cmd_engine` | 9642 | 9630 | 12 | 4403 | 0.0 | 0 | 0.084 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_decoy_prf` | `scarf_dram_randomizer` | 173 | 173 | 0 | 95 | 0.0 | 0 | 0.020 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_drm` | `directed_refresh_manager` | 3050 | 3050 | 0 | 2352 | 0.0 | 0 | 0.053 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ecc_scrubber` | `ecc_scrubber` | 75 | 75 | 0 | 87 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_frontend` | `axi_slave_frontend` | 186 | 186 | 0 | 527 | 0.0 | 0 | 0.034 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_pmu` | `perf_monitor_unit` | 328 | 328 | 0 | 263 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_qos_queue` | `qos_scheduler_queue` | 15265 | 15265 | 0 | 5372 | 0.0 | 0 | 0.052 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rd_iq` | `rd_issue_queue` | 1306 | 1306 | 0 | 503 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rd_ks` | `scrambler_ks_pipe__parameterized0` | 400 | 399 | 0 | 391 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rob` | `reorder_buffer_rob` | 4470 | 4470 | 0 | 9211 | 0.0 | 0 | 0.053 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_sdc_filter` | `sdc_resilient_filter` | 11987 | 11987 | 0 | 9244 | 0.0 | 0 | 0.309 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wdata_buffer` | `wdata_buffer` | 271 | 227 | 44 | 364 | 0.0 | 0 | 0.045 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wds` | `wr_data_store` | 12977 | 12977 | 0 | 9444 | 0.0 | 0 | 0.212 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wr_ks` | `scrambler_ks_pipe` | 446 | 435 | 0 | 446 | 0.0 | 0 | 0.019 |
