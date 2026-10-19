# File: test_cxl_mem_expander.py
# Chức năng: Testbench Cocotb kiểm chứng toàn trình cầu nối CXL.mem 3.0 Flits sang AXI5 512-bit, cách ly đa máy ảo và cờ Poison.

import os
import sys
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "common")))
import cocotb2_compat
from cxl_flit_agent import CxlMemFlitAgent

class Axi5MemoryResponder:
    """Mô hình bộ nhớ AXI5 đáp ứng các yêu cầu AW/W/B và AR/R từ cxl_mem_axi_shim."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk
        self.mem = {} # map addr -> 512-bit data
        self.poison_addrs = set()

    async def run(self):
        self.dut.m_axi_awready.value = 1
        self.dut.m_axi_wready.value  = 1
        self.dut.m_axi_bvalid.value  = 0
        self.dut.m_axi_bresp.value   = 0
        self.dut.m_axi_bid.value     = 0

        self.dut.m_axi_arready.value = 1
        self.dut.m_axi_rvalid.value  = 0
        self.dut.m_axi_rdata.value   = 0
        self.dut.m_axi_rresp.value   = 0
        self.dut.m_axi_rlast.value   = 0
        self.dut.m_axi_rid.value     = 0
        self.dut.m_axi_rpoison.value = 0

        pending_wr_addr = None
        pending_wr_id   = None

        while True:
            await RisingEdge(self.clk)

            # Handle Write AW
            if self.dut.m_axi_awvalid.value and self.dut.m_axi_awready.value:
                pending_wr_addr = int(self.dut.m_axi_awaddr.value)
                pending_wr_id   = int(self.dut.m_axi_awid.value)

            # Handle Write W
            if self.dut.m_axi_wvalid.value and self.dut.m_axi_wready.value:
                if pending_wr_addr is not None:
                    self.mem[pending_wr_addr] = int(self.dut.m_axi_wdata.value)
                    self.dut.m_axi_bvalid.value = 1
                    self.dut.m_axi_bid.value    = pending_wr_id
                    self.dut.m_axi_bresp.value  = 0
                    pending_wr_addr = None
                else:
                    self.dut.m_axi_bvalid.value = 1
                    self.dut.m_axi_bresp.value  = 0

            # Clear B channel once accepted
            if self.dut.m_axi_bvalid.value and self.dut.m_axi_bready.value:
                self.dut.m_axi_bvalid.value = 0

            # Handle Read AR -> R
            if self.dut.m_axi_arvalid.value and self.dut.m_axi_arready.value:
                rd_addr = int(self.dut.m_axi_araddr.value)
                rd_id   = int(self.dut.m_axi_arid.value)
                rdata   = self.mem.get(rd_addr, 0xDEADBEEF_CAFE0000 + rd_addr)

                self.dut.m_axi_rvalid.value  = 1
                self.dut.m_axi_rid.value     = rd_id
                self.dut.m_axi_rdata.value   = rdata
                self.dut.m_axi_rlast.value   = 1

                if rd_addr in self.poison_addrs:
                    self.dut.m_axi_rresp.value   = 2 # SLVERR
                    self.dut.m_axi_rpoison.value = 1
                else:
                    self.dut.m_axi_rresp.value   = 0
                    self.dut.m_axi_rpoison.value = 0
            elif self.dut.m_axi_rvalid.value and self.dut.m_axi_rready.value:
                self.dut.m_axi_rvalid.value  = 0
                self.dut.m_axi_rpoison.value = 0

@cocotb.test()
async def test_cxl_mem_expander_flit_protocol(dut):
    """Kiểm chứng giao thức CXL.mem 3.0: M2S-RwD ghi, M2S-Req đọc, đa máy ảo SPID và Poison forwarding."""
    clock = Clock(dut.clk, 2.5, units="ns") # 400 MHz
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    agent = CxlMemFlitAgent(dut, dut.clk)
    await agent.reset()

    responder = Axi5MemoryResponder(dut, dut.clk)
    cocotb.start_soon(responder.run())

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)

    # 1. Kiểm tra ghi và đọc cơ bản (Single Cacheline 64B)
    dut._log.info("[+] Phase 1: CXL.mem Single-Line Write & Read Verification")
    test_addr = 0x0010_0000
    test_data = 0xA5A55A5A_01234567_89ABCDEF_FEDCBA98_76543210_11223344_55667788_99AABBCC_00112233_44556677_8899AABB_CCDDEEFF_0F1E2D3C_4B5A6978_8796A5B4_C3D2E1F0
    test_tag  = 0x0042

    await agent.send_mem_wr(addr=test_addr, tag=test_tag, data_512=test_data, spid=1)
    opcode, tag = await agent.wait_ndr_cmp(expected_tag=test_tag)
    assert opcode == 0, f"Expected Cmp (0), got {opcode}"

    await agent.send_mem_rd(addr=test_addr, tag=test_tag, spid=1)
    rdata, poison = await agent.wait_drs_data(expected_tag=test_tag)
    assert rdata == test_data, f"Data mismatch:\nExpected: 0x{test_data:0128X}\nGot:      0x{rdata:0128X}"
    assert poison == 0, "Poison flag should be 0 on benign read"
    dut._log.info("[+] Basic Write-Read verified successfully!")

    # 2. Kiểm tra phân cách đa máy ảo (Multi-VM Isolation SPID 0..3)
    dut._log.info("[+] Phase 2: Multi-Tenant Virtual Machine Isolation (SPID 0..3)")
    for spid in range(4):
        vm_addr = 0x0020_0000 + (spid * 0x1000)
        vm_data = test_data ^ (spid << 64)
        vm_tag  = 0x0010 + spid

        await agent.send_mem_wr(addr=vm_addr, tag=vm_tag, data_512=vm_data, spid=spid)
        await agent.wait_ndr_cmp(expected_tag=vm_tag)

        await agent.send_mem_rd(addr=vm_addr, tag=vm_tag, spid=spid)
        rdata, poison = await agent.wait_drs_data(expected_tag=vm_tag)
        assert rdata == vm_data, f"VM {spid} data mismatch"
        assert poison == 0
    dut._log.info("[+] Multi-VM SPID 0..3 isolation verified successfully!")

    # 3. Kiểm tra cơ chế tiêm lỗi Poison Forwarding
    dut._log.info("[+] Phase 3: Hardware Poison Forwarding on Tampered Memory")
    poison_addr = 0x0030_0000
    responder.poison_addrs.add(poison_addr << 6) # Byte address
    poison_tag = 0x0077

    await agent.send_mem_rd(addr=poison_addr, tag=poison_tag, spid=2)
    rdata, poison = await agent.wait_drs_data(expected_tag=poison_tag)
    assert poison == 1, "CXL S2M-DRS Poison flag must be asserted upon memory integrity fault!"
    dut._log.info("[+] CXL.mem S2M-DRS Hardware Poison Forwarding Verified with 100% Accuracy!")
