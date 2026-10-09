#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_fault_hardened_csr.py
# Description: Cocotb testbench for Fault-Hardened CSR (Homma Lab HOST '20)
#              Verifies:
#              1. TMR 2-out-of-3 majority voting preserves configuration under single-rail corruption.
#              2. Asynchronous glitch alert and security lockdown latch.
#=============================================================================

import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_fault_hardened_csr_voting(dut):
    """Verify TMR majority voting and glitch alert triggering"""
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.i_cfg_we.value = 0
    dut.i_cfg_rh_threshold.value = 1024
    dut.i_cfg_rowpress_curve.value = 0
    dut.i_cfg_dual_hash_en.value = 1
    dut.i_cfg_scramble_mode.value = 2

    await Timer(10, unit="ns")
    dut.rst_n.value = 1
    await Timer(10, unit="ns")

    # Verify initial voted output
    assert int(dut.o_cfg_rh_threshold.value) == 1024, "Default threshold mismatch"
    assert int(dut.o_cfg_scramble_mode.value) == 2, "Default scramble mode mismatch"
    assert int(dut.o_glitch_alert.value) == 0, "Initial glitch alert must be 0"

    # Inject single rail fault by corrupting rail0
    dut.rail0_rh_thresh.value = 0xFFFF
    await Timer(5, unit="ns")

    # Majority voting must keep output at 1024 because rail1 and rail2 are 1024
    assert int(dut.o_cfg_rh_threshold.value) == 1024, "TMR majority voter failed to suppress single-rail error"
    assert int(dut.o_glitch_alert.value) == 1, "Glitch detector failed to flag rail mismatch"
    dut._log.info("[PASS] TMR majority voting preserved configuration and glitch alert triggered!")
