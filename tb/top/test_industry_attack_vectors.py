# test_industry_attack_vectors.py
# Verification of Q-Shield resilience against ZenHammer, SledgeHammer, and Blacksmith attack patterns

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.aresetn_axi.value = 0
    dut.aresetn_ddr.value = 0
    
    dut.s_axi_awid.value    = 0
    dut.s_axi_awaddr.value  = 0
    dut.s_axi_awlen.value   = 0
    dut.s_axi_awsize.value  = 3
    dut.s_axi_awburst.value = 1
    dut.s_axi_awqos.value   = 0
    dut.s_axi_awvalid.value = 0
    
    dut.s_axi_wdata.value   = 0
    dut.s_axi_wstrb.value   = 0
    dut.s_axi_wlast.value   = 0
    dut.s_axi_wvalid.value  = 0
    
    dut.s_axi_bready.value  = 1
    
    dut.s_axi_arid.value    = 0
    dut.s_axi_araddr.value  = 0
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value   = 0
    dut.s_axi_arvalid.value = 0
    
    dut.s_axi_rready.value  = 1
    
    dut.cfg_is_ddr5.value      = 1
    dut.cfg_dual_hash_en.value = 1
    dut.cfg_rh_threshold.value = 6
    dut.cfg_window_size.value  = 80
    
    for _ in range(10):
        await RisingEdge(dut.clk_axi)
        
    dut.aresetn_axi.value = 1
    dut.aresetn_ddr.value = 1
    
    for _ in range(5):
        await RisingEdge(dut.clk_axi)

async def send_ar_transaction(dut, arid, addr, qos):
    dut.s_axi_arid.value    = arid
    dut.s_axi_araddr.value  = addr
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value   = qos
    dut.s_axi_arvalid.value = 1

    for _ in range(30):
        await RisingEdge(dut.clk_axi)
        if int(dut.s_axi_arready.value) == 1:
            dut.s_axi_arvalid.value = 0
            return True
    dut.s_axi_arvalid.value = 0
    return False

@cocotb.test()
async def test_zenhammer_multi_sided_defense(dut):
    """ZenHammer attack pattern: Multi-sided aggressor hammering across bank groups"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    dut.cfg_rh_threshold.value = 5
    dut.cfg_window_size.value  = 100

    # Xen-ke 2 hang tan cong kep (double-sided / multi-sided aggressors)
    aggressor_row_a = 0x0004_0000
    aggressor_row_b = 0x0004_2000

    for i in range(12):
        target = aggressor_row_a if (i % 2 == 0) else aggressor_row_b
        success = await send_ar_transaction(dut, arid=(i & 0x7), addr=target, qos=2)
        assert success, f"ZenHammer AR transaction {i} timed out"
        await RisingEdge(dut.clk_axi)

    for _ in range(60):
        await RisingEdge(dut.clk_axi)

    throttled = int(dut.o_throttled_events.value)
    dut._log.info(f"ZenHammer test completed: throttled_events = {throttled}")
    assert throttled > 0, "SDC filter failed to catch multi-sided ZenHammer pattern"

@cocotb.test()
async def test_sledgehammer_burst_defense(dut):
    """SledgeHammer attack pattern: Synchronized dense burst hammering"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    dut.cfg_rh_threshold.value = 4
    dut.cfg_window_size.value  = 60

    target_row = 0x0007_0000
    # Phat chuoi burst lien tuc khong bubble nham gay dot bien tan suat kich hoat
    for i in range(8):
        success = await send_ar_transaction(dut, arid=(i & 0x7), addr=target_row, qos=1)
        assert success, f"SledgeHammer burst beat {i} timed out"

    for _ in range(50):
        await RisingEdge(dut.clk_axi)

    throttled = int(dut.o_throttled_events.value)
    dut._log.info(f"SledgeHammer test completed: throttled_events = {throttled}")
    assert throttled > 0, "SDC filter failed to throttle synchronized SledgeHammer burst"

@cocotb.test()
async def test_blacksmith_frequency_modulation_and_qos_isolation(dut):
    """Blacksmith attack pattern: Frequency-modulated non-uniform intervals with concurrent high-QoS traffic"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    dut.cfg_rh_threshold.value = 5
    dut.cfg_window_size.value  = 120

    aggressor_row = 0x0009_0000
    benign_row    = 0x0001_8000  # Vung dia chi cua tien trinh lanh tinh

    # Mo phong chu ky tan cong Blacksmith voi khoang cach thay doi (1, 3, 2, 4 chu ky)
    intervals = [1, 3, 2, 4, 1, 2, 3, 1, 2, 1]
    for i, wait_cycles in enumerate(intervals):
        await send_ar_transaction(dut, arid=1, addr=aggressor_row, qos=2)
        for _ in range(wait_cycles):
            await RisingEdge(dut.clk_axi)

    # Tien trinh lanh tinh gui yeu cau uu tien cao (QoS=7) giua tam bao tan cong
    benign_success = await send_ar_transaction(dut, arid=6, addr=benign_row, qos=7)
    assert benign_success, "Benign high-QoS request was blocked or starved by attack traffic"

    for _ in range(60):
        await RisingEdge(dut.clk_axi)

    throttled = int(dut.o_throttled_events.value)
    dut._log.info(f"Blacksmith test completed: throttled_events = {throttled}")
    assert throttled > 0, "SDC filter failed to throttle frequency-modulated Blacksmith pattern"
