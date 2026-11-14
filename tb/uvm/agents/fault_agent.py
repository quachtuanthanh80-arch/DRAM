# Fault Agent: bơm lỗi SEU ($deposit), Stuck (force/release), Glitch và ghi log [FI]
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import (
    uvm_agent,
    uvm_analysis_port,
    uvm_driver,
    uvm_monitor,
    uvm_sequencer,
)

from tb.uvm.common.seq_item import FaultSeqItem


def _to_int(sig, default: int = 0) -> int:
    try:
        return int(sig.value)
    except ValueError:
        return default


class FaultSequencer(uvm_sequencer):
    pass


class FaultDriver(uvm_driver):
    """Driver điều khiển khối bơm lỗi HDL trên cả mc_uvm_top (clk_axi) và csr_uvm_top (pclk)."""

    async def run_phase(self):
        dut = cocotb.top
        is_mc = hasattr(dut, "clk_axi")
        clk = dut.clk_axi if is_mc else dut.pclk
        rst_n = dut.aresetn_axi if is_mc else dut.presetn
        dut.fi_trig.value = 0
        dut.fi_mode.value = 0
        dut.fi_target.value = 0
        dut.fi_val.value = 0
        if hasattr(dut, "fi_dur"):
            dut.fi_dur.value = 1

        while _to_int(rst_n) == 0:
            await RisingEdge(clk)

        while True:
            item: FaultSeqItem = await self.seq_item_port.get_next_item()
            dut.fi_mode.value = item.mode & 0x3
            dut.fi_target.value = item.target & 0x7
            dut.fi_val.value = item.val & 0xFF
            if hasattr(dut, "fi_dur"):
                dut.fi_dur.value = item.dur & 0xFF
            dut.fi_trig.value = 1
            await RisingEdge(clk)
            dut.fi_trig.value = 0

            for _ in range(100):
                await RisingEdge(clk)
                if _to_int(dut.fi_done) == 1:
                    break
            # Cho phép mạch phát hiện fault chốt sau khi fi_done lên mức 1
            for _ in range(4):
                await RisingEdge(clk)

            if is_mc:
                item.observed_fault_cause = _to_int(dut.o_fault_cause)
                item.observed_glitch = _to_int(dut.o_glitch_alert)
                self.logger.info(
                    f"[FI] env=mc corner={item.corner_id} mode={item.mode} target={item.target} "
                    f"val=0x{item.val:02x} fault_cause=0x{item.observed_fault_cause:03x} "
                    f"glitch={item.observed_glitch}"
                )
                if item.clear_after:
                    dut.cfg_fault_clr.value = 1
                    await RisingEdge(clk)
                    await RisingEdge(clk)
                    dut.cfg_fault_clr.value = 0
                    await RisingEdge(clk)
            else:
                item.observed_tmr_alert = _to_int(dut.o_tmr_alert)
                item.observed_sec_fault_status = _to_int(dut.sec_fault_status)
                self.logger.info(
                    f"[FI] env=csr corner={item.corner_id} target={item.target} "
                    f"val=0x{item.val:02x} tmr_alert={item.observed_tmr_alert} "
                    f"sec_fault_status=0x{item.observed_sec_fault_status:02x}"
                )

            self.seq_item_port.item_done()


class FaultMonitor(uvm_monitor):
    """Monitor Fault Agent phát hiện biến cố fault/tmr đẩy sang scoreboard."""

    def build_phase(self):
        super().build_phase()
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        is_mc = hasattr(dut, "clk_axi")
        clk = dut.clk_axi if is_mc else dut.pclk
        rst_n = dut.aresetn_axi if is_mc else dut.presetn
        while True:
            await RisingEdge(clk)
            if _to_int(rst_n) == 0:
                continue
            if _to_int(dut.fi_done) == 1:
                if is_mc:
                    self.ap.write(
                        {
                            "type": "FI_MC",
                            "target": _to_int(dut.fi_target),
                            "mode": _to_int(dut.fi_mode),
                            "fault_cause": _to_int(dut.o_fault_cause),
                            "glitch": _to_int(dut.o_glitch_alert),
                        }
                    )
                else:
                    self.ap.write(
                        {
                            "type": "FI_CSR",
                            "target": _to_int(dut.fi_target),
                            "tmr_alert": _to_int(dut.o_tmr_alert),
                            "sec_fault_status": _to_int(dut.sec_fault_status),
                        }
                    )


class FaultAgent(uvm_agent):
    def build_phase(self):
        super().build_phase()
        self.seqr = FaultSequencer("seqr", self)
        self.drv = FaultDriver("drv", self)
        self.mon = FaultMonitor("mon", self)
        self.ap = uvm_analysis_port("ap", self)

    def connect_phase(self):
        super().connect_phase()
        self.drv.seq_item_port.connect(self.seqr.seq_item_export)
        self.mon.ap.connect(self.ap)
