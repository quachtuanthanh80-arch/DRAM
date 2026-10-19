# Makefile for CXL.mem 3.0 Flit Expander Cocotb Testbench
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 0
SIM_BUILD ?= sim_build_cxl

ROOT_DIR ?= $(abspath $(CURDIR)/../../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/interfaces/cxl_mem_axi_shim.sv

TOPLEVEL ?= cxl_mem_axi_shim
MODULE ?= test_cxl_mem_expander

EXTRA_ARGS += -Wno-DECLFILENAME -Wno-MULTITOP -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
