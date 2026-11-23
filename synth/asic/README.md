# Q-Shield ASIC Design Enablement & Implementation Suite

> **Trạng thái hiện tại:** Tổng hợp và place-and-route ASIC (OpenROAD Nangate45 / PDK thương mại) **chưa được chạy** trên kho mã nguồn này. Các script dưới đây là mẫu hạ tầng chuẩn bị sẵn; mọi bảng GE/diện tích/công suất/$F_{max}$ ASIC trước đây đã bị rút lại vì không có log tổng hợp thật. Số liệu PPA phần cứng duy nhất đã đo hiện nay là số liệu sau Place & Route trên FPGA `xczu7ev` tại [`reports/paper/fpga/t89/fpga_ppa_summary.md`](../../reports/paper/fpga/t89/fpga_ppa_summary.md) và [`reports/paper/fpga/t92/fpga_ppa_summary.md`](../../reports/paper/fpga/t92/fpga_ppa_summary.md).

Thư mục này chứa hạ tầng chuẩn bị cho **ASIC Synthesis** và **Physical Design Flow** của bộ điều khiển bộ nhớ **Q-Shield DDR5 Memory Controller** (lõi chuẩn `axi_ddr5_mc_top` và top bảo mật `axi_ddr5_mc_secure_top`; lưu ý `sec_ddr5_controller_top` chỉ là top demo tích hợp sớm, không dùng cho báo cáo số liệu).

---

## 1. Cấu Trúc Thư Mục

```text
synth/asic/
├── constraints/
│   └── qshield_dual_clk.sdc          # Mẫu ràng buộc SDC dual-clock cũ (250 MHz / 400 MHz); RTL chuẩn hiện dùng 1 miền clock
├── scripts/
│   ├── filelist_dc.tcl               # Thứ tự biên dịch phân cấp các module RTL SystemVerilog
│   ├── run_dc_synthesis.tcl          # Synopsys Design Compiler synthesis script (chưa chạy trên RTL hiện hành)
│   └── extract_asic_metrics.py       # Python parser trích xuất PPA ra Terminal, JSON và LaTeX
├── openlane/
│   ├── config.json                   # Cấu hình mẫu OpenLane 2 / OpenROAD (chưa chạy)
│   └── pin_order.cfg                 # Ràng buộc hướng I/O pins (AXI ở West, DFI ở East)
├── innovus/
│   └── run_innovus_pnr.tcl           # Cadence Innovus flow script mẫu (chưa chạy)
├── reports/                          # Nơi lưu trữ báo cáo Area, Timing, Power, QoR, LaTeX
├── netlist/                          # Chứa gate-level netlists sau tổng hợp (.v)
└── outputs/                          # Chứa SDC, SDF, DDC, DEF, SPEF, GDSII
```

---

## 2. ASIC Synthesis với Synopsys Design Compiler (Mẫu tham khảo)

### Đặc thù kiến trúc:
- **Clock Domain**:
  - RTL chuẩn (`axi_ddr5_mc_top` và `axi_ddr5_mc_secure_top`) hoạt động trên **một miền xung nhịp duy nhất** với mục tiêu `400 MHz` (`T = 2.50 ns`); các cổng `clk_ddr`/`aresetn_ddr` chỉ giữ tương thích và không nối vào logic lõi.
  - File `constraints/qshield_dual_clk.sdc` (`250 MHz` / `400 MHz`) là mẫu cũ từ phiên bản demo dual-clock và cần cập nhật trước khi chạy tổng hợp ASIC thật.
- **Thư viện chuẩn (PDK)**:
  - Cấu hình mẫu hướng tới **Nangate 45nm Open Cell Library** (`NangateOpenCellLibrary_typical.db`) cho nghiên cứu học thuật (chưa có lần chạy và log thực tế trong kho này).
  - Hỗ trợ chuyển đổi nhanh sang TSMC 28nm HPC+ hoặc GF 22FDX bằng cách thay đổi biến `$TARGET_DB` trong `run_dc_synthesis.tcl`.

### Hướng dẫn chạy tổng hợp:
```bash
cd synth/asic/scripts
dc_shell -f run_dc_synthesis.tcl | tee dc_synth.log
```

### Bóc tách PPA tự động ra bảng LaTeX & JSON:
Sau khi Synopsys DC hoàn tất, chạy script trích xuất:
```bash
python synth/asic/scripts/extract_asic_metrics.py
```
*Kết quả sẽ tự động sinh:*
- Terminal Dashboard: Tóm tắt Area ($\mu\text{m}^2$), Gate Equivalent (GE), Fmax, Dynamic/Leakage Power.
- `reports/axi_ddr5_mc_top_asic_ppa_summary.json`
- `reports/axi_ddr5_mc_top_asic_ppa_summary.tex` (Sẵn sàng `\input{...}` vào paper LaTeX).

---

## 3. G2: Physical Design Flow

### Lựa chọn A: OpenLane 2 / OpenROAD (Mã nguồn mở)
Dành cho việc chạy trên Linux / WSL2 mà không cần commercial license:
```bash
cd synth/asic/openlane
openlane config.json
```
*Đặc tính cấu hình:*
- Floorplan: Core utilization 55%, Aspect Ratio 1.0 (hình vuông cân đối).
- Pin order: Chân AXI đặt cạnh Tây (West), chân DFI đặt cạnh Đông (East) tránh nghẽn routing.
- Clock Tree Synthesis: Đích nhắm độ lệch skew $< 50\,\text{ps}$.
- Chèn Antenna Diode tự động (Strategy 3).

### Lựa chọn B: Cadence Innovus (Thương mại / Viện nghiên cứu)
Dành cho máy chủ EDA có cài đặt Cadence Innovus:
```bash
cd synth/asic/innovus
innovus -files run_innovus_pnr.tcl -log innovus.log
```
*Quy trình thực thi 8 bước khép kín:*
1. **Init Design**: Nạp LEF, post-synth netlist, SDC constraints.
2. **Floorplan**: Margin $20\,\mu\text{m}$, gán vị trí chân I/O.
3. **Power Ring & Mesh (PDN)**: VDD/VSS core rings trên Metal 6/7, power stripes dọc.
4. **Placement**: Standard cell placement + Timing-driven pre-CTS optimization.
5. **CTS (CCOpt)**: Đồng bộ hóa 2 cây clock `clk_axi` và `clk_ddr`.
6. **NanoRoute**: Định tuyến chi tiết nhiều lớp kim loại (Metal 1-5), sửa lỗi ăng-ten.
7. **Signoff**: STA (Tempus), DRC/LVS, phân tích sụt áp IR-drop (Voltus).
8. **Stream-Out**: Xuất GDSII layout hoàn chỉnh cho chế tạo chip (tapeout).
