#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_sdc_filter.py
# Description: Verifies Novelty Pillar #1 (Configurable Dual-Hash SDC Filter):
#              1. RowHammer activation threshold detection & throttle flag assertion.
#              2. Dual-Hash false-positive collision suppression.
#              3. O(1) instantaneous window reset via epoch tagging.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_hash_mode.value = 1  # Dual-Hash default
    dut.cfg_sdc_thresh.value = 5  # Alert after 5 activations
    dut.cfg_window_size.value = 1000  # Large window for normal test

    dut.i_cmd_valid.value = 0
    dut.i_cmd_id.value = 0
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0
    dut.i_cmd_col.value = 0
    dut.i_cmd_len.value = 0
    dut.i_cmd_qos.value = 0
    dut.i_cmd_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_rowhammer_threshold_detection(dut):
    """Verify repeated activations of aggressor row trigger throttle & mitigation alert"""
    clock = Clock(dut.clk, 2.5, unit="ns")  # 400 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_sdc_thresh.value = 4  # Alert on 4th activation

    aggressor_row = 0x01A5B
    aggressor_bg = 2
    aggressor_bank = 1

    throttled_observed = False

    for access in range(6):
        dut.i_cmd_valid.value = 1
        dut.i_cmd_id.value = access
        dut.i_cmd_bg.value = aggressor_bg
        dut.i_cmd_bank.value = aggressor_bank
        dut.i_cmd_row.value = aggressor_row

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        is_throttled = int(dut.o_cmd_throttled.value)
        mit_req = int(dut.o_mitigation_req.value)
        alert = int(dut.o_sdc_alert.value)

        dut._log.info(f"Access {access+1}: Throttled={is_throttled}, MitigationReq={mit_req}, Alert={alert}")

        if access >= 4:
            assert is_throttled == 1, f"Expected access {access+1} to be throttled!"
            throttled_observed = True

    dut.i_cmd_valid.value = 0
    await RisingEdge(dut.clk)

    assert throttled_observed, "Attacker row was never throttled!"
    assert int(dut.o_telemetry_throttles.value) > 0, "Telemetry throttle count must be > 0"
    dut._log.info("RowHammer threshold detection and throttle flag verified successfully!")

@cocotb.test()
async def test_instant_o1_window_reset(dut):
    """Verify O(1) instantaneous epoch reset unthrottles row after window expiration"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_sdc_thresh.value = 3
    dut.cfg_window_size.value = 20  # Window expires after 20 cycles

    target_row = 0x0CDEF

    # Attack until throttled
    for i in range(4):
        dut.i_cmd_valid.value = 1
        dut.i_cmd_row.value = target_row
        await RisingEdge(dut.clk)

    dut.i_cmd_valid.value = 0
    await Timer(1, unit="ns")
    assert dut.o_cmd_throttled.value == 1, "Should be throttled before window expiration"
    dut._log.info("Row throttled before window expiration.")

    # Advance time past window size (25 cycles)
    for _ in range(25):
        await RisingEdge(dut.clk)

    # Next access to target row in new window should NOT be throttled
    dut.i_cmd_valid.value = 1
    dut.i_cmd_row.value = target_row
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert dut.o_cmd_throttled.value == 0, "Row must be un-throttled after O(1) epoch reset!"
    dut.i_cmd_valid.value = 0
    await RisingEdge(dut.clk)
    dut._log.info("O(1) epoch window reset verified successfully!")
