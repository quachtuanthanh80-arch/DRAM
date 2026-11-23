# Q-Shield FPGA Post-Route PPA Evaluation Summary
- Ngày đo: 2026-11-22T06:55:24.857928
- Chip mục tiêu: `xczu7ev-ffvc1156-2-e` (Xilinx Zynq UltraScale+)
- Vivado: `Vivado v2026.1 (64-bit)` | Threads: `default` | Reuse session presynth DCP: `True`
- Git commit: `b0a9e175c85dc47a497e83743df5a7c590e07429` (dirty (chưa commit))
- Phương pháp đo công suất: vectorless report_power (Vivado default toggle rate 12.5%, no Simulation Activity File)

## 1. Bảng tổng hợp hiệu năng định thời và tài nguyên sau Place & Route

| Module | Initial @ 400 MHz (2.500 ns) WNS / TNS / WHS | Confirmed Period (ns) | Confirmed Fmax (MHz) | Confirmed WNS / TNS / WHS | LUTs (%) | FFs (%) | BRAM Tiles | DSPs | Total Power (W) [Dyn / Static] |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_top` | `-1.673` / `-40375.344` / `0.019` | `4.200` | **`238.10`** | `0.076` / `0.000` / `0.024` | `62623` (`27.18%`) | `44581` (`9.67%`) | `0.0` | `0` | `1.572` (`0.975` / `0.597`) |
| `axi_ddr5_mc_secure_top` | `-1.648` / `-81083.195` / `0.019` | `4.150` | **`240.96`** | `0.018` / `0.000` / `0.023` | `165776` (`71.95%`) | `110405` (`23.96%`) | `7.5` | `0` | `4.301` (`3.689` / `0.612`) |

## 2. Toàn bộ các điểm đo đã chạy (trung thực mọi lần thử)

| Top | Tag | Period (ns) | Fmax (MHz) | WNS (ns) | TNS (ns) | WHS (ns) | Failing EP | LUTs | FFs | Total Power (W) | Elapsed (s) | Log |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `axi_ddr5_mc_top` | `core_2500ps` | `2.500` | `400.00` | `-1.673` | `-40375.344` | `0.019` | `70632` | `64147` | `44574` | `2.337` | 4963.3 | `reports\paper\fpga\t89\core_2500ps_vivado.log` |
| `axi_ddr5_mc_top` | `core_confirmed` | `4.200` | `238.10` | `0.076` | `0.000` | `0.024` | `0` | `62623` | `44581` | `1.572` | 2671.2 | `reports\paper\fpga\t89\core_confirmed_vivado.log` |
| `axi_ddr5_mc_secure_top` | `sec_2500ps` | `2.500` | `400.00` | `-1.648` | `-81083.195` | `0.019` | `132736` | `167139` | `110454` | `6.933` | 10256.9 | `reports\paper\fpga\t89\sec_2500ps_vivado.log` |
| `axi_ddr5_mc_secure_top` | `sec_confirmed` | `4.150` | `240.96` | `0.018` | `0.000` | `0.023` | `0` | `165776` | `110405` | `4.301` | 6917.2 | `reports\paper\fpga\t89\sec_confirmed_vivado.log` |

## 3. Phân rã tài nguyên và công suất theo khối (Post-Route Confirmed)

### axi_ddr5_mc_top (`core_confirmed` @ `4.200 ns` / `238.10 MHz`)
| Hierarchical Path | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM Tiles | DSP | Dynamic Power (W) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_top` | `(top)` | 62623 | 62472 | 108 | 44581 | 0.0 | 0 | 0.975 |
| `axi_ddr5_mc_top/(axi_ddr5_mc_top)` | `(top)` | 210 | 158 | 52 | 760 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_addr_mapper` | `addr_mapper_ddr5` | 447 | 416 | 0 | 153 | 0.0 | 0 | 0.025 |
| `axi_ddr5_mc_top/u_addr_mapper/u_scarf_randomizer` | `scarf_dram_randomizer_2` | 411 | 401 | 0 | 111 | 0.0 | 0 | 0.024 |
| `axi_ddr5_mc_top/u_ar_split` | `axi_burst_splitter` | 168 | 168 | 0 | 112 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_top/u_arbiter` | `slack_aware_arbiter` | 279 | 279 | 0 | 11 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_ate` | `adaptive_threshold_engine` | 278 | 278 | 0 | 246 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_top/u_aw_split` | `axi_burst_splitter_0` | 208 | 208 | 0 | 112 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_top/u_bank_credit` | `bank_credit_ctrl` | 943 | 943 | 0 | 204 | 0.0 | 0 | 0.020 |
| `axi_ddr5_mc_top/u_cmd_engine` | `ddr5_cmd_engine` | 9886 | 9874 | 12 | 4408 | 0.0 | 0 | 0.088 |
| `axi_ddr5_mc_top/u_decoy_prf` | `scarf_dram_randomizer` | 170 | 170 | 0 | 95 | 0.0 | 0 | 0.021 |
| `axi_ddr5_mc_top/u_drm` | `directed_refresh_manager` | 3867 | 3867 | 0 | 2432 | 0.0 | 0 | 0.049 |
| `axi_ddr5_mc_top/u_ecc_scrubber` | `ecc_scrubber` | 74 | 74 | 0 | 87 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_top/u_frontend` | `axi_slave_frontend` | 194 | 194 | 0 | 517 | 0.0 | 0 | 0.006 |
| `axi_ddr5_mc_top/u_frontend/u_w_skid` | `axi4_skid_buffer__parameterized0` | 63 | 63 | 0 | 148 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_top/u_frontend/u_ar_skid` | `axi4_skid_buffer` | 39 | 39 | 0 | 108 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_frontend/u_aw_skid` | `axi4_skid_buffer_1` | 33 | 33 | 0 | 108 | 0.0 | 0 | — |
| `axi_ddr5_mc_top/u_frontend/u_r_skid` | `axi4_skid_buffer__parameterized2` | 54 | 54 | 0 | 142 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_top/u_pmu` | `perf_monitor_unit` | 328 | 328 | 0 | 263 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_top/u_qos_queue` | `qos_scheduler_queue` | 13923 | 13923 | 0 | 5374 | 0.0 | 0 | 0.050 |
| `axi_ddr5_mc_top/u_rd_iq` | `rd_issue_queue` | 1302 | 1302 | 0 | 503 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_top/u_rd_ks` | `scrambler_ks_pipe__parameterized0` | 400 | 399 | 0 | 391 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_top/u_rob` | `reorder_buffer_rob` | 4487 | 4487 | 0 | 9211 | 0.0 | 0 | 0.050 |
| `axi_ddr5_mc_top/u_sdc_filter` | `sdc_resilient_filter` | 11676 | 11676 | 0 | 9420 | 0.0 | 0 | 0.324 |
| `axi_ddr5_mc_top/u_wdata_buffer` | `wdata_buffer` | 289 | 245 | 44 | 364 | 0.0 | 0 | 0.022 |
| `axi_ddr5_mc_top/u_wds` | `wr_data_store` | 13166 | 13166 | 0 | 9444 | 0.0 | 0 | 0.192 |
| `axi_ddr5_mc_top/u_wr_ks` | `scrambler_ks_pipe` | 446 | 435 | 0 | 450 | 0.0 | 0 | 0.019 |

### axi_ddr5_mc_secure_top (`sec_confirmed` @ `4.150 ns` / `240.96 MHz`)
| Hierarchical Path | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM Tiles | DSP | Dynamic Power (W) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_secure_top` | `(top)` | 165776 | 164253 | 1478 | 110405 | 7.5 | 0 | 3.689 |
| `axi_ddr5_mc_secure_top/(axi_ddr5_mc_secure_top)` | `(top)` | 1 | 1 | 0 | 0 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge` | `qshield_axi_crypto_bridge` | 101978 | 100606 | 1370 | 65827 | 7.5 | 0 | 2.590 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/(u_crypto_bridge)` | `qshield_axi_crypto_bridge` | 36213 | 34843 | 1370 | 20288 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[10].u_mask_rnd` | `aes_round_pipe` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[10].u_mask_rnd/(gen_mask_aes_round[10].u_mask_rnd)` | `aes_round_pipe` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[11].u_mask_rnd` | `aes_round_pipe_3` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[11].u_mask_rnd/(gen_mask_aes_round[11].u_mask_rnd)` | `aes_round_pipe_3` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[12].u_mask_rnd` | `aes_round_pipe_4` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[12].u_mask_rnd/(gen_mask_aes_round[12].u_mask_rnd)` | `aes_round_pipe_4` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[13].u_mask_rnd` | `aes_round_pipe_5` | 0 | 0 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[13].u_mask_rnd/(gen_mask_aes_round[13].u_mask_rnd)` | `aes_round_pipe_5` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[14].u_mask_rnd` | `aes_round_pipe_6` | 198 | 198 | 0 | 129 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[14].u_mask_rnd/(gen_mask_aes_round[14].u_mask_rnd)` | `aes_round_pipe_6` | 198 | 198 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[1].u_mask_rnd` | `aes_round_pipe_7` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.013 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[1].u_mask_rnd/(gen_mask_aes_round[1].u_mask_rnd)` | `aes_round_pipe_7` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[2].u_mask_rnd` | `aes_round_pipe_8` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[2].u_mask_rnd/(gen_mask_aes_round[2].u_mask_rnd)` | `aes_round_pipe_8` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[3].u_mask_rnd` | `aes_round_pipe_9` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[3].u_mask_rnd/(gen_mask_aes_round[3].u_mask_rnd)` | `aes_round_pipe_9` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/gen_mask_aes_round[4].u_mask_rnd` | `aes_round_pipe_10` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.009 |
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
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine` | `qshield_bmt_engine` | 30425 | 30424 | 0 | 21651 | 7.5 | 0 | 0.783 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/(u_bmt_engine)` | `qshield_bmt_engine` | 13199 | 13199 | 0 | 11847 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[10].u_rnd` | `aes_round_pipe_744` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[10].u_rnd/(gen_aes_round[10].u_rnd)` | `aes_round_pipe_744` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[11].u_rnd` | `aes_round_pipe_745` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[11].u_rnd/(gen_aes_round[11].u_rnd)` | `aes_round_pipe_745` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[12].u_rnd` | `aes_round_pipe_746` | 79 | 79 | 0 | 129 | 0.0 | 0 | 0.007 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[12].u_rnd/(gen_aes_round[12].u_rnd)` | `aes_round_pipe_746` | 79 | 79 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[13].u_rnd` | `aes_round_pipe_747` | 0 | 0 | 0 | 65 | 0.0 | 0 | 0.003 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[13].u_rnd/(gen_aes_round[13].u_rnd)` | `aes_round_pipe_747` | 0 | 0 | 0 | 65 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[14].u_rnd` | `aes_round_pipe_748` | 68 | 68 | 0 | 65 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[14].u_rnd/(gen_aes_round[14].u_rnd)` | `aes_round_pipe_748` | 68 | 68 | 0 | 65 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[1].u_rnd` | `aes_round_pipe_749` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[1].u_rnd/(gen_aes_round[1].u_rnd)` | `aes_round_pipe_749` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[2].u_rnd` | `aes_round_pipe_750` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[2].u_rnd/(gen_aes_round[2].u_rnd)` | `aes_round_pipe_750` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[3].u_rnd` | `aes_round_pipe_751` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[3].u_rnd/(gen_aes_round[3].u_rnd)` | `aes_round_pipe_751` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[4].u_rnd` | `aes_round_pipe_752` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[4].u_rnd/(gen_aes_round[4].u_rnd)` | `aes_round_pipe_752` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[5].u_rnd` | `aes_round_pipe_753` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[5].u_rnd/(gen_aes_round[5].u_rnd)` | `aes_round_pipe_753` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[6].u_rnd` | `aes_round_pipe_754` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[6].u_rnd/(gen_aes_round[6].u_rnd)` | `aes_round_pipe_754` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[7].u_rnd` | `aes_round_pipe_755` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[7].u_rnd/(gen_aes_round[7].u_rnd)` | `aes_round_pipe_755` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[8].u_rnd` | `aes_round_pipe_756` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[8].u_rnd/(gen_aes_round[8].u_rnd)` | `aes_round_pipe_756` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[9].u_rnd` | `aes_round_pipe_757` | 142 | 142 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/gen_aes_round[9].u_rnd/(gen_aes_round[9].u_rnd)` | `aes_round_pipe_757` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_key_expand` | `aes256_key_expand_758` | 672 | 672 | 0 | 2312 | 0.0 | 0 | 0.053 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_key_expand/(u_key_expand)` | `aes256_key_expand_758` | 672 | 672 | 0 | 2312 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit` | `qshield_mac_unit_759` | 8127 | 8126 | 0 | 2252 | 0.0 | 0 | 0.266 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit/(u_mac_unit)` | `qshield_mac_unit_759` | 608 | 608 | 0 | 1159 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_mac_unit/u_gf128_mul` | `gf128_mul_pipe_760` | 7519 | 7518 | 0 | 1093 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_bmt_engine/u_meta_cache` | `qshield_meta_cache` | 6719 | 6719 | 0 | 3562 | 7.5 | 0 | 0.168 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_data_mac` | `qshield_mac_unit` | 7874 | 7873 | 0 | 2314 | 0.0 | 0 | 0.260 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_data_mac/u_gf128_mul` | `gf128_mul_pipe` | 7562 | 7561 | 0 | 1090 | 0.0 | 0 | 0.236 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe` | `aes_inv_cipher_pipe` | 14923 | 14923 | 0 | 5283 | 0.0 | 0 | 0.676 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/(u_dec_pipe)` | `aes_inv_cipher_pipe` | 7168 | 7168 | 0 | 1890 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[10].u_inv_round` | `aes_inv_round_pipe` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.047 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[10].u_inv_round/(gen_inv_rounds[10].u_inv_round)` | `aes_inv_round_pipe` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[11].u_inv_round` | `aes_inv_round_pipe_506` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.045 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[11].u_inv_round/(gen_inv_rounds[11].u_inv_round)` | `aes_inv_round_pipe_506` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[12].u_inv_round` | `aes_inv_round_pipe_507` | 449 | 449 | 0 | 129 | 0.0 | 0 | 0.044 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[12].u_inv_round/(gen_inv_rounds[12].u_inv_round)` | `aes_inv_round_pipe_507` | 449 | 449 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[13].u_inv_round` | `aes_inv_round_pipe_508` | 2 | 2 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[13].u_inv_round/(gen_inv_rounds[13].u_inv_round)` | `aes_inv_round_pipe_508` | 2 | 2 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[14].u_inv_round` | `aes_inv_round_pipe_509` | 129 | 129 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[14].u_inv_round/(gen_inv_rounds[14].u_inv_round)` | `aes_inv_round_pipe_509` | 129 | 129 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[1].u_inv_round` | `aes_inv_round_pipe_510` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[1].u_inv_round/(gen_inv_rounds[1].u_inv_round)` | `aes_inv_round_pipe_510` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[2].u_inv_round` | `aes_inv_round_pipe_511` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.011 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[2].u_inv_round/(gen_inv_rounds[2].u_inv_round)` | `aes_inv_round_pipe_511` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[3].u_inv_round` | `aes_inv_round_pipe_512` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.048 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[3].u_inv_round/(gen_inv_rounds[3].u_inv_round)` | `aes_inv_round_pipe_512` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[4].u_inv_round` | `aes_inv_round_pipe_513` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.052 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[4].u_inv_round/(gen_inv_rounds[4].u_inv_round)` | `aes_inv_round_pipe_513` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[5].u_inv_round` | `aes_inv_round_pipe_514` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.057 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[5].u_inv_round/(gen_inv_rounds[5].u_inv_round)` | `aes_inv_round_pipe_514` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[6].u_inv_round` | `aes_inv_round_pipe_515` | 445 | 445 | 0 | 129 | 0.0 | 0 | 0.054 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[6].u_inv_round/(gen_inv_rounds[6].u_inv_round)` | `aes_inv_round_pipe_515` | 445 | 445 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[7].u_inv_round` | `aes_inv_round_pipe_516` | 0 | 0 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[7].u_inv_round/(gen_inv_rounds[7].u_inv_round)` | `aes_inv_round_pipe_516` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[8].u_inv_round` | `aes_inv_round_pipe_517` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.049 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[8].u_inv_round/(gen_inv_rounds[8].u_inv_round)` | `aes_inv_round_pipe_517` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[9].u_inv_round` | `aes_inv_round_pipe_518` | 447 | 447 | 0 | 129 | 0.0 | 0 | 0.046 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/gen_inv_rounds[9].u_inv_round/(gen_inv_rounds[9].u_inv_round)` | `aes_inv_round_pipe_518` | 447 | 447 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_mid_skid` | `aes_inv_skid_stage` | 592 | 592 | 0 | 529 | 0.0 | 0 | 0.049 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_out_skid` | `aes_inv_skid_stage_519` | 930 | 930 | 0 | 530 | 0.0 | 0 | 0.017 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_dec_pipe/u_s0_skid` | `aes_inv_skid_stage_520` | 1195 | 1195 | 0 | 528 | 0.0 | 0 | 0.017 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane` | `aes_xts_lane` | 4025 | 4025 | 0 | 4907 | 0.0 | 0 | 0.239 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/(u_enc_lane)` | `aes_xts_lane` | 128 | 128 | 0 | 1806 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[10].u_round` | `aes_round_pipe_267` | 143 | 143 | 0 | 129 | 0.0 | 0 | 0.017 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[10].u_round/(gen_rounds[10].u_round)` | `aes_round_pipe_267` | 143 | 143 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[11].u_round` | `aes_round_pipe_268` | 146 | 146 | 0 | 129 | 0.0 | 0 | 0.018 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[11].u_round/(gen_rounds[11].u_round)` | `aes_round_pipe_268` | 146 | 146 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[12].u_round` | `aes_round_pipe_269` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.018 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[12].u_round/(gen_rounds[12].u_round)` | `aes_round_pipe_269` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[13].u_round` | `aes_round_pipe_270` | 5 | 5 | 0 | 129 | 0.0 | 0 | 0.012 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[13].u_round/(gen_rounds[13].u_round)` | `aes_round_pipe_270` | 5 | 5 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[14].u_round` | `aes_round_pipe_271` | 129 | 129 | 0 | 129 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[14].u_round/(gen_rounds[14].u_round)` | `aes_round_pipe_271` | 129 | 129 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[1].u_round` | `aes_round_pipe_272` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[1].u_round/(gen_rounds[1].u_round)` | `aes_round_pipe_272` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[2].u_round` | `aes_round_pipe_273` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[2].u_round/(gen_rounds[2].u_round)` | `aes_round_pipe_273` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[3].u_round` | `aes_round_pipe_274` | 143 | 143 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[3].u_round/(gen_rounds[3].u_round)` | `aes_round_pipe_274` | 143 | 143 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[4].u_round` | `aes_round_pipe_275` | 146 | 146 | 0 | 129 | 0.0 | 0 | 0.009 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[4].u_round/(gen_rounds[4].u_round)` | `aes_round_pipe_275` | 146 | 146 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[5].u_round` | `aes_round_pipe_276` | 145 | 145 | 0 | 129 | 0.0 | 0 | 0.010 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[5].u_round/(gen_rounds[5].u_round)` | `aes_round_pipe_276` | 145 | 145 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[6].u_round` | `aes_round_pipe_277` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.022 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[6].u_round/(gen_rounds[6].u_round)` | `aes_round_pipe_277` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[7].u_round` | `aes_round_pipe_278` | 1 | 1 | 0 | 129 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[7].u_round/(gen_rounds[7].u_round)` | `aes_round_pipe_278` | 1 | 1 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[8].u_round` | `aes_round_pipe_279` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.018 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[8].u_round/(gen_rounds[8].u_round)` | `aes_round_pipe_279` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[9].u_round` | `aes_round_pipe_280` | 144 | 144 | 0 | 129 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/gen_rounds[9].u_round/(gen_rounds[9].u_round)` | `aes_round_pipe_280` | 144 | 144 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_mid_skid` | `aes_xts_skid_stage` | 280 | 280 | 0 | 519 | 0.0 | 0 | 0.017 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_out_skid` | `aes_xts_skid_stage__parameterized0` | 513 | 513 | 0 | 260 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_enc_lane/u_s0_skid` | `aes_xts_skid_stage_281` | 1386 | 1386 | 0 | 516 | 0.0 | 0 | 0.012 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_integ_csr` | `qshield_integrity_csr` | 1760 | 1760 | 0 | 337 | 0.0 | 0 | 0.012 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k1_expand` | `aes256_key_expand` | 805 | 805 | 0 | 2441 | 0.0 | 0 | 0.062 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k1_expand/(u_k1_expand)` | `aes256_key_expand` | 805 | 805 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k2_expand` | `aes256_key_expand_16` | 1117 | 1117 | 0 | 2441 | 0.0 | 0 | 0.059 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k2_expand/(u_k2_expand)` | `aes256_key_expand_16` | 1117 | 1117 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k3_expand` | `aes256_key_expand_17` | 827 | 827 | 0 | 2441 | 0.0 | 0 | 0.061 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_k3_expand/(u_k3_expand)` | `aes256_key_expand_17` | 827 | 827 | 0 | 2441 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit` | `qshield_xts_tweak_unit` | 2116 | 2116 | 0 | 1918 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[10].u_round` | `aes_round_pipe_18` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[10].u_round/(gen_tweak_rounds[10].u_round)` | `aes_round_pipe_18` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[11].u_round` | `aes_round_pipe_19` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[11].u_round/(gen_tweak_rounds[11].u_round)` | `aes_round_pipe_19` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[12].u_round` | `aes_round_pipe_20` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[12].u_round/(gen_tweak_rounds[12].u_round)` | `aes_round_pipe_20` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[13].u_round` | `aes_round_pipe_21` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[13].u_round/(gen_tweak_rounds[13].u_round)` | `aes_round_pipe_21` | 0 | 0 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[14].u_round` | `aes_round_pipe_22` | 285 | 285 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[14].u_round/(gen_tweak_rounds[14].u_round)` | `aes_round_pipe_22` | 285 | 285 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[1].u_round` | `aes_round_pipe_23` | 244 | 244 | 0 | 129 | 0.0 | 0 | 0.007 |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[1].u_round/(gen_tweak_rounds[1].u_round)` | `aes_round_pipe_23` | 244 | 244 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[2].u_round` | `aes_round_pipe_24` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[2].u_round/(gen_tweak_rounds[2].u_round)` | `aes_round_pipe_24` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[3].u_round` | `aes_round_pipe_25` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[3].u_round/(gen_tweak_rounds[3].u_round)` | `aes_round_pipe_25` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[4].u_round` | `aes_round_pipe_26` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[4].u_round/(gen_tweak_rounds[4].u_round)` | `aes_round_pipe_26` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[5].u_round` | `aes_round_pipe_27` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[5].u_round/(gen_tweak_rounds[5].u_round)` | `aes_round_pipe_27` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[6].u_round` | `aes_round_pipe_28` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[6].u_round/(gen_tweak_rounds[6].u_round)` | `aes_round_pipe_28` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[7].u_round` | `aes_round_pipe_29` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[7].u_round/(gen_tweak_rounds[7].u_round)` | `aes_round_pipe_29` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[8].u_round` | `aes_round_pipe_30` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[8].u_round/(gen_tweak_rounds[8].u_round)` | `aes_round_pipe_30` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[9].u_round` | `aes_round_pipe_31` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_crypto_bridge/u_tweak_unit/gen_tweak_rounds[9].u_round/(gen_tweak_rounds[9].u_round)` | `aes_round_pipe_31` | 142 | 142 | 0 | 129 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core` | `axi_ddr5_mc_top` | 63800 | 63649 | 108 | 44578 | 0.0 | 0 | 1.099 |
| `axi_ddr5_mc_secure_top/u_mc_core/(u_mc_core)` | `axi_ddr5_mc_top` | 235 | 183 | 52 | 763 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core/u_addr_mapper` | `addr_mapper_ddr5` | 468 | 437 | 0 | 153 | 0.0 | 0 | 0.026 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ar_split` | `axi_burst_splitter` | 170 | 170 | 0 | 112 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_arbiter` | `slack_aware_arbiter` | 212 | 212 | 0 | 11 | 0.0 | 0 | — |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ate` | `adaptive_threshold_engine` | 276 | 276 | 0 | 246 | 0.0 | 0 | 0.005 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_aw_split` | `axi_burst_splitter_0` | 212 | 212 | 0 | 112 | 0.0 | 0 | 0.008 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_bank_credit` | `bank_credit_ctrl` | 942 | 942 | 0 | 204 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_cmd_engine` | `ddr5_cmd_engine` | 9540 | 9528 | 12 | 4414 | 0.0 | 0 | 0.082 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_decoy_prf` | `scarf_dram_randomizer` | 171 | 171 | 0 | 95 | 0.0 | 0 | 0.019 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_drm` | `directed_refresh_manager` | 5018 | 5018 | 0 | 2433 | 0.0 | 0 | 0.038 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_ecc_scrubber` | `ecc_scrubber` | 75 | 75 | 0 | 87 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_frontend` | `axi_slave_frontend` | 186 | 186 | 0 | 536 | 0.0 | 0 | 0.041 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_pmu` | `perf_monitor_unit` | 328 | 328 | 0 | 263 | 0.0 | 0 | 0.002 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_qos_queue` | `qos_scheduler_queue` | 13299 | 13299 | 0 | 5376 | 0.0 | 0 | 0.050 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rd_iq` | `rd_issue_queue` | 1358 | 1358 | 0 | 503 | 0.0 | 0 | 0.004 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rd_ks` | `scrambler_ks_pipe__parameterized0` | 400 | 399 | 0 | 391 | 0.0 | 0 | 0.017 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_rob` | `reorder_buffer_rob` | 4482 | 4482 | 0 | 9211 | 0.0 | 0 | 0.056 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_sdc_filter` | `sdc_resilient_filter` | 11944 | 11944 | 0 | 9388 | 0.0 | 0 | 0.348 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wdata_buffer` | `wdata_buffer` | 272 | 228 | 44 | 364 | 0.0 | 0 | 0.052 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wds` | `wr_data_store` | 13965 | 13965 | 0 | 9444 | 0.0 | 0 | 0.229 |
| `axi_ddr5_mc_secure_top/u_mc_core/u_wr_ks` | `scrambler_ks_pipe` | 446 | 435 | 0 | 450 | 0.0 | 0 | 0.018 |

## 4. So sánh với mốc T83 (trước T86/T88)

| Module | T83 Fmax (MHz) [Period] | T89 Fmax (MHz) [Period] | ΔFmax (MHz) | T83 LUT | T89 LUT (Δ) | T83 FF | T89 FF (Δ) | T83 BRAM | T89 BRAM (Δ) | T83 Power (W) | T89 Power (W) (Δ) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axi_ddr5_mc_top` | `263.16` (`3.800 ns`) | `238.10` (`4.200 ns`) | `-25.06` | `63785` | `62623` (`-1162`) | `44243` | `44581` (`+338`) | `0.0` | `0.0` (`+0.0`) | `1.618` | `1.572` (`-0.046`) |
| `axi_ddr5_mc_secure_top` | `240.96` (`4.150 ns`) | `240.96` (`4.150 ns`) | `+0.00` | `164062` | `165776` (`+1714`) | `110190` | `110405` (`+215`) | `7.5` | `7.5` (`+0.0`) | `4.437` | `4.301` (`-0.136`) |

### File `rtl/**` thay đổi giữa `rem/T83` và `HEAD` (chưa tách nhân quả riêng từng file bằng ablation P&R)
- `M	rtl/backend/ddr5_cmd_engine.sv`
- `M	rtl/backend/directed_refresh_manager.sv`
- `M	rtl/backend/rs_chipkill_decoder.sv`
- `M	rtl/core/adaptive_threshold_engine.sv`
- `M	rtl/core/reorder_buffer_rob.sv`
- `M	rtl/core/sdc_resilient_filter.sv`
- `M	rtl/crypto/qshield_axi_crypto_bridge.sv`
- `M	rtl/interfaces/pcie_cxl_io_apb_shim.sv`
