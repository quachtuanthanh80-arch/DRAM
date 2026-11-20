# File: test_aes_tweak_gen.py
# Chức năng: Kiểm chứng bộ sinh vector Tweak AES-256-XTS chuẩn IEEE 1619 (qshield_xts_tweak_unit).

import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

SBOX = [
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
]

RCON = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]


def pack_aes256_round_keys(key_bytes: bytes) -> int:
    """Mo rong khoa AES-256 theo FIPS-197 va dong goi thanh vector 15*128-bit khop RTL."""
    w = [int.from_bytes(key_bytes[4 * i : 4 * (i + 1)], "little") for i in range(8)]
    for i in range(8, 60):
        temp = w[i - 1]
        if i % 8 == 0:
            rot = ((temp >> 8) & 0xFFFFFF) | ((temp & 0xFF) << 24)
            sub = sum(SBOX[(rot >> (8 * b)) & 0xFF] << (8 * b) for b in range(4))
            temp = sub ^ RCON[i // 8]
        elif i % 8 == 4:
            temp = sum(SBOX[(temp >> (8 * b)) & 0xFF] << (8 * b) for b in range(4))
        w.append(w[i - 8] ^ temp)
    packed = 0
    for r in range(15):
        rk = (w[4 * r + 3] << 96) | (w[4 * r + 2] << 64) | (w[4 * r + 1] << 32) | w[4 * r]
        packed |= rk << (128 * r)
    return packed


def aes256_ecb_encrypt_int(key_bytes: bytes, tweak_int: int) -> int:
    enc = Cipher(algorithms.AES(key_bytes), modes.ECB()).encryptor()
    out = enc.update(tweak_int.to_bytes(16, "little")) + enc.finalize()
    return int.from_bytes(out, "little")


def aes256_ecb_decrypt_int(key_bytes: bytes, ct_int: int) -> int:
    dec = Cipher(algorithms.AES(key_bytes), modes.ECB()).decryptor()
    out = dec.update(ct_int.to_bytes(16, "little")) + dec.finalize()
    return int.from_bytes(out, "little")


def ref_xts_mul_alpha(val_128: int) -> int:
    """Nhan alpha tren GF(2^128) voi da thuc irreducible P(x) = x^128 + x^7 + x^2 + x + 1 (0x87)."""
    msb = (val_128 >> 127) & 1
    res = (val_128 << 1) & ((1 << 128) - 1)
    if msb:
        res ^= 0x87
    return res


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_valid.value = 0
    dut.i_tweak.value = 0
    dut.i_round_keys.value = 0
    dut.i_meta.value = 0
    dut.i_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def run_one_tweak(dut, tweak_int: int, round_keys_int: int, meta: int):
    dut.i_valid.value = 1
    dut.i_tweak.value = tweak_int
    dut.i_round_keys.value = round_keys_int
    dut.i_meta.value = meta
    await RisingEdge(dut.clk)
    dut.i_valid.value = 0

    for _ in range(20):
        await Timer(1, unit="ns")
        if int(dut.o_valid.value) == 1:
            return (
                int(dut.o_tweak0.value),
                int(dut.o_tweak1.value),
                int(dut.o_tweak2.value),
                int(dut.o_tweak3.value),
                int(dut.o_meta.value),
            )
        await RisingEdge(dut.clk)
    raise AssertionError("Timeout waiting for qshield_xts_tweak_unit o_valid")


@cocotb.test()
async def test_reset_and_defaults(dut):
    """Kiem tra khoi tao reset: o_valid = 0, o_ready = 1 va cac thanh ghi tweak bang 0."""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    assert int(dut.o_valid.value) == 0, "o_valid phai bang 0 sau reset"
    assert int(dut.o_ready.value) == 1, "o_ready phai bang 1 sau reset"
    assert int(dut.o_tweak0.value) == 0
    assert int(dut.o_tweak1.value) == 0
    assert int(dut.o_tweak2.value) == 0
    assert int(dut.o_tweak3.value) == 0


@cocotb.test()
async def test_single_vector_generation(dut):
    """Kiem tra tinh toan 4 block tweak t0..t3 chuan IEEE 1619 (AES256_K2 + alpha mul)."""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    key_bytes = bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
    rk_int = pack_aes256_round_keys(key_bytes)
    tweak_in = 0x1000_2040
    meta_in = 0xCAFE

    t0, t1, t2, t3, meta_out = await run_one_tweak(dut, tweak_in, rk_int, meta_in)

    exp_t0 = aes256_ecb_encrypt_int(key_bytes, tweak_in)
    exp_t1 = ref_xts_mul_alpha(exp_t0)
    exp_t2 = ref_xts_mul_alpha(exp_t1)
    exp_t3 = ref_xts_mul_alpha(exp_t2)

    assert meta_out == meta_in, f"meta mismatch: got {hex(meta_out)}, exp {hex(meta_in)}"
    assert t0 == exp_t0, f"t0 mismatch: got {hex(t0)}, exp {hex(exp_t0)}"
    assert t1 == exp_t1, f"t1 mismatch: got {hex(t1)}, exp {hex(exp_t1)}"
    assert t2 == exp_t2, f"t2 mismatch: got {hex(t2)}, exp {hex(exp_t2)}"
    assert t3 == exp_t3, f"t3 mismatch: got {hex(t3)}, exp {hex(exp_t3)}"


@cocotb.test()
async def test_gf128_poly_reduction(dut):
    """Kiem tra tran bit MSB=1 kich hoat phep khu da thuc 0x87 tren GF(2^128) sau ma hoa K2."""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    key_bytes = bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    rk_int = pack_aes256_round_keys(key_bytes)
    # Chon tweak sao cho AES256_K2(tweak) = (1 << 127) de kich hoat MSB reduction
    tweak_in = aes256_ecb_decrypt_int(key_bytes, 1 << 127)

    t0, t1, t2, t3, _ = await run_one_tweak(dut, tweak_in, rk_int, 0x0042)

    exp_t0 = 1 << 127
    exp_t1 = 0x87
    exp_t2 = 0x87 << 1
    exp_t3 = 0x87 << 2

    assert t0 == exp_t0, f"t0 mismatch: got {hex(t0)}, exp {hex(exp_t0)}"
    assert t1 == exp_t1, f"t1 mismatch: got {hex(t1)}, exp {hex(exp_t1)}"
    assert t2 == exp_t2, f"t2 mismatch: got {hex(t2)}, exp {hex(exp_t2)}"
    assert t3 == exp_t3, f"t3 mismatch: got {hex(t3)}, exp {hex(exp_t3)}"


@cocotb.test()
async def test_random_continuous_stream(dut):
    """Kiem tra chuoi 50 giao dich ngau nhien pipeline lien tuc khop mo hinh AES-256-XTS Python."""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    random.seed(2026)

    key_bytes = bytes(random.getrandbits(8) for _ in range(32))
    rk_int = pack_aes256_round_keys(key_bytes)
    dut.i_round_keys.value = rk_int

    expected_q = []
    out_count = 0
    for step in range(50 + 20):
        if step < 50:
            tweak_in = random.getrandbits(128)
            meta_in = step & 0xFFFF
            exp_t0 = aes256_ecb_encrypt_int(key_bytes, tweak_in)
            exp_t1 = ref_xts_mul_alpha(exp_t0)
            exp_t2 = ref_xts_mul_alpha(exp_t1)
            exp_t3 = ref_xts_mul_alpha(exp_t2)
            expected_q.append((exp_t0, exp_t1, exp_t2, exp_t3, meta_in))
            dut.i_valid.value = 1
            dut.i_tweak.value = tweak_in
            dut.i_meta.value = meta_in
        else:
            dut.i_valid.value = 0

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        if int(dut.o_valid.value) == 1:
            exp_t0, exp_t1, exp_t2, exp_t3, exp_meta = expected_q.pop(0)
            assert int(dut.o_meta.value) == exp_meta
            assert int(dut.o_tweak0.value) == exp_t0
            assert int(dut.o_tweak1.value) == exp_t1
            assert int(dut.o_tweak2.value) == exp_t2
            assert int(dut.o_tweak3.value) == exp_t3
            out_count += 1

    assert out_count == 50 and len(expected_q) == 0, f"Stream mismatch: out={out_count}, rem={len(expected_q)}"
