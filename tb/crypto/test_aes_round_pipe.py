# File: test_aes_round_pipe.py
# Chức năng: Kiểm chứng tầng pipeline biến đổi AES round (SubBytes, ShiftRows, MixColumns, AddRoundKey).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

SBOX = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5e, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
]

def xtime(b):
    return ((b << 1) ^ 0x1b) & 0xff if (b & 0x80) else (b << 1) & 0xff

def mul03(b):
    return xtime(b) ^ b

def ref_aes_round(state_in_128, round_key_128, is_final=False):
    # 1. SubBytes: 16 bytes
    raw_bytes = [(state_in_128 >> (i * 8)) & 0xff for i in range(16)]
    sub_bytes = [SBOX[b] for b in raw_bytes]

    # Convert to 4x4 matrix: matrix[col][row] where col = 0..3, row = 0..3
    matrix = [[sub_bytes[c * 4 + r] for r in range(4)] for c in range(4)]

    # 2. ShiftRows
    shifted = [[0]*4 for _ in range(4)]
    # Row 0: no shift
    for c in range(4): shifted[c][0] = matrix[c][0]
    # Row 1: shift left 1
    shifted[0][1] = matrix[1][1]; shifted[1][1] = matrix[2][1]
    shifted[2][1] = matrix[3][1]; shifted[3][1] = matrix[0][1]
    # Row 2: shift left 2
    shifted[0][2] = matrix[2][2]; shifted[1][2] = matrix[3][2]
    shifted[2][2] = matrix[0][2]; shifted[3][2] = matrix[1][2]
    # Row 3: shift left 3
    shifted[0][3] = matrix[3][3]; shifted[1][3] = matrix[0][3]
    shifted[2][3] = matrix[1][3]; shifted[3][3] = matrix[2][3]

    # 3. MixColumns (if not final)
    mixed = [[0]*4 for _ in range(4)]
    for c in range(4):
        if is_final:
            mixed[c] = shifted[c]
        else:
            c0, c1, c2, c3 = shifted[c][0], shifted[c][1], shifted[c][2], shifted[c][3]
            mixed[c][0] = xtime(c0) ^ mul03(c1) ^ c2 ^ c3
            mixed[c][1] = c0 ^ xtime(c1) ^ mul03(c2) ^ c3
            mixed[c][2] = c0 ^ c1 ^ xtime(c2) ^ mul03(c3)
            mixed[c][3] = mul03(c0) ^ c1 ^ c2 ^ xtime(c3)

    # 4. Pack into 128-bit vector
    mixed_128 = 0
    for c in range(4):
        for r in range(4):
            byte_idx = c * 4 + r
            mixed_128 |= (mixed[c][r] << (byte_idx * 8))

    # 5. AddRoundKey
    return mixed_128 ^ round_key_128

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.is_final_round.value = 0
    dut.state_in.value = 0
    dut.round_key.value = 0
    dut.out_ready.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_reset_and_ready(dut):
    """Kiem tra reset khoi tao: valid out bang 0 va san sang tiep nhan du lieu (in_ready = 1)"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    assert dut.out_valid.value == 0, "out_valid phai bang 0 sau reset"
    assert dut.in_ready.value == 1, "in_ready phai bang 1 sau reset"

@cocotb.test()
async def test_intermediate_round_kat(dut):
    """Kiem tra tinh toan vong trung gian (SubBytes -> ShiftRows -> MixColumns -> AddRoundKey)"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    state = 0x00102030_40506070_8090A0B0_C0D0E0F0
    rkey  = 0xD6AA74FD_D2AF72F8_DDAA77FD_D2AF72F8

    dut.is_final_round.value = 0
    dut.state_in.value = state
    dut.round_key.value = rkey
    dut.in_valid.value = 1

    await RisingEdge(dut.clk)
    dut.in_valid.value = 0

    await Timer(1, unit="ns")
    assert dut.out_valid.value == 1, "out_valid phai asserted sau 1 chu ky clock"

    exp_result = ref_aes_round(state, rkey, is_final=False)
    got_result = int(dut.state_out.value)
    assert got_result == exp_result, f"Intermediate round mismatch: got {hex(got_result)}, exp {hex(exp_result)}"

@cocotb.test()
async def test_final_round_kat(dut):
    """Kiem tra tinh toan vong cuoi (khong thuc hien MixColumns)"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    state = 0xBD6E7C3D_F2B5779E_0B61216E_8B102035
    rkey  = 0x13111D7F_E3944A17_F307A78B_4D2B30C5

    dut.is_final_round.value = 1
    dut.state_in.value = state
    dut.round_key.value = rkey
    dut.in_valid.value = 1

    await RisingEdge(dut.clk)
    dut.in_valid.value = 0

    await Timer(1, unit="ns")
    assert dut.out_valid.value == 1

    exp_result = ref_aes_round(state, rkey, is_final=True)
    got_result = int(dut.state_out.value)
    assert got_result == exp_result, f"Final round mismatch: got {hex(got_result)}, exp {hex(exp_result)}"

@cocotb.test()
async def test_backpressure_stall(dut):
    """Kiem tra co che backpressure: out_ready = 0 giu nguyen output va keo in_ready ve 0"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    state = 0x01234567_89ABCDEF_FEDCBA98_76543210
    rkey  = 0xCAFEBABE_DEADBEEF_00112233_44556677

    # Nap 1 block
    dut.is_final_round.value = 0
    dut.state_in.value = state
    dut.round_key.value = rkey
    dut.in_valid.value = 1
    dut.out_ready.value = 0 # Downstream dang bận

    await RisingEdge(dut.clk)
    dut.in_valid.value = 0

    await Timer(1, unit="ns")
    assert dut.out_valid.value == 1, "Output valid phai asserted sau khi nap"
    assert dut.in_ready.value == 0, "in_ready phai ha xuong 0 vi register slice dang giu ket qua va out_ready=0"

    exp_result = ref_aes_round(state, rkey, is_final=False)
    assert int(dut.state_out.value) == exp_result

    # Giu out_ready = 0 trong 3 cycles, output khong duoc thay doi
    for _ in range(3):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        assert dut.out_valid.value == 1
        assert int(dut.state_out.value) == exp_result
        assert dut.in_ready.value == 0

    # Downstream san sang tiep nhan
    dut.out_ready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.out_valid.value == 0, "out_valid phai deassert sau khi downstream doc du lieu"
    assert dut.in_ready.value == 1, "in_ready phai tro lai 1"

@cocotb.test()
async def test_random_streaming(dut):
    """Kiem tra chuoi 30 vector ngau nhien continuous stream voi ca normal va final rounds"""
    clock = Clock(dut.clk, 4, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for i in range(30):
        state = random.getrandbits(128)
        rkey  = random.getrandbits(128)
        is_final = (i % 5 == 0)

        dut.is_final_round.value = int(is_final)
        dut.state_in.value = state
        dut.round_key.value = rkey
        dut.in_valid.value = 1
        dut.out_ready.value = 1

        await RisingEdge(dut.clk)
        dut.in_valid.value = 0

        await Timer(1, unit="ns")
        exp = ref_aes_round(state, rkey, is_final=is_final)
        assert int(dut.state_out.value) == exp
