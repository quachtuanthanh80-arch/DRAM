# Makefile for Cocotb testing of axi_slave_frontend
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../../rtl/frontend/axi4_skid_buffer.sv
VERILOG_SOURCES += $(PWD)/../../rtl/frontend/axi_slave_frontend.sv

TOPLEVEL = axi_slave_frontend
MODULE = test_frontend

EXTRA_ARGS += --trace --trace-fst --trace-structs -Wno-DECLFILENAME -Wno-MULTITOP

include $(shell cocotb-config --makefiles)/Makefile.sim
