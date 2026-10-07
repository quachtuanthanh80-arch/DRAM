# Q-Shield ASIC Design Enablement & Implementation Suite

Thư mục này chứa toàn bộ hạ tầng phục vụ **ASIC Synthesis (G1)** và **Physical Design Flow (G2)** cho lõi điều khiển bộ nhớ **Q-Shield DDR5/DDR4 Memory Controller** (`axi_ddr5_mc_top` và `sec_ddr5_controller_top`).

---

## 1. Cấu Trúc Thư Mục

```text
synth/asic/
├── constraints/
│   └── qshield_dual_clk.sdc          # SDC constraints cho Dual-Clock (250 MHz / 400 MHz) & I/O delays
├── scripts/
│   ├── filelist_dc.tcl               # Thứ tự biên dịch phân cấp các module RTL SystemVerilog
│   ├── run_dc_synthesis.tcl          # Synopsys Design Compiler master synthesis script
│   └── extract_asic_metrics.py       # Python parser trích xuất PPA ra Terminal, JSON và LaTeX
├── openlane/
│   ├── config.json                   # Cấu hình OpenLane 2 / OpenROAD (Open-source P&R)
│   └── pin_order.cfg                 # Ràng buộc hướng I/O pins (AXI ở West, DFI ở East)
├── innovus/
│   └── run_innovus_pnr.tcl           # Cadence Innovus flow script (Commercial P&R)
├── reports/                          # Nơi lưu trữ báo cáo Area, Timing, Power, QoR, LaTeX
├── netlist/                          # Chứa gate-level netlists sau tổng hợp (.v)
└── outputs/                          # Chứa SDC, SDF, DDC, DEF, SPEF, GDSII
```

---

## 2. G1: ASIC Synthesis với Synopsys Design Compiler

### Đặc thù kiến trúc:
- **Dual Clock Domains**:
  - `clk_axi`: **250 MHz** ($T = 4.00\,\text{ns}$) phục vụ AMBA AXI4 Host Interface.
  - `clk_ddr`: **400 MHz** ($T = 2.50\,\text{ns}$) phục vụ DFI 5.0 / DDR5 Backend Memory Interface.
  - **Asynchronous Clock Grouping**: Đã khai báo `set_clock_groups -asynchronous` bảo vệ Gray-code CDC FIFOs.
- **Thư viện chuẩn (PDK)**:
  - Mặc định sử dụng **Nangate 45nm Open Cell Library** (`NangateOpenCellLibrary_typical.db`) phục vụ nghiên cứu học thuật và đối chiếu với các công trình IEEE SOTA.
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
