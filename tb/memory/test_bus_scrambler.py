# test_bus_scrambler.py
# Cocotb: bộ xáo trộn dữ liệu không trạng thái, keystream theo seed và địa chỉ word vật lý

import random

import cocotb
from cocotb.triggers import Timer


async def apply(dut, en, seed, key, data):
    dut.cfg_scramble_en.value = en
    dut.cfg_seed.value = seed
    dut.i_key.value = key
    dut.i_data.value = data
    await Timer(1, unit="ns")
    return dut.o_data.value.to_unsigned()


@cocotb.test()
async def test_scrambler_bypass(dut):
    """Tắt xáo trộn: dữ liệu ra bằng dữ liệu vào"""
    for _ in range(50):
        d = random.getrandbits(64)
        assert await apply(dut, 0, random.getrandbits(64), random.getrandbits(40), d) == d


@cocotb.test()
async def test_scrambler_involution(dut):
    """Cùng seed và địa chỉ: xáo hai lần trả lại dữ liệu gốc (chiều ghi và chiều đọc dùng chung một hàm)"""
    seed = 0x1357_9BDF_2468_ACE0
    for _ in range(200):
        key = random.getrandbits(40)
        d = random.getrandbits(64)
        s = await apply(dut, 1, seed, key, d)
        assert s != d, "Mặt nạ bằng 0 cho địa chỉ ngẫu nhiên"
        assert await apply(dut, 1, seed, key, s) == d, "Không giải xáo được bằng cùng seed và địa chỉ"


@cocotb.test()
async def test_scrambler_address_and_seed_dependence(dut):
    """Mặt nạ phụ thuộc địa chỉ và seed: hai địa chỉ kề nhau hay hai seed khác nhau cho mặt nạ khác nhau"""
    seed = 0xA5A5_5A5A_0123_4567
    masks = set()
    for key in range(256):
        masks.add(await apply(dut, 1, seed, key, 0))
    assert len(masks) == 256, f"Chỉ có {len(masks)} mặt nạ khác nhau cho 256 địa chỉ liên tiếp"
    m1 = await apply(dut, 1, seed, 0x1234, 0)
    m2 = await apply(dut, 1, seed ^ 1, 0x1234, 0)
    assert m1 != m2, "Đổi seed không đổi mặt nạ"
    # Khuếch tán: lật 1 bit địa chỉ làm đổi trung bình khoảng nửa số bit mặt nạ
    flips = []
    for b in range(40):
        a = await apply(dut, 1, seed, 0x5A5A5A5A5A, 0)
        c = await apply(dut, 1, seed, 0x5A5A5A5A5A ^ (1 << b), 0)
        flips.append(bin(a ^ c).count("1"))
    avg = sum(flips) / len(flips)
    assert 20 <= avg <= 44, f"Khuếch tán kém: trung bình {avg:.1f}/64 bit đổi khi lật 1 bit địa chỉ"


@cocotb.test()
async def test_scrambler_stateless(dut):
    """Mặt nạ không phụ thuộc thời gian hay số lệnh đã phát (LFSR bước theo lệnh cũ làm hỏng giải xáo, S16)"""
    seed = 0x0F0F_F0F0_1234_5678
    first = await apply(dut, 1, seed, 0x777, 0)
    for _ in range(100):
        await apply(dut, 1, seed, random.getrandbits(40), random.getrandbits(64))
    assert await apply(dut, 1, seed, 0x777, 0) == first
