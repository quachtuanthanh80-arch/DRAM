# Makefile for bus subsystem Cocotb testbenches
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 0
SIM_BUILD ?= sim_build_pmu

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/bus/perf_monitor_unit.sv
TOPLEVEL ?= perf_monitor_unit
MODULE ?= test_perf_monitor_unit

EXTRA_ARGS += -Wno-DECLFILENAME -Wno-MULTITOP -Wno-UNUSEDSIGNAL

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
