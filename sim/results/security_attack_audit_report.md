# Q-Shield Master Hardware Security Audit Report

- **Execution Timestamp**: 2026-10-26 13:30:35 UTC
- **Git Commit SHA**: `1d21ae8ea4866712d68ca851322b6501803a3e70`
- **Overall Security Verdict**: **CERTIFIED_SECURE**

## 1. Multi-Tier Security Verification Matrix

| Tier | Level of Abstraction | Scenarios / Beats | Escaped Bit-Flips | Detection Rate | Benign FPR | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Tier 1** | Architectural Emulation | 8 Threat Traces | **0** | **100.0%** | **0.020%** | **PASS** |
| **Tier 1 (Fuzzer)** | Randomized Fuzzing Stream | 1,000,000 Beats | **0** | **100.0%** | **0.000%** | **PASS** |
| **Tier 2** | Synthesizable RTL (Iverilog) | 13 Hardware Vectors | **0** | **100.0%** | **0.000%** | **PASS** |
| **Tier 3** | Formal SVA (SymbiYosys) | 11 Safety Invariants (k=30) | **0** | **100.0%** | **0.000%** | **PASS** |

## 2. GTKWave Waveform Instrumentation

- **Waveform Artifact**: `waveform_security_attacks.vcd`
- **File Size**: 2.53 MB
- **Signals Tracked**: `clk_axi`, `clk_ddr`, `s_axi_arready`, `o_throttled_events`, `o_coordinated_throttle_active`, `o_tras_clamped_alert`, `s_axi_rresp`, `dfi_cmd`
