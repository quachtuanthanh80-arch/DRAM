# Makefile for Cocotb testing of axi_slave_frontend
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES += $(ROOT_DIR)/rtl/frontend/axi4_skid_buffer.sv
VERILOG_SOURCES += $(ROOT_DIR)/rtl/frontend/axi_slave_frontend.sv

TOPLEVEL = axi_slave_frontend
MODULE = test_frontend

EXTRA_ARGS += --trace --trace-fst --trace-structs -Wno-DECLFILENAME -Wno-MULTITOP

include $(shell cocotb-config --makefiles)/Makefile.sim
