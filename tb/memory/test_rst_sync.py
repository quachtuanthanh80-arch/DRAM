# File: test_rst_sync.py
# Chức năng: Kiểm chứng đồng bộ hóa reset bất đồng bộ/giải phóng đồng bộ (rst_sync).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

@cocotb.test()
async def test_async_assertion(dut):
    """Kiem tra dac tinh assert bat dong bo: reset lap tuc keo sync_rst_n ve 0 giua chu ky clk"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.async_rst_n.value = 1
    # Cho reset giai phong sau it nhat 3 clock cycles
    for _ in range(4):
        await RisingEdge(dut.clk)
    assert dut.sync_rst_n.value == 1, "sync_rst_n phai dat 1 sau khi deassert on dinh"

    # Assert reset bat dong bo tai thoi diem giua 2 xung clock
    await Timer(3, unit="ns")
    dut.async_rst_n.value = 0
    await Timer(1, unit="ns")
    assert dut.sync_rst_n.value == 0, "sync_rst_n phai keo xuong 0 ngay lap tuc ma khong can cho posedge clk"

@cocotb.test()
async def test_sync_deassertion_latency(dut):
    """Kiem tra dac tinh deassert dong bo: giai phong reset can dung STAGES chu ky clock de propagate"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.async_rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.sync_rst_n.value == 0

    # Bat dau deassert async_rst_n truoc suon duong clock
    dut.async_rst_n.value = 1

    # Cycle 1: bit dau tien cua sync_reg vao stage 0, stage 1 (output) van la 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.sync_rst_n.value == 0, "Sau 1 cycle, sync_rst_n chua duoc phep release (STAGES=2)"

    # Cycle 2: bit 1 dich sang stage 1 (output)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.sync_rst_n.value == 1, "Sau 2 cycles du STAGES, sync_rst_n phai duoc release len 1"

@cocotb.test()
async def test_glitch_filtering(dut):
    """Kiem tra loc xung nhieu (glitch): xung release ngan hon 1 chu ky clock khong duoc giai phong reset"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.async_rst_n.value = 0
    await RisingEdge(dut.clk)

    # Glitch release: len 1 trong 4ns (< chu ky 10ns) roi lap tuc bi keo xuong 0 giua 2 suon clock
    await Timer(2, unit="ns")
    dut.async_rst_n.value = 1
    await Timer(4, unit="ns")
    dut.async_rst_n.value = 0

    # Cho clock edge tiep theo
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.sync_rst_n.value == 0, "Xung glitch release khong duoc lam sync_rst_n nhay len 1"

    # Sau do deassert on dinh >= 2 chu ky de khoi phuc
    dut.async_rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.sync_rst_n.value == 1, "sync_rst_n phai khoi phuc on dinh sau 2 clock cycles"
