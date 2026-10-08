# Q-Shield Toolchain & Dependency Versioning Matrix

This document provides exact version numbers for all electronic design automation (EDA) tools, compilers, simulators, standard cell libraries, and Python dependencies utilized in this research project.

---

## 1. Hardware Verification & Simulation Toolchains

| Tool / Software | Pinned Version | Minimum Version | Source / Vendor |
| :--- | :---: | :---: | :--- |
| **Icarus Verilog** | `12.0 (devel)` | `11.0` | Stephen Williams / Open Source |
| **Verilator** | `5.032` | `5.020` | Wilson Snyder / Veripool |
| **Cocotb** | `2.1.0` | `2.0.0` | Cocotb Development Team |
| **Cocotb-Bus** | `0.2.1` | `0.2.0` | Cocotb Ecosystem |
| **Cocotb-Coverage**| `1.2.0` | `1.1.0` | Cocotb Ecosystem |
| **SymbiYosys (SBY)**| `0.69` | `0.38` | YosysHQ GmbH |
| **Z3 SMT Solver** | `4.12.2` | `4.8.12` | Microsoft Research |
| **Boolector** | `3.2.2` | `3.2.0` | JKU Linz / Stanford |
| **Yices2** | `2.6.4` | `2.6.0` | SRI International |
| **Ramulator 2.0** | `2.0-ddr5-ext` | `2.0` | CMU SAFARI Research Group |

---

## 2. ASIC Synthesis & Standard Cell PDKs

| Process Design Kit (PDK) | Node Geometry | Standard Cell Library | Synthesis Tool | Target Voltage / Temp |
| :--- | :---: | :--- | :---: | :---: |
| **Nangate Open Cell** | 45nm Planar | NangateOpenCellLibrary_typical | Yosys 0.52 + OpenROAD | $1.10\text{V}, 25^\circ\text{C}$ |
| **SkyWater SKY130** | 130nm eFlash | sky130_fd_sc_hd (High Density) | Yosys 0.52 + OpenROAD | $1.80\text{V}, 25^\circ\text{C}$ |
| **IHP SG13G2** | 130nm BiCMOS | sg13g2_stdcell | Yosys 0.52 + OpenROAD | $1.20\text{V}, 25^\circ\text{C}$ |
| **GlobalFoundries GF180**| 180nm BCD | gf180mcu_fd_sc_mcu7t5v0 | Yosys 0.52 + OpenROAD | $5.00\text{V}, 25^\circ\text{C}$ |

---

## 3. FPGA Target Architecture

| Target FPGA Family | Part Number | Logic Cells | Look-Up Tables (LUTs) | Flip-Flops (FFs) | Synthesis Flow |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Xilinx Zynq-7000** | `XC7Z020-CLG400-1` | 85,000 | 53,200 | 106,400 | Vivado 2023.2 / Yosys |

---

## 4. Hardware Specifications & Protocols

| Protocol / Standard | Governing Body | Exact Specification Identifier |
| :--- | :--- | :--- |
| **AMBA AXI5 / AXI4** | ARM Ltd. | ARM IHI 0022H (Issue H) |
| **AMBA APB4** | ARM Ltd. | ARM IHI 0024C (Issue C) |
| **SystemVerilog RTL**| IEEE-SA | IEEE 1800-2017 Language Reference Manual |
| **JEDEC DDR5 SDRAM** | JEDEC Solid State Technology | JESD79-5C (DDR5 Specification) |
| **JEDEC DDR4 SDRAM** | JEDEC Solid State Technology | JESD79-4D (DDR4 Specification) |
| **DFI Interface** | DDR PHY Interface WG | DFI 5.0 Protocol Specification |

---

## 5. Python Environment & Library Pinning

```
python >= 3.10, < 3.14
numpy == 1.26.4
pandas == 2.2.1
matplotlib == 3.8.3
seaborn == 0.13.2
pyyaml == 6.0.1
tabulate == 0.9.0
```
