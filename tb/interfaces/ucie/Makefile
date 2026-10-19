# Makefile for UCIe 1.1 FDI AoU Bridge Cocotb Testbench
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 0
SIM_BUILD ?= sim_build_ucie

ROOT_DIR ?= $(abspath $(CURDIR)/../../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/interfaces/ucie_fdi_axi_shim.sv

TOPLEVEL ?= ucie_fdi_axi_shim
MODULE ?= test_ucie_aou_top

EXTRA_ARGS += -Wno-DECLFILENAME -Wno-MULTITOP -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
