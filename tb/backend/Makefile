# Makefile for backend Cocotb testbenches
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 1

VERILOG_SOURCES ?= /mnt/d/RAM/rtl/backend/slack_aware_arbiter.sv
TOPLEVEL ?= slack_aware_arbiter
MODULE ?= test_slack_arbiter

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

include $(shell cocotb-config --makefiles)/Makefile.sim
