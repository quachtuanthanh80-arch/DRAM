#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# Testbench:   test_rob.py
# Description: Verifies reorder_buffer_rob:
#              1. Out-of-Order DRAM Data Reassembly & In-Order AXI R Retirement.
#              2. Read-After-Write (RAW) Hazard Detection against active writes.
#              3. Zero-Bubble Flow Control and Skid Buffer backpressure resilience.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.i_alloc_valid.value = 0
    dut.i_alloc_id.value = 0
    dut.i_alloc_addr.value = 0
    dut.i_alloc_len.value = 0

    dut.i_wr_active_valid.value = 0
    dut.i_wr_active_addr.value = 0

    dut.i_wb_valid.value = 0
    dut.i_wb_tag.value = 0
    dut.i_wb_data.value = 0
    dut.i_wb_resp.value = 0
    dut.i_wb_last.value = 0

    dut.i_rready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_ooo_writeback_inorder_retirement(dut):
    """Verify Out-of-Order DRAM writebacks are retired in strict in-order sequence"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # 1. Allocate 3 requests
    # Req 0: ID=0x1, Addr=0x1000, Len=1 (2 beats)
    dut.i_alloc_valid.value = 1
    dut.i_alloc_id.value = 0x1
    dut.i_alloc_addr.value = 0x1000
    dut.i_alloc_len.value = 1
    await RisingEdge(dut.clk)
    tag0 = int(dut.o_alloc_tag.value)

    # Req 1: ID=0x2, Addr=0x2000, Len=0 (1 beat)
    dut.i_alloc_id.value = 0x2
    dut.i_alloc_addr.value = 0x2000
    dut.i_alloc_len.value = 0
    await RisingEdge(dut.clk)
    tag1 = int(dut.o_alloc_tag.value)

    # Req 2: ID=0x3, Addr=0x3000, Len=1 (2 beats)
    dut.i_alloc_id.value = 0x3
    dut.i_alloc_addr.value = 0x3000
    dut.i_alloc_len.value = 1
    await RisingEdge(dut.clk)
    tag2 = int(dut.o_alloc_tag.value)

    dut.i_alloc_valid.value = 0
    await RisingEdge(dut.clk)

    dut._log.info(f"Allocated tags: tag0={tag0}, tag1={tag1}, tag2={tag2}")

    # 2. DRAM completes writeback OUT-OF-ORDER!
    # Req 1 (tag 1) arrives FIRST
    dut.i_wb_valid.value = 1
    dut.i_wb_tag.value = tag1
    dut.i_wb_data.value = 0xBBBB_2222_BBBB_2222
    dut.i_wb_resp.value = 0
    dut.i_wb_last.value = 1
    await RisingEdge(dut.clk)

    # Req 2 (tag 2) arrives SECOND (2 beats)
    dut.i_wb_tag.value = tag2
    dut.i_wb_data.value = 0xCCCC_3333_0000_0001
    dut.i_wb_last.value = 0
    await RisingEdge(dut.clk)
    dut.i_wb_data.value = 0xCCCC_3333_0000_0002
    dut.i_wb_last.value = 1
    await RisingEdge(dut.clk)

    # Note: Even though Req 1 and Req 2 arrived, ROB head is Req 0!
    # Since Req 0 has not arrived yet, o_rvalid must be 0!
    await Timer(1, unit="ns")
    assert int(dut.o_rvalid.value) == 0, "ROB leaked out-of-order data before head transaction arrived!"
    dut._log.info("Verified: ROB holds back later transactions until head arrives.")

    # Req 0 (tag 0) arrives LAST (2 beats)
    dut.i_wb_tag.value = tag0
    dut.i_wb_data.value = 0xAAAA_1111_0000_0001
    dut.i_wb_last.value = 0
    await RisingEdge(dut.clk)
    dut.i_wb_data.value = 0xAAAA_1111_0000_0002
    dut.i_wb_last.value = 1
    await RisingEdge(dut.clk)
    dut.i_wb_valid.value = 0

    # 3. Now verify retired data stream to AXI R-channel
    # Expected retired beats:
    # Beat 0: ID=0x1, data=0xAAAA_1111_0000_0001, last=0
    # Beat 1: ID=0x1, data=0xAAAA_1111_0000_0002, last=1
    # Beat 2: ID=0x2, data=0xBBBB_2222_BBBB_2222, last=1
    # Beat 3: ID=0x3, data=0xCCCC_3333_0000_0001, last=0
    # Beat 4: ID=0x3, data=0xCCCC_3333_0000_0002, last=1
    expected = [
        (0x1, 0xAAAA_1111_0000_0001, 0),
        (0x1, 0xAAAA_1111_0000_0002, 1),
        (0x2, 0xBBBB_2222_BBBB_2222, 1),
        (0x3, 0xCCCC_3333_0000_0001, 0),
        (0x3, 0xCCCC_3333_0000_0002, 1)
    ]

    received = []
    dut.i_rready.value = 1

    for cycle in range(20):
        await Timer(1, unit="ns")
        if int(dut.o_rvalid.value) == 1:
            rec_id   = int(dut.o_rid.value)
            rec_data = int(dut.o_rdata.value)
            rec_last = int(dut.o_rlast.value)
            received.append((rec_id, rec_data, rec_last))
            dut._log.info(f"R-beat received: ID={hex(rec_id)}, Data={hex(rec_data)}, Last={rec_last}")
            if len(received) == len(expected):
                break
        await RisingEdge(dut.clk)

    assert len(received) == len(expected), f"Expected {len(expected)} beats, got {len(received)}"
    for idx, (exp, rec) in enumerate(zip(expected, received)):
        assert exp == rec, f"Beat {idx} mismatch: expected {exp}, got {rec}"

    dut._log.info("Out-of-order reassembly and in-order retirement verified successfully!")

@cocotb.test()
async def test_raw_hazard_detection(dut):
    """Verify Read-After-Write (RAW) collision detection on matching cachelines"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Set an active write transaction at address 0x0000_4000 (cacheline 0x0000_4000 >> 6 = 0x100)
    dut.i_wr_active_valid.value = 0x01 # Slot 0 active
    dut.i_wr_active_addr.value  = 0x0000_4000
    await RisingEdge(dut.clk)

    # Case 1: Incoming Read to same cacheline (0x0000_4020)
    dut.i_alloc_valid.value = 1
    dut.i_alloc_id.value    = 0x5
    dut.i_alloc_addr.value  = 0x0000_4020  # offset 0x20 in same 64B cacheline!
    dut.i_alloc_len.value   = 0
    await Timer(1, unit="ns")

    assert int(dut.o_raw_hazard.value) == 1, "RAW hazard was NOT asserted for matching cacheline!"
    assert (int(dut.o_raw_match_mask.value) & 1) == 1, "RAW match mask should point to slot 0"
    dut._log.info("RAW collision correctly asserted for same cacheline (0x4020 vs 0x4000)")

    # Case 2: Incoming Read to different cacheline (0x0000_5000)
    dut.i_alloc_addr.value = 0x0000_5000
    await Timer(1, unit="ns")
    assert int(dut.o_raw_hazard.value) == 0, "RAW hazard falsely asserted for non-colliding address!"
    dut._log.info("Non-colliding address correctly reported no hazard (0x5000 vs 0x4000)")

    # Case 3: Write completes -> hazard clears
    dut.i_alloc_addr.value = 0x0000_4020
    dut.i_wr_active_valid.value = 0x00
    await Timer(1, unit="ns")
    assert int(dut.o_raw_hazard.value) == 0, "RAW hazard should clear once active write clears!"
    dut._log.info("RAW hazard cleared after write completed successfully!")

@cocotb.test()
async def test_skid_buffer_backpressure(dut):
    """Verify AXI R-channel skid buffer holds data under backpressure without bubble or loss"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Allocate 1 request: ID=0x8, Addr=0x8000, Len=0 (1 beat)
    dut.i_alloc_valid.value = 1
    dut.i_alloc_id.value    = 0x8
    dut.i_alloc_addr.value  = 0x8000
    dut.i_alloc_len.value   = 0
    await RisingEdge(dut.clk)
    tag = int(dut.o_alloc_tag.value)
    dut.i_alloc_valid.value = 0
    await RisingEdge(dut.clk)

    # Master applies backpressure: i_rready = 0
    dut.i_rready.value = 0

    # DRAM completes data
    dut.i_wb_valid.value = 1
    dut.i_wb_tag.value   = tag
    dut.i_wb_data.value  = 0xDEAD_BEEF_CAFE_BABE
    dut.i_wb_resp.value  = 0
    dut.i_wb_last.value  = 1
    await RisingEdge(dut.clk)
    dut.i_wb_valid.value = 0

    # Wait 5 cycles while backpressured
    for _ in range(5):
        await RisingEdge(dut.clk)

    # Verify o_rvalid is asserted and data is preserved
    await Timer(1, unit="ns")
    assert int(dut.o_rvalid.value) == 1, "o_rvalid must remain high during backpressure"
    assert int(dut.o_rdata.value) == 0xDEAD_BEEF_CAFE_BABE, "Data corrupted under backpressure!"
    assert int(dut.o_rid.value) == 0x8

    # Master releases backpressure
    dut.i_rready.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    # Buffer should now be empty
    assert int(dut.o_rob_empty.value) == 1, "ROB should be empty after transaction retirement!"
    dut._log.info("Skid buffer backpressure and data integrity verified successfully!")
