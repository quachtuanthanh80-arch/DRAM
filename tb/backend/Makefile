# Makefile for backend Cocotb testbenches
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 1

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES ?= $(ROOT_DIR)/rtl/backend/slack_aware_arbiter.sv
TOPLEVEL ?= slack_aware_arbiter
MODULE ?= test_slack_arbiter

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

include $(shell cocotb-config --makefiles)/Makefile.sim
