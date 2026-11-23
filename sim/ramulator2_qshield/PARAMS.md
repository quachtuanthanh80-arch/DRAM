# Q-Shield Ramulator2 Model Parameter Provenance (`sim/ramulator2_qshield/`)
Chức năng: Đối chiếu từng tham số mô hình Q-Shield, cấu hình DRAM DDR5 và các baseline với nguồn RTL và tài liệu chuẩn.

## 1. Tham số mô hình Q-Shield (`qshield_controller.cpp`) đối chiếu RTL

| Tham số Ramulator2 | Giá trị mặc định / dùng | Nguồn RTL (`file:dòng`) | Ghi chú đối chiếu |
|---|---|---|---|
| `sdc_thresh` | `{1024:127, 512:63, 256:31, 128:15}` | `rtl/core/sdc_resilient_filter.sv:26`, `rtl/core/adaptive_threshold_engine.sv:46-52`, `docs/security_bound.md:57-62` | Công thức `T_max = floor((N_RH - 2 - Λ) / (4R))` với `R=2, Λ=6` (đã đo ở T82/T86) |
| `table_entries` | `256` | `rtl/core/sdc_resilient_filter.sv:13`, `rtl/top/axi_ddr5_mc_top.sv:1163` | 256 bin mỗi bảng A và B |
| `dual_hash_en` | `true` | `rtl/core/sdc_resilient_filter.sv:23`, `rtl/top/axi_ddr5_mc_top.sv:1169` | Bật đồng thời bảng A và B |
| `pxor_mode` | `true` | `rtl/core/sdc_resilient_filter.sv:24`, `rtl/top/axi_ddr5_mc_top.sv:1170` | Dùng ma trận Toeplitz `pxor_hash_engine` |
| `pxor_seed_hex` | `"A5A55A5A01234567"` | `rtl/core/sdc_resilient_filter.sv:25`, `rtl/core/pxor_hash_engine.sv:15` | Bảng B dùng `~seed ^ 0xF0F00F0FAAAA5555` (`sdc_resilient_filter.sv:129`) |
| Hash PXOR bit matrix | `IDX1=(t*3+h*7)%64`, `IDX2=(t*5+h+13)%64` | `rtl/core/pxor_hash_engine.sv:25-27` | Cài đặt y hệt phép nhân bit-matrix trên thẻ 22-bit `{bg[2:0], bank[1:0], row[16:0]}` |
| Subtract-T on throttle | `cnt -= sdc_thresh` | `rtl/core/sdc_resilient_filter.sv:269-272` | Cơ chế T86 giữ phần dư của hàng va chạm bin; chỉ kích DRFM khi `will_throttle` (`:397-402`) |
| `refw_refs` | `8192` | `rtl/core/sdc_resilient_filter.sv:17,184-189` | Đảo bit epoch O(1) mỗi 8192 lần `REFab` (`tREFW = 32 ms`) |
| `window_size_ctrl_cycles` | `4096` (`16384` DRAM nCK) | `rtl/core/sdc_resilient_filter.sv:27,361-363` | Cửa sổ theo dõi đa bank SledgeHammer, quy đổi ×4 từ chu kỳ điều khiển 400 MHz sang DDR5-3200 CK |
| `multibank_thresh` | `2` | `rtl/core/sdc_resilient_filter.sv:29,368` | Đếm trên đủ 32 bank vật lý `{bg, bank}` (`:237,366`) |
| `blast_radius` | `2` (`R=2`, nạn nhân `±1, ±2`) | `rtl/top/axi_ddr5_mc_top.sv:1274-1275`, `rtl/backend/directed_refresh_manager.sv:16-17,441-518` | `cfg_victim2_en=1`, `cfg_victim3_en=0`; kẹp biên `[0, num_rows-1]` |
| `proq_depth` | `32` | `rtl/backend/directed_refresh_manager.sv:9` | Hàng đợi PROQ 32 mục, khử trùng lặp (`:354-368`) và chặn hàng người dùng `row` và `row ± 1` (`:235-255`) |
| `o_drm_stall` backpressure | `proq + 2*R > 32 \|\| alert_fifo >= 14` | `rtl/backend/directed_refresh_manager.sv:178`, `rtl/top/axi_ddr5_mc_top.sv:1189,1326` | Chặn `ACT` mới của người dùng khi PROQ/Alert FIFO gần đầy để không rơi cảnh báo |
| Victim refresh | `ACT -> tRAS -> PREpb` | `rtl/backend/ddr5_cmd_engine.sv:1151-1156` | Không nạp ACT giảm thiểu lại vào bộ lọc SDC (`docs/security_bound.md:122`) |
| `throttle_pace_clk` | `80` nCK (~1 `tRC`) | `rtl/core/sdc_resilient_filter.sv:55,387` | Pacing mềm (tăng 4× khi `coordinated_throttle_active`) |
| `raammt_thresh` | `32` | `rtl/backend/ddr5_cmd_engine.sv:99,946-954` | Bộ đếm ACT cuốn chiếu theo từng BG phát `RFMab` tự trị |
| `tras_max_ns` | `21937` (`8775` ctrl cyc @ 2.5 ns) | `rtl/top/axi_ddr5_mc_top.sv:187`, `rtl/backend/ddr5_cmd_engine.sv:77,1026` | Kẹp `tRAS(max)` cưỡng bức đóng hàng và kích làm tươi |
| `rowpress_thresh_ns` / `curve` | `12500` ns (`5000` cyc) / `0` | `rtl/backend/ddr5_cmd_engine.sv:42,74,190-226`, `rtl/top/axi_ddr5_mc_top.sv:1609-1610` | Ngưỡng tĩnh mặc định 5000 chu kỳ 400 MHz |
| `mc_sets` / `mc_ways` | `16` × `4` (64 dòng 64B, Tree-PLRU) | `rtl/crypto/qshield_meta_cache.sv:7-8,87-99` | Metadata cache tin cậy trên chip cùng thuật toán cập nhật PLRU 3-bit |
| `prot_lines` / `tree_levels` | `1048576` (`2^20`, 64 MiB) / `4` | `rtl/crypto/qshield_meta_layout.sv:8,34-86`, `docs/spec_integrity_integration.md:39-56` | Bố cục CB + ML + cây 8-ary 4 mức DRAM + `tree_root` trên chip |
| `crypto_extra_lat_clk` | `84` nCK (`52.5` ns) | `rtl/crypto/subchannel_aes_xts_pipe.sv:10`, `rtl/crypto/qshield_mac_unit.sv:7` | Độ trễ không suy đoán: 14 tầng AES-XTS + GF(2^128) MAC trước khi trả RDATA (`docs/spec_integrity_integration.md:103-104`) |

## 2. Đối chiếu cấu hình DRAM Ramulator2 (`DDR5_VRR`: `DDR5_16Gb_x4`, `DDR5_3200C`, 1 ch, 1 rank) với RTL

Preset gần nhất với bin thời gian của RTL trong `python/ramulator/dram/ddr5.py` là `DDR5_3200C` (tCK = `625 ps`, `1600 MHz` DRAM CK; tỷ lệ 4:1 so với `TCK_PS = 2500 ps` / `400 MHz` của `axi_ddr5_mc_top.sv`), dùng `DDR5_VRR` để có lệnh `VRR` cho các baseline (PARA, Graphene, Hydra). **Không khớp 100% ở mọi trường** — bảng dưới ghi rõ từng tham số và chỗ khác biệt:

| Tham số | RTL (`axi_ddr5_mc_top.sv` / `ddr5_jedec_bin_pkg.sv`) | Ramulator2 `DDR5_VRR` (`DDR5_16Gb_x4`, `DDR5_3200C`) | Khớp / Sai khác |
|---|---|---|---|
| Số kênh / Rank / BG / Bank | `1` ch / `1` rank / `8` BG / `4` bank (`32` bank, `axi_ddr5_mc_top.sv:14-17`) | `1` ch / `1` rank / `8` BG / `4` bank (`32` bank, `ddr5.py:375`) | Khớp `32` bank |
| `ROW_WIDTH` | `17` bit (`131,072` hàng, `axi_ddr5_mc_top.sv:18`) | `16` bit (`65,536` hàng, `ddr5.py:375`) | **Khác** (16Gb x4 JEDEC chuẩn có 16-bit row; ảnh hưởng địa chỉ row trên `64K`) |
| `tCK` (DRAM vs MC) | `TCK_PS = 2500 ps` (DFI 1:4 -> `625 ps` DRAM CK, `:28`) | `tCK_ps = 625 ps` (`ddr5.py:400`) | Khớp tỷ lệ DFI 1:4 |
| `tRCD` | `17,500 ps` (`7` ctrl = `28` nCK, `bin_pkg:7`) | `nRCD = 28` (`17,500 ps`, `ddr5.py:400`) | Khớp chính xác (`28` nCK) |
| `tRP` | `17,500 ps` (`7` ctrl = `28` nCK, `bin_pkg:8`) | `nRP = 28` (`17,500 ps`, `ddr5.py:400`) | Khớp chính xác (`28` nCK) |
| `tRAS` | `32,000 ps` (`13` ctrl = `52` nCK, `bin_pkg:9`) | `nRAS = 52` (`32,500 ps`, `ddr5.py:401`) | Khớp `nRAS = 52` |
| `tRC` | `49,500 ps` (`20` ctrl = `80` nCK, `bin_pkg:10`) | `nRC = 80` (`50,000 ps`, `ddr5.py:401`) | Khớp `nRC = 80` |
| `tWR` | `30,000 ps` (`12` ctrl = `48` nCK, `bin_pkg:17`) | `nWR = 48` (`30,000 ps`, `ddr5.py:401`) | Khớp chính xác |
| `tRTP` | `7,500 ps` (`3` ctrl = `12` nCK, `bin_pkg:18`) | `nRTP = 12` (`7,500 ps`, `ddr5.py:401`) | Khớp chính xác |
| `tCCD_S` / `tCCD_L` | `5,000 ps` (`2` ctrl = `8` nCK, `bin_pkg:14-15`) | `nCCDS = 8`, `nCCDL = 8` (`ddr5.py:402`) | Khớp chính xác |
| `tCCD_L_WR` | `20,000 ps` (`8` ctrl = `32` nCK, `bin_pkg:16`) | `nCCDL_WR = 32` (`dq=4`, `ddr5.py:223`) | Khớp chính xác (`dq=4` cho `32` nCK; `dq=8` cho `16` nCK) |
| `tRRD_S` / `tRRD_L` | `5,000 ps` (`2` ctrl = `8` nCK, `bin_pkg:11-12`) | `nRRDS = 8`, `nRRDL = 8` (`ddr5.py:160,214`) | Khớp chính xác |
| `tFAW` | `25,000 ps` (`10` ctrl = `40` nCK, `bin_pkg:13`) | `nFAW = 40` (`2KB` page `dq=4`, `ddr5.py:218`) | Khớp chính xác (`dq=4` cho page `2KB` -> `nFAW=40`; `dq=8` chỉ `32`) |
| `tWTR_S` / `tWTR_L` | `2,500 / 10,000 ps` (`1 / 4` ctrl = `4 / 16` nCK, `bin_pkg:19-20`) | `nWTRS = 4`, `nWTRL = 16` (`ddr5.py:402`) | Khớp chính xác |
| `tRFC` / `tRFM` | `295,000 ps` (`118` ctrl = `472` nCK, `bin_pkg:21-23`) | `nRFC = nRFM = 471` (`294,375 ps`, `ddr5.py:236,275`) | Gần khớp (làm tròn JESD `0.997` trong Ramulator2 cho `471` vs `472`) |
| `tREFI` | `3,900,000 ps` (`1560` ctrl = `6240` nCK, `bin_pkg:24`) | `nREFI = 6240` (`3,900,000 ps`, `ddr5.py:246`) | Khớp chính xác |
| `tCL` / `tCWL` | `DFI_RDLAT=8, DFI_WRLAT=9` (gồm PHY/pipe lõi, `axi_ddr5_mc_top.sv:24-26`) | `nCL = 28`, `nCWL = 26` (`ddr5.py:400-401`) | Khác phạm vi đo (DRAM pin-level vs DFI controller-level; `28` vs `8*4=32` nCK) |

Lý do chọn `DDR5_16Gb_x4` + `DDR5_3200C`: ngoài `nFAW=40` (`25 ns`) và `nCCDL_WR=32` (`20 ns`) chỉ khớp khi `dq=4`, toàn bộ bin `nRCD=28, nRP=28, nRAS=52, nRC=80, nCL=28, nCWL=26` của `DDR5_3200C` khớp `ddr5_jedec_bin_pkg.sv:27` ("bin 3200C") và `axi_ddr5_mc_top.sv:28-46`.

## 3. Công thức hiệu chuẩn baseline cho `N_RH ∈ {1024, 512, 256, 128}`

- `Baseline`: `GenericDDR` + `FRFCFS` + `AllBank` + `Open` (không giảm thiểu).
- `PARA`: `threshold = 1 - (1e-15)^(1/N_RH)` -> `{1024: 0.033196, 512: 0.065290, 256: 0.126227, 128: 0.236451}`, 3 seed `{123, 456, 789}`.
- `Graphene`: `activation_threshold = N_RH / 2` (`{512, 256, 128, 64}`), `reset_period_ns = 32000000`, `num_table_entries = ceil((32000000 / 50) / (N_RH / 2)) - 1` (`{1249, 2499, 4999, 9999}`).
- `Hydra`: `hydra_tracking_threshold = N_RH / 2`, `hydra_group_threshold = max(16, int(0.8 * (N_RH / 2)))`, `hydra_row_group_size = 128`, `hydra_reset_period_ns = 32000000`, `hydra_rcc_num_per_rank = 4096`.
- `BlockHammer`: `bf_trefw = 32000000`, `bf_len_epoch = 32000000`, `bf_trc = 50`, `bf_num_rh = N_RH`, `bf_ctr_thresh = N_RH / 2`, `bf_ctr_count = 1024`, `bf_num_hashes = 4`, `bf_num_filters = 2`.
- `PRAC`: `abo_threshold = N_RH / 2`, `abo_act_ns = 180`, `abo_recovery_refs = 4`, `abo_delay_acts = 4`.
- `RFM`: `RFMManager(rfm_mode="ab", rfm_thresh={1024:80, 512:40, 256:32, 128:16}[N_RH])`.
- `QShield`: `sdc_thresh = {1024:127, 512:63, 256:31, 128:15}[N_RH]`, `blast_radius = 2`, `raammt_thresh = 32`, `integrity_en = False`.
- `QShield_Integ`: như `QShield` nhưng `integrity_en = True`, `mc_sets = 16`, `mc_ways = 4`, `tree_levels = 4`, `crypto_extra_lat_clk = 84`.

## 4. Ghi chú overlay tối thiểu và giới hạn mô hình

- **Bản vá tương thích `all_bank.cpp` (2 dòng):** `sim/ramulator2_qshield/src/ramulator/controller/refresh/impl/all_bank.cpp` thêm `{"DDR4_VRR", "Rank"}` và `{"DDR5_VRR", "Rank"}` vào `all_bank_refresh_scopes` vì upstream commit `72427a1` bỏ sót hai tên chuẩn `*_VRR` trong `AllBankRefresh::init()`.
- **Không sao chép diff cục bộ trong `~/ramulator2`:** Theo `build/ramulator2_local_ref.diff`, các thay đổi cục bộ cũ ở `~/ramulator2` (`blockhammer_controller.cpp` và file `qshield_controller.cpp` cũ) không được chép vào overlay. Thay vào đó, toàn bộ ma trận chạy chung frontend `BHO3` để dùng nguyên vẹn `blockhammer_controller.cpp` của upstream `72427a1`, còn `qshield_controller.cpp` được viết mới khớp RTL.
- **Tương tác RowPress / `tRAS(max)` dưới `AllBankRefresh`:** Với chế độ làm tươi `AllBankRefresh` chuẩn (`tREFI = 3.9 us = 6240 nCK`, không dời refresh), mọi hàng mở đều bị `REFab` đóng cưỡng bức tối đa sau `3.9 us`. Do đó ngưỡng mặc định của RTL (`rowpress_thresh_ns = 12500 ns`, `rowpress_curve = 0`, `tras_max_ns = 21937 ns`) không tự kích hoạt dưới `tREFI` chuẩn; giữ nguyên tham số RTL để phản ánh đúng phần cứng. Khi bật `ref_postpone_max = 4` (khớp `MAX_POSTPONE = 4` trong `rtl/backend/ddr5_cmd_engine.sv:39,364,976-993`), hàng mở liên tục được duy trì qua tối đa 4 chu kỳ `tREFI` (`6240` chu kỳ điều khiển > `5000`), kích hoạt đúng cảnh báo RowPress như RTL.
- **Năng lượng DRAM:** Upstream Ramulator2 commit `72427a1` không cung cấp mô hình năng lượng/công suất DRAM (`DRAM Energy: N/A`).

## 5. Tham số hiệu chuẩn kiểm chéo RTL–Ramulator2 (T81, `tools/crossval_ramulator_rtl.py`)

Mọi tham số hiệu chuẩn thêm trong T81 đều có giá trị mặc định bảo toàn 100% hành vi của T80 (`0` hoặc `false`), chỉ bật khi chạy `tools/crossval_ramulator_rtl.py` để khớp cấu hình vi kiến trúc của `axi_ddr5_mc_top.sv` + `ddr5_cmd_engine.sv` + `tb_bench_trace.sv`:

| Thành phần / Tham số | Giá trị T81 | Mặc định T80 | Nguồn RTL (`file:dòng`) | Lý do hiệu chuẩn |
|---|---|---|---|---|
| `QShieldAddrMapper` (`scramble_en`) | `false` (`base`) / `true` (`secure`) | `RoBaRaCoCh` | `rtl/frontend/domain_bank_coloring.sv:28,36`, `rtl/core/scarf_dram_randomizer.sv:29-166` | Khớp ánh xạ địa chỉ `{row[30:14], bg[8:6], bank[13:12], col[11:9,5:3]}` và mạng Feistel 10 vòng SCARF trên `{row, bg, bank}` |
| `QShieldTrace` (`max_outstanding_reads`, `max_outstanding_writes`, `issue_gap_fe_ticks`) | `19`, `8`, `2` (`5.0 ns`) | `N/A` (`BHO3`) | `rtl/top/axi_ddr5_mc_top.sv:20,1073,1075`, `tb/top/tb_bench_trace.sv:434-474` | Khớp độ sâu ROB (`ROB_DEPTH=16` + 3 tầng skid/mapper), `MAX_WR_TRACK=8` và nhịp phát lệnh AXI AR/AW 1 yêu cầu / 2 chu kỳ 400 MHz |
| `FRFCFSRowHit` scheduler | Bật cho T81 | `FRFCFS` | `rtl/core/qos_scheduler_queue.sv:74-103`, `rtl/backend/ddr5_cmd_engine.sv:437-445` | Giữ ưu tiên row-hit CAS đang chờ bus DQ thay vì để một lệnh row-miss mới hơn phát `PREpb` đóng mất hàng đang mở |
| `dq_cas_gap_{rd_rd,wr_wr,rd_wr,wr_rd}_clk` | `40, 40, 36, 72` nCK (`10, 10, 9, 18` ctrl cyc) | `0` | `rtl/backend/ddr5_cmd_engine.sv:441-445,653,909-911` | Phản ánh độ chiếm dụng bus dữ liệu 64-bit 8-beat (`cmd_to_data_Gap=7` + 8-cycle burst + turnaround `RD<->WR`) của RTL |
| `rtl_rd_extra_lat_clk` | `48` nCK (`12.0 ns`) | `0` | `rtl/top/axi_ddr5_mc_top.sv:1050-1080`, `tb/common/dram_model.sv` | Bù chênh lệch `DFI_RDLAT=8` ctrl cyc (`32` nCK vs `nCL=28` pin-level), truyền burst 8 nhịp AXI R và đường ống ROB |
| `disable_wr_coalesce` / `sdc_count_requests` | `true` / `true` | `false` / `false` | `rtl/top/axi_ddr5_mc_top.sv:1176` | RTL không gộp write trùng địa chỉ trong WDB và đưa mọi giao dịch AXI hợp lệ (`sched_req_valid && sched_req_ready`) qua `u_sdc_filter` |
| `scrub_interval_ctrl_cycles` | `320` ctrl cyc | `0` | `rtl/top/axi_ddr5_mc_top.sv:1722`, `rtl/backend/directed_refresh_manager.sv:527-565` | Hiệu chuẩn chu kỳ phát tuần tra ECC nền khi kết hợp điều kiện rảnh sau `REFab`/`RFMab` hoặc khoảng lặng điều khiển để khớp số lượng patrol scrub (`~38–47` ACT) của RTL |
| `ref_postpone_max` + `REFab -> REFab` `nRFC` | `4` (`472` nCK spacing) | `0` | `rtl/backend/ddr5_cmd_engine.sv:39,364,976-993` | Cho phép hoãn tối đa 4 `REFab` khi còn hàng mở và cưỡng bức khoảng cách `118` ctrl cyc (`472` nCK `tRFC1`) giữa hai lệnh `REFab`/`RFMab` liên tiếp (bù thiếu sót `REFab -> REFab` trong `ddr5.py:88,95`) |
| `m_mit_act_reserved[b]` | Bật tự động khi `PREpb` giảm thiểu | Bật | `rtl/backend/ddr5_cmd_engine.sv:1118-1156` | Khóa bank `b` từ lúc phát `PREpb` của PROQ/scrub cho tới khi phát xong `ACT` giảm thiểu, ngăn user `FRFCFS` cướp bank gây livelock `PREpb <-> ACT` |
| `rtl_integrity_mode` & `rtl_ml_reenc_ack_overlap` | `true` & `false` (hậu T88) / `true` (trước T88) | `false` & `false` | `rtl/crypto/qshield_bmt_engine.sv:540-920`, `rtl/crypto/qshield_axi_crypto_bridge.sv:580-655,746-766,885-890` | Khớp máy trạng thái BMT/MC/ML Cache 8 dòng. Sau T88 (đã khóa đẩy lặp bằng `!ml/reenc_dram_wr_ack` và `!ml/reenc_dram_rd_valid_in`), RTL hậu-T88 khớp bản kiến trúc sạch `rtl_ml_reenc_ack_overlap = false` (`83 RD / 131 WR`, sai số `0.00%`); cờ `true` chỉ giữ lại để tái lập RTL cũ trước T88 (`112 RD / 164 WR`) |

## 6. Biến thể DRAM thương mại (`*_ACT`) và bảo vệ hàng metadata (T87)

- **Biến thể thương mại `ParaAct`, `GrapheneAct`, `HydraAct`** (`sim/ramulator2_qshield/src/ramulator/controller/plugin/impl/{para_act,graphene_act,hydra_act}.cpp`, dẫn xuất MIT từ `72427a1`, xem `NOTICE.md`):
  - Giữ nguyên thuật toán chọn nạn nhân, cấu trúc bảng và công thức hiệu chuẩn của `PARA`, `Graphene`, `Hydra` ở mục 3, nhưng thay lệnh không chuẩn `VRR` bằng chuỗi `ACT -> tRAS -> PREpb` (`blast_radius = 2`, 4 nạn nhân `row ± 1, row ± 2`, kẹp biên `[0, num_rows-1]`) gửi qua `priority_send`.
  - **Quy ước đếm ACT giảm thiểu:** Không đếm lại ACT làm tươi nạn nhân do chính plugin phát (`req.source_id == -99`), đồng nhất với quy ước của `QShieldController` (mục 1 "Victim refresh") để so sánh công bằng trên DRAM thương mại. Riêng `HydraAct` vẫn theo dõi ACT bảng RCT của chính nó trong `RCTCT` giống `Hydra` gốc.
- **Bảo vệ hàng metadata trong `QShieldController` (`meta_bypass_drm = false`, mặc định):**
  - Trong RTL (`rtl/top/axi_ddr5_mc_secure_top.sv:344-462` -> `rtl/frontend/axi_slave_frontend.sv:133,255` -> `rtl/frontend/addr_mapper_ddr5.sv:105` -> `rtl/top/axi_ddr5_mc_top.sv:1165-1210`), mọi giao dịch AXI metadata (`id = 8/9/10`, `id[3] = 1`) từ `u_crypto_bridge` đi thẳng vào `u_mc_core` và qua `u_sdc_filter` + `u_drm` (`o_drm_stall`, danh sách chặn PROQ, điều tiết pacing) giống hệt dữ liệu người dùng.
  - Ở bản T80, `qshield_controller.cpp` có đưa ACT metadata vào `sdc_on_act`, nhưng `meta_filter` bỏ qua `is_drm_stall()`, `is_proq_blacklisted()` và `m_row_cooldown`, đồng thời `any_user_blocked_by_proq()` chỉ kiểm tra bộ đệm người dùng -> khiến hàng metadata nóng tiếp tục bị kích hoạt làm tràn `m_alert_fifo`/`m_proq` (`Worst R1 > N_RH`). T87 sửa `meta_filter` và `any_user_blocked_by_proq()` khớp RTL (`meta_bypass_drm = false`).


