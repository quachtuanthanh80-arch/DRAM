# Makefile for PCIe / CXL.io CSR Bridge Cocotb Testbench
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 0
SIM_BUILD ?= sim_build_pcie

ROOT_DIR ?= $(abspath $(CURDIR)/../../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/interfaces/pcie_cxl_io_apb_shim.sv \
                   $(ROOT_DIR)/rtl/bus/apb_csr_regs.sv \
                   $(ROOT_DIR)/rtl/core/fault_hardened_csr.sv

TOPLEVEL ?= pcie_cxl_io_csr_top
MODULE ?= test_pcie_cxl_io_csr

EXTRA_ARGS += -Wno-DECLFILENAME -Wno-MULTITOP -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
