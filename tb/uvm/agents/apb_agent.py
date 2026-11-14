# APB4 Agent: kiểm thử thanh ghi CSR với pprot[2:0], pstrb[3:0] và độ trễ setup
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import (
    uvm_agent,
    uvm_analysis_port,
    uvm_driver,
    uvm_monitor,
    uvm_sequencer,
)

from tb.uvm.common.seq_item import ApbSeqItem


def _to_int(sig, default: int = 0) -> int:
    try:
        return int(sig.value)
    except ValueError:
        return default


class ApbSequencer(uvm_sequencer):
    pass


class ApbDriver(uvm_driver):
    """Driver APB4 hoàn chỉnh với pprot và pstrb trên csr_uvm_top."""

    async def run_phase(self):
        dut = cocotb.top
        dut.psel.value = 0
        dut.penable.value = 0
        dut.pwrite.value = 0
        dut.paddr.value = 0
        dut.pwdata.value = 0
        dut.pstrb.value = 0xF
        dut.pprot.value = 0
        while _to_int(dut.presetn) == 0:
            await RisingEdge(dut.pclk)

        while True:
            item: ApbSeqItem = await self.seq_item_port.get_next_item()
            for _ in range(max(0, item.setup_delay)):
                await RisingEdge(dut.pclk)
            # Pha SETUP
            dut.paddr.value = item.addr & 0xFFF
            dut.pwrite.value = 1 if item.op == "WRITE" else 0
            dut.pwdata.value = item.wdata & 0xFFFF_FFFF
            dut.pstrb.value = item.pstrb & 0xF
            dut.pprot.value = item.pprot & 0x7
            dut.psel.value = 1
            dut.penable.value = 0
            await RisingEdge(dut.pclk)
            # Pha ACCESS
            dut.penable.value = 1
            while True:
                await RisingEdge(dut.pclk)
                if _to_int(dut.pready) == 1:
                    break
            item.rdata = _to_int(dut.prdata)
            item.pslverr = _to_int(dut.pslverr)
            dut.psel.value = 0
            dut.penable.value = 0
            dut.pwrite.value = 0
            self.seq_item_port.item_done()


class ApbMonitor(uvm_monitor):
    """Monitor APB4 ghi nhận mọi chu kỳ ACCESS hoàn tất (psel & penable & pready)."""

    def build_phase(self):
        super().build_phase()
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        while True:
            await RisingEdge(dut.pclk)
            if _to_int(dut.presetn) == 0:
                continue
            if _to_int(dut.psel) == 1 and _to_int(dut.penable) == 1 and _to_int(dut.pready) == 1:
                self.ap.write(
                    {
                        "type": "APB",
                        "op": "WRITE" if _to_int(dut.pwrite) == 1 else "READ",
                        "addr": _to_int(dut.paddr),
                        "wdata": _to_int(dut.pwdata),
                        "pstrb": _to_int(dut.pstrb),
                        "pprot": _to_int(dut.pprot),
                        "rdata": _to_int(dut.prdata),
                        "pslverr": _to_int(dut.pslverr),
                    }
                )


class ApbAgent(uvm_agent):
    def build_phase(self):
        super().build_phase()
        self.seqr = ApbSequencer("seqr", self)
        self.drv = ApbDriver("drv", self)
        self.mon = ApbMonitor("mon", self)
        self.ap = uvm_analysis_port("ap", self)

    def connect_phase(self):
        super().connect_phase()
        self.drv.seq_item_port.connect(self.seqr.seq_item_export)
        self.mon.ap.connect(self.ap)
