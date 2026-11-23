# Q-Shield Verification, Testbench & Validation Suite

Toàn bộ môi trường kiểm chứng phần cứng của **Q-Shield Secure DDR5 Memory Controller**, kết hợp đa phương pháp: **Icarus Verilog 12**, **Cocotb 2.1 + Verilator 5.032**, **pyuvm 5.0.0**, **SystemVerilog Assertions (SVA)** và **SymbiYosys BMC/Cover**.

---

## 📁 Cấu trúc Thư mục Kiểm chứng (Verification Hierarchy)

```
tb/
├── frontend/                     # 1. AMBA AXI5/AXI4 Frontend & Address Mapping Suite
│   ├── test_frontend.py          # Cocotb: Kiểm thử bắt tay AXI5/AXI4, kiểm tra biên 4KB, chia burst, backpressure
│   ├── test_addr_mapper.py       # Cocotb: Ánh xạ địa chỉ xen kẽ Rank/BG/Bank/Row/Col theo chuẩn JEDEC DDR5
│   ├── tb_axi5_compliance.sv     # SystemVerilog: Kiểm chứng AMBA AXI5 Data Poisoning & ASIL-D Parity Protection
│   └── Makefile                  # Cocotb runner cho khối frontend
│
├── core/                         # 2. Core Security & Scheduling Engine Suite
│   ├── test_sdc_filter.py        # Cocotb: Bộ lọc băm đôi O(1) Dual-Hash, chống tràn và reset epoch tức thời kèm CoMeT (HPCA '24) Golden Model
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
├── top/                          # 4. Top-Level E2E, Integrity & Regression Suite
│   ├── tb_axi_ddr5_mc_top.sv     # Testbench chuẩn cho lõi chính axi_ddr5_mc_top (19 checks)
│   ├── tb_axi_ddr5_mc_secure_top.sv # Testbench chuẩn cho top bảo mật axi_ddr5_mc_secure_top (15 checks)
│   ├── tb_secure_top_integrity.sv   # Kiểm chứng toàn vẹn đầu-cuối BMT+MAC+XTS (279 FAST / 405 full checks)
│   ├── tb_sec_ddr5_controller_top.sv # Top DEMO tích hợp sớm (không dùng để công bố kết quả)
│   ├── test_top_e2e.py           # Cocotb: Kiểm thử E2E AXI5/AXI4 burst read/write & RowHammer
│   ├── test_semiconductor_lifecycle.py # Cocotb: Mô phỏng March C-, Own Address, stress PVT
│   └── Makefile                  # Cocotb runner cho khối top-level
│
├── memory/                       # 5. Physical Interface & Subchannel Suite (SV/Verilog)
│   ├── jedec_timing_checker.sv   # Bộ giám sát thời gian thực định thời JEDEC DDR5 (tRCD, tRP, tRAS, tCCD, tRRD, tRFC)
│   ├── tb_dfi_phy_adapter.sv     # Kiểm chứng giao diện DFI 5.0 PHY timing và cơ chế bắt tay
│   ├── tb_ddr5_subchannel_scheduler.sv # Kiểm chứng bộ điều phối hai kênh con độc lập 32-bit (Dual Subchannel)
│   └── tb_async_fifo_cdc.sv      # Kiểm chứng FIFO vượt miền xung nhịp bất đồng bộ (CDC Gray-code pointers)
│
├── bus/                          # 6. Host Bus Interconnect & Register Suite (SV/Verilog)
│   ├── tb_apb_csr_regs.sv        # Kiểm chứng bản đồ thanh ghi điều khiển APB4 CSR read/write
│   └── tb_axi4_slave_adapter.sv  # Kiểm chứng adapter chuyển đổi giao thức AMBA AXI5/AXI4 Slave
│
├── crypto/                       # 7. Hardware Cryptographic & Integrity Engine Suite (SV/Verilog)
│   ├── tb_aes_xts_pipe.sv        # Đường ống mã hóa 14-stage kép AES-256-XTS
│   ├── tb_qshield_xts_tweak_unit.sv # Kiểm chứng đơn vị tweak IEEE Std 1619 (2,048 KAT)
│   ├── tb_qshield_bmt_engine.sv  # Kiểm chứng động cơ Bonsai Merkle Tree (20,000+ ops)
│   ├── tb_qshield_meta_cache.sv  # Kiểm chứng bộ đệm metadata tin cậy (50,000 ops)
│   └── tb_aes_sbox_test.sv       # Kiểm chứng toán học hộp thế phi tuyến S-box trên trường GF(2^8)
│
├── findings/                     # 8. Suite tái hiện lỗi & kiểm tra hồi quy (15 checks: 4 demo open + guards)
├── uvm/                          # 9. Môi trường UVM-style pyuvm 5.0.0 với 3 mô hình vàng Python độc lập (23/23 checks)
└── corner_cases/                 # 10. Ma trận 26 ca góc cạnh (matrix.yaml)
```

---

## 🚀 Hướng dẫn Chạy Kiểm Thử (Execution Commands)

### 1. Chạy bộ kiểm thử Icarus Verilog chuẩn (Canonical Regression)
```bash
# Chạy một testbench đơn lẻ
python tools/run_one_tb.py tb_axi_ddr5_mc_top 600
python tools/run_one_tb.py tb_secure_top_integrity 600

# Chạy bộ tái hiện finding và guard (15 checks)
python tb/findings/run_findings.py

# Chạy toàn bộ hồi quy Icarus Verilog
python run_iverilog_regression.py --timeout 1800
```

### 2. Chạy môi trường pyuvm 5.0.0
```bash
python tb/uvm/run_uvm.py --env all --seeds 2
```

### 3. Chạy kiểm chứng hình thức (SymbiYosys BMC + Cover trong WSL)
```bash
sby -f formal/formal_integrity.sby      # Mô hình trừu tượng (abstract model, không instantiate RTL)
sby -f formal/formal_sec_lock.sby
sby -f formal/formal_scheduler_bank.sby
sby -f formal/formal_axi_protocol.sby
sby -f formal/formal_rob_retire.sby
```

### 4. Chạy bộ Cocotb + Verilator (trong WSL / Linux)
```bash
make sim -C tb/frontend
make sim -C tb/core
make sim -C tb/backend
make sim -C tb/top
```

---

## 📊 Tóm tắt Kết quả Kiểm chứng Hiện hành

Các số liệu dưới đây trích từ các lần chạy thực tế trên kho mã nguồn (xem `README.md` và `LIMITATIONS.md`):

| Nhóm kiểm thử | Top / Phạm vi | Kết quả thực đo | Ghi chú |
| :--- | :--- | :---: | :--- |
| **Lõi chuẩn (`axi_ddr5_mc_top`)** | `tb_axi_ddr5_mc_top` | `19/19 PASS` | Đường dữ liệu chính DDR5 |
| **Top bảo mật (`axi_ddr5_mc_secure_top`)** | `tb_axi_ddr5_mc_secure_top` | `15/15 PASS` | Lõi + cầu mã hóa AES-256-XTS |
| **Toàn vẹn đầu-cuối (BMT+MAC+XTS)** | `tb_secure_top_integrity` | `279/279` (`FAST`) / `405/405` (full) | Khớp 1:1 giao dịch AXI metadata (`83/131`) |
| **Finding & Guard Suite** | `tb/findings/run_findings.py` | `15/15 PASS` (`4/4` demo open tái hiện) | Cấm hồi quy các lỗi đã đóng |
| **pyuvm 5.0.0 (`tb/uvm`)** | `mc_env` (16) + `csr_env` (7) | `23/23 PASS` | Độ phủ trên các bin tự định nghĩa |
| **Cocotb + Verilator 5.032** | 24 stage (`T45`) | `23/24 PASS` | Stage 24 (`pyuvm`) phụ thuộc gói trong WSL |
| **SymbiYosys Formal (`formal/`)** | 5 suite BMC + Cover (`T61`) | `5/5 BMC` (`depth 15`), `5/5 Cover` (`17` traces) | `formal_integrity.sby` chạy trên mô hình trừu tượng |
| **Top demo (`sec_ddr5_controller_top`)** | `tb_sec_ddr5_controller_top` | `10 checks + 4 XFAIL` (DEMO) | Giữ lại để minh họa sớm; không dùng cho số liệu chính |
