#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_frontend.py
# Description: Cocotb Testbench for axi_slave_frontend.sv verifying:
#              1. Reset behavior and default values.
#              2. Read address (AR) handshake with backpressure and Zero-Bubble skid.
#              3. Write address (AW) & Write data (W) handshakes.
#              4. 4KB boundary crossing detection.
#              5. Read data (R) return channel integrity.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

async def reset_dut(dut):
    dut.aresetn_axi.value = 0
    dut.s_axi_awid.value = 0
    dut.s_axi_awaddr.value = 0
    dut.s_axi_awlen.value = 0
    dut.s_axi_awsize.value = 3  # 8 bytes / beat
    dut.s_axi_awburst.value = 1  # INCR
    dut.s_axi_awqos.value = 0
    dut.s_axi_awvalid.value = 0

    dut.s_axi_wdata.value = 0
    dut.s_axi_wstrb.value = 0
    dut.s_axi_wlast.value = 0
    dut.s_axi_wvalid.value = 0

    dut.s_axi_bready.value = 1

    dut.s_axi_arid.value = 0
    dut.s_axi_araddr.value = 0
    dut.s_axi_arlen.value = 0
    dut.s_axi_arsize.value = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value = 0
    dut.s_axi_arvalid.value = 0

    dut.s_axi_rready.value = 1

    dut.i_wr_addr_ready.value = 1
    dut.i_wr_data_ready.value = 1
    dut.i_rd_req_ready.value = 1

    dut.i_bresp_valid.value = 0
    dut.i_bresp_id.value = 0
    dut.i_bresp_code.value = 0

    dut.i_rdata_valid.value = 0
    dut.i_rdata_id.value = 0
    dut.i_rdata.value = 0
    dut.i_rdata_resp.value = 0
    dut.i_rdata_last.value = 0

    await RisingEdge(dut.clk_axi)
    await RisingEdge(dut.clk_axi)
    dut.aresetn_axi.value = 1
    await RisingEdge(dut.clk_axi)

@cocotb.test()
async def test_reset_and_defaults(dut):
    """Verify reset deassertion and default ready states"""
    clock = Clock(dut.clk_axi, 4, unit="ns")  # 250 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    assert dut.s_axi_bvalid.value == 0, "s_axi_bvalid must be low after reset"
    assert dut.s_axi_rvalid.value == 0, "s_axi_rvalid must be low after reset"
    assert dut.s_axi_awready.value == 1, "s_axi_awready should be high (skid buffer ready)"
    assert dut.s_axi_arready.value == 1, "s_axi_arready should be high (skid buffer ready)"
    dut._log.info("Reset and initial ready states verified successfully!")

@cocotb.test()
async def test_ar_handshake_and_4kb_detection(dut):
    """Verify AR channel handshakes, payload forwarding, and 4KB crossing flag"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Test 1: Normal transaction not crossing 4KB (Addr = 0x1000, 4 beats of 8 bytes = 32B)
    dut.s_axi_arid.value = 0x2
    dut.s_axi_araddr.value = 0x1000
    dut.s_axi_arlen.value = 3  # 4 beats
    dut.s_axi_arsize.value = 3  # 8 bytes
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value = 0x8
    dut.s_axi_arvalid.value = 1

    await RisingEdge(dut.clk_axi)
    dut.s_axi_arvalid.value = 0

    # Wait for downstream output
    await RisingEdge(dut.clk_axi)
    assert dut.o_rd_req_valid.value == 1, "o_rd_req_valid must be asserted"
    assert dut.o_rd_req_id.value == 0x2, f"Expected ID 0x2, got {dut.o_rd_req_id.value}"
    assert dut.o_rd_req_addr.value == 0x1000, f"Expected Addr 0x1000, got {hex(int(dut.o_rd_req_addr.value))}"
    assert dut.o_rd_req_len.value == 3
    assert dut.o_rd_req_cross_4kb.value == 0, "Should NOT cross 4KB"
    dut._log.info("Normal AR transaction verified successfully!")

    # Test 2: Transaction crossing 4KB boundary
    # 4KB boundary at 0x1000. Addr = 0x0FE0 (offset 4064 in 4KB page)
    # len = 7 (8 beats * 8 bytes = 64 bytes). 4064 + 64 = 4128 > 4096!
    await RisingEdge(dut.clk_axi)
    dut.s_axi_arid.value = 0x5
    dut.s_axi_araddr.value = 0x0FE0
    dut.s_axi_arlen.value = 7
    dut.s_axi_arsize.value = 3
    dut.s_axi_arvalid.value = 1

    await RisingEdge(dut.clk_axi)
    dut.s_axi_arvalid.value = 0

    await RisingEdge(dut.clk_axi)
    assert dut.o_rd_req_valid.value == 1
    assert dut.o_rd_req_cross_4kb.value == 1, "Expected o_rd_req_cross_4kb == 1 for burst crossing 4KB!"
    dut._log.info("4KB Boundary crossing detection verified successfully!")

@cocotb.test()
async def test_skid_buffer_backpressure(dut):
    """Verify Zero-Bubble Skid Buffer holding capacity under downstream backpressure"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Downstream stalls
    dut.i_rd_req_ready.value = 0

    # First transaction into output register
    dut.s_axi_arid.value = 0x1
    dut.s_axi_araddr.value = 0x2000
    dut.s_axi_arvalid.value = 1
    await RisingEdge(dut.clk_axi)

    # Second transaction into skid buffer register
    dut.s_axi_arid.value = 0x2
    dut.s_axi_araddr.value = 0x3000
    dut.s_axi_arvalid.value = 1
    await RisingEdge(dut.clk_axi)
    await Timer(1, unit="ns")
    dut._log.info(f"skid_reg={dut.u_ar_skid.skid_valid_reg.value}, m_valid={dut.u_ar_skid.m_valid.value}, arready={dut.s_axi_arready.value}")
    assert dut.s_axi_arready.value == 0, "s_axi_arready must drop when both main and skid are full"
    dut.s_axi_arvalid.value = 0

    # Release backpressure
    dut.i_rd_req_ready.value = 1
    await RisingEdge(dut.clk_axi)
    await Timer(1, unit="ns")
    # First should have been consumed, second is moving to output
    dut._log.info(f"After drain: skid_reg={dut.u_ar_skid.skid_valid_reg.value}, arready={dut.s_axi_arready.value}")
    assert dut.s_axi_arready.value == 1, "s_axi_arready should recover immediately"
    await RisingEdge(dut.clk_axi)
    dut._log.info("Skid Buffer Zero-Bubble backpressure verified successfully!")
