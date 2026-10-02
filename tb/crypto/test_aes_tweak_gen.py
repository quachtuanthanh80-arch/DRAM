# File: test_aes_tweak_gen.py
# Chức năng: Kiểm chứng bộ sinh vector Tweak tiền tính toán cho mã hóa AES-XTS (aes_tweak_gen).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

def ref_xts_mul_alpha(val_128):
    """Nhan alpha tren GF(2^128) voi da thuc irreducible P(x) = x^128 + x^7 + x^2 + x + 1 (0x87)"""
    msb = (val_128 >> 127) & 1
    res = ((val_128 << 1) & ((1 << 128) - 1))
    if msb:
        res ^= 0x87
    return res

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.addr_valid.value = 0
    dut.addr_in.value = 0
    dut.tweak_key.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_reset_and_defaults(dut):
    """Kiem tra khoi tao reset: cac thanh ghi tweak phai bang 0 va tweak_ready = 0"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    assert dut.tweak_ready.value == 0, "tweak_ready phai bang 0 sau reset"
    assert dut.tweak_t0.value == 0
    assert dut.tweak_t1.value == 0
    assert dut.tweak_t2.value == 0
    assert dut.tweak_t3.value == 0

@cocotb.test()
async def test_single_vector_generation(dut):
    """Kiem tra tinh toan 4 block tweak t0..t3 tu dia chi sector va tweak key"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    addr = 0x1000_2040
    key = 0xDEAD_BEEF_CAFE_BABE_0123_4567_89AB_CDEF

    dut.addr_valid.value = 1
    dut.addr_in.value = addr
    dut.tweak_key.value = key

    await RisingEdge(dut.clk)
    dut.addr_valid.value = 0

    await Timer(1, unit="ns")
    assert dut.tweak_ready.value == 1, "tweak_ready phai asserted 1 chu ky sau addr_valid"

    exp_t0 = addr ^ key
    exp_t1 = ref_xts_mul_alpha(exp_t0)
    exp_t2 = ref_xts_mul_alpha(exp_t1)
    exp_t3 = ref_xts_mul_alpha(exp_t2)

    assert int(dut.tweak_t0.value) == exp_t0, f"t0 mismatch: got {hex(int(dut.tweak_t0.value))}, exp {hex(exp_t0)}"
    assert int(dut.tweak_t1.value) == exp_t1, f"t1 mismatch: got {hex(int(dut.tweak_t1.value))}, exp {hex(exp_t1)}"
    assert int(dut.tweak_t2.value) == exp_t2, f"t2 mismatch: got {hex(int(dut.tweak_t2.value))}, exp {hex(exp_t2)}"
    assert int(dut.tweak_t3.value) == exp_t3, f"t3 mismatch: got {hex(int(dut.tweak_t3.value))}, exp {hex(exp_t3)}"

@cocotb.test()
async def test_gf128_poly_reduction(dut):
    """Kiem tra truong hop tran bit MSB=1 kich hoat phep tru/XOR modulo da thuc 0x87 tren GF(2^128)"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Thiet lap tweak key co MSB = 1 de kich hoat reduction logic
    addr = 0x0
    key = 1 << 127 # MSB = 1, con lai = 0

    dut.addr_valid.value = 1
    dut.addr_in.value = addr
    dut.tweak_key.value = key
    await RisingEdge(dut.clk)
    dut.addr_valid.value = 0

    await Timer(1, unit="ns")
    exp_t0 = 1 << 127
    exp_t1 = 0x87 # (1 << 127) * alpha mod P(x) = 0x87
    exp_t2 = 0x87 << 1 # 0x10e
    exp_t3 = 0x87 << 2 # 0x21c

    assert int(dut.tweak_t0.value) == exp_t0
    assert int(dut.tweak_t1.value) == exp_t1, f"t1 mismatch: got {hex(int(dut.tweak_t1.value))}, exp {hex(exp_t1)}"
    assert int(dut.tweak_t2.value) == exp_t2
    assert int(dut.tweak_t3.value) == exp_t3

@cocotb.test()
async def test_random_continuous_stream(dut):
    """Kiem tra chuoi 50 giao dich ngau nhien back-to-back de dam bao tinh toan dung tuyet doi"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for i in range(50):
        addr = random.getrandbits(32)
        key = random.getrandbits(128)

        dut.addr_valid.value = 1
        dut.addr_in.value = addr
        dut.tweak_key.value = key
        await RisingEdge(dut.clk)
        dut.addr_valid.value = 0

        await Timer(1, unit="ns")
        exp_t0 = addr ^ key
        exp_t1 = ref_xts_mul_alpha(exp_t0)
        exp_t2 = ref_xts_mul_alpha(exp_t1)
        exp_t3 = ref_xts_mul_alpha(exp_t2)

        assert int(dut.tweak_t0.value) == exp_t0
        assert int(dut.tweak_t1.value) == exp_t1
        assert int(dut.tweak_t2.value) == exp_t2
        assert int(dut.tweak_t3.value) == exp_t3
