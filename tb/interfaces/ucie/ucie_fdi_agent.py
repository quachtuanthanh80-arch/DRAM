# File: ucie_fdi_agent.py
# Chức năng: Transactor Cocotb điều khiển tín hiệu FDI 1.1 và truyền nhận gói AXI-over-UCIe (AoU) Streaming.

import cocotb
from cocotb.triggers import RisingEdge

class UcieFdiAgent:
    """Agent mô phỏng Compute Chiplet giao tiếp qua giao diện chuẩn UCIe 1.1 FDI."""
    def __init__(self, dut, clk):
        self.dut = dut
        self.clk = clk

    async def bring_up_link(self):
        """Thực hiện chuỗi bắt tay huấn luyện liên kết chuẩn UCIe 1.1 FDI Bring-up."""
        self.dut.pl_valid.value         = 0
        self.dut.pl_data.value          = 0
        self.dut.pl_state_sts.value     = 0 # RESET
        self.dut.pl_rx_active_req.value = 0
        self.dut.lp_ready.value         = 1

        await RisingEdge(self.clk)

        # Host phát xung yêu cầu active
        self.dut.pl_rx_active_req.value = 1
        self.dut.pl_state_sts.value     = 1 # ACTIVE

        # Chờ DUT xác nhận lp_rx_active_ack và vào trạng thái active
        for _ in range(50):
            await RisingEdge(self.clk)
            if self.dut.lp_rx_active_ack.value and self.dut.ucie_link_active.value:
                return True
        raise TimeoutError("UCIe FDI Link Bring-up handshake timed out!")

    async def send_aou_write(self, addr, tag, data_512, vm_id=0):
        """Đóng gói và gửi giao dịch AoU Write trên bus FDI 512-bit."""
        # Opcode = 2 (WRITE_REQ+DATA)
        # [511:508] = 4'h2, [507:500] = vm_id, [499:492] = tag, [491:458] = addr[33:0]
        flit = data_512
        flit &= (1 << 458) - 1 # Giữ payload
        flit |= (addr & 0x3_FFFF_FFFF) << 458
        flit |= (tag & 0xFF) << 492
        flit |= (vm_id & 0xFF) << 500
        flit |= (2 & 0xF) << 508

        self.dut.pl_data.value  = flit
        self.dut.pl_valid.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.pl_ready.value:
                break
        self.dut.pl_valid.value = 0

    async def send_aou_read(self, addr, tag, vm_id=0):
        """Đóng gói và gửi giao dịch AoU Read trên bus FDI 512-bit."""
        # Opcode = 1 (READ_REQ)
        flit = 0
        flit |= (addr & 0x3_FFFF_FFFF) << 458
        flit |= (tag & 0xFF) << 492
        flit |= (vm_id & 0xFF) << 500
        flit |= (1 & 0xF) << 508

        self.dut.pl_data.value  = flit
        self.dut.pl_valid.value = 1

        while True:
            await RisingEdge(self.clk)
            if self.dut.pl_ready.value:
                break
        self.dut.pl_valid.value = 0

    async def wait_aou_read_data(self, expected_tag=None, timeout_cycles=100):
        """Chờ nhận phản hồi dữ liệu đọc qua bus FDI từ Q-Shield IOD."""
        for _ in range(timeout_cycles):
            await RisingEdge(self.clk)
            if self.dut.lp_valid.value:
                flit   = int(self.dut.lp_data.value)
                opcode = (flit >> 508) & 0xF
                poison = (flit >> 507) & 0x1
                tag    = (flit >> 492) & 0xFF
                data   = flit & ((1 << 492) - 1)

                if opcode == 1: # READ_DATA
                    if expected_tag is not None:
                        assert tag == expected_tag, f"Tag mismatch: expected {expected_tag}, got {tag}"
                    return data, poison
        raise TimeoutError("Timeout waiting for AoU Read Data response over UCIe FDI")
