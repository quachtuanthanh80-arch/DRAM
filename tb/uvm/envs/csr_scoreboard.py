# Scoreboard cho csr_env: kiểm tra APB4 pprot PSLVERR, khóa SecLock, che khóa write-only và TMR $deposit
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import ConfigDB, uvm_scoreboard, uvm_tlm_analysis_fifo

from tb.uvm.common.report_json import CoverageTracker


CSR_COV_BINS = [
    "apb_secure_wr_rd",
    "apb_nonsec_pprot_slverr",
    "apb_pstrb_partial",
    "wo_secret_zero_read",
    "ext_cfg_parity_bit12",
    "sec_lock_magic_enforced",
    "fi_tmr_rail_deposit",
]


class CsrScoreboard(uvm_scoreboard):
    """Scoreboard độc lập cho apb_csr_regs: đối chiếu APB4 bảo mật, khóa bí mật và bơm lỗi TMR."""

    def build_phase(self):
        super().build_phase()
        self.apb_fifo = uvm_tlm_analysis_fifo("apb_fifo", self)
        self.fault_fifo = uvm_tlm_analysis_fifo("fault_fifo", self)
        self.cov = CoverageTracker(CSR_COV_BINS)
        ConfigDB().set(None, "*", "CSR_COV_TRACKER", self.cov)
        self.errors: list[str] = []
        self.shadow_ext_cfg = 0
        self.locked = False
        self.stats = {
            "apb_tx": 0,
            "apb_pprot_slverr": 0,
            "fi_csr_events": 0,
        }

    def _fail(self, msg: str):
        self.errors.append(msg)
        self.logger.error(f"[CSR_SB_ERR] {msg}")

    def _handle_apb(self, ev: dict):
        self.stats["apb_tx"] += 1
        non_sec = bool((ev["pprot"] >> 1) & 1)
        if non_sec:
            if ev["pslverr"] != 1:
                self._fail(f"Non-secure APB (pprot=0b{ev['pprot']:03b}) @0x{ev['addr']:03x} did not return PSLVERR=1")
            else:
                self.stats["apb_pprot_slverr"] += 1
                self.cov.hit("apb_nonsec_pprot_slverr")
            return

        if ev["pslverr"] != 0:
            self._fail(f"Secure APB @0x{ev['addr']:03x} raised unexpected PSLVERR=1")
            return

        addr = ev["addr"]
        if ev["op"] == "WRITE":
            if ev["pstrb"] != 0xF:
                self.cov.hit("apb_pstrb_partial")
            if addr == 0x100 and not self.locked:
                # Chỉ các byte có PSTRB=1 mới cập nhật; bit 1 (cfg_scramble_reseed) tự xóa sau 1 chu kỳ
                for b in range(4):
                    if (ev["pstrb"] >> b) & 1:
                        mask = 0xFF << (8 * b)
                        self.shadow_ext_cfg = (self.shadow_ext_cfg & ~mask) | (ev["wdata"] & mask)
                self.shadow_ext_cfg &= ~0x2
                self.cov.hit("apb_secure_wr_rd")
            elif addr == 0x008 and ev["wdata"] == 0xA55A_0001 and ev["pstrb"] == 0xF:
                self.locked = True
                self.cov.hit("sec_lock_magic_enforced")
        else:
            self.cov.hit("apb_secure_wr_rd")
            if addr in (0x010, 0x014, 0x030, 0x104, 0x108):
                if ev["rdata"] != 0:
                    self._fail(f"Write-only secret register @0x{addr:03x} leaked 0x{ev['rdata']:08x} != 0")
                else:
                    self.cov.hit("wo_secret_zero_read")
            elif addr == 0x100:
                if (ev["rdata"] & 0xFFFF_FFFF) != (self.shadow_ext_cfg & 0xFFFF_FFFF):
                    self._fail(
                        f"EXT_CONFIG readback mismatch: got 0x{ev['rdata']:08x} != exp 0x{self.shadow_ext_cfg:08x}"
                    )
                if (self.shadow_ext_cfg >> 12) & 1:
                    dut = cocotb.top
                    if int(dut.cfg_parity_check_en.value) == 1:
                        self.cov.hit("ext_cfg_parity_bit12")
                    else:
                        self._fail("EXT_CONFIG[12] written=1 but cfg_parity_check_en output is 0")

    def _handle_fault(self, ev: dict):
        self.stats["fi_csr_events"] += 1
        if ev["tmr_alert"] == 1 or (ev["sec_fault_status"] != 0):
            self.cov.hit("fi_tmr_rail_deposit")
        else:
            self._fail(
                f"CSR TMR $deposit fault (target={ev['target']}) produced neither o_tmr_alert nor sec_fault_status"
            )

    def _drain_all(self):
        while True:
            ok, item = self.apb_fifo.try_get()
            if not ok:
                break
            self._handle_apb(item)
        while True:
            ok, item = self.fault_fifo.try_get()
            if not ok:
                break
            self._handle_fault(item)

    async def run_phase(self):
        dut = cocotb.top
        while True:
            await RisingEdge(dut.pclk)
            self._drain_all()

    def check_phase(self):
        super().check_phase()
        self._drain_all()
        ConfigDB().set(None, "*", "CSR_SB_ERRORS", list(self.errors))
        ConfigDB().set(None, "*", "CSR_SB_STATS", dict(self.stats))
        for line in self.cov.format_lines():
            self.logger.info(line)
        try:
            seed = ConfigDB().get(None, "", "UVM_SEED")
            seed_json_path = ConfigDB().get(None, "", "SEED_JSON_PATH")
            root_dir = ConfigDB().get(None, "", "ROOT_DIR")
            from tb.uvm.common.report_json import write_seed_report

            write_seed_report(
                out_path=seed_json_path,
                env="csr",
                seed=seed,
                passed=(len(self.errors) == 0),
                coverage=self.cov,
                checks=self.stats,
                root=root_dir,
                extra={"errors": self.errors[:10]},
            )
        except Exception:
            pass
        if self.errors:
            seed = ConfigDB().get(None, "", "UVM_SEED")
            self.logger.error(f"[UVM_FAIL] env=csr seed={seed} errors={self.errors[:5]}")
            raise AssertionError(f"CsrScoreboard failed (seed={seed}) with {len(self.errors)} errors: {self.errors[:5]}")
