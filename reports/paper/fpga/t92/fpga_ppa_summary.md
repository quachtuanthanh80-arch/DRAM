# Q-Shield FPGA Post-Route Core Fmax Sweep Summary (T92)
- Ngày đo: 2026-11-22T20:27:28.239103
- Chip mục tiêu: `xczu7ev-ffvc1156-2-e` (Xilinx Zynq UltraScale+)
- Vivado: `Vivado v2026.1 (64-bit)` | Threads: `2` | Presynth DCP: `reports/paper/fpga/t89/core_2500ps_presynth.dcp`
- Git commit: `545c89161663f81216066d1a580e05ff671a1bd7` | RTL hash snapshot: `reports/paper/fpga/t92/RTL_HASHES.txt` (khớp 100% với T89 và không đổi sau mọi lượt route)
- Phương pháp đo công suất: vectorless report_power (Vivado default toggle rate 12.5%, no Simulation Activity File)

## 1. Bảng từng điểm quét của `axi_ddr5_mc_top`

| Tag | Nguồn | Period (ns) | Fmax (MHz) | WNS (ns) | TNS (ns) | WHS (ns) | Failing EP | LUTs (%) | FFs (%) | Power (W) | Elapsed (s) | Kết quả |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `core_confirmed` | T89 (dẫn chiếu) | `4.200` | `238.10` | `0.076` | `0.000` | `0.024` | `0` | `62623` (`27.18%`) | `44581` (`9.67%`) | `1.572` | `2671.24` | PASS |
| `core_4150ps` | T92 (mới) | `4.150` | `240.96` | `0.092` | `0.000` | `0.019` | `0` | `62677` (`27.20%`) | `44515` (`9.66%`) | `1.577` | 2405.0 | PASS |
| `core_4100ps` | T92 (mới) | `4.100` | `243.90` | `0.050` | `0.000` | `0.024` | `0` | `62671` (`27.20%`) | `44528` (`9.66%`) | `1.598` | 3505.7 | PASS |
| `core_4050ps` | T92 (mới) | `4.050` | `246.91` | `0.013` | `0.000` | `0.023` | `0` | `62901` (`27.30%`) | `44453` (`9.65%`) | `1.626` | 4036.0 | PASS |
| `core_4000ps` | T92 (mới) | `4.000` | `250.00` | `0.014` | `0.000` | `0.028` | `0` | `62620` (`27.18%`) | `44513` (`9.66%`) | `1.615` | 4899.2 | PASS |
| `core_3950ps` | T92 (mới) | `3.950` | `253.16` | `0.133` | `0.000` | `0.025` | `0` | `62585` (`27.16%`) | `44550` (`9.67%`) | `1.638` | 3992.7 | PASS |
| `core_3900ps` | T92 (mới) | `3.900` | `256.41` | `0.014` | `0.000` | `0.028` | `0` | `62699` (`27.21%`) | `44485` (`9.65%`) | `1.645` | 4236.9 | PASS |

## 2. Fmax xác nhận và đối chiếu T83 / T89
- **Fmax xác nhận (`WNS >= 0`, `0` failing EP, chu kỳ nhỏ nhất đạt):** **`256.41 MHz`** tại **`3.900 ns`** (`WNS = +0.014 ns`, `TNS = 0.000 ns`, `0` EP trượt, `LUT = 62699`, `FF = 44485`, `Power = 1.645 W`, nguồn: `t92_sweep`).
- **Điểm trượt kế bên:** Không có điểm trượt trong dải đã quét.
- **Tính đơn điệu:** Đơn điệu trong dải quét.

| Mốc | Period (ns) | Fmax (MHz) | WNS (ns) | Failing EP | LUTs | FFs | Power (W) | ΔFmax (T92 so với mốc) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| T83 (trước T86/T88) | `3.800` | `263.16` | `+0.024` | `0` | `63785` | `44243` | `1.618` | `-6.75 MHz` |
| T89 (nhảy bước 2.5→4.2) | `4.200` | `238.10` | `+0.076` | `0` | `62623` | `44581` | `1.572` | `+18.31 MHz` |
| **T92 (quét mịn bước 0.05 ns)** | **`3.900`** | **`256.41`** | **`+0.014`** | **`0`** | **`62699`** | **`44485`** | **`1.645`** | `0.00 MHz` |

- **Lưu ý nhân quả:** Không khẳng định nguyên nhân chênh lệch Fmax giữa T92 và T83 vì có 8 file `rtl/**` đổi giữa `rem/T83` và `HEAD` và chưa chạy ablation P&R từng thay đổi.
- **Phạm vi `axi_ddr5_mc_secure_top`:** Không quét lại vì T83 đã kẹp chặt giữa `4.100 ns` (`WNS = -0.005 ns`, `3` EP trượt) và `4.150 ns` (`WNS = +0.021 ns`, `0` EP) và T89 đã xác nhận lại đúng `4.150 ns` (`WNS = +0.018 ns`, `0` EP).
