# File: test_wdata_buffer.py
# Chuc nang: Cocotb testbench kiem chung hang doi WDATA buffer va command staging FIFO.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

async def reset_dut(dut):
    dut.aresetn_axi.value = 0
    dut.i_wr_addr_valid.value = 0
    dut.i_wr_addr_id.value = 0
    dut.i_wr_addr.value = 0
    dut.i_wr_len.value = 0
    dut.i_wr_size.value = 3
    dut.i_wr_burst.value = 1
    dut.i_wr_qos.value = 0
    dut.i_wr_addr_cross_4kb.value = 0

    dut.i_wr_data_valid.value = 0
    dut.i_wr_data.value = 0
    dut.i_wr_strb.value = 0
    dut.i_wr_last.value = 0

    dut.i_cmd_ready.value = 0
    dut.i_data_ready.value = 0

    await RisingEdge(dut.clk_axi)
    await RisingEdge(dut.clk_axi)
    dut.aresetn_axi.value = 1
    await RisingEdge(dut.clk_axi)

@cocotb.test()
async def test_reset_and_defaults(dut):
    """Kiem tra khoi tao reset va trang thai default ready cua buffer"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    assert dut.o_wr_addr_ready.value == 1, "AW FIFO phai ready sau reset"
    assert dut.o_wr_data_ready.value == 1, "W FIFO phai ready sau reset"
    assert dut.o_cmd_valid.value == 0, "Command downstream valid phai bang 0 khi rong"
    assert dut.o_data_valid.value == 0, "Data downstream valid phai bang 0 khi rong"

@cocotb.test()
async def test_single_beat_write_and_strobe(dut):
    """Kiem chung giao dich ghi don beat voi WSTRB masking va 4KB flag"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 1. Phat Write Address Command
    dut.i_wr_addr_id.value = 0x5
    dut.i_wr_addr.value = 0x8000_1000
    dut.i_wr_len.value = 0
    dut.i_wr_size.value = 3
    dut.i_wr_burst.value = 1
    dut.i_wr_qos.value = 0x4
    dut.i_wr_addr_cross_4kb.value = 0
    dut.i_wr_addr_valid.value = 1

    # 2. Phat Write Data Beat voi WSTRB masking byte le
    dut.i_wr_data.value = 0x1122_3344_5566_7788
    dut.i_wr_strb.value = 0b1111_0000
    dut.i_wr_last.value = 1
    dut.i_wr_data_valid.value = 1

    await RisingEdge(dut.clk_axi)
    dut.i_wr_addr_valid.value = 0
    dut.i_wr_data_valid.value = 0

    await RisingEdge(dut.clk_axi)
    assert dut.o_cmd_valid.value == 1, "Command staging phai valid sau khi nhan AW"
    assert dut.o_cmd_id.value == 0x5
    assert dut.o_cmd_addr.value == 0x8000_1000
    assert dut.o_cmd_qos.value == 0x4
    assert dut.o_cmd_cross_4kb.value == 0

    assert dut.o_data_valid.value == 1, "Data staging phai valid sau khi nhan W"
    assert dut.o_data.value == 0x1122_3344_5566_7788
    assert dut.o_strb.value == 0b1111_0000
    assert dut.o_last.value == 1

    # Handshake downstream consume
    dut.i_cmd_ready.value = 1
    dut.i_data_ready.value = 1
    await RisingEdge(dut.clk_axi)
    dut.i_cmd_ready.value = 0
    dut.i_data_ready.value = 0

    await RisingEdge(dut.clk_axi)
    assert dut.o_cmd_valid.value == 0, "Command buffer phai rong sau handshake"
    assert dut.o_data_valid.value == 0, "Data buffer phai rong sau handshake"

@cocotb.test()
async def test_burst_write_sequential_drain(dut):
    """Kiem chung burst INCR 8-beat duoc luu tru va drain tuan tu dung thu tu"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    burst_len = 8
    # Push AW
    dut.i_wr_addr_id.value = 0x1
    dut.i_wr_addr.value = 0x1000_0000
    dut.i_wr_len.value = burst_len - 1
    dut.i_wr_size.value = 3
    dut.i_wr_burst.value = 1
    dut.i_wr_addr_valid.value = 1
    await RisingEdge(dut.clk_axi)
    dut.i_wr_addr_valid.value = 0

    test_payloads = [0xA000_0000_0000_0000 + i for i in range(burst_len)]
    for idx, payload in enumerate(test_payloads):
        dut.i_wr_data.value = payload
        dut.i_wr_strb.value = 0xFF
        dut.i_wr_last.value = 1 if idx == burst_len - 1 else 0
        dut.i_wr_data_valid.value = 1
        await RisingEdge(dut.clk_axi)

    dut.i_wr_data_valid.value = 0
    dut.i_wr_last.value = 0

    # Downstream doc ra va kiem tra thu tu
    dut.i_cmd_ready.value = 1
    dut.i_data_ready.value = 1
    received_payloads = []

    for _ in range(burst_len):
        while dut.o_data_valid.value == 0:
            await RisingEdge(dut.clk_axi)
        await Timer(1, unit="ps")
        received_payloads.append(int(dut.o_data.value))
        await RisingEdge(dut.clk_axi)

    dut.i_cmd_ready.value = 0
    dut.i_data_ready.value = 0

    assert received_payloads == test_payloads, f"Payload mismatch: {received_payloads} vs {test_payloads}"

@cocotb.test()
async def test_fifo_backpressure_and_full_capacity(dut):
    """Kiem chung co che backpressure khi CMD_FIFO va DATA_FIFO day dung muc depth"""
    clock = Clock(dut.clk_axi, 4, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 1. Fill CMD_FIFO (CMD_FIFO_DEPTH = 8)
    dut.i_cmd_ready.value = 0
    for i in range(8):
        await Timer(1, unit="ps")
        assert dut.o_wr_addr_ready.value == 1, f"CMD FIFO phai ready o entry {i}"
        dut.i_wr_addr_id.value = i
        dut.i_wr_addr.value = 0x2000 + i * 64
        dut.i_wr_len.value = 0
        dut.i_wr_addr_valid.value = 1
        await RisingEdge(dut.clk_axi)

    dut.i_wr_addr_valid.value = 0
    await Timer(1, unit="ps")
    # CMD FIFO phai full va ha o_wr_addr_ready ve 0
    assert dut.o_wr_addr_ready.value == 0, f"o_wr_addr_ready phai bang 0 khi CMD FIFO day 8 entries, got {dut.o_wr_addr_ready.value}"

    # 2. Fill DATA_FIFO (BUFFER_DEPTH = 32)
    dut.i_data_ready.value = 0
    for i in range(32):
        await Timer(1, unit="ps")
        assert dut.o_wr_data_ready.value == 1, f"DATA FIFO phai ready o beat {i}"
        dut.i_wr_data.value = 0xD000_0000 + i
        dut.i_wr_strb.value = 0xFF
        dut.i_wr_last.value = 0
        dut.i_wr_data_valid.value = 1
        await RisingEdge(dut.clk_axi)

    dut.i_wr_data_valid.value = 0
    await Timer(1, unit="ps")
    # DATA FIFO phai full va ha o_wr_data_ready ve 0
    assert dut.o_wr_data_ready.value == 0, f"o_wr_data_ready phai bang 0 khi DATA FIFO day 32 beats, got {dut.o_wr_data_ready.value}"

    # 3. Drain CMD FIFO
    dut.i_cmd_ready.value = 1
    for i in range(8):
        await RisingEdge(dut.clk_axi)
        await Timer(1, unit="ps")
        assert dut.o_wr_addr_ready.value == 1, "o_wr_addr_ready phai tro lai 1 ngay khi co khoang trong"
    dut.i_cmd_ready.value = 0

    # 4. Drain DATA FIFO
    dut.i_data_ready.value = 1
    for i in range(32):
        await RisingEdge(dut.clk_axi)
        await Timer(1, unit="ps")
        assert dut.o_wr_data_ready.value == 1, "o_wr_data_ready phai tro lai 1 ngay khi drain"
    dut.i_data_ready.value = 0
