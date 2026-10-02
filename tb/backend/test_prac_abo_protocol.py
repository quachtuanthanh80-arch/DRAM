#=============================================================================
# File:        test_prac_abo_protocol.py
# Description: Cocotb 2.1 Verification for PRAC Alert-Back-Off (ABO) Protocol (JESD79-5B)
#              Verifies:
#              1. Alert-Back-Off response latency <= t_ABO_MAX (4 cycles)
#              2. Normal command queue gating during ABO alert
#              3. Telemetry counter monotonicity and clean resume
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

CMD_NOP = 0
CMD_ACT = 1
CMD_PRE = 2
CMD_RD  = 3
CMD_WR  = 4
CMD_REF = 5

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
    dut.cfg_rowpress_thresh.value = 5000
    dut.cfg_rowpress_curve.value = 0
    dut.i_dram_abo_alert.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_prac_abo_latency_bound(dut):
    """Verify DRAM ABO Alert asserts o_abo_active within t_ABO_MAX <= 4 cycles"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Initially, ABO must be inactive
    assert int(dut.o_abo_active.value) == 0, "ABO active unexpectedly high on reset"
    initial_cnt = int(dut.o_abo_alert_cnt.value)

    # Assert DRAM ABO Alert pin (ALERT_n asserted low, so i_dram_abo_alert is high)
    dut.i_dram_abo_alert.value = 1
    abo_detected = False
    cycles_to_abo = 0

    for c in range(4):
        await RisingEdge(dut.clk)
        await Timer(100, unit="ps")
        cycles_to_abo += 1
        if int(dut.o_abo_active.value) == 1:
            abo_detected = True
            break

    assert abo_detected, f"ABO alert not asserted within t_ABO_MAX=4 cycles (took > {cycles_to_abo})"
    dut._log.info(f"[PASS] ABO activated in {cycles_to_abo} cycle(s) (<= t_ABO_MAX=4)")
    assert int(dut.o_abo_alert_cnt.value) == initial_cnt + 1, "ABO alert counter did not increment"

@cocotb.test()
async def test_prac_abo_command_backoff(dut):
    """Verify that during active ABO alert, normal memory commands are throttled/backed-off"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Assert ABO Alert
    dut.i_dram_abo_alert.value = 1
    await RisingEdge(dut.clk)
    await Timer(100, unit="ps")
    assert int(dut.o_abo_active.value) == 1, "ABO failed to activate"

    # Attempt to issue regular read command
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 1
    dut.i_cmd_bank.value = 2
    dut.i_cmd_row.value = 0x555
    dut.i_cmd_col.value = 0x20
    dut.i_cmd_is_mitigation.value = 0

    # Under ABO backoff, normal user command must not be issued to DRAM
    for _ in range(5):
        await RisingEdge(dut.clk)
        await Timer(100, unit="ps")
        cmd = int(dut.o_dfi_cmd.value)
        assert cmd != CMD_ACT and cmd != CMD_RD and cmd != CMD_WR, \
            f"User command issued during active ABO back-off! (dfi_cmd={cmd})"

    dut._log.info("[PASS] Normal memory commands successfully backed off during ABO active")

@cocotb.test()
async def test_prac_abo_resume_cleanly(dut):
    """Verify that deasserting ABO alert allows clean command dispatch resumption"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Pulse ABO alert
    dut.i_dram_abo_alert.value = 1
    await RisingEdge(dut.clk)
    await Timer(100, unit="ps")
    assert int(dut.o_abo_active.value) == 1

    # Deassert ABO alert
    dut.i_dram_abo_alert.value = 0
    await RisingEdge(dut.clk)
    await Timer(100, unit="ps")
    assert int(dut.o_abo_active.value) == 0, "ABO active did not deassert after release"

    # Now issue normal command
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0x123
    dut.i_cmd_col.value = 0x08
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    # Engine must issue CMD_ACT cleanly
    await Timer(100, unit="ps")
    assert int(dut.o_dfi_cmd.value) == CMD_ACT, "Engine failed to issue ACT after ABO release"
    dut._log.info("[PASS] Clean command resumption after ABO deassertion verified")
