# Makefile for Cocotb testing of bus_scrambler
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES += $(ROOT_DIR)/rtl/memory/bus_scrambler.sv

TOPLEVEL = bus_scrambler
MODULE = test_bus_scrambler

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
