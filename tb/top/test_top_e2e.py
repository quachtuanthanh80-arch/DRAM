#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5 Memory Controller
# File:        test_top_e2e.py
# Description: Full System End-to-End Cocotb Testbench for axi_ddr5_mc_top.
#              Tests:
#              1. Full AXI Write transaction flow through decoupling buffer,
#                 address mapper, QoS queue, and DFI command issue.
#              2. Full AXI Read transaction flow through ROB allocation,
#                 DRAM read latency shift pipe, and AXI R channel return.
#              3. End-to-End RowHammer Defense: Repeated row activation triggers
#                 SDC dual-hash throttling and graceful QoS degradation.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

SECDED_MASKS = (
    0xAB55555556AAAD5B,
    0xCD9999999B33366D,
    0xF1E1E1E1E3C3C78E,
    0x01FE01FE03FC07F0,
    0x01FFFE0003FFF800,
    0x01FFFFFFFC000000,
    0xFE00000000000000,
)


def secded72_enc(d: int) -> int:
    d &= (1 << 64) - 1
    e = 0
    for i, mask in enumerate(SECDED_MASKS):
        if (d & mask).bit_count() & 1:
            e |= 1 << i
    p7 = (d.bit_count() ^ e.bit_count()) & 1
    return (e | (p7 << 7)) ^ 0xAA


async def dfi_dram_responder(dut, rdlat: int = 8):
    """Phan hoi du lieu doc DFI dung do tre DFI_RDLAT va kem ECC SEC-DED hop le."""
    cyc = 0
    rd_sched = {}
    wr_queue = []
    mem = {}
    while True:
        await RisingEdge(dut.clk_axi)
        await Timer(1, unit="ps")
        if int(dut.aresetn_axi.value) == 0:
            cyc = 0
            rd_sched.clear()
            wr_queue.clear()
            dut.dfi_rddata_valid.value = 0
            dut.dfi_rddata.value = 0
            dut.dfi_rddata_ecc.value = 0
            continue

        cmd = int(dut.dfi_cmd.value)
        bg = int(dut.dfi_bg.value)
        bank = int(dut.dfi_bank.value)
        row = int(dut.dfi_row.value)
        col = int(dut.dfi_col.value)
        blen = int(dut.dfi_len.value)

        if cmd == 3:  # CMD_RD
            for b in range(blen + 1):
                rd_sched[cyc + rdlat + b] = (bg, bank, row, col + b)
        elif cmd == 4:  # CMD_WR
            wr_queue.append([bg, bank, row, col, blen, 0])

        if int(dut.dfi_wrdata_en.value) == 1 and wr_queue:
            w = wr_queue[0]
            key = (w[0], w[1], w[2], w[3] + w[5])
            wdata = int(dut.dfi_wrdata.value)
            wmask = int(dut.dfi_wrdata_mask.value)
            cur = mem.get(key, 0)
            for by in range(8):
                if (wmask >> by) & 1:
                    cur = (cur & ~(0xFF << (8 * by))) | (((wdata >> (8 * by)) & 0xFF) << (8 * by))
            mem[key] = cur
            if w[5] == w[4]:
                wr_queue.pop(0)
            else:
                w[5] += 1

        if cyc in rd_sched:
            key = rd_sched.pop(cyc)
            val = mem.get(key, (0xDEAD << 48) | ((key[2] & 0xFFFF) << 16) | (key[3] & 0xFFFF))
            dut.dfi_rddata_valid.value = 1
            dut.dfi_rddata.value = val
            dut.dfi_rddata_ecc.value = secded72_enc(val)
        else:
            dut.dfi_rddata_valid.value = 0
            dut.dfi_rddata.value = 0
            dut.dfi_rddata_ecc.value = 0
        cyc += 1

async def reset_dut(dut):
    """Async assert, sync deassert reset for both clock domains"""
    dut.aresetn_axi.value = 0
    dut.aresetn_ddr.value = 0
    
    # AXI Inputs
    dut.s_axi_awid.value    = 0
    dut.s_axi_awaddr.value  = 0
    dut.s_axi_awlen.value   = 0
    dut.s_axi_awsize.value  = 3  # 8 bytes per beat (64-bit)
    dut.s_axi_awburst.value = 1  # INCR
    dut.s_axi_awqos.value   = 0
    dut.s_axi_awvalid.value = 0
    
    dut.s_axi_wdata.value   = 0
    dut.s_axi_wstrb.value   = 0
    dut.s_axi_wlast.value   = 0
    dut.s_axi_wvalid.value  = 0
    
    dut.s_axi_bready.value  = 1
    
    dut.s_axi_arid.value    = 0
    dut.s_axi_araddr.value  = 0
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value   = 0
    dut.s_axi_arvalid.value = 0
    
    dut.s_axi_rready.value  = 1
    dut.dfi_rddata_valid.value = 0
    dut.dfi_rddata.value       = 0
    dut.dfi_rddata_ecc.value   = 0
    
    # Configuration
    dut.cfg_bank_coloring_en.value = 0
    dut.cfg_mapping_mode.value     = 0
    dut.cfg_scramble_en.value      = 0
    dut.cfg_scramble_reseed.value  = 0
    dut.cfg_scramble_seed.value    = 0xA5A5_5A5A_0123_4567
    dut.cfg_pmu_en.value           = 1
    dut.cfg_pmu_reset.value        = 0
    dut.cfg_rowpress_curve.value   = 0
    dut.cfg_victim3_en.value       = 0
    dut.i_dram_abo_alert.value     = 0
    dut.cfg_scramble_mode.value    = 0
    dut.cfg_decoy_en.value         = 0
    dut.cfg_is_ddr5.value      = 1
    dut.cfg_dual_hash_en.value = 1
    dut.cfg_rh_threshold.value = 8
    dut.cfg_window_size.value  = 100
    
    for _ in range(10):
        await RisingEdge(dut.clk_axi)
        
    dut.aresetn_axi.value = 1
    dut.aresetn_ddr.value = 1
    
    for _ in range(5):
        await RisingEdge(dut.clk_axi)

@cocotb.test()
async def test_axi_write_burst_e2e(dut):
    """Verify end-to-end AXI write transaction: Frontend -> WBuffer -> Mapper -> Queue -> DFI"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns") # 200 MHz
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns") # Synced for testing
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    cocotb.start_soon(dfi_dram_responder(dut))
    dut._log.info("Reset complete. Starting AXI Write Burst E2E Test.")

    # Issue AXI Write Address & Data
    dut.s_axi_awid.value    = 0x1
    dut.s_axi_awaddr.value  = 0x0001_0000
    dut.s_axi_awlen.value   = 0
    dut.s_axi_awsize.value  = 3
    dut.s_axi_awburst.value = 1
    dut.s_axi_awqos.value   = 4
    dut.s_axi_awvalid.value = 1

    dut.s_axi_wdata.value   = 0xDEADBEEFCAFE1234
    dut.s_axi_wstrb.value   = 0xFF
    dut.s_axi_wlast.value   = 1
    dut.s_axi_wvalid.value  = 1

    aw_done = False
    w_done  = False

    for _ in range(50):
        await RisingEdge(dut.clk_axi)
        if int(dut.s_axi_awready.value) == 1 and not aw_done:
            aw_done = True
            dut.s_axi_awvalid.value = 0
        if int(dut.s_axi_wready.value) == 1 and not w_done:
            w_done = True
            dut.s_axi_wvalid.value = 0
        if aw_done and w_done:
            break

    assert aw_done, "AW handshake failed to complete"
    assert w_done, "W handshake failed to complete"
    dut._log.info("AW & W handshakes successfully completed!")

    # Wait for B response
    b_received = False
    for _ in range(50):
        await RisingEdge(dut.clk_axi)
        if int(dut.s_axi_bvalid.value) == 1:
            assert int(dut.s_axi_bid.value) == 0x1, f"Expected BID 0x1, got {int(dut.s_axi_bid.value)}"
            assert int(dut.s_axi_bresp.value) == 0, f"Expected BRESP OKAY, got {int(dut.s_axi_bresp.value)}"
            b_received = True
            break

    assert b_received, "AXI B-channel response was not received within timeout"
    dut._log.info("AXI B-channel OKAY response verified successfully!")

    # Verify DFI command stream activity (ACT or WR)
    dfi_seen = False
    for _ in range(100):
        await RisingEdge(dut.clk_axi)
        cmd = int(dut.dfi_cmd.value)
        if cmd != 0: # 1=RD, 2=WR, 3=ACT, 4=PRE
            dut._log.info(f"Observed DFI Command: {cmd} at BG={int(dut.dfi_bg.value)} Bank={int(dut.dfi_bank.value)}")
            dfi_seen = True
            break

    assert dfi_seen, "DFI Command Engine did not emit any memory command"
    dut._log.info("AXI Write Burst E2E Test PASSED!")


@cocotb.test()
async def test_axi_read_e2e_reorder_and_return(dut):
    """Verify end-to-end AXI read transaction: Frontend -> ROB -> DFI -> Return -> R Channel"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    cocotb.start_soon(dfi_dram_responder(dut))
    dut._log.info("Reset complete. Starting AXI Read E2E Test.")

    # Issue AXI Read Address
    dut.s_axi_arid.value    = 0x5
    dut.s_axi_araddr.value  = 0x0002_4000
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value   = 7
    dut.s_axi_arvalid.value = 1

    ar_done = False
    for _ in range(50):
        await RisingEdge(dut.clk_axi)
        if int(dut.s_axi_arready.value) == 1:
            ar_done = True
            dut.s_axi_arvalid.value = 0
            break

    assert ar_done, "AR handshake failed to complete"
    dut._log.info("AR handshake completed successfully!")

    # Wait for R channel data return from ROB
    r_received = False
    for _ in range(150):
        await RisingEdge(dut.clk_axi)
        if int(dut.s_axi_rvalid.value) == 1:
            assert int(dut.s_axi_rid.value) == 0x5, f"Expected RID 0x5, got {int(dut.s_axi_rid.value)}"
            assert int(dut.s_axi_rresp.value) == 0, f"Expected RRESP OKAY, got {int(dut.s_axi_rresp.value)}"
            assert int(dut.s_axi_rlast.value) == 1, "Expected RLAST asserted for single beat"
            r_received = True
            dut._log.info(f"Received R beat: Data=0x{int(dut.s_axi_rdata.value):016x} ID={int(dut.s_axi_rid.value)}")
            break

    assert r_received, "AXI R-channel read data was not returned within timeout"
    dut._log.info("AXI Read E2E Test PASSED!")


@cocotb.test()
async def test_rowhammer_sdc_defense_e2e(dut):
    """Verify End-to-End RowHammer Defense: Blast target row > threshold, verify throttling telemetry"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)
    cocotb.start_soon(dfi_dram_responder(dut))
    dut.cfg_rh_threshold.value = 4  # Low threshold to trigger quickly
    dut.cfg_window_size.value  = 50
    dut._log.info("Configured RH threshold = 4, window = 50 cycles")

    # Send 8 consecutive reads to target row address (0x0005_0000)
    target_addr = 0x0005_0000
    for i in range(8):
        dut.s_axi_arid.value    = (i & 0xF)
        dut.s_axi_araddr.value  = target_addr
        dut.s_axi_arlen.value   = 0
        dut.s_axi_arqos.value   = 2
        dut.s_axi_arvalid.value = 1

        for _ in range(20):
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_arready.value) == 1:
                dut.s_axi_arvalid.value = 0
                break
        await RisingEdge(dut.clk_axi)

    # Allow controller pipeline to process and update filter
    for _ in range(60):
        await RisingEdge(dut.clk_axi)

    throttled = int(dut.o_throttled_events.value)
    dut._log.info(f"Observed total throttled events: {throttled}")
    assert throttled > 0, f"Expected throttled events > 0 after blasting row, got {throttled}"

    dut._log.info("End-to-End RowHammer SDC Defense Test PASSED!")
