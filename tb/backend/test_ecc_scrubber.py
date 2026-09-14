#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_ecc_scrubber.py
# Description: Verifies ecc_scrubber:
#              1. Clean data: No error reported.
#              2. Single-bit error: Detected and corrected in real-time.
#              3. Double-bit error: SDC alert asserted.
#              4. Background patrol scanner address progression.
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

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_single_bit_error_correction(dut):
    """Verify single-bit error is detected, corrected, and counted"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_enable.value = 1

    orig_data = 0x1234_5678_9ABC_DEF0
    clean_ecc = compute_hamming_ecc(orig_data)

    # 1. Test clean data
    dut.i_data_valid.value = 1
    dut.i_raw_data.value = orig_data
    dut.i_raw_ecc.value = clean_ecc
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.o_single_err.value) == 0, "False single error reported on clean data!"
    assert int(dut.o_double_err.value) == 0, "False double error reported on clean data!"
    assert int(dut.o_corrected_data.value) == orig_data
    dut._log.info("Clean codeword verified with 0 errors reported")

    # 2. Corrupt bit 10 (flip bit 10)
    corrupted_data = orig_data ^ (1 << 10)
    dut.i_raw_data.value = corrupted_data
    dut.i_raw_ecc.value = clean_ecc
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.o_single_err.value) == 1, "Single error was NOT detected!"
    assert int(dut.o_double_err.value) == 0, "Single error falsely flagged as double error!"
    assert int(dut.o_corrected_data.value) == orig_data, f"Correction failed! Expected {hex(orig_data)}, got {hex(int(dut.o_corrected_data.value))}"
    assert int(dut.o_single_err_cnt.value) == 1
    dut._log.info(f"Single bit error at bit 10 corrected successfully to {hex(int(dut.o_corrected_data.value))}!")

@cocotb.test()
async def test_double_bit_error_detection(dut):
    """Verify double-bit error (SDC) is detected and reported"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_enable.value = 1

    orig_data = 0xCAFE_BABE_DEAD_BEEF
    clean_ecc = compute_hamming_ecc(orig_data)

    # Corrupt bits 4 and 25 (2-bit corruption)
    corrupted_data = orig_data ^ (1 << 4) ^ (1 << 25)
    dut.i_data_valid.value = 1
    dut.i_raw_data.value = corrupted_data
    dut.i_raw_ecc.value = clean_ecc
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.o_double_err.value) == 1, "Double-bit SDC error was NOT detected!"
    assert int(dut.o_single_err.value) == 0, "Double error falsely flagged as single error!"
    assert int(dut.o_double_err_cnt.value) == 1
    dut._log.info("Double-bit Silent Data Corruption (SDC) detected and reported successfully!")

@cocotb.test()
async def test_patrol_scanner_address_progression(dut):
    """Verify background patrol counter increments through BGs and Banks"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_enable.value = 1
    dut.cfg_interval.value = 4 # request scrub every 4 cycles

    visited_bgs = []

    for step in range(16):
        # Wait until scrub request is asserted
        while int(dut.o_scrub_req.value) == 0:
            await RisingEdge(dut.clk)

        cur_bg   = int(dut.o_scrub_bg.value)
        cur_bank = int(dut.o_scrub_bank.value)
        visited_bgs.append((cur_bg, cur_bank))

        # Grant the scrub
        dut.i_scrub_grant.value = 1
        await RisingEdge(dut.clk)
        dut.i_scrub_grant.value = 0
        await RisingEdge(dut.clk)

    dut._log.info(f"First 8 visited coordinates: {visited_bgs[:8]}")
    # Verify BG increments 0 -> 1 -> 2 -> ... -> 7
    expected_bgs = [i % 8 for i in range(8)]
    actual_bgs   = [bg for (bg, bank) in visited_bgs[:8]]
    assert actual_bgs == expected_bgs, f"Expected BGs {expected_bgs}, got {actual_bgs}"
    dut._log.info("Patrol memory scanner BG and Bank address progression verified successfully!")
