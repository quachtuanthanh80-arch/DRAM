# test_split_counter.py
# Kiem tra bang bo dem Major-Minor chong phat lai (Anti-Replay) va tinh nang phat tin hieu ma hoa lai trang (Reseed)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_lookup_valid.value = 0
    dut.i_lookup_is_write.value = 0
    dut.i_lookup_key_id.value = 0
    dut.i_lookup_epoch_nonce.value = 0
    dut.i_lookup_addr.value = 0
    dut.i_commit_valid.value = 0
    dut.i_commit_addr.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_counter_read_write_increment(dut):
    """Kiem tra thao tac commit ghi tang bo dem va thao tac doc giu nguyen gia tri bo dem"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    target_page = 5
    target_addr = (target_page << 12) | (2 << 6) # Page 5, Line 2

    # 1. Lan doc dau tien: Bo dem ban dau phai bang 0
    dut.i_lookup_valid.value = 1
    dut.i_lookup_is_write.value = 0
    dut.i_lookup_addr.value = target_addr
    await Timer(1, unit="ns")

    assert int(dut.o_lookup_valid.value) == 1
    assert int(dut.o_minor_ctr.value) == 0, f"Expected initial minor 0, got {int(dut.o_minor_ctr.value)}"
    assert int(dut.o_major_ctr.value) == 0, f"Expected initial major 0, got {int(dut.o_major_ctr.value)}"
    await RisingEdge(dut.clk)
    dut.i_lookup_valid.value = 0

    # 2. Thuc hien 5 thao tac commit ghi vao Line 2 cua Trang 5
    for i in range(1, 6):
        dut.i_commit_valid.value = 1
        dut.i_commit_addr.value = target_addr
        await RisingEdge(dut.clk)
        dut.i_commit_valid.value = 0

        # Kiem tra gia tri doc sau khi commit
        dut.i_lookup_valid.value = 1
        dut.i_lookup_is_write.value = 0
        dut.i_lookup_addr.value = target_addr
        await Timer(1, unit="ns")
        assert int(dut.o_minor_ctr.value) == i, f"Expected minor {i}, got {int(dut.o_minor_ctr.value)}"
        await RisingEdge(dut.clk)
        dut.i_lookup_valid.value = 0

    # 3. Kiem tra tinh nang Pre-computation Write (eff_minor phai bang minor + 1 = 6)
    dut.i_lookup_valid.value = 1
    dut.i_lookup_is_write.value = 1
    dut.i_lookup_addr.value = target_addr
    await Timer(1, unit="ns")
    assert int(dut.o_minor_ctr.value) == 6, f"Expected precomputed write minor 6, got {int(dut.o_minor_ctr.value)}"
    dut.i_lookup_valid.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_page_isolation(dut):
    """Kiem tra cach ly bo dem giua cac trang: Ghi vao trang A khong duoc anh huong trang B"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    addr_a = (12 << 12) | (4 << 6) # Page 12
    addr_b = (45 << 12) | (4 << 6) # Page 45

    # Ghi 10 lan vao addr_a
    for _ in range(10):
        dut.i_commit_valid.value = 1
        dut.i_commit_addr.value = addr_a
        await RisingEdge(dut.clk)
        dut.i_commit_valid.value = 0

    # Doc addr_b: phai van la 0
    dut.i_lookup_valid.value = 1
    dut.i_lookup_is_write.value = 0
    dut.i_lookup_addr.value = addr_b
    await Timer(1, unit="ns")

    assert int(dut.o_minor_ctr.value) == 0, f"Page B was polluted by Page A: {int(dut.o_minor_ctr.value)}"
    dut.i_lookup_valid.value = 0
    await RisingEdge(dut.clk)
