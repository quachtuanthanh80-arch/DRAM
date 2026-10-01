# test_bus_scrambler.py
# Cocotb verification suite cho module bus_scrambler

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_scramble_en.value = 0
    dut.cfg_reseed.value = 0
    dut.cfg_seed.value = 0
    dut.step_en.value = 0
    dut.i_data.value = 0
    dut.i_addr.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(5, unit="ns")

@cocotb.test()
async def test_scrambler_bypass(dut):
    """Kiem tra che do bypass (cfg_scramble_en=0): Du lieu va dia chi ra phai y het vao."""
    clock = Clock(dut.clk, 2.5, unit="ns") # 400 MHz
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_scramble_en.value = 0

    for _ in range(50):
        data_in = random.getrandbits(128)
        addr_in = random.getrandbits(18)
        dut.i_data.value = data_in
        dut.i_addr.value = addr_in
        await Timer(1, unit="ns")

        assert dut.o_data.value.to_unsigned() == data_in, f"Bypass loi data: in=0x{data_in:X} != out=0x{dut.o_data.value.to_unsigned():X}"
        assert dut.o_addr.value.to_unsigned() == addr_in, f"Bypass loi addr: in=0x{addr_in:X} != out=0x{dut.o_addr.value.to_unsigned():X}"

@cocotb.test()
async def test_scrambler_symmetric_identity(dut):
    """Kiem tra tinh doi xung toan hoc: Scramble(Scramble(Data)) == Data."""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Bat xao tron
    dut.cfg_scramble_en.value = 1

    for _ in range(50):
        data_orig = random.getrandbits(128)
        addr_orig = random.getrandbits(18)

        # Chieu ghi: Scramble
        dut.step_en.value = 0 # Giu nguyen trang thai LFSR de kiem tra tinh doi xung
        dut.i_data.value = data_orig
        dut.i_addr.value = addr_orig
        await Timer(1, unit="ns")

        scrambled_data = dut.o_data.value.to_unsigned()
        scrambled_addr = dut.o_addr.value.to_unsigned()

        # Du lieu da xao tron phai khac du lieu goc (tru truong hop dac biet mask=0)
        assert scrambled_data != data_orig, "Loi: Data sau xao tron bi trung voi data goc"

        # Chieu doc: Descramble bang cach dua data da xao tron quay lai
        dut.i_data.value = scrambled_data
        dut.i_addr.value = scrambled_addr
        await Timer(1, unit="ns")

        recovered_data = dut.o_data.value.to_unsigned()
        recovered_addr = dut.o_addr.value.to_unsigned()

        assert recovered_data == data_orig, f"Loi giai ma data: goc=0x{data_orig:X}, khoi phuc=0x{recovered_data:X}"
        assert recovered_addr == addr_orig, f"Loi giai ma addr: goc=0x{addr_orig:X}, khoi phuc=0x{recovered_addr:X}"

        # Buoc nhay LFSR cho chu ky tiep theo
        dut.step_en.value = 1
        await RisingEdge(dut.clk)
        dut.step_en.value = 0

@cocotb.test()
async def test_scrambler_reseed(dut):
    """Kiem tra tinh nang nap lai seed moi tu thanh ghi CSR."""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_scramble_en.value = 1
    fixed_data = 0xAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444

    # Lay output voi default seed
    dut.i_data.value = fixed_data
    await Timer(1, unit="ns")
    out_default_seed = dut.o_data.value.to_unsigned()

    # Nap seed moi
    new_seed = 0x1234_5678_9ABC_DEF0
    dut.cfg_seed.value = new_seed
    dut.cfg_reseed.value = 1
    await RisingEdge(dut.clk)
    dut.cfg_reseed.value = 0
    await Timer(1, unit="ns")

    out_new_seed = dut.o_data.value.to_unsigned()
    assert out_new_seed != out_default_seed, "Loi reseed: Keystream khong doi sau khi nap seed moi"
