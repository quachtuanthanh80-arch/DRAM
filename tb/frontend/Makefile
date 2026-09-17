# Makefile for Cocotb testing of axi_slave_frontend
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES += $(ROOT_DIR)/rtl/frontend/axi4_skid_buffer.sv
VERILOG_SOURCES += $(ROOT_DIR)/rtl/frontend/axi_slave_frontend.sv

TOPLEVEL = axi_slave_frontend
MODULE = test_frontend

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
