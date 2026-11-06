# test_rs_chipkill.py
# Kiem tra RS(18,16) tren GF(2^8) Chipkill: sua loi 1 chip x4 (symbol 8 bit), do ty le phat hien loi 2 chip so voi mo hinh Python
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

POLY = 0x11D


def gmul(a, b):
    p = 0
    while b:
        if b & 1:
            p ^= a
        a <<= 1
        if a & 0x100:
            a ^= POLY
        b >>= 1
    return p


ALPHA = [1]
for _ in range(17):
    ALPHA.append(gmul(ALPHA[-1], 2))


def ref_decode(symbols):
    """Independent syndrome decoder: returns ('clean'|'corrected'|'uncorrectable', position)."""
    s0 = s1 = 0
    for i, s in enumerate(symbols):
        s0 ^= s
        s1 ^= gmul(s, ALPHA[i])
    if s0 == 0 and s1 == 0:
        return "clean", None
    for j in range(18):
        if s0 and s1 == gmul(s0, ALPHA[j]):
            return "corrected", j
    return "uncorrectable", None


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


async def xfer(dut, data, count=0, s0=0, v0=0, s1=0, v1=0):
    dut.i_valid.value = 1
    dut.i_data.value = data
    dut.i_inject_en.value = 1 if count else 0
    dut.i_inject_count.value = count
    dut.i_inject_sym_idx0.value = s0
    dut.i_inject_val0.value = v0
    dut.i_inject_sym_idx1.value = s1
    dut.i_inject_val1.value = v1
    await RisingEdge(dut.clk)
    dut.i_valid.value = 0
    dut.i_inject_en.value = 0
    while not dut.o_valid.value:
        await RisingEdge(dut.clk)
    out = (int(dut.o_data.value), int(dut.o_single_corrected.value), int(dut.o_uncorrectable.value),
           int(dut.o_error_symbol_idx.value))
    await RisingEdge(dut.clk)
    return out


@cocotb.test()
async def test_chipkill_clean_data(dut):
    """Du lieu sach di qua khong doi va khong co co bao loi"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    for _ in range(30):
        data = random.getrandbits(128)
        out, sc, ue, _ = await xfer(dut, data)
        assert (out, sc, ue) == (data, 0, 0), f"clean mismatch exp={data:x} got={out:x} sc={sc} ue={ue}"


@cocotb.test()
async def test_chipkill_single_symbol_correction(dut):
    """Hong mot chip x4 bat ky (ke ca chip kiem tra) voi nhieu do lon loi: phai sua dung va dinh vi dung"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    for sym in range(18):
        for err in [0x01, 0x80, 0x5A, 0xFF, random.randint(1, 255)]:
            data = random.getrandbits(128)
            out, sc, ue, idx = await xfer(dut, data, 1, sym, err)
            assert out == data and sc == 1 and ue == 0 and idx == sym, \
                f"sym {sym} err {err:02x}: out={out:x} sc={sc} ue={ue} idx={idx}"


@cocotb.test()
async def test_chipkill_double_symbol_vs_reference(dut):
    """Loi 2 chip: RTL phai cho cung ket luan voi bo giai ma Python doc lap (phat hien hay sua nham)"""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)
    detected = 0
    n = 300
    for _ in range(n):
        data = random.getrandbits(128)
        a, b = random.sample(range(18), 2)
        va, vb = random.randint(1, 255), random.randint(1, 255)
        out, sc, ue, _ = await xfer(dut, data, 2, a, va, b, vb)
        # Ket luan cua mo hinh chi phu thuoc vector loi (ma tuyen tinh): dung codeword 0 cong loi
        sym = [0] * 18
        sym[a] ^= va
        sym[b] ^= vb
        kind, _ = ref_decode(sym)
        assert kind != "clean"
        assert (ue == 1) == (kind == "uncorrectable") and (sc == 1) == (kind == "corrected"), \
            f"syms {a},{b}: RTL sc={sc} ue={ue}, reference {kind}"
        detected += ue
    dut._log.info(f"double-chip failures detected {detected}/{n} ({100 * detected / n:.1f}%); d=3 gives SSC only")
