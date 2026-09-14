# Makefile for Top-Level Cocotb E2E Verification
TOPLEVEL_LANG ?= verilog
SIM ?= verilator
WAVES ?= 1

VERILOG_SOURCES = \
    /mnt/d/RAM/rtl/frontend/axi4_skid_buffer.sv \
    /mnt/d/RAM/rtl/frontend/axi_slave_frontend.sv \
    /mnt/d/RAM/rtl/frontend/wdata_buffer.sv \
    /mnt/d/RAM/rtl/frontend/addr_mapper_ddr5.sv \
    /mnt/d/RAM/rtl/cdc/rst_sync.sv \
    /mnt/d/RAM/rtl/cdc/async_fifo_cdc.sv \
    /mnt/d/RAM/rtl/core/sdc_resilient_filter.sv \
    /mnt/d/RAM/rtl/core/qos_scheduler_queue.sv \
    /mnt/d/RAM/rtl/core/reorder_buffer_rob.sv \
    /mnt/d/RAM/rtl/backend/slack_aware_arbiter.sv \
    /mnt/d/RAM/rtl/backend/ddr5_cmd_engine.sv \
    /mnt/d/RAM/rtl/backend/ecc_scrubber.sv \
    /mnt/d/RAM/rtl/top/axi_ddr5_mc_top.sv

TOPLEVEL ?= axi_ddr5_mc_top
MODULE ?= test_top_e2e

EXTRA_ARGS += --trace -Wno-DECLFILENAME -Wno-MULTITOP -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
              -I/mnt/d/RAM/rtl/frontend -I/mnt/d/RAM/rtl/cdc -I/mnt/d/RAM/rtl/core -I/mnt/d/RAM/rtl/backend -I/mnt/d/RAM/rtl/top

include $(shell cocotb-config --makefiles)/Makefile.sim
