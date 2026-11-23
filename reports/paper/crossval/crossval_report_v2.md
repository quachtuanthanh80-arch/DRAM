# Q-Shield T90 Out-of-Sample Cross-Validation & Calibration Impact (`reports/paper/crossval/crossval_report_v2.md`)
- **Frozen Calibration:** `reports/paper/crossval/calibration_frozen.json` (`libramulator.so` SHA-256 `678f1a1deaa9c07d3022458abe0ea309ac131f8e0fd8be0285e41c3e4a35ee43`, đóng băng trước khi sinh holdout, giữ nguyên 100% tham số sau đóng băng).
- **Original 8 Traces Hash Check:** 8/8 file trong `sim/traces/rtl_bench/` giữ nguyên SHA-256 so với mốc đóng băng.
- **Holdout Traces (`6` trace mới, seed=`902026`, `4000` ops):** `burst_idle_rw.trace, dual_interleaved.trace, hammer_3row.trace, hammer_multibank.trace, large_stride.trace, random_70_30.trace`.
- **Holdout Stop Condition (`> 1/3` lệch BW hoặc Lat `> 10%`):** `3/12` → `NOT TRIGGERED (OK)`.

## 1. Đính chính thống kê T81 (tự tính lại từ `crossval_table.csv`)
- Trên `reports/paper/crossval/crossval_table.csv` của T81 (`13` dòng sạch ngoài 3 hiện vật RTL trước T88): BW `<= 10%`: `13/13`, Lat `<= 10%`: `13/13`, `act_traffic <= 5%`: **`9/13`** (đính chính con số `10/13` nêu sai trong note T81), `act_victim <= 5%`: `3/13`.

## 2. Thống kê tự động từ CSV (`crossval_table_v2.csv`, RTL hậu-T88, 0 lỗi glitch/ATE)
| Tập dữ liệu | Dòng | BW `<=10%` (Mean ± SD) | Lat `<=10%` (Mean ± SD) | `act_traffic <=5%` (Mean ± SD) | `act_victim <=5%` (Mean ± SD) | Đạt cả 4 |
|---|---:|---|---|---|---|---:|
| `in_sample` | 16 | 14/16 (`+4.43% ± 5.13%`, max `20.37%`) | 14/16 (`-3.96% ± 5.20%`, max `15.68%`) | 11/16 (`+7.49% ± 28.07%`) | 4/16 (`-5.27% ± 22.96%`) | 1/16 |
| `holdout` | 12 | 11/12 (`+5.42% ± 3.52%`, max `11.86%`) | 9/12 (`-4.09% ± 7.35%`, max `12.79%`) | 9/12 (`+4.93% ± 7.18%`) | 7/12 (`+5.62% ± 14.56%`) | 4/12 |
| `all_14_traces` | 28 | 25/28 (`+4.85% ± 4.46%`, max `20.37%`) | 23/28 (`-4.02% ± 6.08%`, max `15.68%`) | 20/28 (`+6.39% ± 21.45%`) | 11/28 (`-0.60% ± 20.23%`) | 5/28 |

## 3. Bảng chi tiết 14 Trace × `{base, secure}` (28 dòng, RTL hậu-T88)
| Split | Workload | Cfg | RTL BW | Cal BW | BW Err% | RTL Lat | Cal Lat | Lat Err% | RTL ACT | Cal ACT | ACT Err% | RTL Vic | Cal Vic | Vic Err% | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `in_sample` | `bank_conflict` | `base` | 2.3090 | 2.3456 | +1.59% | 499.6 | 514.6 | +3.01% | 28 | 29 | +3.57% | 55 | 63 | +14.55% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `bank_conflict` | `secure` | 2.1348 | 2.2123 | +3.63% | 551.0 | 545.9 | -0.93% | 121 | 83 | -31.40% | 271 | 252 | -7.01% | `EXPLAINED_ABLATED` |
| `in_sample` | `gups_read` | `base` | 2.2139 | 2.2234 | +0.43% | 555.3 | 543.1 | -2.20% | 3984 | 3999 | +0.38% | 43 | 38 | -11.63% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `gups_read` | `secure` | 2.2216 | 2.2357 | +0.63% | 555.5 | 540.1 | -2.77% | 3986 | 4000 | +0.35% | 43 | 36 | -16.28% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `hammer_double` | `base` | 2.2387 | 2.2863 | +2.13% | 537.9 | 528.1 | -1.83% | 2176 | 2196 | +0.92% | 29 | 39 | +34.48% | `EXPLAINED_ABLATED` |
| `in_sample` | `hammer_double` | `secure` | 2.2032 | 2.2527 | +2.25% | 546.1 | 535.0 | -2.03% | 2200 | 2211 | +0.50% | 154 | 166 | +7.79% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `hammer_many` | `base` | 2.1592 | 2.1932 | +1.57% | 566.4 | 549.6 | -2.97% | 3993 | 4000 | +0.18% | 50 | 43 | -14.00% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `hammer_many` | `secure` | 2.1676 | 2.1959 | +1.31% | 564.1 | 550.0 | -2.51% | 3556 | 3693 | +3.85% | 158 | 161 | +1.90% | `PASS` |
| `in_sample` | `random_rw` | `base` | 1.9905 | 2.0624 | +3.61% | 920.9 | 857.6 | -6.88% | 3992 | 3995 | +0.08% | 50 | 40 | -20.00% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `random_rw` | `secure` | 1.9801 | 2.0715 | +4.62% | 917.6 | 856.8 | -6.63% | 3993 | 3998 | +0.13% | 50 | 38 | -24.00% | `EXPLAINED_ABLATED` |
| `in_sample` | `row_local` | `base` | 2.3139 | 2.3673 | +2.31% | 497.2 | 509.9 | +2.55% | 284 | 304 | +7.04% | 47 | 54 | +14.89% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `row_local` | `secure` | 2.3107 | 2.3662 | +2.40% | 497.2 | 510.1 | +2.59% | 295 | 305 | +3.39% | 48 | 51 | +6.25% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `stream_copy` | `base` | 2.1399 | 2.2358 | +4.48% | 1156.7 | 1081.8 | -6.47% | 443 | 498 | +12.42% | 103 | 99 | -3.88% | `HYPOTHESIS_UNVERIFIED` |
| `in_sample` | `stream_copy` | `secure` | 1.9613 | 2.1178 | +7.98% | 1248.1 | 1142.3 | -8.47% | 1483 | 1647 | +11.06% | 168 | 171 | +1.79% | `EXPLAINED_ABLATED` |
| `in_sample` | `stream_triad` | `base` | 1.8665 | 2.2467 | +20.37% | 957.2 | 807.1 | -15.68% | 364 | 752 | +106.59% | 432 | 127 | -70.60% | `EXPLAINED_ABLATED` |
| `in_sample` | `stream_triad` | `secure` | 1.9401 | 2.1648 | +11.58% | 953.5 | 837.9 | -12.13% | 2245 | 2264 | +0.85% | 137 | 139 | +1.46% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `burst_idle_rw` | `base` | 2.1744 | 2.2885 | +5.25% | 929.5 | 1020.6 | +9.80% | 297 | 327 | +10.10% | 42 | 56 | +33.33% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `burst_idle_rw` | `secure` | 2.1508 | 2.2894 | +6.44% | 925.1 | 1020.5 | +10.32% | 329 | 321 | -2.43% | 46 | 62 | +34.78% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `dual_interleaved` | `base` | 1.9870 | 2.1634 | +8.88% | 931.7 | 838.2 | -10.03% | 2385 | 2451 | +2.77% | 42 | 40 | -4.76% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `dual_interleaved` | `secure` | 1.9500 | 2.1205 | +8.74% | 947.0 | 855.0 | -9.71% | 3042 | 3114 | +2.37% | 164 | 167 | +1.83% | `PASS` |
| `holdout` | `hammer_3row` | `base` | 2.2744 | 2.3044 | +1.32% | 537.7 | 523.9 | -2.57% | 1544 | 1563 | +1.23% | 34 | 38 | +11.76% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `hammer_3row` | `secure` | 2.2109 | 2.2789 | +3.08% | 556.8 | 529.8 | -4.85% | 1562 | 1609 | +3.01% | 190 | 207 | +8.95% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `hammer_multibank` | `base` | 2.2135 | 2.2227 | +0.42% | 554.8 | 543.3 | -2.07% | 2660 | 2733 | +2.74% | 42 | 41 | -2.38% | `PASS` |
| `holdout` | `hammer_multibank` | `secure` | 2.0727 | 2.1149 | +2.04% | 594.4 | 571.1 | -3.92% | 3532 | 3583 | +1.44% | 150 | 148 | -1.33% | `PASS` |
| `holdout` | `large_stride` | `base` | 1.9746 | 2.2087 | +11.86% | 836.6 | 729.6 | -12.79% | 2198 | 2561 | +16.52% | 40 | 41 | +2.50% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `large_stride` | `secure` | 1.9795 | 2.1478 | +8.50% | 826.7 | 750.5 | -9.22% | 2588 | 3134 | +21.10% | 42 | 41 | -2.38% | `HYPOTHESIS_UNVERIFIED` |
| `holdout` | `random_70_30` | `base` | 1.9895 | 2.0765 | +4.37% | 896.7 | 832.7 | -7.14% | 3992 | 3997 | +0.13% | 45 | 43 | -4.44% | `PASS` |
| `holdout` | `random_70_30` | `secure` | 1.9877 | 2.0690 | +4.09% | 897.5 | 835.4 | -6.92% | 3989 | 3996 | +0.18% | 48 | 43 | -10.42% | `HYPOTHESIS_UNVERIFIED` |

## 4. Bảng độ chậm tương đối `secure / base` (`slowdown = BW_base / BW_secure`) — Hiệu chuẩn vs Mặc định T80
- **In-sample (8 trace):** Calibrated err mean `+0.20% ± 3.32%` (max `7.88%`) vs Uncalibrated T80 err mean `+0.14% ± 8.81%` (max `20.91%`).
- **Holdout (6 trace):** Calibrated err mean `-0.15% ± 1.80%` (max `3.09%`) vs Uncalibrated T80 err mean `+0.38% ± 1.08%` (max `2.06%`).
- **All 14 traces:** Calibrated max abs err `7.88%` vs Uncalibrated T80 max abs err `20.91%`.

| Split | Workload | `slowdown_RTL` | `slowdown_Ram_calibrated` | Err Cal% | `slowdown_Ram_uncalibrated` (T80) | Err Uncal% |
|---|---|---:|---:|---:|---:|---:|
| `in_sample` | `bank_conflict` | 1.0816 | 1.0603 | -1.97% | 1.0000 | -7.54% |
| `in_sample` | `gups_read` | 0.9965 | 0.9945 | -0.20% | 0.9986 | +0.21% |
| `in_sample` | `hammer_double` | 1.0161 | 1.0149 | -0.12% | 0.9850 | -3.06% |
| `in_sample` | `hammer_many` | 0.9961 | 0.9988 | +0.27% | 0.9374 | -5.90% |
| `in_sample` | `random_rw` | 1.0053 | 0.9956 | -0.96% | 0.9995 | -0.57% |
| `in_sample` | `row_local` | 1.0014 | 1.0005 | -0.09% | 0.9936 | -0.78% |
| `in_sample` | `stream_copy` | 1.0911 | 1.0557 | -3.24% | 1.0678 | -2.13% |
| `in_sample` | `stream_triad` | 0.9621 | 1.0378 | +7.88% | 1.1633 | +20.91% |
| `holdout` | `burst_idle_rw` | 1.0110 | 0.9996 | -1.12% | 1.0143 | +0.32% |
| `holdout` | `dual_interleaved` | 1.0190 | 1.0202 | +0.12% | 1.0197 | +0.07% |
| `holdout` | `hammer_3row` | 1.0287 | 1.0112 | -1.70% | 1.0337 | +0.48% |
| `holdout` | `hammer_multibank` | 1.0679 | 1.0510 | -1.59% | 1.0750 | +0.66% |
| `holdout` | `large_stride` | 0.9975 | 1.0284 | +3.09% | 1.0180 | +2.06% |
| `holdout` | `random_70_30` | 1.0009 | 1.0036 | +0.27% | 0.9878 | -1.31% |

## 5. Thí nghiệm tách cơ chế (Ablation Suite — 5 dòng mục tiêu)
Chỉ các dòng có thí nghiệm tách dưới đây mới được gắn nhãn `EXPLAINED_ABLATED`; mọi dòng lệch khác giữ nhãn `HYPOTHESIS_UNVERIFIED` (`GIẢ THUYẾT`).

### `bank_conflict` (`secure`, `in_sample`) — Bắt buộc theo brief (ACT -31.4% ở T81)
- RTL: `ACT=121`, `Vic=271`, `throttles=60` | Calibrated: `ACT=83` (`-31.40%`), `Vic=252` (`-7.01%`).
| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline_calibrated` | 83 | +0 | -31.40% | 252 | +0 | -7.01% | 240 | 12 | 0 | 60 |
| `no_patrol_scrub` | 82 | -1 | -32.23% | 240 | -12 | -11.44% | 240 | 0 | 0 | 60 |
| `scrub_interval_420` | 83 | +0 | -31.40% | 252 | +0 | -7.01% | 240 | 12 | 0 | 60 |
| `no_rowpress` | 83 | +0 | -31.40% | 252 | +0 | -7.01% | 240 | 12 | 0 | 60 |
| `no_ref_postpone` | 129 | +46 | +6.61% | 271 | +19 | +0.00% | 240 | 31 | 0 | 60 |
| `sdc_count_act_only` | 29 | -54 | -76.03% | 63 | -189 | -76.75% | 56 | 7 | 14 | 0 |
| `no_sdc_drm` | 29 | -54 | -76.03% | 63 | -189 | -76.75% | 56 | 7 | 14 | 0 |
| `frfcfs_sched` | 83 | +0 | -31.40% | 252 | +0 | -7.01% | 240 | 12 | 0 | 60 |

### `stream_triad` (`base`, `in_sample`) — Top act_victim lệch nhất trong mẫu (-70.60%)
- RTL: `ACT=364`, `Vic=432`, `throttles=0` | Calibrated: `ACT=752` (`+106.59%`), `Vic=127` (`-70.60%`).
| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline_calibrated` | 752 | +0 | +106.59% | 127 | +0 | -70.60% | 80 | 47 | 20 | 0 |
| `no_patrol_scrub` | 719 | -33 | +97.53% | 96 | -31 | -77.78% | 96 | 0 | 24 | 0 |
| `scrub_interval_420` | 762 | +10 | +109.34% | 126 | -1 | -70.83% | 80 | 46 | 20 | 0 |
| `no_rowpress` | 724 | -28 | +98.90% | 50 | -77 | -88.43% | 0 | 50 | 0 | 0 |
| `no_ref_postpone` | 809 | +57 | +122.25% | 50 | -77 | -88.43% | 0 | 50 | 0 | 0 |
| `sdc_count_act_only` | 752 | +0 | +106.59% | 127 | +0 | -70.60% | 80 | 47 | 20 | 0 |
| `no_sdc_drm` | 752 | +0 | +106.59% | 127 | +0 | -70.60% | 80 | 47 | 20 | 0 |
| `frfcfs_sched` | 752 | +0 | +106.59% | 127 | +0 | -70.60% | 80 | 47 | 20 | 0 |

### `hammer_double` (`base`, `in_sample`) — Top act_victim lệch nhất trong mẫu (+34.48%)
- RTL: `ACT=2176`, `Vic=29`, `throttles=0` | Calibrated: `ACT=2196` (`+0.92%`), `Vic=39` (`+34.48%`).
| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline_calibrated` | 2196 | +0 | +0.92% | 39 | +0 | +34.48% | 0 | 39 | 0 | 0 |
| `no_patrol_scrub` | 2195 | -1 | +0.87% | 0 | -39 | -100.00% | 0 | 0 | 0 | 0 |
| `scrub_interval_420` | 2196 | +0 | +0.92% | 41 | +2 | +41.38% | 0 | 41 | 0 | 0 |
| `no_rowpress` | 2196 | +0 | +0.92% | 39 | +0 | +34.48% | 0 | 39 | 0 | 0 |
| `no_ref_postpone` | 2199 | +3 | +1.06% | 41 | +2 | +41.38% | 0 | 41 | 0 | 0 |
| `sdc_count_act_only` | 2196 | +0 | +0.92% | 39 | +0 | +34.48% | 0 | 39 | 0 | 0 |
| `no_sdc_drm` | 2196 | +0 | +0.92% | 39 | +0 | +34.48% | 0 | 39 | 0 | 0 |
| `frfcfs_sched` | 2979 | +783 | +36.90% | 47 | +8 | +62.07% | 0 | 47 | 0 | 0 |

### `random_rw` (`secure`, `in_sample`) — Top act_victim lệch nhất trong mẫu (-24.00%)
- RTL: `ACT=3993`, `Vic=50`, `throttles=0` | Calibrated: `ACT=3998` (`+0.13%`), `Vic=38` (`-24.00%`).
| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline_calibrated` | 3998 | +0 | +0.13% | 38 | +0 | -24.00% | 0 | 38 | 0 | 0 |
| `no_patrol_scrub` | 3998 | +0 | +0.13% | 0 | -38 | -100.00% | 0 | 0 | 0 | 0 |
| `scrub_interval_420` | 3998 | +0 | +0.13% | 38 | +0 | -24.00% | 0 | 38 | 0 | 0 |
| `no_rowpress` | 3998 | +0 | +0.13% | 38 | +0 | -24.00% | 0 | 38 | 0 | 0 |
| `no_ref_postpone` | 3997 | -1 | +0.10% | 44 | +6 | -12.00% | 0 | 44 | 0 | 0 |
| `sdc_count_act_only` | 3998 | +0 | +0.13% | 38 | +0 | -24.00% | 0 | 38 | 0 | 0 |
| `no_sdc_drm` | 3998 | +0 | +0.13% | 38 | +0 | -24.00% | 0 | 38 | 0 | 0 |
| `frfcfs_sched` | 3998 | +0 | +0.13% | 40 | +2 | -20.00% | 0 | 40 | 0 | 0 |

### `stream_copy` (`secure`, `in_sample`) — Kiểm tra bổ sung chênh lệch ACT streaming 1:1 RD/WR
- RTL: `ACT=1483`, `Vic=168`, `throttles=67` | Calibrated: `ACT=1647` (`+11.06%`), `Vic=171` (`+1.79%`).
| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `baseline_calibrated` | 1647 | +0 | +11.06% | 171 | +0 | +1.79% | 128 | 43 | 0 | 32 |
| `no_patrol_scrub` | 1650 | +3 | +11.26% | 128 | -43 | -23.81% | 128 | 0 | 0 | 32 |
| `scrub_interval_420` | 1640 | -7 | +10.59% | 166 | -5 | -1.19% | 128 | 38 | 0 | 32 |
| `no_rowpress` | 1647 | +0 | +11.06% | 171 | +0 | +1.79% | 128 | 43 | 0 | 32 |
| `no_ref_postpone` | 1778 | +131 | +19.89% | 179 | +8 | +6.55% | 128 | 51 | 0 | 32 |
| `sdc_count_act_only` | 1595 | -52 | +7.55% | 77 | -94 | -54.17% | 40 | 37 | 0 | 10 |
| `no_sdc_drm` | 1710 | +63 | +15.31% | 45 | -126 | -73.21% | 0 | 45 | 0 | 0 |
| `frfcfs_sched` | 1648 | +1 | +11.13% | 170 | -1 | +1.19% | 128 | 42 | 0 | 32 |

## 6. Kiểm chứng toàn vẹn T38 sau T88 (`rtl_ml_reenc_ack_overlap = false` khớp kiến trúc sạch)
- Nguồn log RTL hậu-T88: `regression_logs/tb_secure_top_integrity.log` (`checks=279`, `fails=0`).
| Metric | RTL hậu-T88 | Ramulator2 (`rtl_ml_reenc_ack_overlap=False`) | Legacy trước-T88 (`True`) | Rel Err% | Status |
|---|---:|---:|---:|---:|---|
| `META_RD` | 83 | 83 | 112 | +0.00% | `PASS` |
| `META_WR` | 131 | 131 | 164 | +0.00% | `PASS` |
| MC Hit Rate | 78.5% (157/200) | 78.50% (157/200) | 78.50% | +0.00% | `PASS` |
| `reencrypt_events` | 1 | 1 | 1 | +0.00% | `PASS` |
