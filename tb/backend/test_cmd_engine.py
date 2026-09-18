#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_cmd_engine.py
# Description: Verifies ddr5_cmd_engine:
#              1. Row-Miss: Closed bank -> ACT -> tRCD -> RD.
#              2. Row-Hit: Open bank same row -> Immediate RD without PRE/ACT.
#              3. Row-Conflict: Open bank diff row -> PRE -> tRP -> ACT -> tRCD -> RD.
#              4. CAS Read Latency (tCL) and writeback return to ROB.
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

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_row_miss_activate_and_read(dut):
    """Verify Row-Miss triggers ACT, waits tRCD, then issues RD, followed by tCL writeback"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Issue Read to closed bank: BG 0, Bank 0, Row 0x100, Col 0x10
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0x100
    dut.i_cmd_col.value = 0x10
    dut.i_cmd_len.value = 0 # 1 beat
    dut.i_cmd_tag.value = 0x3
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    # In this cycle, engine must issue CMD_ACT
    await Timer(1, unit="ns")
    assert int(dut.o_dfi_cmd.value) == CMD_ACT, f"Expected CMD_ACT but got {int(dut.o_dfi_cmd.value)}"
    assert int(dut.o_dfi_bg.value) == 0
    assert int(dut.o_dfi_row.value) == 0x100
    dut._log.info("CMD_ACT issued successfully for Row-Miss")

    # Monitor progression until CMD_RD is issued
    rd_issued = False
    for cycle in range(12):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.o_dfi_cmd.value) == CMD_RD:
            rd_issued = True
            dut._log.info(f"CMD_RD issued after {cycle + 1} cycles (tRCD requirement met)")
            assert int(dut.o_dfi_col.value) == 0x10
            break

    assert rd_issued, "CMD_RD was not issued after tRCD delay!"

    # Wait for CAS Read Latency (tCL = 8 cycles) and check writeback to ROB
    wb_received = False
    for cycle in range(15):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.o_wb_valid.value) == 1:
            wb_received = True
            assert int(dut.o_wb_tag.value) == 0x3, f"Expected tag 0x3, got {int(dut.o_wb_tag.value)}"
            dut._log.info(f"Writeback arrived at ROB with tag {int(dut.o_wb_tag.value)} and data {hex(int(dut.o_wb_data.value))}")
            break

    assert wb_received, "Read writeback data did not arrive at ROB within expected CAS latency!"

@cocotb.test()
async def test_row_hit_direct_issue(dut):
    """Verify Row-Hit directly issues RD without re-activating the bank"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    # Bank 0 Row 0x100 was left open from previous test!
    # Wait until engine is ready
    while int(dut.o_engine_ready.value) == 0:
        await RisingEdge(dut.clk)

    # Issue Read to same bank and same open row: BG 0, Bank 0, Row 0x100, Col 0x20
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0x100
    dut.i_cmd_col.value = 0x20
    dut.i_cmd_len.value = 0
    dut.i_cmd_tag.value = 0x4
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    await Timer(1, unit="ns")
    # MUST directly issue CMD_RD! No CMD_ACT!
    assert int(dut.o_dfi_cmd.value) == CMD_RD, f"Expected immediate CMD_RD for Row-Hit, got {int(dut.o_dfi_cmd.value)}"
    assert int(dut.o_dfi_col.value) == 0x20
    dut._log.info("Immediate CMD_RD on Row-Hit verified successfully (Zero-Bubble ACT avoidance)!")

@cocotb.test()
async def test_row_conflict_precharge_and_activate(dut):
    """Verify Row-Conflict executes PRE -> tRP -> ACT -> tRCD -> RD"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    # Bank 0 is currently open to Row 0x100.
    # Target DIFFERENT row in same bank: Row 0x200
    while int(dut.o_engine_ready.value) == 0:
        await RisingEdge(dut.clk)

    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0x200 # DIFFERENT ROW!
    dut.i_cmd_col.value = 0x30
    dut.i_cmd_len.value = 0
    dut.i_cmd_tag.value = 0x5
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    # Step 1: Must issue CMD_PRE
    await Timer(1, unit="ns")
    assert int(dut.o_dfi_cmd.value) == CMD_PRE, f"Expected CMD_PRE on Row Conflict, got {int(dut.o_dfi_cmd.value)}"
    dut._log.info("Step 1: CMD_PRE issued on Row Conflict")

    # Step 2: Must wait tRP and issue CMD_ACT with new row 0x200
    act_issued = False
    for cycle in range(10):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.o_dfi_cmd.value) == CMD_ACT:
            act_issued = True
            assert int(dut.o_dfi_row.value) == 0x200, f"Expected Row 0x200, got {hex(int(dut.o_dfi_row.value))}"
            dut._log.info("Step 2: CMD_ACT issued for new row 0x200 after tRP")
            break

    assert act_issued, "CMD_ACT was not issued after tRP precharge delay!"

    # Step 3: Must wait tRCD and issue CMD_RD with Col 0x30
    rd_issued = False
    for cycle in range(12):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.o_dfi_cmd.value) == CMD_RD:
            rd_issued = True
            assert int(dut.o_dfi_col.value) == 0x30
            dut._log.info("Step 3: CMD_RD issued after tRCD delay")
            break

    assert rd_issued, "CMD_RD was not issued after tRCD delay on Row Conflict!"
    dut._log.info("Row-Conflict PRE -> ACT -> RD sequence verified successfully!")

@cocotb.test()
async def test_rowpress_detection(dut):
    """Verify RowPress detection fires alert when a bank remains open beyond threshold"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    dut.cfg_rowpress_thresh.value = 20 # Low threshold for simulation
    await reset_dut(dut)

    # Open bank: BG 1, Bank 2, Row 0x0ABC
    dut.i_cmd_valid.value = 1
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 1
    dut.i_cmd_bank.value = 2
    dut.i_cmd_row.value = 0x0ABC
    dut.i_cmd_col.value = 0x04
    dut.i_cmd_len.value = 0
    dut.i_cmd_tag.value = 0x7

    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    alert_seen = False
    for cycle in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        if int(dut.o_rowpress_alert.value) == 1:
            alert_seen = True
            assert int(dut.o_rowpress_bg.value) == 1
            assert int(dut.o_rowpress_bank.value) == 2
            assert int(dut.o_rowpress_row.value) == 0x0ABC
            assert int(dut.o_rowpress_alert_cnt.value) >= 1
            dut._log.info(f"RowPress attack alert fired at cycle {cycle}! Aggressor row: {hex(int(dut.o_rowpress_row.value))}")
            break

    assert alert_seen, "RowPress alert did not fire after keeping bank open > 20 cycles!"
    dut._log.info("RowPress attack detection verified successfully!")

