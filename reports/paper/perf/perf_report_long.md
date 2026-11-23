# Q-Shield Ramulator2 Long-Window Evaluation (`>= 1 tREFW = 32 ms`, `reports/paper/perf/perf_report_long.md`)
- Commit: `847f9ba8e849a2b5b74efc57d075f6a17802994b` | Upstream Ramulator2: `72427a1bba3771564c4fb0e494ba02242fd1eaa7`
- DRAM Energy: `N/A (not provided by upstream Ramulator2 commit 72427a1)`
- Cửa sổ theo thời gian: `num_max_cycles = 134400000` (chu kỳ lõi BHO3), `num_expected_insts = 2000000000`, `ctrl_cycles = 53760000`, **`sim_time_ms` thực đo: `[33.6000, 33.6000] ms`** (`>= 32.0 ms = 1 tREFW` trên **`321/321`** lượt chạy).
- Thời gian thực tế: `4990.43s` (`83.17 phút`) | Lượt chạy lâu nhất: `326.82s` (`<= 900s`) | Đỉnh RSS/worker: `455.6 MB` | `*_ACT` VRR=`0`, dropped=`0`.
- Kiểm tra tái lập cùng seed (`PARA_ACT` & `QShield` @ `tpch6`, `N_RH=128`, `seed=123`, `33.6 ms`): **`PASS (khớp tuyệt đối)`**.
- Lưu ý về hiệu chuẩn: Giữ cùng tham số mô hình mặc định như T80/T87 (chưa bật bộ tham số hiệu chuẩn trong mẫu của T81/T90, có độ lạc quan hệ thống ~4–5% theo R-86/R-89).

## 1. Cách chọn tập con workload và phân tích lặp trace (`BHO3`)
- 6 single-core workloads (2 per LLC MPKI group from matrix_spec.json): High=[429.mcf (highest MPKI, mandatory), tpch6 (explicitly requested, low DRAM MPKI 4.46, short trace 279,379 lines)]; Medium=[tpch17 (mid-high Medium), 401.bzip2 (median Medium, attack co-runner)]; Low=[511.povray (longest Low trace 3.22M lines), 458.sjeng (median Low, attack co-runner)]. Plus all 4 attack scenarios (1 attacker + 3 co-runners: 434.zeusmp, 401.bzip2, 458.sjeng) and Baseline alone run for 434.zeusmp at the exact same time window.
- **Cảnh báo lặp trace:** `BHO3`/`SimpleO3` tự quay vòng về đầu trace khi đọc hết file. Ở cửa sổ dài `33.6 ms`, các trace ngắn (`tpch6` 279.379 dòng, `458.sjeng` 71.977 dòng, 4 attack trace 1.800–14.720 dòng) bị lặp nhiều lần; các số liệu dưới đây phải đọc kèm số lần lặp ước lượng (`llc_accesses / trace_lines`, với kịch bản tấn công là tổng truy cập LLC của cả 4 nhân chia cho số dòng trace tấn công).

| Category | Workload | Nhóm MPKI | Số dòng trace | Kích thước (MB) | Lệnh core 0 (Baseline 33.6 ms) | Tổng truy cập LLC | Ước lượng vòng lặp (`LLC/dòng`) | IPC Baseline | Worst R1 Baseline (`N_RH=1024`) |
|---|---|---|---|---|---|---|---|---|---|
| single | `429.mcf` | High | 15281312 | 277.28 | 46645719 | 30028396 | 1.97 | 0.3471 | 1606 |
| single | `tpch6` | High | 279379 | 4.98 | 359348492 | 1606616 | 5.75 | 2.6737 | 614 |
| single | `tpch17` | Medium | 2339287 | 40.64 | 125983093 | 2022651 | 0.86 | 0.9374 | 932 |
| single | `401.bzip2` | Medium | 856299 | 19.76 | 372794845 | 2282344 | 2.67 | 2.7738 | 815 |
| single | `511.povray` | Low | 3218300 | 44.65 | 432340039 | 7977472 | 2.48 | 3.2168 | 126 |
| single | `458.sjeng` | Low | 71977 | 2.0 | 446398435 | 267961 | 3.72 | 3.3214 | 160 |
| attack | `double_sided` | Attack(1+3) | 1800 | 0.0219 | 446899 | 138556066 | 76975.59 | 1.3421 | 47176 |
| attack | `half_double` | Attack(1+3) | 2160 | 0.0262 | 463863 | 138496906 | 64118.94 | 1.3208 | 32664 |
| attack | `many_sided` | Attack(1+3) | 1800 | 0.0189 | 620827 | 529951914 | 294417.73 | 0.0387 | 65594 |
| attack | `rowpress_hold` | Attack(1+3) | 14720 | 0.1794 | 4381330 | 135835385 | 9227.95 | 1.3513 | 46946 |

## 2. Tái lập và giải thích hai hiện tượng cảnh giác trên `429.mcf`
### 2.1. Đối chiếu trực tiếp điểm đo 13,44 ms (`num_max_cycles = 53,760,000`, `N_RH = 1024`) và cửa sổ dài 33,6 ms
| Cấu hình | Cửa sổ | `ctrl_cycles` | `sim_time_ms` | IPC | Tỉ lệ chậm vs Baseline | `avg_read_lat` (nCK) | Tổng ACT | Meta ACT | Mit ACT | MC Miss Rate | `RFMab` | `Worst R1` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `Baseline` (`429.mcf`) | 13.44 ms | 21504000 | 13.44 | 0.3581 | 1.000× | — | 1274192 | 0 | 0 | — | 0 | **1157** (b=5, r=37478) |
| `QShield_Integ` (`429.mcf`) | 13.44 ms | 21504000 | 13.44 | **0.0739** | **4.843×** | 802.45 | 972576 | 669829 | 28856 | 69.4% | 5253 | 1001 |
| `Baseline` (`tpch6`) | 13.44 ms | 21504000 | 13.44 | 2.7051 | 1.000× | — | — | 0 | 0 | — | 0 | 281 |
| `Baseline` (`429.mcf`) | **33.6 ms** | 53760000 | 33.6 | 0.3471 | 1.000× | 159.73 | 3195813 | 0 | 0 | — | 0 | **1606** (b=13, r=37478) |
| `QShield` (`429.mcf`) | **33.6 ms** | 53760000 | 33.6 | 0.284 | 1.222× | 195.09 | 2735884 | 0 | 81716 | — | 14466 | 510 |
| `QShield_Integ` (`429.mcf`) | **33.6 ms** | 53760000 | 33.6 | **0.0723** | **4.798×** | 808.03 | 2421492 | 1669840 | 72144 | 69.19% | 13072 | 1005 |

### 2.2. Giải thích cơ chế định lượng
1. **Tại sao `Baseline` `429.mcf` đạt `Worst R1 = 1157` (13.44 ms) và `1606` (33.6 ms) không có tấn công:** `429.mcf` (tối ưu mạng đơn hình SPEC CPU2006) có mật độ truy cập DRAM cực lớn (`LLC MPKI = 464.65`, `DRAM MPKI = 72.20`, xung đột hàng cao khi duyệt danh sách cung/nút liên tục qua `15.28M` dòng trace, gần như không lặp lại nhiều trong 13.44 ms). Các cấu trúc nút gốc/cung nóng nằm gần nhau về địa chỉ vật lý dưới ánh xạ `RoBaRaCoCh` nên tạo ra xung đột đóng/mở hàng liên tục trên cùng bank (tại `b=5, r=37478` sau 13.44 ms và `b=13, r=37478` sau 33.6 ms), tích lũy nhiễu vượt `N_RH = 1024` ngay cả trên tải lành tính khi chưa hết 1 `tREFW`. Đây là hiện tượng **benign RowHammer-like hot-row thrashing** có thật trong ứng dụng bộ nhớ dày đặc, khẳng định vì sao cửa sổ ngắn 0.24 ms ở T80 (`Worst R1 = 133`) che khuất rủi ro này.
2. **Tại sao `QShield_Integ` chậm ~`4.843×` (13.44 ms) / `4.80×` (33.6 ms) trên `429.mcf` trong khi `QShield` không toàn vẹn chỉ chậm ~`1.22×`:** Nguyên nhân không phải lỗi mô phỏng mà là **nút cổ chai dung lượng bộ đệm metadata (Metadata Cache thrashing)** khớp đúng RTL (`qshield_meta_cache.sv`: chỉ `16 sets × 4 ways = 64 entries = 4 KB` dùng chung cho Counter Block, 4 tầng Bonsai Merkle Tree và MAC Line): trên `429.mcf`, tỉ lệ trượt metadata cache lên tới **`69.19%`** (`hits=1105332`, `misses=2482617`), phát sinh `1669840` lệnh ACT metadata (`69.0%` tổng ACT), kéo theo `13072` lệnh `RFMab` (so với `14466` của `QShield`) và `72144` ACT giảm thiểu, đẩy độ trễ đọc trung bình từ `159.7` nCK lên `808.0` nCK (cộng thêm `crypto_extra_lat_clk = 84` nCK). Khi báo cáo trong paper, con số chậm ~4–5× trên `429.mcf` phải nêu rõ là **chi phí của cấu hình FPGA-scale 4 KB metadata cache trên tải random-pointer-chasing cực hạn**, không được che giấu cũng không được quy nạp thành chi phí trung bình của mọi workload.

## 3. Bảng A — Cửa sổ dài (`>= 1 tREFW`), cấu hình KHÔNG cần sửa chip DRAM thương mại (`dram_support = none`)
| Category | N_RH | Scheme | dram_support | OK/Total | `sim_ms` min..max | Mean IPC | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 | Ca `R1 > N_RH` (runs / wl) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| attack | 128 | Baseline | `none` | 4/4 | 33.60..33.60 | 1.0132 | 1.0 | 0.0 | 0.5395 | 9704.4957 | 0 | 65594 | 65594 | 4/4 (4/4) |
| attack | 128 | BlockHammer | `none` | 4/4 | 33.60..33.60 | 1.0785 | 7.3635 | 0.0 | 0.1374 | 18.8671 | 0 | 11225 | 18058 | 4/4 (4/4) |
| attack | 128 | PARA_ACT | `none` | 12/12 | 33.60..33.60 | 0.5013 | 0.5819 | 0.00264 | 0.1915 | 9708.3594 | 379449.2 | 3926 | 7852 | 12/12 (4/4) |
| attack | 128 | Graphene_ACT | `none` | 4/4 | 33.60..33.60 | 0.9449 | 0.9428 | 0.0 | 0.4938 | 9704.6572 | 52034 | 483 | 966 | 4/4 (4/4) |
| attack | 128 | Hydra_ACT | `none` | 4/4 | 33.60..33.60 | 0.7125 | 0.7553 | 0.0 | 0.3423 | 9705.5344 | 58450 | 481 | 962 | 4/4 (4/4) |
| attack | 128 | QShield | `none` | 4/4 | 33.60..33.60 | 0.8973 | 0.8815 | 0.0 | 0.425 | 9705.1237 | 240929 | 1386 | 2772 | 4/4 (4/4) |
| attack | 128 | QShield_Integ | `none` | 4/4 | 33.60..33.60 | 0.46 | 0.5462 | 0.0 | 0.1531 | 9710.2476 | 432024 | 5452 | 10906 | 4/4 (4/4) |
| attack | 1024 | Baseline | `none` | 4/4 | 33.60..33.60 | 1.0132 | 1.0 | 0.0 | 0.5395 | 9704.4957 | 0 | 65594 | 65594 | 4/4 (4/4) |
| attack | 1024 | BlockHammer | `none` | 4/4 | 33.60..33.60 | 1.0151 | 1.0385 | 0.0 | 0.5418 | 58.887 | 0 | 65562 | 65562 | 4/4 (4/4) |
| attack | 1024 | PARA_ACT | `none` | 12/12 | 33.60..33.60 | 0.8719 | 0.8758 | 0.00591 | 0.4332 | 9704.9769 | 124292.5 | 1022 | 2044 | 0/12 (0/4) |
| attack | 1024 | Graphene_ACT | `none` | 4/4 | 33.60..33.60 | 1.0115 | 0.9983 | 0.0 | 0.5378 | 9704.5023 | 3758 | 1026 | 2046 | 1/4 (1/4) |
| attack | 1024 | Hydra_ACT | `none` | 4/4 | 33.60..33.60 | 0.8413 | 0.8583 | 0.0 | 0.4228 | 9704.9842 | 11066 | 1026 | 2048 | 1/4 (1/4) |
| attack | 1024 | QShield | `none` | 4/4 | 33.60..33.60 | 0.9277 | 0.9191 | 0.0 | 0.4678 | 9704.8181 | 47389.8 | 628 | 686 | 0/4 (0/4) |
| attack | 1024 | QShield_Integ | `none` | 4/4 | 33.60..33.60 | 0.4748 | 0.5568 | 0.0 | 0.1639 | 9709.6654 | 76999 | 797 | 1594 | 0/4 (0/4) |
| single | 128 | Baseline | `none` | 6/6 | 33.60..33.60 | 2.2117 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 1606 | 3311 | 5/6 (5/6) |
| single | 128 | BlockHammer | `none` | 6/6 | 33.60..33.60 | 1.5011 | 0.5272 | 0.0 | 0.5272 | 3.2265 | 0 | 645 | 1002 | 5/6 (5/6) |
| single | 128 | PARA_ACT | `none` | 18/18 | 33.60..33.60 | 1.8428 | 0.7099 | 0.00156 | 0.7099 | 2.1531 | 190858.2 | 164 | 379 | 6/18 (2/6) |
| single | 128 | Graphene_ACT | `none` | 6/6 | 33.60..33.60 | 2.1901 | 0.9533 | 0.0 | 0.9533 | 1.062 | 27670.7 | 151 | 237 | 2/6 (2/6) |
| single | 128 | Hydra_ACT | `none` | 6/6 | 33.60..33.60 | 2.0696 | 0.8357 | 0.0 | 0.8357 | 1.5289 | 26939 | 243 | 489 | 1/6 (1/6) |
| single | 128 | QShield | `none` | 6/6 | 33.60..33.60 | 2.102 | 0.8909 | 0.0 | 0.8909 | 1.1459 | 130303.7 | 98 | 224 | 0/6 (0/6) |
| single | 128 | QShield_Integ | `none` | 6/6 | 33.60..33.60 | 1.6704 | 0.6421 | 0.0 | 0.6421 | 2.0478 | 178034.8 | 4497 | 8994 | 5/6 (5/6) |
| single | 1024 | Baseline | `none` | 6/6 | 33.60..33.60 | 2.2117 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 1606 | 3311 | 1/6 (1/6) |
| single | 1024 | BlockHammer | `none` | 6/6 | 33.60..33.60 | 2.2003 | 0.9673 | 0.0 | 0.9673 | 1.0406 | 0 | 1424 | 2993 | 1/6 (1/6) |
| single | 1024 | PARA_ACT | `none` | 18/18 | 33.60..33.60 | 2.1402 | 0.9049 | 0.00134 | 0.9049 | 1.1485 | 58936.3 | 253 | 426 | 0/18 (0/6) |
| single | 1024 | Graphene_ACT | `none` | 6/6 | 33.60..33.60 | 2.2095 | 0.9938 | 0.0 | 0.9938 | 1.0064 | 2983.3 | 769 | 1158 | 0/6 (0/6) |
| single | 1024 | Hydra_ACT | `none` | 6/6 | 33.60..33.60 | 2.1321 | 0.8685 | 0.0 | 0.8685 | 1.4261 | 3665.8 | 549 | 930 | 0/6 (0/6) |
| single | 1024 | QShield | `none` | 6/6 | 33.60..33.60 | 2.1718 | 0.9526 | 0.0 | 0.9526 | 1.0549 | 21927.7 | 510 | 1051 | 0/6 (0/6) |
| single | 1024 | QShield_Integ | `none` | 6/6 | 33.60..33.60 | 1.7082 | 0.6602 | 0.0 | 0.6602 | 1.9623 | 27479.2 | 1005 | 1380 | 0/6 (0/6) |

## 4. Bảng B — Cửa sổ dài (`>= 1 tREFW`), cấu hình CẦN lệnh không chuẩn hoặc hỗ trợ trong chip DRAM (`vrr_non_jedec`, `in_dram`)
| Category | N_RH | Scheme | dram_support | OK/Total | `sim_ms` min..max | Mean IPC | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 | Ca `R1 > N_RH` (runs / wl) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| attack | 128 | PARA | `vrr_non_jedec` | 12/12 | 33.60..33.60 | 0.7771 | 0.7719 | 0.0063 | 0.3103 | 9706.2874 | 138577.2 | 62 | 62 | 0/12 (0/4) |
| attack | 128 | Graphene | `vrr_non_jedec` | 4/4 | 33.60..33.60 | 0.9775 | 0.9682 | 0.0 | 0.513 | 9704.5935 | 13406.2 | 150 | 253 | 2/4 (2/4) |
| attack | 128 | Hydra | `vrr_non_jedec` | 4/4 | 33.60..33.60 | 0.7487 | 0.7822 | 0.0 | 0.3618 | 9705.3957 | 16792.2 | 127 | 253 | 0/4 (0/4) |
| attack | 128 | PRAC | `in_dram` | 4/4 | 33.60..33.60 | 0.9605 | 0.9565 | 0.0 | 0.5044 | 9704.6156 | 8042 | 59104 | 60320 | 4/4 (4/4) |
| attack | 128 | RFM | `in_dram` | 4/4 | 33.60..33.60 | 0.8978 | 0.8903 | 0.0 | 0.4407 | 9704.9774 | 25153.2 | 47936 | 50324 | 4/4 (4/4) |
| attack | 1024 | PARA | `vrr_non_jedec` | 12/12 | 33.60..33.60 | 0.9552 | 0.9385 | 0.00212 | 0.4816 | 9704.7723 | 34401.0 | 352 | 352 | 0/12 (0/4) |
| attack | 1024 | Graphene | `vrr_non_jedec` | 4/4 | 33.60..33.60 | 1.0113 | 0.9983 | 0.0 | 0.5379 | 9704.5015 | 939.2 | 1023 | 2045 | 0/4 (0/4) |
| attack | 1024 | Hydra | `vrr_non_jedec` | 4/4 | 33.60..33.60 | 0.8491 | 0.864 | 0.0 | 0.427 | 9704.9662 | 2886.2 | 1023 | 2045 | 0/4 (0/4) |
| attack | 1024 | PRAC | `in_dram` | 4/4 | 33.60..33.60 | 1.0069 | 0.9949 | 0.0 | 0.5354 | 9704.5084 | 1036 | 64714 | 64724 | 4/4 (4/4) |
| attack | 1024 | RFM | `in_dram` | 4/4 | 33.60..33.60 | 0.9796 | 0.9697 | 0.0 | 0.5144 | 9704.5892 | 6210 | 61090 | 61704 | 4/4 (4/4) |
| single | 128 | PARA | `vrr_non_jedec` | 18/18 | 33.60..33.60 | 1.9312 | 0.7707 | 0.00127 | 0.7707 | 1.4455 | 78713.4 | 51 | 59 | 0/18 (0/6) |
| single | 128 | Graphene | `vrr_non_jedec` | 6/6 | 33.60..33.60 | 2.1992 | 0.9758 | 0.0 | 0.9758 | 1.0273 | 7918 | 155 | 233 | 2/6 (2/6) |
| single | 128 | Hydra | `vrr_non_jedec` | 6/6 | 33.60..33.60 | 2.0802 | 0.8429 | 0.0 | 0.8429 | 1.4654 | 7503.8 | 125 | 162 | 0/6 (0/6) |
| single | 128 | PRAC | `in_dram` | 6/6 | 33.60..33.60 | 2.2019 | 0.9868 | 0.0 | 0.9868 | 1.0139 | 925.3 | 1540 | 3196 | 5/6 (5/6) |
| single | 128 | RFM | `in_dram` | 6/6 | 33.60..33.60 | 2.1488 | 0.9462 | 0.0 | 0.9462 | 1.0599 | 5402.7 | 1411 | 2929 | 5/6 (5/6) |
| single | 1024 | PARA | `vrr_non_jedec` | 18/18 | 33.60..33.60 | 2.1649 | 0.9383 | 0.00122 | 0.9383 | 1.077 | 18037.8 | 333 | 333 | 0/18 (0/6) |
| single | 1024 | Graphene | `vrr_non_jedec` | 6/6 | 33.60..33.60 | 2.2103 | 0.996 | 0.0 | 0.996 | 1.0041 | 764.8 | 771 | 1158 | 0/6 (0/6) |
| single | 1024 | Hydra | `vrr_non_jedec` | 6/6 | 33.60..33.60 | 2.1322 | 0.8689 | 0.0 | 0.8689 | 1.4214 | 931.2 | 555 | 904 | 0/6 (0/6) |
| single | 1024 | PRAC | `in_dram` | 6/6 | 33.60..33.60 | 2.2114 | 0.9995 | 0.0 | 0.9995 | 1.0005 | 35.3 | 1598 | 3303 | 1/6 (1/6) |
| single | 1024 | RFM | `in_dram` | 6/6 | 33.60..33.60 | 2.2075 | 0.9942 | 0.0 | 0.9942 | 1.0059 | 698.2 | 1595 | 3289 | 1/6 (1/6) |

## 5. So sánh số ca `Worst R1 > N_RH` giữa cửa sổ ngắn (T80, T87) và cửa sổ dài (T91, `>= 1 tREFW`)
Bảng so sánh trực tiếp trên **cùng tập con 6 đơn nhân + 4 tấn công tại `N_RH ∈ {1024, 128}`** (và cột tham chiếu ma trận đầy đủ `single+attack @ 1024/128` của T87). Các nhóm `dram_support` vẫn tách rõ, không xếp hạng chung.

| Nhóm DRAM | Scheme | T80 ngắn (cùng tập con: `viol/runs`) | T87 ngắn (cùng tập con: `viol/runs`) | **T91 dài ≥ 1 tREFW (`viol/runs`)** | T91 `single@1024` | T91 `single@128` | T91 `attack@1024` | T91 `attack@128` | T87 full (`single+atk@1024,128`) |
|---|---|---|---|---|---|---|---|---|---|
| `none` | `Baseline` | 9/20 | 9/20 | **14/20** | 1/6 | 5/6 | 4/4 | 4/4 | 13/50 |
| `none` | `BlockHammer` | 9/20 | 9/20 | **14/20** | 1/6 | 5/6 | 4/4 | 4/4 | 13/50 |
| `none` | `PARA_ACT` | N/A (T87) | 10/60 | **18/60** | 0/18 | 6/18 | 0/12 | 12/12 | 10/150 |
| `none` | `Graphene_ACT` | N/A (T87) | 2/20 | **7/20** | 0/6 | 2/6 | 1/4 | 4/4 | 2/50 |
| `none` | `Hydra_ACT` | N/A (T87) | 2/20 | **6/20** | 0/6 | 1/6 | 1/4 | 4/4 | 2/50 |
| `none` | `QShield` | 1/20 | 1/20 | **4/20** | 0/6 | 0/6 | 0/4 | 4/4 | 1/50 |
| `none` | `QShield_Integ` | 5/20 | 5/20 | **9/20** | 0/6 | 5/6 | 0/4 | 4/4 | 7/50 |
| `vrr_non_jedec` | `PARA` | 0/60 | 0/60 | **0/60** | 0/18 | 0/18 | 0/12 | 0/12 | 0/150 |
| `vrr_non_jedec` | `Graphene` | 0/20 | 0/20 | **4/20** | 0/6 | 2/6 | 0/4 | 2/4 | 0/50 |
| `vrr_non_jedec` | `Hydra` | 0/20 | 0/20 | **0/20** | 0/6 | 0/6 | 0/4 | 0/4 | 0/50 |
| `in_dram` | `PRAC` | 9/20 | 9/20 | **14/20** | 1/6 | 5/6 | 4/4 | 4/4 | 13/50 |
| `in_dram` | `RFM` | 9/20 | 9/20 | **14/20** | 1/6 | 5/6 | 4/4 | 4/4 | 13/50 |

## 6. Chi tiết các ca `Worst R1 > N_RH` của `QShield` và `QShield_Integ` ở cửa sổ dài (`count = 13`)
| Category | Workload | Scheme | N_RH | Worst R1 | Bank | Row | `row_is_meta` | `a_meta` | `a_mit` | `a_usr` | `rows_exceed_r1` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| attack | `many_sided` | `QShield` | 128 | 1386 | 0 | 137 | 0 | 0 | 1386 | 0 | 2 |
| attack | `double_sided` | `QShield` | 128 | 1035 | 0 | 97 | 0 | 0 | 1035 | 0 | 6 |
| attack | `rowpress_hold` | `QShield` | 128 | 1030 | 0 | 97 | 0 | 0 | 1030 | 0 | 6 |
| attack | `half_double` | `QShield` | 128 | 718 | 0 | 97 | 0 | 0 | 718 | 0 | 8 |
| attack | `rowpress_hold` | `QShield_Integ` | 128 | 5452 | 2 | 295 | 0 | 0 | 5452 | 0 | 54 |
| attack | `double_sided` | `QShield_Integ` | 128 | 5444 | 2 | 295 | 0 | 0 | 5444 | 0 | 52 |
| attack | `half_double` | `QShield_Integ` | 128 | 4771 | 2 | 295 | 0 | 0 | 4771 | 0 | 55 |
| attack | `many_sided` | `QShield_Integ` | 128 | 2219 | 1 | 295 | 0 | 0 | 2219 | 0 | 58 |
| single | `429.mcf` | `QShield_Integ` | 128 | 4497 | 2 | 295 | 0 | 0 | 4497 | 0 | 111 |
| single | `458.sjeng` | `QShield_Integ` | 128 | 2022 | 6 | 295 | 0 | 0 | 2022 | 0 | 19 |
| single | `tpch6` | `QShield_Integ` | 128 | 1242 | 10 | 295 | 0 | 0 | 1242 | 0 | 28 |
| single | `tpch17` | `QShield_Integ` | 128 | 800 | 6 | 295 | 0 | 0 | 800 | 0 | 19 |
| single | `401.bzip2` | `QShield_Integ` | 128 | 397 | 8 | 295 | 0 | 0 | 397 | 0 | 25 |
