#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_slack_arbiter.py
# Description: Verifies slack_aware_arbiter:
#              1. Multi-tier priority: Starved > Normal High-QoS > Throttled.
#              2. BG readiness gating: unready BG cannot win arbitration.
#              3. Opportunistic slack mitigation grant during idle cycles.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_cand_valid.value = 0
    dut.i_cand_id.value = 0
    dut.i_cand_is_write.value = 0
    dut.i_cand_bank.value = 0
    dut.i_cand_row.value = 0
    dut.i_cand_col.value = 0
    dut.i_cand_len.value = 0
    dut.i_cand_qos.value = 0
    dut.i_cand_throttled.value = 0
    dut.i_cand_starved.value = 0
    dut.i_cand_queue_idx.value = 0

    dut.i_bg_ready.value = 0xFF  # all 8 BGs ready initially
    dut.i_engine_ready.value = 1
    dut.i_slack_cycle.value = 0

    dut.i_mitigation_req.value = 0
    dut.i_mitigation_bg.value = 0
    dut.i_mitigation_bank.value = 0
    dut.i_mitigation_row.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_starved_priority_boost(dut):
    """Verify Starved candidate beats higher nominal QoS candidate"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # BG 0: Starved entry (QoS = 1, Starved = 1, ID = 0x5)
    # BG 1: High QoS entry (QoS = 15, Starved = 0, ID = 0xA)
    cand_valid = (1 << 0) | (1 << 1)
    cand_starved = (1 << 0)
    cand_throttled = 0
    cand_qos = (1 << 0) | (15 << 4) # BG0=1, BG1=15
    cand_id = (0x5 << 0) | (0xA << 4)

    dut.i_cand_valid.value = cand_valid
    dut.i_cand_starved.value = cand_starved
    dut.i_cand_throttled.value = cand_throttled
    dut.i_cand_qos.value = cand_qos
    dut.i_cand_id.value = cand_id

    await Timer(1, unit="ns")

    assert int(dut.o_cmd_valid.value) == 1
    assert int(dut.o_cmd_bg.value) == 0, f"Expected Starved BG 0 to win, but BG {int(dut.o_cmd_bg.value)} won!"
    assert int(dut.o_cmd_id.value) == 0x5
    dut._log.info("Starved candidate emergency priority verified successfully!")

@cocotb.test()
async def test_bg_readiness_gating(dut):
    """Verify candidate on an unready BG is blocked, letting ready BG win"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # BG 2: QoS = 15, but BG 2 is NOT ready (timing violation)
    # BG 3: QoS = 8, and BG 3 IS ready
    cand_valid = (1 << 2) | (1 << 3)
    cand_starved = 0
    cand_throttled = 0
    cand_qos = (15 << (2*4)) | (8 << (3*4))
    cand_id = (0x2 << (2*4)) | (0x3 << (3*4))

    dut.i_cand_valid.value = cand_valid
    dut.i_cand_starved.value = cand_starved
    dut.i_cand_throttled.value = cand_throttled
    dut.i_cand_qos.value = cand_qos
    dut.i_cand_id.value = cand_id

    # BG 2 is NOT ready!
    dut.i_bg_ready.value = 0xFF ^ (1 << 2)

    await Timer(1, unit="ns")

    assert int(dut.o_cmd_valid.value) == 1
    assert int(dut.o_cmd_bg.value) == 3, f"Expected ready BG 3 to win, but BG {int(dut.o_cmd_bg.value)} won!"
    assert int(dut.o_cmd_id.value) == 0x3
    dut._log.info("Bank Group timing readiness gating verified successfully!")

@cocotb.test()
async def test_opportunistic_slack_mitigation(dut):
    """Verify arbiter grants mitigation during idle slack cycle when no user command is pending"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # No user commands
    dut.i_cand_valid.value = 0
    # Command engine signals slack cycle
    dut.i_slack_cycle.value = 1
    dut.i_engine_ready.value = 1

    # Mitigation request for BG 4, Bank 1, Row 0x0123
    dut.i_mitigation_req.value = 1
    dut.i_mitigation_bg.value = 4
    dut.i_mitigation_bank.value = 1
    dut.i_mitigation_row.value = 0x0123

    await Timer(1, unit="ns")

    assert int(dut.o_mitigation_grant.value) == 1, "Expected mitigation grant to be asserted!"
    assert int(dut.o_cmd_valid.value) == 1
    assert int(dut.o_cmd_is_mitigation.value) == 1
    assert int(dut.o_cmd_bg.value) == 4
    assert int(dut.o_cmd_row.value) == 0x0123
    dut._log.info("Opportunistic slack mitigation grant verified successfully!")
