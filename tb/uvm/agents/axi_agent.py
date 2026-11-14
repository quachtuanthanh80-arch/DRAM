# AXI4 Agent: hỗ trợ trễ AW/W/B/AR/R độc lập, WSTRB ngẫu nhiên, backpressure RREADY/BREADY và reset giữa burst
import random
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import (
    ConfigDB,
    uvm_agent,
    uvm_analysis_port,
    uvm_driver,
    uvm_monitor,
    uvm_sequencer,
)

from tb.uvm.common.seq_item import AxiSeqItem


def _to_int(sig, default: int = 0) -> int:
    try:
        return int(sig.value)
    except ValueError:
        return default


class AxiSequencer(uvm_sequencer):
    pass


class AxiDriver(uvm_driver):
    """Driver AXI4 điều khiển độc lập pha AW, W, B, AR, R trên mc_uvm_top."""

    def build_phase(self):
        super().build_phase()
        try:
            self.rng = ConfigDB().get(self, "", "UVM_RNG")
        except Exception:
            self.rng = random.Random(1001)

    async def _reset_signals(self, dut):
        dut.s_axi_awid.value = 0
        dut.s_axi_awaddr.value = 0
        dut.s_axi_awlen.value = 0
        dut.s_axi_awsize.value = 3
        dut.s_axi_awburst.value = 1
        dut.s_axi_awqos.value = 0
        dut.s_axi_awvalid.value = 0
        dut.s_axi_wdata.value = 0
        dut.s_axi_wstrb.value = 0xFF
        dut.s_axi_wlast.value = 0
        dut.s_axi_wvalid.value = 0
        dut.s_axi_bready.value = 1
        dut.s_axi_arid.value = 0
        dut.s_axi_araddr.value = 0
        dut.s_axi_arlen.value = 0
        dut.s_axi_arsize.value = 3
        dut.s_axi_arburst.value = 1
        dut.s_axi_arqos.value = 0
        dut.s_axi_arvalid.value = 0
        dut.s_axi_rready.value = 1

    async def _drive_aw(self, dut, item: AxiSeqItem, delay: int):
        for _ in range(delay):
            await RisingEdge(dut.clk_axi)
        dut.s_axi_awid.value = item.tx_id & 0xF
        dut.s_axi_awaddr.value = item.addr & 0xFFFF_FFFF
        dut.s_axi_awlen.value = item.length & 0xFF
        dut.s_axi_awsize.value = item.size & 0x7
        dut.s_axi_awburst.value = item.burst & 0x3
        dut.s_axi_awqos.value = item.qos & 0xF
        dut.s_axi_awvalid.value = 1
        while True:
            await RisingEdge(dut.clk_axi)
            if _to_int(dut.s_axi_awready) == 1:
                break
        dut.s_axi_awvalid.value = 0

    async def _drive_w(self, dut, item: AxiSeqItem, delay: int, reset_abort: bool = False):
        for _ in range(delay):
            await RisingEdge(dut.clk_axi)
        beats = item.length + 1
        limit = min(item.reset_after_beats, beats) if reset_abort else beats
        for idx in range(limit):
            dut.s_axi_wdata.value = item.wdata_list[idx] & ((1 << 64) - 1)
            dut.s_axi_wstrb.value = item.wstrb_list[idx] & 0xFF
            dut.s_axi_wlast.value = 1 if (idx == beats - 1) else 0
            dut.s_axi_wvalid.value = 1
            while True:
                await RisingEdge(dut.clk_axi)
                if _to_int(dut.s_axi_wready) == 1:
                    break
            if item.w_inter_beat_delay > 0 and idx < limit - 1:
                dut.s_axi_wvalid.value = 0
                for _ in range(item.w_inter_beat_delay):
                    await RisingEdge(dut.clk_axi)
        dut.s_axi_wvalid.value = 0
        dut.s_axi_wlast.value = 0

    async def _wait_b(self, dut, item: AxiSeqItem):
        cycles = 0
        while cycles < 2000:
            if item.bready_rand_en:
                # Backpressure ngẫu nhiên nhưng luôn đảm bảo tiến triển (khả năng ready=1 >= 50%)
                dut.s_axi_bready.value = 1 if (cycles % 3 != 1 or self.rng.random() < 0.6) else 0
            else:
                dut.s_axi_bready.value = 1
            await RisingEdge(dut.clk_axi)
            cycles += 1
            if _to_int(dut.s_axi_bvalid) == 1 and _to_int(dut.s_axi_bready) == 1:
                item.bresp = _to_int(dut.s_axi_bresp)
                dut.s_axi_bready.value = 1
                return
        raise TimeoutError(f"AXI B response timeout at addr=0x{item.addr:08x}")

    async def _drive_read(self, dut, item: AxiSeqItem):
        for _ in range(max(0, item.ar_delay)):
            await RisingEdge(dut.clk_axi)
        dut.s_axi_arid.value = item.tx_id & 0xF
        dut.s_axi_araddr.value = item.addr & 0xFFFF_FFFF
        dut.s_axi_arlen.value = item.length & 0xFF
        dut.s_axi_arsize.value = item.size & 0x7
        dut.s_axi_arburst.value = item.burst & 0x3
        dut.s_axi_arqos.value = item.qos & 0xF
        dut.s_axi_arvalid.value = 1
        while True:
            await RisingEdge(dut.clk_axi)
            if _to_int(dut.s_axi_arready) == 1:
                break
        dut.s_axi_arvalid.value = 0

        item.rdata_list = []
        item.rresp_list = []
        cycles = 0
        while cycles < 4000:
            if item.rready_rand_en:
                dut.s_axi_rready.value = 1 if (cycles % 4 != 2 or self.rng.random() < 0.55) else 0
            else:
                dut.s_axi_rready.value = 1
            await RisingEdge(dut.clk_axi)
            cycles += 1
            if _to_int(dut.s_axi_rvalid) == 1 and _to_int(dut.s_axi_rready) == 1:
                item.rdata_list.append(_to_int(dut.s_axi_rdata))
                item.rresp_list.append(_to_int(dut.s_axi_rresp))
                if _to_int(dut.s_axi_rlast) == 1:
                    dut.s_axi_rready.value = 1
                    return
        raise TimeoutError(f"AXI R response timeout at addr=0x{item.addr:08x}")

    async def run_phase(self):
        dut = cocotb.top
        await self._reset_signals(dut)
        while _to_int(dut.aresetn_axi) == 0:
            await RisingEdge(dut.clk_axi)

        while True:
            item: AxiSeqItem = await self.seq_item_port.get_next_item()
            if item.op == "WRITE":
                if item.w_delay >= 0:
                    aw_d = max(0, item.aw_delay)
                    w_d = aw_d + item.w_delay
                else:
                    w_d = max(0, item.aw_delay)
                    aw_d = w_d + abs(item.w_delay)
                aw_task = cocotb.start_soon(self._drive_aw(dut, item, aw_d))
                w_task = cocotb.start_soon(self._drive_w(dut, item, w_d, reset_abort=False))
                b_task = cocotb.start_soon(self._wait_b(dut, item))
                await aw_task
                await w_task
                await b_task
            elif item.op == "READ":
                await self._drive_read(dut, item)
            elif item.op == "RESET_MID_BURST":
                aw_task = cocotb.start_soon(self._drive_aw(dut, item, 0))
                w_task = cocotb.start_soon(self._drive_w(dut, item, 0, reset_abort=True))
                await aw_task
                await w_task
                # Kéo reset đồng bộ giữa burst rồi khởi động lại sạch sẽ
                await self._reset_signals(dut)
                dut.aresetn_axi.value = 0
                for _ in range(8):
                    await RisingEdge(dut.clk_axi)
                dut.aresetn_axi.value = 1
                for _ in range(12):
                    await RisingEdge(dut.clk_axi)
            self.seq_item_port.item_done()


class AxiMonitor(uvm_monitor):
    """Monitor AXI4 bắt các pha AW, W, B, AR, R và sự kiện reset gửi qua analysis_port."""

    def build_phase(self):
        super().build_phase()
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        prev_rst = _to_int(dut.aresetn_axi)
        w_beats_acc: list[tuple[int, int]] = []
        r_beats_acc: list[tuple[int, int]] = []
        while True:
            await RisingEdge(dut.clk_axi)
            rst_n = _to_int(dut.aresetn_axi)
            if rst_n == 0:
                if prev_rst == 1:
                    w_beats_acc.clear()
                    r_beats_acc.clear()
                    self.ap.write({"type": "RESET"})
                prev_rst = 0
                continue
            prev_rst = 1

            if _to_int(dut.s_axi_awvalid) == 1 and _to_int(dut.s_axi_awready) == 1:
                self.ap.write(
                    {
                        "type": "AW",
                        "id": _to_int(dut.s_axi_awid),
                        "addr": _to_int(dut.s_axi_awaddr),
                        "len": _to_int(dut.s_axi_awlen),
                        "size": _to_int(dut.s_axi_awsize),
                        "burst": _to_int(dut.s_axi_awburst),
                        "qos": _to_int(dut.s_axi_awqos),
                    }
                )
            if _to_int(dut.s_axi_wvalid) == 1 and _to_int(dut.s_axi_wready) == 1:
                w_beats_acc.append((_to_int(dut.s_axi_wdata), _to_int(dut.s_axi_wstrb)))
                if _to_int(dut.s_axi_wlast) == 1:
                    self.ap.write({"type": "W_BURST", "beats": list(w_beats_acc)})
                    w_beats_acc.clear()
            if _to_int(dut.s_axi_bvalid) == 1 and _to_int(dut.s_axi_bready) == 1:
                self.ap.write(
                    {
                        "type": "B",
                        "id": _to_int(dut.s_axi_bid),
                        "resp": _to_int(dut.s_axi_bresp),
                    }
                )
            if _to_int(dut.s_axi_arvalid) == 1 and _to_int(dut.s_axi_arready) == 1:
                self.ap.write(
                    {
                        "type": "AR",
                        "id": _to_int(dut.s_axi_arid),
                        "addr": _to_int(dut.s_axi_araddr),
                        "len": _to_int(dut.s_axi_arlen),
                        "size": _to_int(dut.s_axi_arsize),
                        "burst": _to_int(dut.s_axi_arburst),
                        "qos": _to_int(dut.s_axi_arqos),
                    }
                )
            if _to_int(dut.s_axi_rvalid) == 1 and _to_int(dut.s_axi_rready) == 1:
                r_beats_acc.append((_to_int(dut.s_axi_rdata), _to_int(dut.s_axi_rresp)))
                if _to_int(dut.s_axi_rlast) == 1:
                    self.ap.write(
                        {
                            "type": "R_BURST",
                            "id": _to_int(dut.s_axi_rid),
                            "beats": list(r_beats_acc),
                        }
                    )
                    r_beats_acc.clear()


class AxiAgent(uvm_agent):
    """Agent AXI4 đầy đủ driver, monitor, sequencer và analysis_port."""

    def build_phase(self):
        super().build_phase()
        self.seqr = AxiSequencer("seqr", self)
        self.drv = AxiDriver("drv", self)
        self.mon = AxiMonitor("mon", self)
        self.ap = uvm_analysis_port("ap", self)

    def connect_phase(self):
        super().connect_phase()
        self.drv.seq_item_port.connect(self.seqr.seq_item_export)
        self.mon.ap.connect(self.ap)
