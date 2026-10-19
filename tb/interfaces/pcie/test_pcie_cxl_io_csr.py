# File: test_pcie_cxl_io_csr.py
# Chức năng: Testbench Cocotb kiểm chứng giao diện PCIe / CXL.io đọc ghi DVSEC Header và cấu hình thanh ghi TMR bảo mật.

import os
import sys
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Nạp lớp tương thích cocotb 2.1
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "common")))
import cocotb2_compat

class AxilDriver:
    """Driver AXI4-Lite mô phỏng các gói Memory / Config TLP từ PCIe Root Complex."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def write(self, addr, data, strb=0xF):
        self.dut.s_axil_awaddr.value = addr
        self.dut.s_axil_awprot.value = 0
        self.dut.s_axil_awvalid.value = 1
        self.dut.s_axil_wdata.value = data
        self.dut.s_axil_wstrb.value = strb
        self.dut.s_axil_wvalid.value = 1
        self.dut.s_axil_bready.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.s_axil_awready.value and self.dut.s_axil_wready.value:
                break

        self.dut.s_axil_awvalid.value = 0
        self.dut.s_axil_wvalid.value = 0

        while True:
            await RisingEdge(self.clk)
            if self.dut.s_axil_bvalid.value:
                break
        self.dut.s_axil_bready.value = 0
        await RisingEdge(self.clk)

    async def read(self, addr):
        self.dut.s_axil_araddr.value = addr
        self.dut.s_axil_arprot.value = 0
        self.dut.s_axil_arvalid.value = 1
        self.dut.s_axil_rready.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.s_axil_arready.value:
                break
        self.dut.s_axil_arvalid.value = 0

        while True:
            await RisingEdge(self.clk)
            if self.dut.s_axil_rvalid.value:
                rdata = int(self.dut.s_axil_rdata.value)
                break
        self.dut.s_axil_rready.value = 0
        await RisingEdge(self.clk)
        return rdata

@cocotb.test()
async def test_pcie_cxl_io_enumeration_and_tmr_csr(dut):
    """Kiểm chứng quá trình Enumeration đọc CXL 3.0 DVSEC và cấu hình thanh ghi TMR bảo mật."""
    clock = Clock(dut.clk, 4.0, units="ns") # 250 MHz
    cocotb.start_soon(clock.start())

    # Khởi tạo tín hiệu và reset
    dut.rst_n.value = 0
    dut.s_axil_awaddr.value = 0
    dut.s_axil_awprot.value = 0
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wdata.value = 0
    dut.s_axil_wstrb.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_araddr.value = 0
    dut.s_axil_arprot.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)

    axil = AxilDriver(dut, dut.clk)

    # 1. Kiểm tra Enumeration đọc CXL 3.0 DVSEC Capabilities (0x100 - 0x124)
    dut._log.info("[+] Phase 1: PCIe Enumeration & CXL 3.0 DVSEC Capability Readback")
    hdr1 = await axil.read(0x100)
    assert hdr1 == 0x03C11E98, f"Mismatch DVSEC Header 1: expected 0x03C11E98, got 0x{hdr1:08X}"

    hdr2 = await axil.read(0x104)
    assert hdr2 == 0x00030000, f"Mismatch DVSEC Header 2: expected 0x00030000, got 0x{hdr2:08X}"

    cap = await axil.read(0x108)
    assert cap == 0x00000005, f"Mismatch CXL Capability: expected 0x00000005, got 0x{cap:08X}"

    hdm_size = await axil.read(0x11C)
    assert hdm_size == 0x40000000, f"Mismatch HDM Window Size: expected 0x40000000, got 0x{hdm_size:08X}"

    # Kiểm tra ghi/đọc CXL Control Register (0x10C)
    await axil.write(0x10C, 0x00000007)
    ctrl_read = await axil.read(0x10C)
    assert ctrl_read == 0x00000007, f"Mismatch CXL Control: expected 0x00000007, got 0x{ctrl_read:08X}"
    dut._log.info("[+] CXL 3.0 DVSEC Capability Header Verified Successfully!")

    # 2. Kiểm tra ghi/đọc thanh ghi bảo mật TMR Q-Shield qua cầu APB4 (0x040..0x050)
    dut._log.info("[+] Phase 2: Configuring Q-Shield TMR Security CSRs via CXL.io APB Bridge")
    # REG_CRYPTO_PROFILE (0x040): Cấu hình Profile 2 (High-Throughput CTR Pre-computation)
    await axil.write(0x040, 0x00000002)
    profile_read = await axil.read(0x040)
    assert (profile_read & 0x3) == 0x2, f"Mismatch Crypto Profile: expected 0x2, got 0x{profile_read:08X}"
    assert dut.o_cfg_crypto_profile.value == 0x2, "Mismatch hardware output o_cfg_crypto_profile"

    # REG_DEFAULT_KEY_ID (0x044): Cấu hình KeyID mặc định = 0x05
    await axil.write(0x044, 0x00000005)
    keyid_read = await axil.read(0x044)
    assert (keyid_read & 0xFF) == 0x05, f"Mismatch Default Key ID: expected 0x05, got 0x{keyid_read:08X}"
    assert dut.o_cfg_default_key_id.value == 0x05, "Mismatch hardware output o_cfg_default_key_id"

    # REG_EPOCH_NONCE (0x048): Cấu hình Nonce = 0x0003_ABCD
    await axil.write(0x048, 0x0003ABCD)
    nonce_read = await axil.read(0x048)
    assert (nonce_read & 0x7FFFF) == 0x0003ABCD, f"Mismatch Epoch Nonce: expected 0x0003ABCD, got 0x{nonce_read:08X}"
    assert dut.o_cfg_epoch_nonce.value == 0x0003ABCD, "Mismatch hardware output o_cfg_epoch_nonce"

    dut._log.info("[+] Q-Shield TMR CSR Configuration via CXL.io Verified with 100% Accuracy!")
