# test_integrity_mac.py
# Kiem tra bo sinh va xac thuc ma toan ven AES-CMAC 64-bit phat hien gia mao du lieu

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_mac_en.value = 0
    dut.cfg_mac_key.value = 0
    dut.i_wr_valid.value = 0
    dut.i_wr_addr.value = 0
    dut.i_wr_counter.value = 0
    dut.i_wr_data.value = 0
    dut.i_rd_valid.value = 0
    dut.i_rd_addr.value = 0
    dut.i_rd_counter.value = 0
    dut.i_rd_data.value = 0
    dut.i_rd_stored_mac.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_mac_generation_and_valid_verification(dut):
    """Kiem tra sinh ma MAC 64-bit luc ghi va xac thuc toan ven thanh cong luc doc voi du lieu nguyen ven"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_mac_en.value = 1
    dut.cfg_mac_key.value = 0x2b7e151628aed2a6abf7158809cf4f3c
    await RisingEdge(dut.clk)

    addr = 0x4000
    counter = 1
    data = 0x123456789ABCDEF0FEDCBA9876543210

    # 1. Sinh MAC tren kenh ghi (Write phase)
    dut.i_wr_valid.value = 1
    dut.i_wr_addr.value = addr
    dut.i_wr_counter.value = counter
    dut.i_wr_data.value = data
    await RisingEdge(dut.clk)
    dut.i_wr_valid.value = 0

    while not dut.o_wr_mac_valid.value:
        await RisingEdge(dut.clk)

    generated_mac = int(dut.o_wr_mac.value)
    assert generated_mac != 0, "Generated MAC must be non-zero!"
    await RisingEdge(dut.clk)

    # 2. Xac thuc MAC tren kenh doc voi du lieu nguyen ban (Read phase)
    dut.i_rd_valid.value = 1
    dut.i_rd_addr.value = addr
    dut.i_rd_counter.value = counter
    dut.i_rd_data.value = data
    dut.i_rd_stored_mac.value = generated_mac
    await RisingEdge(dut.clk)
    dut.i_rd_valid.value = 0

    while not dut.o_rd_mac_valid.value:
        await RisingEdge(dut.clk)

    violation = int(dut.o_integrity_violation.value)
    assert violation == 0, f"Expected 0 integrity violation for authentic data, got {violation}"
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_mac_tamper_detection(dut):
    """Kiem tra phat hien tan cong sua doi bit (Tamper Detection): Du chi doi 1 bit du lieu, violation phai bat len 1"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_mac_en.value = 1
    dut.cfg_mac_key.value = 0x2b7e151628aed2a6abf7158809cf4f3c
    await RisingEdge(dut.clk)

    addr = 0x8000
    counter = 5
    data = 0xCAFEBABE1122334455667788DEADBEEF

    # Sinh MAC hop le
    dut.i_wr_valid.value = 1
    dut.i_wr_addr.value = addr
    dut.i_wr_counter.value = counter
    dut.i_wr_data.value = data
    await RisingEdge(dut.clk)
    dut.i_wr_valid.value = 0

    while not dut.o_wr_mac_valid.value:
        await RisingEdge(dut.clk)

    valid_mac = int(dut.o_wr_mac.value)
    await RisingEdge(dut.clk)

    # Thuc hien doc voi du lieu bi ke xau sua doi 1 bit (Bit flip attack)
    tampered_data = data ^ 0x01
    dut.i_rd_valid.value = 1
    dut.i_rd_addr.value = addr
    dut.i_rd_counter.value = counter
    dut.i_rd_data.value = tampered_data
    dut.i_rd_stored_mac.value = valid_mac
    await RisingEdge(dut.clk)
    dut.i_rd_valid.value = 0

    while not dut.o_rd_mac_valid.value:
        await RisingEdge(dut.clk)

    violation = int(dut.o_integrity_violation.value)
    assert violation == 1, "Security violation must be raised when data bit is flipped!"
