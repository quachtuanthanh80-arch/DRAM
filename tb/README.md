# Verification & Testbench Suite (10 Suites — 100% PASS)

Thư mục chứa toàn bộ môi trường kiểm chứng phần cứng toàn diện dựa trên **Cocotb 2.0 (Python)**, **SystemVerilog Assertions (SVA)** và **Self-Checking SystemVerilog Testbenches**.

## 📁 Cấu trúc Thư mục Kiểm chứng

```
tb/
├── cocotb/                   # Môi trường kiểm thử Cocotb 2.0 + Icarus Verilog
│   ├── riscv_isa/            # 1. RV32I ISA Compliance Suite (7 micro-programs)
│   │   ├── test_riscv_isa.py
│   │   └── run_tests.py
│   ├── hazard_unit/          # 2. Hazard & Forwarding Suite + SVA (13 test cases)
│   │   ├── test_hazard_unit.py
│   │   └── run_tests.py
│   ├── cpu_units/            # 3. CPU Core Units (Branch Comparator & RegFile - 8 cases)
│   │   ├── test_branch_cmp.py
│   │   ├── test_regfile.py
│   │   └── run_tests.py
│   ├── alu_top/              # 4. ALU Top Unit + alu_coverage.py (91.25% Coverage - 20 cases)
│   │   ├── test_alu_top.py
│   │   ├── alu_coverage.py
│   │   └── run_tests.py
│   ├── secure_mac/           # 5. Secure MAC Unit + mac_coverage.py (100% Coverage) + Fault Campaigns
│   │   ├── test_secure_mac.py
│   │   ├── mac_coverage.py
│   │   ├── run_mac_tests.py
│   │   ├── test_fault_campaign.py
│   │   ├── run_fault_campaign.py
│   │   ├── test_ai_inference_resilience.py
│   │   └── run_ai_resilience_test.py
│   ├── top_module/           # 6. System-Level SoC Testbench (4 cases)
│   │   ├── test_top_module.py
│   │   └── run_top_tests.py
│   └── common/               # 7. Bus Functional Model (BFM) cho SoC Bus
│       └── bfm_soc.py        # SoCBusMaster BFM Driver & Monitor
│
└── sv_tb/                    # SystemVerilog Testbenches truyền thống (Self-Checking)
    ├── tb_secure_mac.sv      # Direct SV Testbench với $fatal và rollback timing check
    └── tb_top_module.sv      # SoC Top SV Testbench với Memory Polling tự động
```

---

## 🚀 Hướng dẫn Chạy Kiểm thử

### 1. Chạy toàn bộ 10 Test Suites (Khuyến nghị)
```bash
python run_all_tests.py
```
*(Thời gian thực thi ~56 giây, tự động biên dịch và tạo báo cáo chất lượng tại `reports/master_verification_report.md`)*.

### 2. Kiểm tra Độ phủ Chức năng (Functional Coverage)
```bash
# Độ phủ Secure MAC (100% toán hạng và thặng dư)
python -m pytest tb/cocotb/secure_mac/mac_coverage.py

# Độ phủ ALU Control & Corner Cases (91.25%)
python -m pytest tb/cocotb/alu_top/alu_coverage.py
```

### 3. Chạy kiểm chứng SV Testbench thuần túy
```bash
# Kiểm tra trực tiếp SV Testbenches với Icarus Verilog
python tools/run_sv_tb.py
```
