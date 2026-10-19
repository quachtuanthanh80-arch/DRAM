# File: test_aes_key_expand.py
# Chức năng: Kiểm chứng bộ mở rộng khóa phần cứng aes_key_expand theo NIST FIPS-197 Appendix C.1 (AES-128) & C.3 (AES-256).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_key_expand_fips197(dut):
    """Kiem tra mo rong khoa AES-128 / AES-256 theo NIST FIPS-197"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.key_valid.value = 0
    dut.cipher_key.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Detect KEY_WIDTH from dut
    key_width = len(dut.cipher_key)

    if key_width == 128:
        # NIST FIPS-197 C.1: AES-128
        cipher_key = 0x2b7e151628aed2a6abf7158809cf4f3c
        exp_rk0    = 0x2b7e151628aed2a6abf7158809cf4f3c
        exp_rk1    = 0xa0fafe1788542cb123a339392a6c7605
        exp_rk10   = 0xd014f9a8c9ee2589e13f0cc8b6630ca6

        dut.cipher_key.value = cipher_key
        dut.key_valid.value = 1
        await RisingEdge(dut.clk)
        dut.key_valid.value = 0

        await Timer(1, unit="ns")
        assert dut.expand_done.value == 1, "expand_done phai asserted sau khi nạp key_valid"

        rk0 = int(dut.round_keys[0].value)
        rk1 = int(dut.round_keys[1].value)
        rk10 = int(dut.round_keys[10].value)

        assert rk0 == exp_rk0, f"Round 0 Mismatch: got {hex(rk0)}, exp {hex(exp_rk0)}"
        assert rk1 == exp_rk1, f"Round 1 Mismatch: got {hex(rk1)}, exp {hex(exp_rk1)}"
        assert rk10 == exp_rk10, f"Round 10 Mismatch: got {hex(rk10)}, exp {hex(exp_rk10)}"
        dut._log.info("[PASS] AES-128 NIST FIPS-197 C.1 Key Expansion verified perfectly!")

    elif key_width == 256:
        # NIST FIPS-197 C.3: AES-256
        cipher_key = 0x603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4
        exp_rk0    = 0x603deb1015ca71be2b73aef0857d7781
        exp_rk1    = 0x1f352c073b6108d72d9810a30914dff4
        exp_rk14   = 0xfe4890d1e6188d0b046df344706c631e

        dut.cipher_key.value = cipher_key
        dut.key_valid.value = 1
        await RisingEdge(dut.clk)
        dut.key_valid.value = 0

        await Timer(1, unit="ns")
        assert dut.expand_done.value == 1, "expand_done phai asserted sau khi nạp key_valid"

        rk0 = int(dut.round_keys[0].value)
        rk1 = int(dut.round_keys[1].value)
        rk14 = int(dut.round_keys[14].value)

        assert rk0 == exp_rk0, f"AES-256 Round 0 Mismatch: got {hex(rk0)}, exp {hex(exp_rk0)}"
        assert rk1 == exp_rk1, f"AES-256 Round 1 Mismatch: got {hex(rk1)}, exp {hex(exp_rk1)}"
        assert rk14 == exp_rk14, f"AES-256 Round 14 Mismatch: got {hex(rk14)}, exp {hex(exp_rk14)}"
        dut._log.info("[PASS] AES-256 NIST FIPS-197 C.3 Key Expansion verified perfectly!")
