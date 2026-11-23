# Q-Shield Performance Evaluation Workloads (`sim/paper_perf/WORKLOADS.md`)
Chức năng: Danh mục trace Chronus, kết quả đo MPKI không giảm thiểu, 21 workload đơn nhân và 20 tổ hợp 4 nhân có seed.

## 1. Nguồn và giấy phép
- Bộ trace: **Chronus CPU Traces** (`~/refs/Chronus/cputraces/`)
- Nguồn công bố: Zenodo DOI `10.5281/zenodo.14281771` (2024-12-05)
- Giấy phép: **CC-BY-4.0** (chỉ ghi đường dẫn, hash SHA-256 và số dòng; không chép file trace vào repo).
- Đo MPKI bằng cấu hình `Baseline` (`DDR5_16Gb_x4`, `DDR5_3200C`, 1 kênh, 1 rank, `BHO3` 2MB LLC/core) với `num_expected_insts = 5000000`.
- Ngưỡng phân nhóm LLC MPKI (tự đo trên 57 trace hợp lệ, chọn từ tập `<= 300 MB`):
  - **Low**: `LLC MPKI < 2.0` (17 trace khả dụng, chọn 7)
  - **Medium**: `2.0 <= LLC MPKI < 10.0` (15 trace khả dụng, chọn 7)
  - **High**: `LLC MPKI >= 10.0` (20 trace khả dụng, chọn 7)

## 2. 21 Workload đơn nhân đã chọn
| Nhóm | Tên | Đường dẫn WSL | SHA-256 | Số dòng | Kích thước (B) | LLC MPKI | DRAM MPKI | IPC Baseline |
|---|---|---|---|---|---|---|---|---|
| High | `429.mcf` | `~/refs/Chronus/cputraces/429.mcf` | `3cb7239ad448c19375522c26c684846a1563eeddf4ad5d604a06e2941781bc37` | 15281312 | 290750457 | 464.6451 | 72.1980 | 0.3869 |
| High | `jp2_decode` | `~/refs/Chronus/cputraces/jp2_decode` | `20260d98b25d02f5a7d923a31105ab16bb7a1e1dd46a7f1551c21585bc051448` | 3423692 | 105930578 | 94.7351 | 37.9520 | 0.2732 |
| High | `470.lbm` | `~/refs/Chronus/cputraces/470.lbm` | `63e4d5286d6d1d54dc04ea9a1ccdc63a33eb1563be8730e0d5195e787cad1d97` | 5710822 | 165493827 | 49.4726 | 42.7130 | 0.4071 |
| High | `434.zeusmp` | `~/refs/Chronus/cputraces/434.zeusmp` | `482a6c2ababc7788df52e21e2f4f67700db14e46c59be9f297b2ec5fc63224b9` | 1850730 | 42296593 | 25.5344 | 42.5120 | 0.4028 |
| High | `tpch6` | `~/refs/Chronus/cputraces/tpch6` | `c4dead49e9a1a361868b4ceaa33a71c2e5bfa4992816fe6758fc0c52acfddce3` | 279379 | 5218073 | 17.2958 | 4.4582 | 2.3172 |
| High | `450.soplex` | `~/refs/Chronus/cputraces/450.soplex` | `e5991917e9cecd6fce4aac504903a78331b7fd48c798e05d7e6a748a58aef404` | 5678732 | 98720293 | 13.9942 | 15.4424 | 0.7342 |
| High | `520.omnetpp` | `~/refs/Chronus/cputraces/520.omnetpp` | `e814541375437813b850f99c6ca9737993e4d85417826bd867ceb29b5262df5c` | 4026877 | 67667937 | 10.7896 | 12.0274 | 0.9516 |
| Medium | `464.h264ref` | `~/refs/Chronus/cputraces/464.h264ref` | `715959d35c5be6912175a3292af52411ba93727ced6a714d13991d8fb726f8cf` | 252571 | 4229134 | 2.4072 | 1.9686 | 2.4259 |
| Medium | `ycsb_bserver` | `~/refs/Chronus/cputraces/ycsb_bserver` | `0054c883d87585890fc41c320df0bb08fa6fb62bcefd7a950ea825952dd24936` | 7234350 | 187492293 | 2.9016 | 2.7820 | 1.9448 |
| Medium | `ycsb_dserver` | `~/refs/Chronus/cputraces/ycsb_dserver` | `5d3db77a8efcce6a45b60dd9cc6ba555d2fddd555acdfb2a299ba4361ee0f68e` | 7074793 | 188616000 | 3.1254 | 2.6616 | 2.0063 |
| Medium | `401.bzip2` | `~/refs/Chronus/cputraces/401.bzip2` | `c3d251c8fd7f0f6d8575e50a63f359ce75bdd20f5076ce4fcde16f715074068d` | 856299 | 20716563 | 3.3076 | 3.3076 | 2.2355 |
| Medium | `tpch17` | `~/refs/Chronus/cputraces/tpch17` | `71a3b53fc65a90234fe5507059daebe2d40d3883234415aa512f0b5d55727cfb` | 2339287 | 42615312 | 6.7552 | 6.8332 | 1.2399 |
| Medium | `523.xalancbmk` | `~/refs/Chronus/cputraces/523.xalancbmk` | `354cea808e8ee743e0de6b6f9857348f268988d66110927c37f3197b86cf207d` | 9114466 | 117661062 | 8.7800 | 1.4470 | 2.6037 |
| Medium | `459.GemsFDTD` | `~/refs/Chronus/cputraces/459.GemsFDTD` | `06ea603f8b00350f92c0d5d8a1b43809095e7bb364edcafcaf4c4a5530ff7fe5` | 5083460 | 116881253 | 9.9906 | 9.7488 | 0.8513 |
| Low | `538.imagick` | `~/refs/Chronus/cputraces/538.imagick` | `21fd9ff31210270d51eb3be49b493ab4617bb333a42f929d8226b25651f9b23f` | 4701 | 105161 | 0.0266 | 0.0266 | 3.9032 |
| Low | `511.povray` | `~/refs/Chronus/cputraces/511.povray` | `55a244b78ba4706588d4287b0f67a64953a5a380a70ae5f31e3f57daddc186d1` | 3218300 | 46817099 | 0.3580 | 0.2852 | 2.9740 |
| Low | `447.dealII` | `~/refs/Chronus/cputraces/447.dealII` | `acf634a50ed1519c41b30caad786b9e678dd4eda9f7fa550eea16087f013e065` | 23059 | 483806 | 0.4142 | 0.4142 | 3.5390 |
| Low | `458.sjeng` | `~/refs/Chronus/cputraces/458.sjeng` | `8f13ca712f36daac7d914b01a5d794fde6689fa5c5b962a02056f2824a44c128` | 71977 | 2100864 | 0.5810 | 0.5100 | 3.1946 |
| Low | `541.leela` | `~/refs/Chronus/cputraces/541.leela` | `ef72b0a40ce5b5ec1ce481a69283dbb5f3dbbd2a75a8f8583960c6abbef79ecb` | 657016 | 11213124 | 0.9218 | 0.4610 | 3.0714 |
| Low | `445.gobmk` | `~/refs/Chronus/cputraces/445.gobmk` | `02de70aa59926b4eeffdc130cb99f27c1a8056b661828c42641b4096790f8c07` | 107852 | 2861908 | 1.2382 | 0.8958 | 3.0920 |
| Low | `500.perlbench` | `~/refs/Chronus/cputraces/500.perlbench` | `0437da0ccd6b9353b0e5210535a9abc14abf1a2147d398f0656bbd13d8d6ae29` | 581900 | 7828488 | 1.9026 | 1.9026 | 2.1234 |

## 3. 20 Tổ hợp 4 nhân (Random Seed = `20261121`)
| Mix | Loại | Core 0 | Core 1 | Core 2 | Core 3 |
|---|---|---|---|---|---|
| `mix_H_1` | HHHH | `tpch6` | `jp2_decode` | `470.lbm` | `470.lbm` |
| `mix_H_2` | HHHH | `520.omnetpp` | `tpch6` | `429.mcf` | `470.lbm` |
| `mix_H_3` | HHHH | `429.mcf` | `429.mcf` | `jp2_decode` | `jp2_decode` |
| `mix_H_4` | HHHH | `470.lbm` | `470.lbm` | `jp2_decode` | `jp2_decode` |
| `mix_H_5` | HHHH | `tpch6` | `470.lbm` | `434.zeusmp` | `470.lbm` |
| `mix_M_1` | MMMM | `ycsb_dserver` | `tpch17` | `464.h264ref` | `ycsb_bserver` |
| `mix_M_2` | MMMM | `401.bzip2` | `464.h264ref` | `401.bzip2` | `464.h264ref` |
| `mix_M_3` | MMMM | `ycsb_dserver` | `ycsb_bserver` | `464.h264ref` | `ycsb_bserver` |
| `mix_M_4` | MMMM | `523.xalancbmk` | `ycsb_bserver` | `ycsb_dserver` | `464.h264ref` |
| `mix_M_5` | MMMM | `ycsb_dserver` | `tpch17` | `459.GemsFDTD` | `459.GemsFDTD` |
| `mix_L_1` | LLLL | `445.gobmk` | `458.sjeng` | `538.imagick` | `511.povray` |
| `mix_L_2` | LLLL | `511.povray` | `500.perlbench` | `541.leela` | `511.povray` |
| `mix_L_3` | LLLL | `511.povray` | `447.dealII` | `541.leela` | `445.gobmk` |
| `mix_L_4` | LLLL | `500.perlbench` | `541.leela` | `447.dealII` | `447.dealII` |
| `mix_L_5` | LLLL | `458.sjeng` | `458.sjeng` | `541.leela` | `445.gobmk` |
| `mix_X_1` | Mixed | `401.bzip2` | `447.dealII` | `ycsb_bserver` | `434.zeusmp` |
| `mix_X_2` | Mixed | `434.zeusmp` | `541.leela` | `523.xalancbmk` | `464.h264ref` |
| `mix_X_3` | Mixed | `459.GemsFDTD` | `429.mcf` | `464.h264ref` | `445.gobmk` |
| `mix_X_4` | Mixed | `464.h264ref` | `450.soplex` | `434.zeusmp` | `458.sjeng` |
| `mix_X_5` | Mixed | `470.lbm` | `447.dealII` | `ycsb_bserver` | `429.mcf` |

## 4. 4 Kịch bản tấn công (1 kẻ tấn công + 3 lành tính)
- Co-runner lành tính (Core 1–3): `434.zeusmp, 401.bzip2, 458.sjeng` (trung vị 3 nhóm High/Medium/Low).
| Kịch bản | Đường dẫn | SHA-256 | Số dòng | Mẫu tấn công |
|---|---|---|---|---|
| `double_sided` | `sim/paper_perf/attacks/double_sided.trace` | `86167a869011ef2aee34abea0415c18c6957593ecc4ced621c8e60c1fe061844` | 1800 | 2 kẻ tấn công (row 100, 102) kẹp nạn nhân row 101 + xả LLC 8-way |
| `half_double` | `sim/paper_perf/attacks/half_double.trace` | `3baad5b6ed319f3bc210355dfb9ee91889abe3047bebc23b6bfc06bec60d9643` | 2160 | 4 kẻ tấn công (row 100, 101, 103, 104) quanh row 102 (R=1 và R=2) |
| `many_sided` | `sim/paper_perf/attacks/many_sided.trace` | `11fd3f718560b84a3240d1a8b51f8ebd6d061c3aa73176303e97c66748ba7b95` | 1800 | 18 kẻ tấn công (row 100..134 bước 2) tự xả LLC |
| `rowpress_hold` | `sim/paper_perf/attacks/rowpress_hold.trace` | `2e6aa68b21e09dbdb2cbb444f1afe5d956b4a96a2486bda34bf4733f2eb9cf0d` | 14720 | Giữ hàng 100/102 qua 16 col (bubble=400) xen kẽ 80 vòng double-sided |
