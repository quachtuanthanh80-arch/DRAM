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

def compute_hamming_ecc(data):
    p = [0] * 7
    masks = [
        0x5555_5555_5555_5555,
        0x6666_6666_6666_6666,
        0x7878_7878_7878_7878,
        0x7F80_7F80_7F80_7F80,
        0x7FFF_8000_7FFF_8000,
        0x7FFF_FFFF_8000_0000,
        0x8000_0000_0000_0000
    ]
    for i in range(7):
        p[i] = (bin(data & masks[i]).count("1")) % 2

    overall_data_parity = bin(data).count("1") % 2
    overall_p_parity = sum(p) % 2
    p7 = (overall_data_parity ^ overall_p_parity) % 2

    ecc = 0
    for i in range(7):
        ecc |= (p[i] << i)
    ecc |= (p7 << 7)
    return ecc

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

    # Use hardware fault injector with type 2'b11 (3-bit flip cluster)
    orig_data = 0x55AA_33CC_0F0F_A5A5
    clean_ecc = compute_hamming_ecc(orig_data)

    dut.i_data_valid.value = 1
    dut.i_raw_data.value = orig_data
    dut.i_raw_ecc.value = clean_ecc
    dut.i_fault_inject_en.value = 1
    dut.i_fault_inject_type.value = 3 # 3-bit fault cluster
    dut.i_fault_inject_bit.value = 8
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
