# Makefile for Cocotb testing of sdc_resilient_filter
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../../rtl/core/sdc_resilient_filter.sv

TOPLEVEL = sdc_resilient_filter
MODULE = test_sdc_filter

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP

include $(shell cocotb-config --makefiles)/Makefile.sim
