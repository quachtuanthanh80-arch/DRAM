#=============================================================================
# File:        test_eccfail_scrub_verify.py
# Description: Cocotb 2.1 Verification for Scrub-and-Verify Engine (ECCfail USENIX '25 Defense)
#              Verifies:
#              1. Single-bit errors corrected with syndrome re-check pass
#              2. 3-bit error clusters (syndrome aliasing) trapped with miscorrect alert
#              3. Autonomous escalation to Chipkill fallback
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

def hamming_positions():
    """Data bit j sits at the j-th Hamming position that is not a power of two (3, 5, 6, 7, 9, ...)."""
    pos, p = [], 3
    while len(pos) < 64:
        if p & (p - 1):
            pos.append(p)
        p += 1
    return pos


def compute_hamming_ecc(data):
    """Independent reference for SEC-DED (72,64): check bit i = XOR of data bits whose position has bit i set,
    bit 7 = overall parity, then the check byte is stored inverted (XOR 0xAA, as OpenTitan prim_secded_inv).
    Does not reuse the RTL mask constants."""
    ecc = 0
    for i in range(7):
        par = 0
        for j, p in enumerate(hamming_positions()):
            if (p >> i) & 1:
                par ^= (data >> j) & 1
        ecc |= par << i
    ecc |= (bin(data).count("1") + bin(ecc).count("1")) % 2 << 7
    return ecc ^ 0xAA

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_enable.value = 0
    dut.cfg_interval.value = 10
    dut.i_scrub_grant.value = 0
    dut.i_data_valid.value = 0
    dut.i_raw_data.value = 0
    dut.i_raw_ecc.value = 0
    dut.i_fault_inject_en.value = 0
    dut.i_fault_inject_type.value = 0
    dut.i_fault_inject_bit.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_single_bit_scrub_verify_pass(dut):
    """Verify standard single-bit error is corrected and passes verify without alert"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_enable.value = 1

    orig_data = 0xFEED_FACE_CAFE_BEEF
    clean_ecc = compute_hamming_ecc(orig_data)

    # Corrupt bit 12
    corrupted_data = orig_data ^ (1 << 12)
    dut.i_data_valid.value = 1
    dut.i_raw_data.value = corrupted_data
    dut.i_raw_ecc.value = clean_ecc
    await RisingEdge(dut.clk)
    await Timer(100, unit="ps")

    assert int(dut.o_single_err.value) == 1, "Single-bit error not flagged"
    assert int(dut.o_corrected_data.value) == orig_data, "Data correction mismatch"
    assert int(dut.o_ecc_miscorrect_alert.value) == 0, "False miscorrect alert triggered on 1-bit error!"
    dut._log.info("[PASS] Single-bit error successfully corrected and verified cleanly")

@cocotb.test()
async def test_eccfail_3bit_miscorrect_trap(dut):
    """Verify 3-bit error cluster (ECCfail attack) is caught by scrub-and-verify engine"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_enable.value = 1
    initial_miscorrect_cnt = int(dut.o_ecc_miscorrect_cnt.value)

    # Data bits 0, 4, 58 sit at Hamming positions 3, 9, 66: their syndromes XOR to position 72, which does not
    # exist in a (72,64) code. The decoder must trap this instead of flipping a bit.
    pos = hamming_positions()
    assert pos[0] ^ pos[4] ^ pos[58] > 71
    orig_data = 0x55AA_33CC_0F0F_A5A5
    clean_ecc = compute_hamming_ecc(orig_data)

    dut.i_data_valid.value = 1
    dut.i_raw_data.value = orig_data ^ (1 << 0) ^ (1 << 4) ^ (1 << 58)
    dut.i_raw_ecc.value = clean_ecc
    await RisingEdge(dut.clk)
    await Timer(100, unit="ps")

    # Scrub-and-Verify engine must catch the syndrome inconsistency
    assert int(dut.o_ecc_miscorrect_alert.value) == 1, \
        "Scrub-and-Verify Engine failed to trap 3-bit miscorrection!"
    assert int(dut.o_chipkill_fallback_req.value) == 1, \
        "Chipkill fallback request not asserted upon ECCfail trap!"
    assert int(dut.o_ecc_miscorrect_cnt.value) == initial_miscorrect_cnt + 1, \
        "Miscorrection counter did not increment!"

    dut._log.info("[PASS] ECCfail 3-bit cluster successfully trapped by Scrub-and-Verify Engine with Chipkill fallback requested")
