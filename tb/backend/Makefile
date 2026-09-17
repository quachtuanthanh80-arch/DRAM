# Makefile for backend Cocotb testbenches
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 1

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/backend/slack_aware_arbiter.sv
TOPLEVEL ?= slack_aware_arbiter
MODULE ?= test_slack_arbiter

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
