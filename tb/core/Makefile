# Makefile for Cocotb testing of sdc_resilient_filter
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES += $(ROOT_DIR)/rtl/core/sdc_resilient_filter.sv

TOPLEVEL = sdc_resilient_filter
MODULE = test_sdc_filter

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
