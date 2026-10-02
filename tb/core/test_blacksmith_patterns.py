#=============================================================================
# File:        test_blacksmith_patterns.py
# Description: Cocotb 2.1 Verification for Multi-Frequency / Non-Uniform Hammering Patterns
#              (Blacksmith IEEE S&P '22 Threat Model Defense)
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_hash_mode.value = 1       # Dual-Hash
    dut.cfg_sdc_thresh.value = 5       # Throttle on 5th activation
    dut.cfg_window_size.value = 500    # Epoch window size

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
async def test_blacksmith_frequency_sweep_mitigation(dut):
    """Verify that multi-frequency hammering (Blacksmith) cannot bypass rate pacing"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_sdc_thresh.value = 6

    target_row = 0x01E4D
    target_bg = 1
    target_bank = 2

    intervals = [1, 3, 2, 4, 1, 2, 5, 2] # Non-uniform frequency distribution
    throttled_count = 0

    for idx, gap in enumerate(intervals * 2):
        dut.i_cmd_valid.value = 1
        dut.i_cmd_id.value = idx & 0xF
        dut.i_cmd_bg.value = target_bg
        dut.i_cmd_bank.value = target_bank
        dut.i_cmd_row.value = target_row

        await RisingEdge(dut.clk)
        dut.i_cmd_valid.value = 0

        # Wait non-uniform interval
        for _ in range(gap):
            await RisingEdge(dut.clk)

        await Timer(100, unit="ps")
        if int(dut.o_cmd_throttled.value) == 1:
            throttled_count += 1

    assert throttled_count > 0, "Blacksmith multi-frequency attack completely evaded rate pacing!"
    dut._log.info(f"[PASS] Blacksmith multi-frequency pattern successfully paced: {throttled_count} throttles observed")

@cocotb.test()
async def test_many_sided_hammering_distribution(dut):
    """Verify many-sided hammering (up to 16 aggressor rows) correctly tracked by dual-hash filter"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_sdc_thresh.value = 4

    aggressors = [0x0010 + i * 4 for i in range(8)]
    aggressor_throttles = {row: 0 for row in aggressors}

    # Interleave accesses across all 8 aggressors in a round-robin attack
    for round_num in range(6):
        for row in aggressors:
            dut.i_cmd_valid.value = 1
            dut.i_cmd_bg.value = (row >> 2) & 0x7
            dut.i_cmd_bank.value = (row >> 1) & 0x3
            dut.i_cmd_row.value = row

            await RisingEdge(dut.clk)
            await Timer(100, unit="ps")

            if int(dut.o_cmd_throttled.value) == 1:
                aggressor_throttles[row] += 1

    dut.i_cmd_valid.value = 0
    await RisingEdge(dut.clk)

    # Every aggressor was accessed 6 times with thresh=4, so all should have been throttled
    total_throttled_rows = sum(1 for row, count in aggressor_throttles.items() if count > 0)
    assert total_throttled_rows == len(aggressors), \
        f"Some many-sided aggressors escaped throttling: {aggressor_throttles}"

    dut._log.info(f"[PASS] All {len(aggressors)} many-sided aggressors properly throttled under dual-hash tracking")
