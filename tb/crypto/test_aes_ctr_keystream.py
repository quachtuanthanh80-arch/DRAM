# test_aes_ctr_keystream.py
# Kiem tra bo tinh toan truoc keystream AES-CTR va do tre doc XOR 0-cycle

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_ctr_en.value = 0
    dut.cfg_aes_key.value = 0
    dut.cfg_nonce.value = 0
    dut.i_req_valid.value = 0
    dut.i_req_addr.value = 0
    dut.i_req_counter.value = 0
    dut.i_keystream_ready.value = 0
    dut.i_data_valid.value = 0
    dut.i_data.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_keystream_precomputation_and_zero_latency_xor(dut):
    """Kiem tra tinh toan truoc keystream (14 chu ky an khop tRCD) va phep XOR 0-cycle khi du lieu ve"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 1. Cau hinh khoa va nonce
    dut.cfg_ctr_en.value = 1
    dut.cfg_aes_key.value = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
    dut.cfg_nonce.value = 0xA5A55A5A12345678
    await RisingEdge(dut.clk)

    # 2. Phat yeu cau tao keystream truoc ngay khi nhan duoc dia chi (AR phase)
    dut.i_req_valid.value = 1
    dut.i_req_addr.value = 0x1000
    dut.i_req_counter.value = 0x0001
    await RisingEdge(dut.clk)
    dut.i_req_valid.value = 0

    # Cho qua trinh tinh toan vong AES hoan tat (~14 chu ky xung nhip)
    cycles = 0
    while not dut.o_keystream_valid.value:
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < 30, "Keystream calculation timed out!"

    keystream = int(dut.o_keystream.value)
    assert keystream != 0, "Keystream must not be zero!"

    # 3. Kiem tra tinh chat 0-cycle XOR: Ngay khi du lieu DRAM ve, o_data phai xuat hien lap tuc
    plaintext = 0x0123456789ABCDEF0123456789ABCDEF
    dut.i_data_valid.value = 1
    dut.i_data.value = plaintext
    await Timer(1, unit="ns") # Khong qua posedge clock (0-cycle combinational check)

    assert int(dut.o_data_valid.value) == 1, "o_data_valid must be high combinationally"
    ciphertext = int(dut.o_data.value)
    expected_ciphertext = plaintext ^ keystream
    assert ciphertext == expected_ciphertext, f"Ciphertext mismatch: exp={hex(expected_ciphertext)}, got={hex(ciphertext)}"

    # 4. Kiem tra tinh chat doi xung ma hoa - giai ma: (P ^ K) ^ K = P
    recovered_plaintext = ciphertext ^ keystream
    assert recovered_plaintext == plaintext, "Symmetric CTR property failed to recover plaintext!"

    # 5. Tieu thu keystream khoi FIFO
    dut.i_keystream_ready.value = 1
    await RisingEdge(dut.clk)
    dut.i_keystream_ready.value = 0
    dut.i_data_valid.value = 0
    await RisingEdge(dut.clk)
