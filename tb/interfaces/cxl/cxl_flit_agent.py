# File: cxl_flit_agent.py
# Chức năng: Transactor Cocotb sinh và giám sát các gói CXL.mem 3.0 Flits (M2S-Req/RwD, S2M-DRS/NDR).

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly

class CxlMemFlitAgent:
    """Agent mô phỏng Host CXL 3.0 giao tiếp với bộ nhớ mở rộng Type-3 qua Flit Bus."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def reset(self):
        self.dut.cxl_m2s_req_valid.value   = 0
        self.dut.cxl_m2s_req_opcode.value  = 0
        self.dut.cxl_m2s_req_addr.value    = 0
        self.dut.cxl_m2s_req_tag.value     = 0
        self.dut.cxl_m2s_req_spid.value    = 0
        self.dut.cxl_m2s_req_tc.value      = 0

        self.dut.cxl_m2s_rwd_valid.value   = 0
        self.dut.cxl_m2s_rwd_opcode.value  = 0
        self.dut.cxl_m2s_rwd_addr.value    = 0
        self.dut.cxl_m2s_rwd_tag.value     = 0
        self.dut.cxl_m2s_rwd_spid.value    = 0
        self.dut.cxl_m2s_rwd_data.value    = 0
        self.dut.cxl_m2s_rwd_byte_en.value = 0
        self.dut.cxl_m2s_rwd_poison.value  = 0

        self.dut.cxl_s2m_drs_ready.value   = 1
        self.dut.cxl_s2m_ndr_ready.value   = 1
        await RisingEdge(self.clk)

    async def send_mem_wr(self, addr, tag, data_512, spid=0, byte_en=(1 << 64) - 1, poison=0):
        """Gửi gói Flit M2S-RwD mang 64-byte payload ghi vào bộ nhớ."""
        self.dut.cxl_m2s_rwd_valid.value   = 1
        self.dut.cxl_m2s_rwd_opcode.value  = 4 # MemWr
        self.dut.cxl_m2s_rwd_addr.value    = addr
        self.dut.cxl_m2s_rwd_tag.value     = tag
        self.dut.cxl_m2s_rwd_spid.value    = spid
        self.dut.cxl_m2s_rwd_data.value    = data_512
        self.dut.cxl_m2s_rwd_byte_en.value = byte_en
        self.dut.cxl_m2s_rwd_poison.value  = poison

        while True:
            await RisingEdge(self.clk)
            if self.dut.cxl_m2s_rwd_ready.value:
                break
        self.dut.cxl_m2s_rwd_valid.value = 0

    async def send_mem_rd(self, addr, tag, spid=0, tc=0):
        """Gửi gói Flit M2S-Req yêu cầu đọc 64-byte từ bộ nhớ."""
        self.dut.cxl_m2s_req_valid.value  = 1
        self.dut.cxl_m2s_req_opcode.value = 1 # MemRd
        self.dut.cxl_m2s_req_addr.value   = addr
        self.dut.cxl_m2s_req_tag.value    = tag
        self.dut.cxl_m2s_req_spid.value   = spid
        self.dut.cxl_m2s_req_tc.value     = tc

        while True:
            await RisingEdge(self.clk)
            if self.dut.cxl_m2s_req_ready.value:
                break
        self.dut.cxl_m2s_req_valid.value = 0

    async def wait_ndr_cmp(self, expected_tag=None, timeout_cycles=100):
        """Chờ nhận gói xác nhận hoàn tất ghi S2M-NDR (Cmp)."""
        for _ in range(timeout_cycles):
            await RisingEdge(self.clk)
            if self.dut.cxl_s2m_ndr_valid.value:
                opcode = int(self.dut.cxl_s2m_ndr_opcode.value)
                tag    = int(self.dut.cxl_s2m_ndr_tag.value)
                if expected_tag is not None:
                    assert tag == expected_tag, f"NDR Tag mismatch: expected {expected_tag}, got {tag}"
                return opcode, tag
        raise TimeoutError("Timeout waiting for CXL S2M-NDR Completion flit")

    async def wait_drs_data(self, expected_tag=None, timeout_cycles=100):
        """Chờ nhận gói dữ liệu đọc S2M-DRS."""
        for _ in range(timeout_cycles):
            await RisingEdge(self.clk)
            if self.dut.cxl_s2m_drs_valid.value:
                tag    = int(self.dut.cxl_s2m_drs_tag.value)
                data   = int(self.dut.cxl_s2m_drs_data.value)
                poison = int(self.dut.cxl_s2m_drs_poison.value)
                if expected_tag is not None:
                    assert tag == expected_tag, f"DRS Tag mismatch: expected {expected_tag}, got {tag}"
                return data, poison
        raise TimeoutError("Timeout waiting for CXL S2M-DRS Data flit")
