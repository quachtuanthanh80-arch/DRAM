#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_addr_mapper.py
# Description: Verifies XOR-based Bank-Group Interleaved Address Mapping:
#              1. Sequential cacheline burst scattering across 8 DDR5 Bank Groups.
#              2. DDR4 mode (4 Bank Groups) configuration verification.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_is_ddr5.value = 1
    dut.i_req_valid.value = 0
    dut.i_req_id.value = 0
    dut.i_req_is_write.value = 0
    dut.i_req_addr.value = 0
    dut.i_req_len.value = 0
    dut.i_req_qos.value = 0
    dut.i_cmd_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_ddr5_xor_interleaving(dut):
    """Verify consecutive 64B cachelines scatter across different Bank Groups"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_is_ddr5.value = 1

    bg_history = []
    # Send 8 consecutive cachelines (stride = 64 bytes = 0x40)
    for i in range(8):
        dut.i_req_valid.value = 1
        dut.i_req_id.value = i
        dut.i_req_is_write.value = 0
        dut.i_req_addr.value = i * 0x40  # 0x0, 0x40, 0x80, 0xC0...
        dut.i_req_len.value = 0
        dut.i_req_qos.value = 0

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        bg_val = int(dut.o_cmd_bg.value)
        bg_history.append(bg_val)
        dut._log.info(f"Req {i}: Addr={hex(i*0x40)} -> BG={bg_val}, Bank={dut.o_cmd_bank.value}, Col={dut.o_cmd_col.value}")

    dut.i_req_valid.value = 0
    await RisingEdge(dut.clk)

    # In DDR5 XOR mapping, consecutive 64B accesses must have distinct BG indices
    unique_bgs = len(set(bg_history))
    dut._log.info(f"BG distribution across 8 consecutive cachelines: {bg_history} (Unique BGs: {unique_bgs}/8)")
    assert unique_bgs == 8, f"Expected all 8 consecutive 64B requests to hit 8 distinct Bank Groups, got {unique_bgs}"

@cocotb.test()
async def test_ddr4_mapping_constraint(dut):
    """Verify DDR4 mode constrains Bank Groups to [0..3]"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_is_ddr5.value = 0  # DDR4 mode

    for i in range(16):
        dut.i_req_valid.value = 1
        dut.i_req_addr.value = i * 0x40
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        bg_val = int(dut.o_cmd_bg.value)
        assert bg_val < 4, f"DDR4 mode produced BG={bg_val} >= 4!"

    dut.i_req_valid.value = 0
    dut._log.info("DDR4 4-Bank-Group constraint verified successfully!")
