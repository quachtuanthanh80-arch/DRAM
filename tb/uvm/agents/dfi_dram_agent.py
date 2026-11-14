# DFI/DRAM Agent (thụ động): quan sát lệnh DFI, ECC ghi ra DRAM và bộ đếm lỗi JEDEC/DRAM
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import uvm_agent, uvm_analysis_port, uvm_monitor

from tb.uvm.common.seq_item import DfiObsItem


def _to_int(sig, default: int = 0) -> int:
    try:
        return int(sig.value)
    except ValueError:
        return default


class DfiDramMonitor(uvm_monitor):
    """Quan sát các chân DFI thực, wrdata_ecc và đếm lỗi từ dram_model + dfi_jedec_checker."""

    CMD_RD = 3
    CMD_WR = 4

    def build_phase(self):
        super().build_phase()
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        cyc = 0
        while True:
            await RisingEdge(dut.clk_axi)
            cyc += 1
            if _to_int(dut.aresetn_axi) == 0:
                continue
            cmd = _to_int(dut.dfi_cmd)
            if cmd != 0:
                obs = DfiObsItem(f"dfi_cmd_{cyc}")
                obs.kind = "CMD"
                obs.cmd = cmd
                obs.bg = _to_int(dut.dfi_bg)
                obs.bank = _to_int(dut.dfi_bank)
                obs.row = _to_int(dut.dfi_row)
                obs.col = _to_int(dut.dfi_col)
                obs.length = _to_int(dut.dfi_len)
                obs.dram_err_total = _to_int(dut.dram_err_total)
                obs.jedec_viol_cnt = _to_int(dut.jedec_viol_cnt)
                obs.cycle = cyc
                self.ap.write(obs)

            if _to_int(dut.dfi_wrdata_en) == 1:
                obs_w = DfiObsItem(f"dfi_wr_{cyc}")
                obs_w.kind = "WRDATA"
                obs_w.wrdata = _to_int(dut.dfi_wrdata)
                obs_w.wrdata_mask = _to_int(dut.dfi_wrdata_mask)
                obs_w.wrdata_ecc = _to_int(dut.dfi_wrdata_ecc)
                obs_w.dram_err_total = _to_int(dut.dram_err_total)
                obs_w.jedec_viol_cnt = _to_int(dut.jedec_viol_cnt)
                obs_w.cycle = cyc
                self.ap.write(obs_w)

            if cyc % 100 == 0 or _to_int(dut.dram_err_total) > 0 or _to_int(dut.jedec_viol_cnt) > 0:
                obs_s = DfiObsItem(f"dfi_stat_{cyc}")
                obs_s.kind = "STATUS"
                obs_s.dram_err_total = _to_int(dut.dram_err_total)
                obs_s.jedec_viol_cnt = _to_int(dut.jedec_viol_cnt)
                obs_s.cycle = cyc
                self.ap.write(obs_s)


class DfiDramAgent(uvm_agent):
    """Agent bọc thụ động quanh dram_model.sv + dfi_jedec_checker.sv trong mc_uvm_top."""

    def build_phase(self):
        super().build_phase()
        self.mon = DfiDramMonitor("mon", self)
        self.ap = uvm_analysis_port("ap", self)

    def connect_phase(self):
        super().connect_phase()
        self.mon.ap.connect(self.ap)
