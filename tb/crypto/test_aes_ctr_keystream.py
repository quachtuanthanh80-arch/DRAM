# test_aes_ctr_keystream.py
# Kiem tra bo tinh toan truoc keystream AES-256-CTR va do tre doc/ghi XOR 0-cycle

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_ctr_en.value = 0
    for r in range(15):
        dut.round_keys[r].value = 0x000102030405060708090A0B0C0D0E0F ^ (r << 16)
    dut.i_precomp_valid.value = 0
    dut.i_precomp_tag.value = 0
    for b in range(4):
        dut.i_precomp_ctr_blocks[b].value = 0
    dut.i_rd_valid.value = 0
    dut.i_rd_tag.value = 0
    dut.i_rd_data.value = 0
    dut.i_rd_pop.value = 0
    dut.i_wr_valid.value = 0
    dut.i_wr_tag.value = 0
    dut.i_wr_data.value = 0
    dut.i_wr_pop.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_keystream_precomputation_and_zero_latency_xor(dut):
    """Kiem tra tinh toan truoc keystream 512-bit (qua 14 chu ky AES pipeline) va phep XOR 0-cycle"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_ctr_en.value = 1
    await RisingEdge(dut.clk)

    # 1. Phat yeu cau Precomputation cho Tag = 3
    target_tag = 3
    dut.i_precomp_valid.value = 1
    dut.i_precomp_tag.value = target_tag
    for b in range(4):
        dut.i_precomp_ctr_blocks[b].value = 0xA0000000_B0000000_C0000000_D0000000 | b

    await RisingEdge(dut.clk)
    dut.i_precomp_valid.value = 0

    # 2. Cho duong ong AES 14 vong hoan tat (~18 chu ky)
    timeout = 30
    cycles = 0
    while not ((int(dut.tag_valid_q.value) >> target_tag) & 1):
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < timeout, "Precomputation timed out waiting for tag_valid_q!"

    # 3. Kiem tra tinh chat 0-cycle XOR Doc (Combinational hit & decrypt)
    plaintext_rd = 0x112233445566778899AABBCCDDEEFF00_A1B2C3D4E5F60718293A4B5C6D7E8F90_FEDCBA9876543210FEDCBA9876543210_0123456789ABCDEF0123456789ABCDEF
    dut.i_rd_valid.value = 1
    dut.i_rd_tag.value = target_tag
    dut.i_rd_data.value = plaintext_rd
    await Timer(1, unit="ns") # Kiem tra ngay trong chu ky hien tai (0-cycle combinational)

    assert int(dut.o_rd_hit.value) == 1, "o_rd_hit must be high immediately!"
    assert int(dut.o_rd_valid.value) == 1, "o_rd_valid must be asserted combinationally!"
    ciphertext_rd = int(dut.o_rd_data.value)
    assert ciphertext_rd != plaintext_rd, "Ciphertext must be distinct from plaintext!"

    # 4. Pop tag khoi Tag Buffer
    dut.i_rd_pop.value = 1
    await RisingEdge(dut.clk)
    dut.i_rd_pop.value = 0
    dut.i_rd_valid.value = 0
    await Timer(1, unit="ns")

    assert not ((int(dut.tag_valid_q.value) >> target_tag) & 1), "Tag must be cleared after pop!"

    # 5. Kiem tra tiep cho chieu Ghi voi Tag = 7
    wr_tag = 7
    dut.i_precomp_valid.value = 1
    dut.i_precomp_tag.value = wr_tag
    for b in range(4):
        dut.i_precomp_ctr_blocks[b].value = 0x55555555_66666666_77777777_88888888 | (b << 4)
    await RisingEdge(dut.clk)
    dut.i_precomp_valid.value = 0

    cycles = 0
    while not ((int(dut.tag_valid_q.value) >> wr_tag) & 1):
        await RisingEdge(dut.clk)
        cycles += 1
        assert cycles < timeout, "Precomputation for write tag timed out!"

    plaintext_wr = 0xCAFEBABE_DEADBEEF_00112233_44556677_8899AABB_CCDDEEFF_01020304_05060708_12345678_9ABCDEF0_FEDCBA98_76543210_FFFFFFFF_00000000_AAAAAAAA_55555555
    dut.i_wr_valid.value = 1
    dut.i_wr_tag.value = wr_tag
    dut.i_wr_data.value = plaintext_wr
    await Timer(1, unit="ns")

    assert int(dut.o_wr_hit.value) == 1, "o_wr_hit must be high immediately!"
    assert int(dut.o_wr_valid.value) == 1, "o_wr_valid must be asserted combinationally!"
    ciphertext_wr = int(dut.o_wr_data.value)
    assert ciphertext_wr != plaintext_wr, "Write ciphertext must differ from plaintext!"

    dut.i_wr_pop.value = 1
    await RisingEdge(dut.clk)
    dut.i_wr_pop.value = 0
    dut.i_wr_valid.value = 0
