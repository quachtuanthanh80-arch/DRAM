# Makefile for Top-Level Cocotb E2E Verification
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 1

ROOT_DIR ?= $(abspath $(CURDIR)/../..)

VERILOG_SOURCES = \
    $(ROOT_DIR)/rtl/frontend/axi4_skid_buffer.sv \
    $(ROOT_DIR)/rtl/frontend/axi_slave_frontend.sv \
    $(ROOT_DIR)/rtl/frontend/wdata_buffer.sv \
    $(ROOT_DIR)/rtl/frontend/addr_mapper_ddr5.sv \
    $(ROOT_DIR)/rtl/cdc/rst_sync.sv \
    $(ROOT_DIR)/rtl/cdc/async_fifo_cdc.sv \
    $(ROOT_DIR)/rtl/core/sdc_resilient_filter.sv \
    $(ROOT_DIR)/rtl/core/qos_scheduler_queue.sv \
    $(ROOT_DIR)/rtl/core/reorder_buffer_rob.sv \
    $(ROOT_DIR)/rtl/backend/slack_aware_arbiter.sv \
    $(ROOT_DIR)/rtl/backend/ddr5_cmd_engine.sv \
    $(ROOT_DIR)/rtl/backend/ecc_scrubber.sv \
    $(ROOT_DIR)/rtl/top/axi_ddr5_mc_top.sv

TOPLEVEL ?= axi_ddr5_mc_top
MODULE ?= test_top_e2e

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
              -I$(ROOT_DIR)/rtl/frontend -I$(ROOT_DIR)/rtl/cdc -I$(ROOT_DIR)/rtl/core -I$(ROOT_DIR)/rtl/backend -I$(ROOT_DIR)/rtl/top

COCOTB_SHARE_DIR ?= $(shell cocotb-config --makefiles 2>/dev/null || python3 -m cocotb_tools.config --makefiles 2>/dev/null || python -m cocotb_tools.config --makefiles 2>/dev/null)
include $(COCOTB_SHARE_DIR)/Makefile.sim
