# test_rs_chipkill.py
# Kiem tra chuc nang bo ma hoa va giai ma RS(18,16) Chipkill sua loi 1-symbol va phat hien 2-symbol

import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_valid.value = 0
    dut.i_ready.value = 1
    dut.i_data.value = 0
    dut.i_inject_en.value = 0
    dut.i_inject_count.value = 0
    dut.i_inject_sym_idx0.value = 0
    dut.i_inject_val0.value = 0
    dut.i_inject_sym_idx1.value = 0
    dut.i_inject_val1.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_chipkill_clean_data(dut):
    """Kiem tra truyen du lieu sach khong loi: Du lieu ra phai giong het du lieu vao"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(30):
        data = random.randint(0, (1 << 64) - 1)
        dut.i_valid.value = 1
        dut.i_data.value = data
        dut.i_inject_en.value = 0

        await RisingEdge(dut.clk)
        dut.i_valid.value = 0

        # Cho pipeline decoder (2 chu ky)
        while not dut.o_valid.value:
            await RisingEdge(dut.clk)

        out_data = int(dut.o_data.value)
        single_corr = int(dut.o_single_corrected.value)
        double_det = int(dut.o_double_detected.value)

        assert out_data == data, f"Mismatch: exp={hex(data)}, got={hex(out_data)}"
        assert single_corr == 0, f"Expected 0 single error, got {single_corr}"
        assert double_det == 0, f"Expected 0 double error, got {double_det}"
        await RisingEdge(dut.clk)

@cocotb.test()
async def test_chipkill_single_symbol_correction(dut):
    """Kiem tra sua loi toan dien 1 symbol: Moi symbol tu 0 den 15 voi cac loi tu 1 den 15 deu phai sua thanh cong 100%"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for sym_idx in range(16): # 16 data symbols
        for err_val in [1, 2, 4, 7, 8, 15]: # Cac mau bit loi 4-bit
            data = random.randint(0, (1 << 64) - 1)
            dut.i_valid.value = 1
            dut.i_data.value = data
            dut.i_inject_en.value = 1
            dut.i_inject_count.value = 1
            dut.i_inject_sym_idx0.value = sym_idx
            dut.i_inject_val0.value = err_val

            await RisingEdge(dut.clk)
            dut.i_valid.value = 0
            dut.i_inject_en.value = 0

            while not dut.o_valid.value:
                await RisingEdge(dut.clk)

            out_data = int(dut.o_data.value)
            single_corr = int(dut.o_single_corrected.value)
            detected_sym = int(dut.o_error_symbol_idx.value)

            assert out_data == data, f"Correction failed at sym {sym_idx} err {err_val}: exp={hex(data)}, got={hex(out_data)}"
            assert single_corr == 1, f"Expected single error corrected at sym {sym_idx}"
            assert detected_sym == sym_idx, f"Detected sym {detected_sym} != injected sym {sym_idx}"
            await RisingEdge(dut.clk)

@cocotb.test()
async def test_chipkill_double_symbol_detection(dut):
    """Kiem tra phat hien loi kep 2-symbol (loi tren 2 chip DRAM khac nhau): He thong phai bao co double error"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(20):
        data = random.randint(0, (1 << 64) - 1)
        sym0 = random.randint(0, 7)
        sym1 = random.randint(8, 15)
        err = random.randint(1, 15)

        dut.i_valid.value = 1
        dut.i_data.value = data
        dut.i_inject_en.value = 1
        dut.i_inject_count.value = 2
        dut.i_inject_sym_idx0.value = sym0
        dut.i_inject_val0.value = err
        dut.i_inject_sym_idx1.value = sym1
        dut.i_inject_val1.value = err

        await RisingEdge(dut.clk)
        dut.i_valid.value = 0
        dut.i_inject_en.value = 0

        while not dut.o_valid.value:
            await RisingEdge(dut.clk)

        double_det = int(dut.o_double_detected.value)
        assert double_det == 1, f"Expected double error detected for sym {sym0} and {sym1}"
        await RisingEdge(dut.clk)
