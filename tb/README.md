# Q-Shield Verification, Testbench & Validation Suite

Toàn bộ môi trường kiểm chứng phần cứng công nghiệp toàn diện của **Q-Shield Secure DDR5/DDR4 Memory Controller**, kết hợp đa phương pháp: **Cocotb 2.1 (Python)**, **SystemVerilog Assertions (SVA)**, **Verilator**, và **SymbiYosys Formal Proofs**.

---

## 📁 Cấu trúc Thư mục Kiểm chứng (Verification Hierarchy)

```
tb/
├── frontend/                     # 1. AXI4 Frontend & Address Mapping Suite
│   ├── test_frontend.py          # Cocotb: Kiểm thử bắt tay AXI4, kiểm tra biên 4KB, chia burst, backpressure
│   ├── test_addr_mapper.py       # Cocotb: Ánh xạ địa chỉ xen kẽ Rank/BG/Bank/Row/Col chuẩn JEDEC DDR5/DDR4
│   └── Makefile                  # Cocotb runner cho khối frontend
│
├── core/                         # 2. Core Security & Scheduling Engine Suite
│   ├── test_sdc_filter.py        # Cocotb: Bộ lọc băm đôi O(1) Dual-Hash, chống tràn và reset epoch tức thời
│   ├── test_qos_queue.py         # Cocotb: Hàng đợi QoS 8 Bank Group, ưu tiên lệnh và chống bỏ đói (Aging)
│   ├── test_rob.py               # Cocotb: Reorder Buffer 16-entry, khóa nguy cơ RAW và hoàn trả đúng thứ tự
│   └── Makefile                  # Cocotb runner cho khối core
│
├── backend/                      # 3. Backend Arbitration & JEDEC Command Suite
│   ├── test_slack_arbiter.py     # Cocotb: Bộ trọng tài ma trận nhận thức khe hở định thời (Slack Bypassing)
│   ├── test_cmd_engine.py        # Cocotb: Máy trạng thái FSM lệnh JEDEC DDR5 (tRP, tRCD, tCL, tCWL, tWR)
│   ├── test_ecc_scrubber.py      # Cocotb: Bộ quét dọn sửa lỗi tự trị SEC-DED (72, 64) Hamming
│   └── Makefile                  # Cocotb runner cho khối backend
│
├── top/                          # 4. Top-Level E2E & Semiconductor Lifecycle Suite
│   ├── test_top_e2e.py           # Cocotb: Kiểm thử toàn hệ thống End-to-End AXI4 burst read/write & RowHammer
│   ├── test_semiconductor_lifecycle.py # Cocotb: Mô phỏng vòng đời bán dẫn, March C-, Own Address, stress PVT
│   ├── tb_sec_ddr5_controller_top.sv   # Testbench SystemVerilog top-level tự kiểm tra (Self-Checking)
│   └── Makefile                  # Cocotb runner cho khối top-level
│
├── memory/                       # 5. Physical Interface & Subchannel Suite (SV/Verilog)
│   ├── tb_dfi_phy_adapter.sv     # Kiểm chứng giao diện DFI 5.0 PHY timing và cơ chế bắt tay
│   ├── tb_ddr5_subchannel_scheduler.sv # Kiểm chứng bộ điều phối hai kênh con độc lập 32-bit (Dual Subchannel)
│   └── tb_async_fifo_cdc.sv      # Kiểm chứng FIFO vượt miền xung nhịp bất đồng bộ (CDC Gray-code pointers)
│
├── bus/                          # 6. Host Bus Interconnect & Register Suite (SV/Verilog)
│   ├── tb_apb_csr_regs.sv        # Kiểm chứng bản đồ thanh ghi điều khiển APB4 CSR read/write
│   └── tb_axi4_slave_adapter.sv  # Kiểm chứng adapter chuyển đổi giao thức AMBA AXI4 Slave
│
└── crypto/                       # 7. Hardware Cryptographic Engine Suite (SV/Verilog)
    ├── tb_aes_xts_pipe.sv        # Đường ống mã hóa 14-stage kép AES-256-XTS bảo vệ dữ liệu subchannel
    └── tb_aes_sbox_test.sv       # Kiểm chứng toán học hộp thế phi tuyến S-box trên trường phức hợp GF(2^8)
```

---

## 🔬 Quy trình Kiểm chuẩn Vòng đời Bán dẫn 3 Giai đoạn (Industrial 3-Stage Lifecycle)

Q-Shield áp dụng quy trình kiểm chuẩn 3 giai đoạn mô phỏng quy trình kiểm tra chip thực tế từ trước sản xuất (Pre-Silicon) đến xuất xưởng (Post-Silicon):

```
+---------------------------------------------------------------------------------------------------+
|                        Q-SHIELD 3-STAGE LIFECYCLE VALIDATION WORKFLOW                             |
+---------------------------------+---------------------------------+-------------------------------+
| GIAI ĐOẠN 1: PRE-SILICON        | GIAI ĐOẠN 2: POST-SILICON       | GIAI ĐOẠN 3: PLATFORM         |
| Linting tĩnh (Verilator)        | Kiểm thử mảng nhớ March C-      | Mở rộng đa kênh (1 đến 8-CH)  |
| Chuẩn giao diện DFI 5.0 PHY     | Kiểm thử địa chỉ riêng (Own Addr)| Đối chuẩn kiến trúc SOTA      |
| Kiểm chứng hình thức (Formal)   | Quét lỗi SEC-DED ECC tự trị     | Đánh giá suy thoái PVT & Stress|
+---------------------------------+---------------------------------+-------------------------------+
```

---

## 🚀 Hướng dẫn Chạy Kiểm Thử (Execution Commands)

### 1. Chạy toàn bộ quy trình 3 giai đoạn tự động (Master Runner)
```bash
python tools/run_full_lifecycle_validation.py
```
*(Thực thi liên hoàn từ Linting RTL, kiểm thử DFI 5.0, mô phỏng March C-/ECC, đến đối chuẩn đa kênh và Ramulator2)*.

---

### 2. Chạy từng Test Suite Cocotb (Python 3.10+ & Cocotb 2.1+)

Bạn có thể chạy riêng từng thành phần bằng lệnh `make` tại thư mục tương ứng:

```bash
# Kiểm thử tầng giao tiếp Frontend & Address Mapping
make sim -C tb/frontend

# Kiểm thử bộ lọc bảo mật SDC, hàng đợi QoS và ROB
make sim -C tb/core

# Kiểm thử bộ trọng tài Timing Slack, FSM JEDEC và SEC-DED Scrubber
make sim -C tb/backend

# Kiểm thử tích hợp toàn hệ thống End-to-End AXI4
make sim -C tb/top

# Kiểm thử kiểm định vòng đời bán dẫn (March C-, Own Address, Aging)
make sim -C tb/top MODULE=test_semiconductor_lifecycle
```

---

### 3. Chạy kiểm chứng hình thức phần cứng (Formal Verification - SymbiYosys)

Chứng minh toán học tính đúng đắn, không xảy ra bế tắc (deadlock), không trôi dữ liệu (data integrity) và tuân thủ giao thức AXI4:
```bash
cd formal
sby -f formal_skid_buffer.sby   # Chứng minh Zero-Bubble & giới hạn dung lượng Skid Buffer
sby -f formal_sdc_filter.sby     # Chứng minh tính đơn điệu & reset O(1) của bộ lọc SDC
sby -f formal_rob.sby            # Chứng minh khóa nguy cơ RAW & hoàn trả đúng thứ tự
```

---

### 4. Chạy kiểm thử SystemVerilog Testbenches trực tiếp qua Verilator

```bash
# Kiểm tra DFI 5.0 PHY Adapter
verilator --binary --timing rtl/memory/dfi_phy_adapter.sv tb/memory/tb_dfi_phy_adapter.sv --top tb_dfi_phy_adapter -Wno-fatal
./obj_dir/Vtb_dfi_phy_adapter

# Kiểm tra đường ống mã hóa phần cứng AES-XTS
verilator --binary rtl/crypto/*.sv tb/crypto/tb_aes_xts_pipe.sv --top tb_aes_xts_pipe -Wno-fatal
./obj_dir/Vtb_aes_xts_pipe
```

---

## 📊 Bảng Tổng Hợp Kết Quả Kiểm Chứng Tích Hợp (11/11 Suites PASS)

| Test Suite | Module Mục Tiêu | Ca Kiểm Thử (Test Function) | Trạng Thái |
| :--- | :--- | :--- | :---: |
| **`tb/frontend`** | `axi_slave_frontend` | `test_reset_and_defaults` | **PASS** |
| | `axi_slave_frontend` | `test_ar_handshake_and_4kb_detection` | **PASS** |
| | `axi4_skid_buffer` | `test_skid_buffer_backpressure` | **PASS** |
| **`tb/core`** | `sdc_resilient_filter` | `test_rowhammer_threshold_detection` | **PASS** |
| | `sdc_resilient_filter` | `test_instant_o1_window_reset` | **PASS** |
| **`tb/backend`** | `qos_scheduler_queue` | `test_starved_priority_boost` | **PASS** |
| | `slack_aware_arbiter` | `test_bg_readiness_gating` | **PASS** |
| | `slack_aware_arbiter` | `test_opportunistic_slack_mitigation` | **PASS** |
| **`tb/top`** | `sec_ddr5_controller_top` | `test_axi_write_burst_e2e` | **PASS** |
| | `sec_ddr5_controller_top` | `test_axi_read_e2e_reorder_and_return` | **PASS** |
| | `sec_ddr5_controller_top` | `test_rowhammer_sdc_defense_e2e` | **PASS** |
