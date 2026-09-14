#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_qos_queue.py
# Description: Verifies Novelty Pillar #2 (QoS-Aware Bank-Group Selection):
#              1. QoS priority sorting: High-QoS commands beat Low-QoS commands.
#              2. Throttle-based Graceful Degradation: Safe traffic beats Throttled traffic.
#              3. Anti-Starvation aging: Old transactions get emergency boost.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_cmd_valid.value = 0
    dut.i_cmd_id.value = 0
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0
    dut.i_cmd_col.value = 0
    dut.i_cmd_len.value = 0
    dut.i_cmd_qos.value = 0
    dut.i_cmd_throttled.value = 0

    dut.i_issue_grant_valid.value = 0
    dut.i_issue_grant_bg.value = 0
    dut.i_issue_grant_idx.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

def get_cand_valid(dut, bg):
    return bool((int(dut.o_cand_valid.value) >> bg) & 1)

def get_cand_qos(dut, bg):
    return (int(dut.o_cand_qos.value) >> (bg * 4)) & 0xF

def get_cand_id(dut, bg):
    return (int(dut.o_cand_id.value) >> (bg * 4)) & 0xF

def get_cand_throttled(dut, bg):
    return bool((int(dut.o_cand_throttled.value) >> bg) & 1)

def get_cand_starved(dut, bg):
    return bool((int(dut.o_cand_starved.value) >> bg) & 1)

@cocotb.test()
async def test_qos_priority_ordering(dut):
    """Verify higher QoS request is selected as candidate within same Bank Group"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    target_bg = 3

    # Enqueue low QoS command first (QoS = 2, ID = 0x1)
    dut.i_cmd_valid.value = 1
    dut.i_cmd_id.value = 0x1
    dut.i_cmd_bg.value = target_bg
    dut.i_cmd_qos.value = 2
    dut.i_cmd_throttled.value = 0
    await RisingEdge(dut.clk)

    # Enqueue high QoS command second (QoS = 14, ID = 0x2)
    dut.i_cmd_id.value = 0x2
    dut.i_cmd_bg.value = target_bg
    dut.i_cmd_qos.value = 14
    dut.i_cmd_throttled.value = 0
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    await Timer(1, unit="ns")

    # Candidate for target_bg MUST be the high QoS transaction (ID = 0x2, QoS = 14)
    assert get_cand_valid(dut, target_bg) is True
    assert get_cand_qos(dut, target_bg) == 14, f"Expected QoS 14 but got {get_cand_qos(dut, target_bg)}"
    assert get_cand_id(dut, target_bg) == 0x2, f"Expected ID 0x2 but got {get_cand_id(dut, target_bg)}"
    dut._log.info("QoS Priority Ordering verified successfully!")

@cocotb.test()
async def test_throttle_graceful_degradation(dut):
    """Verify unthrottled command wins over throttled command even with higher nominal QoS"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    target_bg = 5

    # Command A: Throttled RowHammer traffic, Nominal QoS = 15 (Max QoS!)
    dut.i_cmd_valid.value = 1
    dut.i_cmd_id.value = 0xA
    dut.i_cmd_bg.value = target_bg
    dut.i_cmd_qos.value = 15
    dut.i_cmd_throttled.value = 1  # Throttled by SDC filter!
    await RisingEdge(dut.clk)

    # Command B: Benign Normal traffic, Nominal QoS = 3
    dut.i_cmd_id.value = 0xB
    dut.i_cmd_bg.value = target_bg
    dut.i_cmd_qos.value = 3
    dut.i_cmd_throttled.value = 0  # Benign!
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    await Timer(1, unit="ns")

    # Graceful Degradation check: Benign traffic (B) MUST be selected ahead of Throttled traffic (A)
    assert get_cand_valid(dut, target_bg) is True
    selected_id = get_cand_id(dut, target_bg)
    selected_throttled = get_cand_throttled(dut, target_bg)

    dut._log.info(f"Candidate Selected ID={hex(selected_id)}, Throttled={selected_throttled}")
    assert selected_id == 0xB, f"Expected Benign Cmd B (0xB) to beat Throttled Cmd A (0xA), but got {hex(selected_id)}"
    assert selected_throttled is False, "Candidate should NOT be throttled!"
    dut._log.info("Throttle Graceful Degradation verified successfully!")

@cocotb.test()
async def test_anti_starvation_aging(dut):
    """Verify aged commands get starvation boost and are served"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    target_bg = 1

    # Enqueue a low-priority command (QoS = 1)
    dut.i_cmd_valid.value = 1
    dut.i_cmd_id.value = 0x7
    dut.i_cmd_bg.value = target_bg
    dut.i_cmd_qos.value = 1
    dut.i_cmd_throttled.value = 0
    await RisingEdge(dut.clk)
    dut.i_cmd_valid.value = 0

    # Wait for STARVATION_LIMIT (64 cycles)
    for _ in range(70):
        await RisingEdge(dut.clk)

    await Timer(1, unit="ns")
    assert get_cand_starved(dut, target_bg) is True, "Expected entry to be flagged starved after 64 cycles!"
    dut._log.info("Anti-starvation aging verified successfully!")
