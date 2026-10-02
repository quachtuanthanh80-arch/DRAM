#=============================================================================
# File:        test_rowpress_dynamic.py
# Description: Cocotb 2.1 Verification for Dynamic RowPress Non-Linear Threshold Curves
#              Validates Linear, Quadratic, and Exponential dwell-time scaling
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CMD_NOP = 0
CMD_ACT = 1
CMD_PRE = 2
CMD_RD  = 3
CMD_WR  = 4

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_cmd_valid.value = 0
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_id.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0
    dut.i_cmd_col.value = 0
    dut.i_cmd_len.value = 0
    dut.i_cmd_tag.value = 0
    dut.i_cmd_is_mitigation.value = 0
    dut.cfg_rowpress_thresh.value = 25
    dut.cfg_rowpress_curve.value = 0
    dut.i_dram_abo_alert.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_linear_rowpress_curve_detection(dut):
    """Verify linear curve triggers RowPress alert after sustaining dwell time"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_rowpress_curve.value = 0 # Linear curve
    dut.cfg_rowpress_thresh.value = 20

    # Activate Bank 0, Row 0xABC
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0xABC
    dut.i_cmd_col.value = 0x00
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    # Wait and sustain the row open without precharge
    alert_seen = False
    for cycle in range(50):
        await RisingEdge(dut.clk)
        await Timer(100, unit="ps")
        if int(dut.o_rowpress_alert.value) == 1:
            alert_seen = True
            assert int(dut.o_rowpress_row.value) == 0xABC, "Mismatched alert row"
            dut._log.info(f"[PASS] Linear RowPress alert triggered at cycle {cycle + 1}")
            break

    assert alert_seen, "Linear RowPress alert failed to trigger within dwell window"

@cocotb.test()
async def test_quadratic_rowpress_curve_detection(dut):
    """Verify quadratic curve triggers earlier under long dwell time"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_rowpress_curve.value = 2 # Quadratic curve
    dut.cfg_rowpress_thresh.value = 25

    # Activate Bank 1, Row 0x789
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 1
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0x789
    dut.i_cmd_col.value = 0x00
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    alert_seen = False
    for cycle in range(40):
        await RisingEdge(dut.clk)
        await Timer(100, unit="ps")
        if int(dut.o_rowpress_alert.value) == 1:
            alert_seen = True
            assert int(dut.o_rowpress_row.value) == 0x789, "Mismatched alert row"
            dut._log.info(f"[PASS] Quadratic RowPress alert triggered at cycle {cycle + 1}")
            break

    assert alert_seen, "Quadratic RowPress alert failed to trigger"

@cocotb.test()
async def test_exponential_rowpress_curve_detection(dut):
    """Verify exponential curve enforces rapid alert triggering"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_rowpress_curve.value = 3 # Exponential curve
    dut.cfg_rowpress_thresh.value = 30

    # Activate Bank 2, Row 0xDEF
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 2
    dut.i_cmd_bank.value = 1
    dut.i_cmd_row.value = 0xDEF
    dut.i_cmd_col.value = 0x00
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    alert_seen = False
    for cycle in range(35):
        await RisingEdge(dut.clk)
        await Timer(100, unit="ps")
        if int(dut.o_rowpress_alert.value) == 1:
            alert_seen = True
            assert int(dut.o_rowpress_row.value) == 0xDEF, "Mismatched alert row"
            dut._log.info(f"[PASS] Exponential RowPress alert triggered at cycle {cycle + 1}")
            break

    assert alert_seen, "Exponential RowPress alert failed to trigger"
