# test_split_counter.py
# Kiem tra bang bo dem Major-Minor chong phat lai (Anti-Replay) va tinh nang phat tin hieu ma hoa lai trang (Reseed)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_req_valid.value = 0
    dut.i_req_is_write.value = 0
    dut.i_req_page_idx.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_counter_read_write_increment(dut):
    """Kiem tra thao tac ghi tang bo dem va thao tac doc giu nguyen gia tri bo dem"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    target_page = 5

    # 1. Lan doc dau tien: Bo dem ban dau phai bang 0
    dut.i_req_valid.value = 1
    dut.i_req_is_write.value = 0
    dut.i_req_page_idx.value = target_page
    await RisingEdge(dut.clk)
    dut.i_req_valid.value = 0
    await Timer(1, unit="ns")

    assert int(dut.o_counter_valid.value) == 1
    assert int(dut.o_unified_counter.value) == 0, f"Expected initial 0, got {int(dut.o_unified_counter.value)}"
    await RisingEdge(dut.clk)

    # 2. Thuc hien 5 thao tac ghi vao trang 5
    for i in range(5):
        dut.i_req_valid.value = 1
        dut.i_req_is_write.value = 1
        dut.i_req_page_idx.value = target_page
        await RisingEdge(dut.clk)
        dut.i_req_valid.value = 0
        await Timer(1, unit="ns")

        # Gia tri bo dem truoc khi tang tai chu ky nay
        assert int(dut.o_unified_counter.value) == i, f"Expected count {i}, got {int(dut.o_unified_counter.value)}"
        await RisingEdge(dut.clk)

    # 3. Thuc hien thao tac doc: Bo dem phai la 5 va khong duoc tang tiep
    for _ in range(3):
        dut.i_req_valid.value = 1
        dut.i_req_is_write.value = 0
        dut.i_req_page_idx.value = target_page
        await RisingEdge(dut.clk)
        dut.i_req_valid.value = 0
        await Timer(1, unit="ns")

        assert int(dut.o_unified_counter.value) == 5, f"Expected persistent count 5, got {int(dut.o_unified_counter.value)}"
        await RisingEdge(dut.clk)

@cocotb.test()
async def test_page_isolation(dut):
    """Kiem tra cach ly bo dem giua cac trang: Ghi vao trang A khong duoc anh huong trang B"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    page_a = 12
    page_b = 45

    # Ghi 10 lan vao page_a
    for _ in range(10):
        dut.i_req_valid.value = 1
        dut.i_req_is_write.value = 1
        dut.i_req_page_idx.value = page_a
        await RisingEdge(dut.clk)
        dut.i_req_valid.value = 0
        await RisingEdge(dut.clk)

    # Doc page_b: phai van la 0
    dut.i_req_valid.value = 1
    dut.i_req_is_write.value = 0
    dut.i_req_page_idx.value = page_b
    await RisingEdge(dut.clk)
    dut.i_req_valid.value = 0
    await Timer(1, unit="ns")

    assert int(dut.o_unified_counter.value) == 0, f"Page B was polluted by Page A: {int(dut.o_unified_counter.value)}"
