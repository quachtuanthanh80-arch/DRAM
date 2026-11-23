# Q-Shield Ramulator2 Performance Evaluation v2 — Commercial DRAM Separation (`reports/paper/perf/perf_report_v2.md`)
- Commit: `d890553c3758fee930e82b4097c72b2af8180a43` | Upstream Ramulator2: `72427a1bba3771564c4fb0e494ba02242fd1eaa7`
- DRAM Energy: `N/A (not provided by upstream Ramulator2 commit 72427a1)`
- `num_expected_insts`: benign=`2000000`, attack=`500000` | T87 New Runs (`1,080`): Est=`27.97 min`, Actual=`1844.25s` (`30.74 min`)
- Validity Gate (T80 16 checks): `PASS` | `*_ACT` VRR issued: `0` | `*_ACT` dropped: `0` | `QShield_Integ` remaining `Worst R1 > N_RH`: `27`

## 1. Cửa sổ mô phỏng (so với `tREFW = 32 ms`)
- Đơn nhân (Baseline, `N_RH=1024`): trung vị **`0.2364 ms`** (phạm vi `0.129..1.6088 ms`, tương đương `0.74%` của `tREFW = 32 ms`).
- Tổ hợp 4 nhân (Baseline): trung vị **`0.7283 ms`** (`2.28%` của `tREFW`).
- Kịch bản tấn công (Baseline): trung vị **`3.125 ms`** (`9.77%` của `tREFW`).
- Lưu ý: Cửa sổ dài `>= 1 tREFW` thuộc phạm vi T91; mọi số liệu dưới đây phản ánh cửa sổ ngắn đồng nhất với T80.

## 2. Phân loại yêu cầu phần cứng DRAM (`dram_support`) và chi phí `VRR` vs `ACT + PREpb`
- Preset DRAM: `DDR5_VRR` (`DDR5_16Gb_x4`, `DDR5_3200C`, `tCK = 625 ps`): **`nVRR = 448 nCK (280.0 ns)`**, **`nRAS = 52 nCK (32.5 ns)`**, **`nRP = 28 nCK (17.5 ns)`**, **`nRC = 80 nCK (50.0 ns)`**.
- Chi phí 4 nạn nhân (`R = 2`, cùng bank): `1 × VRR = 448 nCK (280.0 ns)` so với `4 × (ACT + PREpb) = 4 × nRC = 320 nCK (200.0 ns)` (VRR đắt hơn `128 nCK` = `80.0 ns` mỗi lần kích hoạt, nhưng trong `rh_observer.cpp` VRR xóa nhiễu `±1, ±2` không cộng nhiễu lân cận còn `ACT + PREpb` cộng nhiễu Half-Double lên các hàng kế cận).
- Quy ước đếm ACT giảm thiểu của `PARA_ACT`, `Graphene_ACT`, `Hydra_ACT`: **không đếm lại** ACT làm tươi nạn nhân (`source_id = -99`) vào bộ theo dõi của chính plugin, giống Q-Shield (`PARAMS.md` §1) để so sánh cùng điều kiện; `Hydra_ACT` vẫn đếm ACT đọc/ghi bảng RCT của mình trong `RCTCT` như upstream `Hydra`.

| Scheme | `dram_support` | Căn cứ mã nguồn (`file:dòng`) |
|---|---|---|
| `Baseline` | `none` | `generic_ddr_controller.cpp:8-80 (no mitigation)` |
| `BlockHammer` | `none` | `blockhammer_controller.cpp:1-476 (controller-only throttling, no VRR/RFM)` |
| `PARA_ACT` | `none` | `para_act.cpp:74-121 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)` |
| `Graphene_ACT` | `none` | `graphene_act.cpp:100-178 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)` |
| `Hydra_ACT` | `none` | `hydra_act.cpp:200-355 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)` |
| `QShield` | `none` | `qshield_controller.cpp:1255-1311 (standard ACT->tRAS->PREpb victim refresh)` |
| `QShield_Integ` | `none` | `qshield_controller.cpp:1255-1311,1406-1425 (standard ACT->tRAS->PREpb + BMT/MAC)` |
| `PARA` | `vrr_non_jedec` | `para.cpp:45-62 (requires non-JEDEC VRR command)` |
| `Graphene` | `vrr_non_jedec` | `graphene.cpp:51-59,157-158 (requires non-JEDEC VRR command)` |
| `Hydra` | `vrr_non_jedec` | `hydra.cpp:142-148,303-304,446-447 (requires non-JEDEC VRR command)` |
| `PRAC` | `in_dram` | `prac_controller.cpp:36-40,160-177,225-260 (requires in-DRAM per-row counters + ABO + RFMab)` |
| `RFM` | `in_dram` | `rfm_manager.cpp:69-75,131-132 (requires in-DRAM RFM target selection)` |

## 3. Bảng A — Cấu hình KHÔNG cần sửa chip DRAM thương mại (`dram_support = none`)
| Category | N_RH | Scheme | dram_support | OK/Total | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| attack | 128 | Baseline | `none` | 4/4 | 1.0 | 0.0 | 0.3604 | 893.7994 | 0 | 6270 | 7624 |
| attack | 128 | BlockHammer | `none` | 4/4 | 1.0546 | 0.0 | 0.0447 | 64.3115 | 0 | 695 | 1385 |
| attack | 128 | PARA_ACT | `none` | 12/12 | 0.2607 | 0.02221 | 0.0866 | 902.3603 | 38060.5 | 329 | 658 |
| attack | 128 | Graphene_ACT | `none` | 4/4 | 0.9783 | 0.0 | 0.3438 | 893.9934 | 3662 | 130 | 254 |
| attack | 128 | Hydra_ACT | `none` | 4/4 | 0.8746 | 0.0 | 0.292 | 894.6389 | 4752.5 | 130 | 256 |
| attack | 128 | QShield | `none` | 4/4 | 0.795 | 0.0 | 0.2628 | 895.0836 | 19794 | 132 | 264 |
| attack | 128 | QShield_Integ | `none` | 4/4 | 0.2874 | 0.0 | 0.0917 | 902.1936 | 45800.5 | 622 | 1244 |
| attack | 256 | Baseline | `none` | 4/4 | 1.0 | 0.0 | 0.3604 | 893.7994 | 0 | 6270 | 7624 |
| attack | 256 | BlockHammer | `none` | 4/4 | 1.425 | 0.0 | 0.6064 | 2.2554 | 0 | 2870 | 5646 |
| attack | 256 | PARA_ACT | `none` | 12/12 | 0.4366 | 0.01903 | 0.1484 | 897.6819 | 27869.8 | 251 | 502 |
| attack | 256 | Graphene_ACT | `none` | 4/4 | 0.9973 | 0.0 | 0.3562 | 893.8561 | 1618 | 258 | 510 |
| attack | 256 | Hydra_ACT | `none` | 4/4 | 0.9362 | 0.0 | 0.3286 | 894.1156 | 2390.5 | 258 | 512 |
| attack | 256 | QShield | `none` | 4/4 | 0.8287 | 0.0 | 0.2792 | 894.7775 | 10975.5 | 83 | 146 |
| attack | 256 | QShield_Integ | `none` | 4/4 | 0.293 | 0.0 | 0.0959 | 901.497 | 25328.5 | 352 | 704 |
| attack | 512 | Baseline | `none` | 4/4 | 1.0 | 0.0 | 0.3604 | 893.7994 | 0 | 6270 | 7624 |
| attack | 512 | BlockHammer | `none` | 4/4 | 1.171 | 0.0 | 0.4606 | 3.904 | 0 | 5615 | 7609 |
| attack | 512 | PARA_ACT | `none` | 12/12 | 0.6191 | 0.0487 | 0.2157 | 895.5957 | 17690.3 | 160 | 320 |
| attack | 512 | Graphene_ACT | `none` | 4/4 | 0.9991 | 0.0 | 0.359 | 893.8173 | 767 | 514 | 1022 |
| attack | 512 | Hydra_ACT | `none` | 4/4 | 0.9828 | 0.0 | 0.3534 | 893.855 | 962 | 514 | 1024 |
| attack | 512 | QShield | `none` | 4/4 | 0.8454 | 0.0 | 0.2891 | 894.5963 | 6145.8 | 245 | 250 |
| attack | 512 | QShield_Integ | `none` | 4/4 | 0.2983 | 0.0 | 0.098 | 901.1863 | 13953.5 | 224 | 382 |
| attack | 1024 | Baseline | `none` | 4/4 | 1.0 | 0.0 | 0.3604 | 893.7994 | 0 | 6270 | 7624 |
| attack | 1024 | BlockHammer | `none` | 4/4 | 1.0319 | 0.0 | 0.3788 | 11.8553 | 0 | 6236 | 7596 |
| attack | 1024 | PARA_ACT | `none` | 12/12 | 0.7612 | 0.05196 | 0.27 | 894.6801 | 10294.2 | 313 | 318 |
| attack | 1024 | Graphene_ACT | `none` | 4/4 | 0.9991 | 0.0 | 0.3591 | 893.8143 | 369 | 1026 | 2046 |
| attack | 1024 | Hydra_ACT | `none` | 4/4 | 0.9949 | 0.0 | 0.3597 | 893.8138 | 440 | 1026 | 2048 |
| attack | 1024 | QShield | `none` | 4/4 | 0.8473 | 0.0 | 0.2933 | 894.5054 | 3663.8 | 437 | 473 |
| attack | 1024 | QShield_Integ | `none` | 4/4 | 0.2976 | 0.0 | 0.099 | 901.0038 | 7896.2 | 434 | 461 |
| mix4 | 128 | Baseline | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 128 | BlockHammer | `none` | 20/20 | 0.5944 | 0.0 | 0.4068 | 10.541 | 0 | 323 | 364 |
| mix4 | 128 | PARA_ACT | `none` | 60/60 | 0.3993 | 0.04991 | 0.3744 | 4.9269 | 45872.4 | 67 | 159 |
| mix4 | 128 | Graphene_ACT | `none` | 20/20 | 0.9685 | 0.0 | 0.8822 | 1.3069 | 940 | 128 | 224 |
| mix4 | 128 | Hydra_ACT | `none` | 20/20 | 0.8159 | 0.0 | 0.7543 | 1.8633 | 3125.3 | 128 | 172 |
| mix4 | 128 | QShield | `none` | 20/20 | 0.8552 | 0.0 | 0.7829 | 1.5042 | 10727 | 101 | 102 |
| mix4 | 128 | QShield_Integ | `none` | 20/20 | 0.4296 | 0.0 | 0.3976 | 4.1719 | 48548.1 | 1504 | 3010 |
| mix4 | 256 | Baseline | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 256 | BlockHammer | `none` | 20/20 | 0.9729 | 0.0 | 0.8872 | 1.3258 | 0 | 260 | 408 |
| mix4 | 256 | PARA_ACT | `none` | 60/60 | 0.5508 | 0.03118 | 0.5149 | 3.0144 | 22218.4 | 87 | 120 |
| mix4 | 256 | Graphene_ACT | `none` | 20/20 | 0.9969 | 0.0 | 0.9039 | 1.2705 | 125 | 254 | 390 |
| mix4 | 256 | Hydra_ACT | `none` | 20/20 | 0.8704 | 0.0 | 0.8018 | 1.6395 | 1664.3 | 220 | 318 |
| mix4 | 256 | QShield | `none` | 20/20 | 0.8854 | 0.0 | 0.8089 | 1.4607 | 5128.1 | 130 | 171 |
| mix4 | 256 | QShield_Integ | `none` | 20/20 | 0.4447 | 0.0 | 0.4128 | 3.9154 | 24406.1 | 711 | 1418 |
| mix4 | 512 | Baseline | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 512 | BlockHammer | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 512 | PARA_ACT | `none` | 60/60 | 0.6932 | 0.04318 | 0.6431 | 2.1134 | 10871.6 | 126 | 177 |
| mix4 | 512 | Graphene_ACT | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 512 | Hydra_ACT | `none` | 20/20 | 0.9099 | 0.0 | 0.8347 | 1.4895 | 688.6 | 330 | 497 |
| mix4 | 512 | QShield | `none` | 20/20 | 0.9028 | 0.0 | 0.8247 | 1.4262 | 2474.2 | 183 | 280 |
| mix4 | 512 | QShield_Integ | `none` | 20/20 | 0.4522 | 0.0 | 0.4201 | 3.7873 | 12493.5 | 359 | 718 |
| mix4 | 1024 | Baseline | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 1024 | BlockHammer | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 1024 | PARA_ACT | `none` | 60/60 | 0.8031 | 0.0346 | 0.7395 | 1.696 | 5404.1 | 155 | 227 |
| mix4 | 1024 | Graphene_ACT | `none` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 1024 | Hydra_ACT | `none` | 20/20 | 0.9433 | 0.0 | 0.8618 | 1.3835 | 99 | 512 | 727 |
| mix4 | 1024 | QShield | `none` | 20/20 | 0.9098 | 0.0 | 0.8301 | 1.4184 | 1203.2 | 261 | 423 |
| mix4 | 1024 | QShield_Integ | `none` | 20/20 | 0.4556 | 0.0 | 0.4235 | 3.7435 | 6585.9 | 749 | 1199 |
| single | 128 | Baseline | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 128 | BlockHammer | `none` | 21/21 | 0.7756 | 0.0 | 0.7756 | 3.0461 | 0 | 217 | 324 |
| single | 128 | PARA_ACT | `none` | 63/63 | 0.6692 | 0.01891 | 0.6692 | 1.8431 | 10942.8 | 60 | 141 |
| single | 128 | Graphene_ACT | `none` | 21/21 | 0.9844 | 0.0 | 0.9844 | 1.0176 | 275.8 | 128 | 180 |
| single | 128 | Hydra_ACT | `none` | 21/21 | 0.9303 | 0.0 | 0.9303 | 1.1307 | 782.1 | 127 | 130 |
| single | 128 | QShield | `none` | 21/21 | 0.9381 | 0.0 | 0.9381 | 1.0749 | 2592 | 82 | 98 |
| single | 128 | QShield_Integ | `none` | 21/21 | 0.5771 | 0.0 | 0.5771 | 1.9435 | 8019.4 | 568 | 1136 |
| single | 256 | Baseline | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 256 | BlockHammer | `none` | 21/21 | 0.9703 | 0.0 | 0.9703 | 1.053 | 0 | 246 | 281 |
| single | 256 | PARA_ACT | `none` | 63/63 | 0.7766 | 0.01119 | 0.7766 | 1.4281 | 5610.1 | 75 | 109 |
| single | 256 | Graphene_ACT | `none` | 21/21 | 0.9972 | 0.0 | 0.9972 | 1.0028 | 41.5 | 227 | 266 |
| single | 256 | Hydra_ACT | `none` | 21/21 | 0.9511 | 0.0 | 0.9511 | 1.0945 | 469.5 | 129 | 204 |
| single | 256 | QShield | `none` | 21/21 | 0.9545 | 0.0 | 0.9545 | 1.0524 | 1225.7 | 113 | 138 |
| single | 256 | QShield_Integ | `none` | 21/21 | 0.5888 | 0.0 | 0.5888 | 1.884 | 3932.5 | 278 | 556 |
| single | 512 | Baseline | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 512 | BlockHammer | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 512 | PARA_ACT | `none` | 63/63 | 0.8599 | 0.01147 | 0.8599 | 1.2141 | 2828.0 | 118 | 152 |
| single | 512 | Graphene_ACT | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 512 | Hydra_ACT | `none` | 21/21 | 0.9649 | 0.0 | 0.9649 | 1.0687 | 205.7 | 257 | 308 |
| single | 512 | QShield | `none` | 21/21 | 0.9631 | 0.0 | 0.9631 | 1.041 | 545.8 | 129 | 188 |
| single | 512 | QShield_Integ | `none` | 21/21 | 0.5948 | 0.0 | 0.5948 | 1.855 | 1929.1 | 503 | 504 |
| single | 1024 | Baseline | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 1024 | BlockHammer | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 1024 | PARA_ACT | `none` | 63/63 | 0.9148 | 0.0099 | 0.9148 | 1.1102 | 1450.4 | 164 | 218 |
| single | 1024 | Graphene_ACT | `none` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 1024 | Hydra_ACT | `none` | 21/21 | 0.9757 | 0.0 | 0.9757 | 1.0438 | 27.0 | 512 | 513 |
| single | 1024 | QShield | `none` | 21/21 | 0.9662 | 0.0 | 0.9662 | 1.0371 | 249.3 | 203 | 279 |
| single | 1024 | QShield_Integ | `none` | 21/21 | 0.597 | 0.0 | 0.597 | 1.8443 | 964.1 | 696 | 708 |

## 4. Bảng B — Cấu hình CẦN lệnh không chuẩn hoặc hỗ trợ trong chip DRAM (`vrr_non_jedec`, `in_dram`)
| Category | N_RH | Scheme | dram_support | OK/Total | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| attack | 128 | PARA | `vrr_non_jedec` | 12/12 | 0.6263 | 0.04409 | 0.1801 | 897.3815 | 12803.8 | 45 | 45 |
| attack | 128 | Graphene | `vrr_non_jedec` | 4/4 | 0.9871 | 0.0 | 0.3466 | 893.9839 | 910.5 | 127 | 253 |
| attack | 128 | Hydra | `vrr_non_jedec` | 4/4 | 0.9132 | 0.0 | 0.3069 | 894.4688 | 1231.8 | 127 | 253 |
| attack | 128 | PRAC | `in_dram` | 4/4 | 0.9513 | 0.0 | 0.3357 | 894.0422 | 839 | 5646 | 6968 |
| attack | 128 | RFM | `in_dram` | 4/4 | 0.7679 | 0.0 | 0.2632 | 894.932 | 2597.5 | 4570 | 5680 |
| attack | 256 | PARA | `vrr_non_jedec` | 12/12 | 0.7554 | 0.04417 | 0.2332 | 895.7634 | 8059.1 | 102 | 102 |
| attack | 256 | Graphene | `vrr_non_jedec` | 4/4 | 0.9971 | 0.0 | 0.3558 | 893.8648 | 397.2 | 255 | 509 |
| attack | 256 | Hydra | `vrr_non_jedec` | 4/4 | 0.9478 | 0.0 | 0.3316 | 894.1108 | 598 | 255 | 509 |
| attack | 256 | PRAC | `in_dram` | 4/4 | 0.9949 | 0.0 | 0.3526 | 893.9035 | 423 | 5948 | 7276 |
| attack | 256 | RFM | `in_dram` | 4/4 | 0.8667 | 0.0 | 0.3049 | 894.3535 | 1489.2 | 5282 | 6500 |
| attack | 512 | PARA | `vrr_non_jedec` | 12/12 | 0.8458 | 0.02756 | 0.2803 | 894.8206 | 4734.5 | 178 | 179 |
| attack | 512 | Graphene | `vrr_non_jedec` | 4/4 | 0.999 | 0.0 | 0.3588 | 893.8219 | 191.5 | 511 | 1021 |
| attack | 512 | Hydra | `vrr_non_jedec` | 4/4 | 0.983 | 0.0 | 0.3537 | 893.8522 | 240.5 | 511 | 1021 |
| attack | 512 | PRAC | `in_dram` | 4/4 | 0.9977 | 0.0 | 0.3569 | 893.8441 | 210 | 6102 | 7456 |
| attack | 512 | RFM | `in_dram` | 4/4 | 0.886 | 0.0 | 0.3143 | 894.2268 | 1226.5 | 5456 | 6680 |
| attack | 1024 | PARA | `vrr_non_jedec` | 12/12 | 0.914 | 0.03509 | 0.3123 | 894.3482 | 2669.8 | 311 | 329 |
| attack | 1024 | Graphene | `vrr_non_jedec` | 4/4 | 0.9995 | 0.0 | 0.3597 | 893.8078 | 92.2 | 1023 | 2045 |
| attack | 1024 | Hydra | `vrr_non_jedec` | 4/4 | 0.9944 | 0.0 | 0.359 | 893.8216 | 110.5 | 1023 | 2045 |
| attack | 1024 | PRAC | `in_dram` | 4/4 | 0.9989 | 0.0 | 0.3588 | 893.8176 | 101 | 6186 | 7544 |
| attack | 1024 | RFM | `in_dram` | 4/4 | 0.944 | 0.0 | 0.3352 | 894.0261 | 652.5 | 5832 | 7116 |
| mix4 | 128 | PARA | `vrr_non_jedec` | 60/60 | 0.6722 | 0.06148 | 0.6014 | 2.1323 | 10333.7 | 44 | 53 |
| mix4 | 128 | Graphene | `vrr_non_jedec` | 20/20 | 0.9895 | 0.0 | 0.8987 | 1.2785 | 232.2 | 127 | 217 |
| mix4 | 128 | Hydra | `vrr_non_jedec` | 20/20 | 0.8484 | 0.0 | 0.7809 | 1.6854 | 770.8 | 127 | 163 |
| mix4 | 128 | PRAC | `in_dram` | 20/20 | 0.98 | 0.0 | 0.8899 | 1.3002 | 69.8 | 264 | 420 |
| mix4 | 128 | RFM | `in_dram` | 20/20 | 0.8865 | 0.0 | 0.8072 | 1.4631 | 412.1 | 283 | 465 |
| mix4 | 256 | PARA | `vrr_non_jedec` | 60/60 | 0.7824 | 0.03776 | 0.706 | 1.695 | 5163.2 | 91 | 91 |
| mix4 | 256 | Graphene | `vrr_non_jedec` | 20/20 | 0.9991 | 0.0 | 0.9054 | 1.2696 | 31.2 | 254 | 394 |
| mix4 | 256 | Hydra | `vrr_non_jedec` | 20/20 | 0.8865 | 0.0 | 0.815 | 1.5713 | 409.3 | 232 | 317 |
| mix4 | 256 | PRAC | `in_dram` | 20/20 | 0.9992 | 0.0 | 0.9058 | 1.2688 | 4.6 | 270 | 433 |
| mix4 | 256 | RFM | `in_dram` | 20/20 | 0.9445 | 0.0 | 0.8585 | 1.3532 | 186.1 | 268 | 448 |
| mix4 | 512 | PARA | `vrr_non_jedec` | 60/60 | 0.8653 | 0.04491 | 0.7841 | 1.4827 | 2601.9 | 126 | 143 |
| mix4 | 512 | Graphene | `vrr_non_jedec` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 512 | Hydra | `vrr_non_jedec` | 20/20 | 0.9154 | 0.0 | 0.8393 | 1.458 | 170.1 | 307 | 492 |
| mix4 | 512 | PRAC | `in_dram` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 512 | RFM | `in_dram` | 20/20 | 0.9558 | 0.0 | 0.8678 | 1.3356 | 146.3 | 278 | 446 |
| mix4 | 1024 | PARA | `vrr_non_jedec` | 60/60 | 0.921 | 0.04242 | 0.8365 | 1.3775 | 1314.7 | 168 | 258 |
| mix4 | 1024 | Graphene | `vrr_non_jedec` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 1024 | Hydra | `vrr_non_jedec` | 20/20 | 0.9441 | 0.0 | 0.8626 | 1.3799 | 24.9 | 512 | 740 |
| mix4 | 1024 | PRAC | `in_dram` | 20/20 | 1.0 | 0.0 | 0.9063 | 1.268 | 0 | 265 | 441 |
| mix4 | 1024 | RFM | `in_dram` | 20/20 | 0.9801 | 0.0 | 0.8892 | 1.2956 | 64.5 | 268 | 422 |
| single | 128 | PARA | `vrr_non_jedec` | 63/63 | 0.7667 | 0.02029 | 0.7667 | 1.3932 | 2693.3 | 40 | 47 |
| single | 128 | Graphene | `vrr_non_jedec` | 21/21 | 0.9917 | 0.0 | 0.9917 | 1.0088 | 68.3 | 127 | 177 |
| single | 128 | Hydra | `vrr_non_jedec` | 21/21 | 0.9374 | 0.0 | 0.9374 | 1.106 | 194.8 | 126 | 126 |
| single | 128 | PRAC | `in_dram` | 21/21 | 0.9938 | 0.0 | 0.9938 | 1.0065 | 18.9 | 252 | 353 |
| single | 128 | RFM | `in_dram` | 21/21 | 0.9579 | 0.0 | 0.9579 | 1.0486 | 134.7 | 252 | 322 |
| single | 256 | PARA | `vrr_non_jedec` | 63/63 | 0.8488 | 0.0103 | 0.8488 | 1.2149 | 1386.1 | 81 | 89 |
| single | 256 | Graphene | `vrr_non_jedec` | 21/21 | 0.9982 | 0.0 | 0.9982 | 1.0018 | 10.8 | 223 | 266 |
| single | 256 | Hydra | `vrr_non_jedec` | 21/21 | 0.9561 | 0.0 | 0.9561 | 1.0794 | 117.3 | 128 | 202 |
| single | 256 | PRAC | `in_dram` | 21/21 | 0.999 | 0.0 | 0.999 | 1.001 | 2.5 | 251 | 347 |
| single | 256 | RFM | `in_dram` | 21/21 | 0.9801 | 0.0 | 0.9801 | 1.0214 | 61.9 | 252 | 352 |
| single | 512 | PARA | `vrr_non_jedec` | 63/63 | 0.9077 | 0.01089 | 0.9077 | 1.1153 | 702.5 | 146 | 176 |
| single | 512 | Graphene | `vrr_non_jedec` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 512 | Hydra | `vrr_non_jedec` | 21/21 | 0.9678 | 0.0 | 0.9678 | 1.0605 | 51.5 | 256 | 307 |
| single | 512 | PRAC | `in_dram` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 512 | RFM | `in_dram` | 21/21 | 0.9853 | 0.0 | 0.9853 | 1.0156 | 44.2 | 253 | 347 |
| single | 1024 | PARA | `vrr_non_jedec` | 63/63 | 0.9452 | 0.01017 | 0.9452 | 1.0626 | 361.4 | 192 | 225 |
| single | 1024 | Graphene | `vrr_non_jedec` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 1024 | Hydra | `vrr_non_jedec` | 21/21 | 0.976 | 0.0 | 0.976 | 1.0425 | 6.7 | 512 | 512 |
| single | 1024 | PRAC | `in_dram` | 21/21 | 1.0 | 0.0 | 1.0 | 1.0 | 0 | 251 | 350 |
| single | 1024 | RFM | `in_dram` | 21/21 | 0.9939 | 0.0 | 0.9939 | 1.0063 | 16.4 | 254 | 352 |

## 5. Kiểm tra hàng metadata của `QShield_Integ` (`Worst R1 > N_RH`)
- **Kiểm tra RTL**: Trong RTL thực tế (`rtl/top/axi_ddr5_mc_secure_top.sv:344-462` -> `rtl/frontend/axi_slave_frontend.sv:133,255` -> `rtl/frontend/addr_mapper_ddr5.sv:105` -> `rtl/top/axi_ddr5_mc_top.sv:1165-1210` -> `rtl/core/sdc_resilient_filter.sv:146`), yêu cầu metadata nội bộ (`id[3]=1`) đi qua đường nạp địa chỉ vật lý và `u_sdc_filter` hoàn toàn đồng nhất với yêu cầu người dùng — không có nhánh bỏ qua DRM.
- **Sửa lệch mô hình mô phỏng (`qshield_controller.cpp`)**: Bổ sung kiểm tra `is_drm_stall()`, `is_proq_blacklisted()`, `m_row_cooldown` trong `meta_filter` (khi `meta_bypass_drm=false`, mặc định) và bổ sung kiểm tra hàng đợi metadata trong `any_user_blocked_by_proq()`. Khắc phục triệt để trường hợp vi phạm trực tiếp trên hàng metadata `row 259` (CB region, `mix4/mix_X_5 @ N_RH=1024`).
- **Phát hiện thực nghiệm trên các ca còn lại (`27` ca sau sửa)**: Các ca còn lại tập trung ở hàng biên `row = 295` (khoảng cách `+3` từ hàng BMT Tree Node nóng `row 292`, tức `+1` từ hàng đích làm tươi nạn nhân `row 294`), bị nhiễu thứ cấp (Half-Double cascade) bởi chính các lệnh `ACT+PREpb` làm tươi nạn nhân (`source_id = -99`) của `row 292` vì cả RTL (`rtl/core/ddr5_cmd_engine.sv:1151-1156`) và mô hình Ramulator2 đều không đếm lại ACT làm tươi nạn nhân vào `u_sdc_filter`. Chi tiết đầy đủ từng ca nằm tại `reports/paper/perf/qshield_integ_meta_audit.json`.
