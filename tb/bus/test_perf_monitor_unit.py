# test_perf_monitor_unit.py
# Kiem tra bo giam sat hieu nang PMU 8 kenh dem su kien bao hoa tuong thich Intel PCM

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_perf_en.value = 0
    dut.cfg_counter_reset.value = 0
    dut.ev_act_cmd.value = 0
    dut.ev_rd_cmd.value = 0
    dut.ev_wr_cmd.value = 0
    dut.ev_bg_bypass.value = 0
    dut.ev_sdc_throttle.value = 0
    dut.ev_rowpress_alert.value = 0
    dut.ev_ecc_corrected.value = 0
    dut.ev_rob_stall.value = 0
    dut.i_pmu_reg_sel.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_pmu_event_counting(dut):
    """Kiem tra 8 kenh dem xung su kien giam sat phan cung thoi gian thuc"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_perf_en.value = 1
    await RisingEdge(dut.clk)

    # 1. Phat xung ACT 15 lan, RD 10 lan, WR 5 lan
    for _ in range(15):
        dut.ev_act_cmd.value = 1
        await RisingEdge(dut.clk)
        dut.ev_act_cmd.value = 0

    for _ in range(10):
        dut.ev_rd_cmd.value = 1
        await RisingEdge(dut.clk)
        dut.ev_rd_cmd.value = 0

    for _ in range(5):
        dut.ev_wr_cmd.value = 1
        await RisingEdge(dut.clk)
        dut.ev_wr_cmd.value = 0

    # 2. Phat xung an ninh & QoS: Throttled 8 lan, RowPress 3 lan, ECC 2 lan
    for _ in range(8):
        dut.ev_sdc_throttle.value = 1
        await RisingEdge(dut.clk)
        dut.ev_sdc_throttle.value = 0

    for _ in range(3):
        dut.ev_rowpress_alert.value = 1
        await RisingEdge(dut.clk)
        dut.ev_rowpress_alert.value = 0

    for _ in range(2):
        dut.ev_ecc_corrected.value = 1
        await RisingEdge(dut.clk)
        dut.ev_ecc_corrected.value = 0

    await RisingEdge(dut.clk)

    # 3. Kiem tra gia tri cac bo dem thong qua cong doc APB i_pmu_reg_sel
    expected = {0: 15, 1: 10, 2: 5, 3: 0, 4: 8, 5: 3, 6: 2, 7: 0}
    for idx, exp_val in expected.items():
        dut.i_pmu_reg_sel.value = idx
        await Timer(1, unit="ns")
        act_val = int(dut.o_pmu_reg_data.value)
        assert act_val == exp_val, f"Counter {idx} mismatch: exp={exp_val}, got={act_val}"

@cocotb.test()
async def test_pmu_reset(dut):
    """Kiem tra tinh nang xoa toan bo 8 thanh ghi dem ve 0 bang xung cfg_counter_reset"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_perf_en.value = 1
    dut.ev_act_cmd.value = 1
    dut.ev_rd_cmd.value = 1
    await RisingEdge(dut.clk)
    dut.ev_act_cmd.value = 0
    dut.ev_rd_cmd.value = 0
    await RisingEdge(dut.clk)

    # Kich hoat reset
    dut.cfg_counter_reset.value = 1
    await RisingEdge(dut.clk)
    dut.cfg_counter_reset.value = 0
    await RisingEdge(dut.clk)

    for idx in range(8):
        dut.i_pmu_reg_sel.value = idx
        await Timer(1, unit="ns")
        act_val = int(dut.o_pmu_reg_data.value)
        assert act_val == 0, f"Counter {idx} was not reset: got {act_val}"
