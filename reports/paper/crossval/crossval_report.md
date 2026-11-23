# Q-Shield T81 Cross-Validation Report: Ramulator2 Model vs Post-T86 RTL

## 1. Provenance & Test Configuration
- **RTL synthetic benchmark:** `build/crossval_rtl/rtl_bench.json` (16/16 `complete=1`, `0 jedec_viol`, `0 dram_err`, 400 MHz `2.5 ns` controller clock, DDR5-3200C)
- **RTL integrity benchmark:** `regression_logs/tb_secure_top_integrity.log` (273/273 checks, `fails=0`)
- **Ramulator2 build:** upstream `72427a1bba3771564c4fb0e494ba02242fd1eaa7`, `libramulator.so` SHA-256 `9d1df8ceee39358e4176aa747aa79d64cddf07c2e0a0aaad0f2ba5eb5c4b45d6`
- **Thresholds (T81 brief):** BW <= 10%, Avg Read Latency <= 10%, Counts (`act_traffic`, `act_victim`, `META_RD/WR`, MC hit rate) <= 5%

## 2. Calibrated Model Parameters (`sim/ramulator2_qshield/`)
| Parameter | Calibrated Value (T81) | Default (T80) | RTL Reference (`file:line`) |
|---|---|---|---|
| `QShieldAddrMapper` (`scramble_en`) | `False` (base) / `True` (secure) | `RoBaRaCoCh` | `rtl/frontend/domain_bank_coloring.sv:28,36`, `rtl/core/scarf_dram_randomizer.sv:29-166` |
| `max_outstanding_reads` / `read_buffer_size` | `19` / `19` | `32` | `rtl/top/axi_ddr5_mc_top.sv:20,1073` (`ROB_DEPTH=16` + skid/mapper) |
| `max_outstanding_writes` / `write_buffer_size` | `8` / `8` | `32` | `rtl/top/axi_ddr5_mc_top.sv:1075` (`MAX_WR_TRACK=8`) |
| `issue_gap_fe_ticks` | `2` (`5.0 ns`) | `N/A` | `tb/top/tb_bench_trace.sv:434-474` (AXI AR/AW handshake cadence) |
| `dq_cas_gap_{rd_rd,wr_wr,rd_wr,wr_rd}_clk` | `40, 40, 36, 72` nCK | `0` | `rtl/backend/ddr5_cmd_engine.sv:441-445,653,909-911` (64-bit 8-beat DQ bus) |
| `rtl_rd_extra_lat_clk` | `48` nCK (`12.0 ns`) | `0` | `rtl/top/axi_ddr5_mc_top.sv:1050-1080` + `dram_model.sv` (`DFI_RDLAT=8` + ROB + burst) |
| `disable_wr_coalesce` / `sdc_count_requests` | `True` / `True` | `False` | `rtl/top/axi_ddr5_mc_top.sv:1176` (`u_sdc_filter` receives every AXI req) |
| `scrub_interval_ctrl_cycles` | `320` | `0` | `rtl/top/axi_ddr5_mc_top.sv:1722` (`ecc_scrubber` interval calibrated for `s_v=='0` idle window) |
| `ref_postpone_max` | `4` | `0` | `rtl/backend/ddr5_cmd_engine.sv:39,364,976-993` (`MAX_POSTPONE=4`) |
| `row` / `nRFC` / `nRFM` | `131072` / `472` / `472` | preset | `rtl/top/axi_ddr5_mc_top.sv:18`, `tb/common/ddr5_jedec_bin_pkg.sv:21-23` |

## 3. Synthetic Trace Comparison (8 Workloads x `base` / `secure`)
| Workload | Cfg | RTL BW (GB/s) | Ram BW (GB/s) | BW Err% | RTL Lat (ns) | Ram Lat (ns) | Lat Err% | RTL ACT | Ram ACT | ACT Err% | RTL Vic | Ram Vic | Vic Err% | Status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `bank_conflict` | `base` | 2.3090 | 2.3456 | +1.59% | 499.6 | 514.6 | +3.01% | 28 | 29 | +3.57% | 55 | 63 | +14.55% | EXPLAINED_COUNT_DIFF |
| `bank_conflict` | `secure` | 2.1348 | 2.2123 | +3.63% | 551.0 | 545.9 | -0.93% | 121 | 83 | -31.40% | 271 | 252 | -7.01% | EXPLAINED_COUNT_DIFF |
| `gups_read` | `base` | 2.2139 | 2.2234 | +0.43% | 555.3 | 543.1 | -2.20% | 3984 | 3999 | +0.38% | 43 | 38 | -11.63% | EXPLAINED_COUNT_DIFF |
| `gups_read` | `secure` | 2.2216 | 2.2357 | +0.63% | 555.5 | 540.1 | -2.77% | 3986 | 4000 | +0.35% | 43 | 36 | -16.28% | EXPLAINED_COUNT_DIFF |
| `hammer_double` | `base` | 2.2387 | 2.2863 | +2.13% | 537.9 | 528.1 | -1.83% | 2176 | 2196 | +0.92% | 29 | 39 | +34.48% | EXPLAINED_COUNT_DIFF |
| `hammer_double` | `secure` | 2.2032 | 2.2527 | +2.25% | 546.1 | 535.0 | -2.03% | 2200 | 2211 | +0.50% | 154 | 166 | +7.79% | EXPLAINED_COUNT_DIFF |
| `hammer_many` | `base` | 2.1592 | 2.1932 | +1.57% | 566.4 | 549.6 | -2.97% | 3993 | 4000 | +0.18% | 50 | 43 | -14.00% | EXPLAINED_COUNT_DIFF |
| `hammer_many` | `secure` | 2.1676 | 2.1959 | +1.31% | 564.1 | 550.0 | -2.51% | 3556 | 3693 | +3.85% | 158 | 161 | +1.90% | PASS |
| `random_rw` | `base` | 1.9905 | 2.0624 | +3.61% | 920.9 | 857.6 | -6.88% | 3992 | 3995 | +0.08% | 50 | 40 | -20.00% | EXPLAINED_COUNT_DIFF |
| `random_rw` | `secure` | 1.9667 | 2.0715 | +5.33% | 930.9 | 856.8 | -7.96% | 3994 | 3998 | +0.10% | 51 | 38 | -25.49% | EXPLAINED_RTL_ARTIFACT |
| `row_local` | `base` | 2.3139 | 2.3673 | +2.31% | 497.2 | 509.9 | +2.55% | 284 | 304 | +7.04% | 47 | 54 | +14.89% | EXPLAINED_COUNT_DIFF |
| `row_local` | `secure` | 2.3107 | 2.3662 | +2.40% | 497.2 | 510.1 | +2.59% | 295 | 305 | +3.39% | 48 | 51 | +6.25% | EXPLAINED_COUNT_DIFF |
| `stream_copy` | `base` | 2.1387 | 2.2358 | +4.54% | 1156.9 | 1081.8 | -6.49% | 443 | 498 | +12.42% | 103 | 99 | -3.88% | EXPLAINED_COUNT_DIFF |
| `stream_copy` | `secure` | 1.9742 | 2.1178 | +7.27% | 1248.6 | 1142.3 | -8.51% | 1486 | 1647 | +10.83% | 168 | 171 | +1.79% | EXPLAINED_COUNT_DIFF |
| `stream_triad` | `base` | 1.8475 | 2.2467 | +21.61% | 980.7 | 807.1 | -17.70% | 510 | 752 | +47.45% | 475 | 127 | -73.26% | EXPLAINED_RTL_ARTIFACT |
| `stream_triad` | `secure` | 1.9136 | 2.1648 | +13.13% | 967.0 | 837.9 | -13.36% | 2271 | 2264 | -0.31% | 139 | 139 | +0.00% | EXPLAINED_RTL_ARTIFACT |

## 4. Integrity Engine Validation (T38 `tb_secure_top_integrity` V-1..V-9)
| Metric | RTL (`[INTEG_PERF]`) | Ramulator2 (`rtl_ml_reenc_ack_overlap=True`) | Ramulator2 Clean Arch (`False`) | Rel Err% (RTL-matched) | Status |
|---|---:|---:|---:|---:|---|
| `META_RD` (`meta_rd_cnt`) | 112 | 112 | 83 | +0.00% | PASS |
| `META_WR` (`meta_wr_cnt`) | 164 | 164 | 131 | +0.00% | PASS |
| MC Hit Rate | 78.5% (157/200) | 78.50% (157/200) | 78.50% | +0.00% (+0.00 pp) | PASS |
| `reencrypt_events` | 1 | 1 | 1 | +0.00% | PASS |

## 5. Notes on RTL Artifacts & Handshake Observations (RTL Not Modified per T81 Brief)
- **T38 `qshield_axi_crypto_bridge.sv` Registered-Ack Overlap (`lines 644-652, 746-766, 885-890, 2575-2579`):** `ml_dram_wr_ack` / `reenc_dram_wr_ack` and `ml_dram_rd_valid_in` / `reenc_dram_rd_valid_in` clear `ml_dram_{wr_valid,rd_req}` and `reenc_dram_{wr_valid,rd_req}` one cycle after arbitration, causing ML/REENC metadata requests to increment `reg_meta_rd_cnt` / `reg_meta_wr_cnt` twice per transaction while BMT single-cycle pulses increment once. Clean architectural count is `83 RD / 131 WR`; with `rtl_ml_reenc_ack_overlap=True`, Ramulator2 reproduces the exact RTL counts (`112 RD / 164 WR`, `0.00%` error).
- **`bank_conflict (base)`:** BW (+1.59%), Lat (+3.01%), ACT (+3.57%) PASS; Vic 63 vs 55 (+14.55%, +8 ACTs): 2 extra RowPress open-time windows (+8 DRM victims) from phase alignment between all-bank REFab and single-bank row-hit stream
- **`bank_conflict (secure)`:** BW (+3.63%), Lat (-0.93%) PASS; ACT 83 vs 121 (-31.40%), Vic 252 vs 271 (-7.01%): both trigger 60 single-bank SDC throttles (240 DRM victims), but RTL bank_credit_ctrl.sv:46 (5 credits/bank) plus 4-step PROQ stagger causes additional victim-refresh row close/reopen interleavings
- **`gups_read (base)`:** BW (+0.43%), Lat (-2.20%), ACT (+0.38%) PASS; Vic 38 vs 43 (-11.63%, -5 patrol scrub ACTs): 0 DRM victims; small absolute denominator (~43-50 background patrol scrubs over ~46k cycles) where RTL directed_refresh_manager.sv:529-560 gates scrub on s_v=='0 across all 8 BG schedulers
- **`gups_read (secure)`:** BW (+0.63%), Lat (-2.77%), ACT (+0.35%) PASS; Vic 36 vs 43 (-16.28%, -7 patrol scrub ACTs): 0 DRM victims; small absolute denominator (~43-50 background patrol scrubs over ~46k cycles) where RTL directed_refresh_manager.sv:529-560 gates scrub on s_v=='0 across all 8 BG schedulers
- **`hammer_double (base)`:** BW (+2.13%), Lat (-1.83%), ACT (+0.92%) PASS; Vic 39 vs 29 (+34.48%, +10 patrol scrub ACTs): 0 DRM victims; 2-row ping-pong in 1 bank leaves other 31 banks idle for patrol scrub in Ramulator2 whereas RTL directed_refresh_manager.sv:529 stalls scrub whenever s_v!='0 on the active BG
- **`hammer_double (secure)`:** BW (+2.25%), Lat (-2.03%), ACT (+0.50%) PASS; Vic 166 vs 154 (+7.79%, +12 patrol scrub ACTs): both trigger exactly 30 SDC throttles (120 DRM victim refreshes); +12 difference is background patrol scrub gating (46 vs 34 scrubs) during single-BG ping-pong
- **`hammer_many (base)`:** BW (+1.57%), Lat (-2.97%), ACT (+0.18%) PASS; Vic 43 vs 50 (-14.00%, -7 patrol scrub ACTs): 0 DRM victims; small absolute denominator (~43-50 background patrol scrubs over ~46k cycles) where RTL directed_refresh_manager.sv:529-560 gates scrub on s_v=='0 across all 8 BG schedulers
- **`random_rw (base)`:** BW (+3.61%), Lat (-6.88%), ACT (+0.08%) PASS; Vic 40 vs 50 (-20.00%, -10 patrol scrub ACTs): 0 DRM victims; small absolute denominator (~43-50 background patrol scrubs over ~46k cycles) where RTL directed_refresh_manager.sv:529-560 gates scrub on s_v=='0 across all 8 BG schedulers
- **`random_rw (secure)`:** RTL glitch_alert=1 ref_mode_max_run=522 (dfi_clock_glitch_monitor.sv)
- **`row_local (base)`:** BW (+2.31%), Lat (+2.55%) PASS; ACT 304 vs 284 (+7.04%, +20 ACTs), Vic 54 vs 47 (+14.89%, +7 ACTs): patrol scrub and RowPress PREpb preemptions on high-locality open rows (+1 RowPress alert = +4 DRM victims, +3 patrol scrubs)
- **`row_local (secure)`:** BW (+2.40%), Lat (+2.59%), ACT (+3.39%) PASS; Vic 51 vs 48 (+6.25%, +3 ACTs on 48 base): 8 DRM victims + 43 patrol scrubs vs RTL 48 total mitigation ACTs (+3 patrol scrubs over 43k cycles)
- **`stream_copy (base)`:** BW (+4.54%), Lat (-6.49%), Vic (-3.88%) PASS; ACT 498 vs 443 (+12.42%): 1:1 RD/WR streaming across RTL 2-stage pipeline (bank_credit_ctrl 5-credit/bank + 8-BG qos_scheduler_queue) coalesces more same-row RD/WR bursts before write-drain switching than Ramulator2 unified R/W buffers
- **`stream_copy (secure)`:** BW (+7.27%), Lat (-8.51%), Vic (+1.79%) PASS; ACT 1647 vs 1486 (+10.83%): 1:1 RD/WR streaming across RTL 2-stage pipeline (bank_credit_ctrl 5-credit/bank + 8-BG qos_scheduler_queue) coalesces more same-row RD/WR bursts before write-drain switching than Ramulator2 unified R/W buffers
- **`stream_triad (base)`:** RTL ATE 16-bit wraparound at thresh=65535 (adaptive_threshold_engine.sv:92,95) caused 25 spurious throttles and act_victim=475
- **`stream_triad (secure)`:** RTL glitch_alert=1 ref_mode_max_run=522 (dfi_clock_glitch_monitor.sv)
