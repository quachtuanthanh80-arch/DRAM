# Scoreboard tổng hợp cho mc_env: đối chiếu AXI data/4KB SLVERR, DFI AddrMapModel, SECDED ECC, AES-XTS KAT, Fault & JEDEC
import random
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import ConfigDB, uvm_scoreboard, uvm_tlm_analysis_fifo

from tb.uvm.common.report_json import CoverageTracker
from tb.uvm.golden import AddrMapModel, AesXts256Model, RsSecdedModel


CORNER_BINS = [
    "wr_full_line",
    "rd_basic",
    "partial_wstrb_rmw",
    "rand_rready_stall",
    "rand_bready_stall",
    "aw_w_skew",
    "boundary_4kb_split",
    "raw_same_addr",
    "bg_sweep_8",
    "bank_sweep_4",
    "reset_mid_burst",
    "fi_seu_drm",
    "fi_seu_rcd",
    "dfi_addr_match",
    "secded_encode_match",
    "aes_xts_kat_roundtrip",
]


class McScoreboard(uvm_scoreboard):
    """Scoreboard kiểm tra toàn bộ bất biến AXI4, DFI, ECC, Địa chỉ, Fault và Crypto bằng mô hình vàng độc lập."""

    def build_phase(self):
        super().build_phase()
        self.axi_fifo = uvm_tlm_analysis_fifo("axi_fifo", self)
        self.dfi_fifo = uvm_tlm_analysis_fifo("dfi_fifo", self)
        self.fault_fifo = uvm_tlm_analysis_fifo("fault_fifo", self)

        try:
            self.rng = ConfigDB().get(self, "", "UVM_RNG")
        except Exception:
            self.rng = random.Random(1001)

        self.cov = CoverageTracker(CORNER_BINS)
        ConfigDB().set(None, "*", "MC_COV_TRACKER", self.cov)

        self.errors: list[str] = []
        self.mem: dict[int, int] = {}
        self.aw_queue: list[dict] = []
        self.w_queue: list[dict] = []
        self.b_pending: list[dict] = []
        self.ar_queue: list[dict] = []

        self.expected_wr_locs: set[tuple[int, int, int, int]] = set()
        self.expected_rd_locs: set[tuple[int, int, int, int]] = set()
        self.observed_bgs: set[int] = set()
        self.observed_banks: set[int] = set()
        self.fi_events: list[dict] = []

        self.stats = {
            "axi_writes": 0,
            "axi_reads": 0,
            "axi_4kb_splits": 0,
            "dfi_wr_checked": 0,
            "dfi_rd_checked": 0,
            "secded_beats_checked": 0,
            "resets_observed": 0,
            "fi_events": 0,
            "jedec_viol_cnt": 0,
            "dram_err_total": 0,
        }

    def _fail(self, msg: str):
        self.errors.append(msg)
        self.logger.error(f"[SB_ERR] {msg}")

    def _pair_aw_w(self):
        while self.aw_queue and self.w_queue:
            aw = self.aw_queue.pop(0)
            wb = self.w_queue.pop(0)
            crosses_4kb = ((aw["addr"] & 0xFFF) + ((aw["len"] + 1) << aw["size"])) > 4096
            self.b_pending.append(
                {"id": aw["id"], "addr": aw["addr"], "crosses_4kb": crosses_4kb}
            )
            self.stats["axi_writes"] += 1
            if crosses_4kb:
                self.stats["axi_4kb_splits"] += 1
                self.cov.hit("boundary_4kb_split")
            for idx, (wdata, wstrb) in enumerate(wb["beats"]):
                beat_addr = aw["addr"] + idx * 8
                if wstrb != 0xFF:
                    self.cov.hit("partial_wstrb_rmw")
                else:
                    self.cov.hit("wr_full_line")
                for byte_i in range(8):
                    if (wstrb >> byte_i) & 1:
                        self.mem[beat_addr + byte_i] = (wdata >> (8 * byte_i)) & 0xFF

    def _handle_axi(self, ev: dict):
        etype = ev["type"]
        if etype == "RESET":
            # Xóa hàng đợi đang bay và đánh dấu địa chỉ dở dang không đối chiếu trước khi ghi lại
            for aw in self.aw_queue:
                for b in range((aw["len"] + 1) * 8):
                    self.mem.pop(aw["addr"] + b, None)
            self.aw_queue.clear()
            self.w_queue.clear()
            self.b_pending.clear()
            self.ar_queue.clear()
            self.stats["resets_observed"] += 1
            self.cov.hit("reset_mid_burst")
            return

        if etype == "AW":
            for i in range(ev["len"] + 1):
                loc = AddrMapModel.map_addr(ev["addr"] + i * 8, tenant_id=ev["qos"], is_ddr5=True)
                self.expected_wr_locs.add(loc)
                self.observed_bgs.add(loc[0])
                self.observed_banks.add(loc[1])
            self.aw_queue.append(ev)
            self._pair_aw_w()
        elif etype == "W_BURST":
            self.w_queue.append(ev)
            self._pair_aw_w()
        elif etype == "B":
            if not self.b_pending:
                self._fail(f"Unexpected AXI B response id={ev['id']} resp={ev['resp']}")
                return
            exp = self.b_pending.pop(0)
            if ev["resp"] != 0:
                self._fail(
                    f"AXI BRESP mismatch at addr=0x{exp['addr']:08x}: got {ev['resp']} != exp 0"
                )
        elif etype == "AR":
            for i in range(ev["len"] + 1):
                loc = AddrMapModel.map_addr(ev["addr"] + i * 8, tenant_id=ev["qos"], is_ddr5=True)
                self.expected_rd_locs.add(loc)
            self.ar_queue.append(ev)
        elif etype == "R_BURST":
            if not self.ar_queue:
                self._fail(f"Unexpected AXI R_BURST id={ev['id']}")
                return
            ar = self.ar_queue.pop(0)
            crosses = ((ar["addr"] & 0xFFF) + ((ar["len"] + 1) << ar["size"])) > 4096
            if crosses:
                self.stats["axi_4kb_splits"] += 1
                self.cov.hit("boundary_4kb_split")

            self.stats["axi_reads"] += 1
            self.cov.hit("rd_basic")
            for idx, (rdata, rresp) in enumerate(ev["beats"]):
                if rresp != 0:
                    self._fail(f"AXI RRESP mismatch at addr=0x{ar['addr']:08x}: got {rresp} != 0")
                    continue
                beat_addr = ar["addr"] + idx * 8
                for byte_i in range(8):
                    baddr = beat_addr + byte_i
                    if baddr in self.mem:
                        got_b = (rdata >> (8 * byte_i)) & 0xFF
                        exp_b = self.mem[baddr]
                        if got_b != exp_b:
                            self._fail(
                                f"AXI RDATA byte mismatch @0x{baddr:08x}: got 0x{got_b:02x} != exp 0x{exp_b:02x}"
                            )
                            break

    def _handle_dfi(self, obs):
        self.stats["jedec_viol_cnt"] = max(self.stats["jedec_viol_cnt"], obs.jedec_viol_cnt)
        self.stats["dram_err_total"] = max(self.stats["dram_err_total"], obs.dram_err_total)
        if obs.jedec_viol_cnt > 0:
            self._fail(f"JEDEC timing violation detected by dfi_jedec_checker: count={obs.jedec_viol_cnt}")
        if obs.dram_err_total > 0:
            self._fail(f"DRAM model error detected: dram_err_total={obs.dram_err_total}")

        if obs.kind == "CMD":
            loc = (obs.bg, obs.bank, obs.row, obs.col)
            if obs.cmd == 4:  # DFI_WR
                if loc not in self.expected_wr_locs:
                    self._fail(
                        f"DFI_WR addr mismatch vs AddrMapModel: got (bg={obs.bg}, bank={obs.bank}, "
                        f"row=0x{obs.row:x}, col=0x{obs.col:x}) not in expected AXI mapped coords"
                    )
                else:
                    self.cov.hit("dfi_addr_match")
                self.stats["dfi_wr_checked"] += 1
            elif obs.cmd == 3:  # DFI_RD
                # Đọc thông thường hoặc pha đọc của RMW từ một lệnh ghi
                if loc not in self.expected_rd_locs and loc not in self.expected_wr_locs:
                    self._fail(
                        f"DFI_RD addr mismatch vs AddrMapModel: got (bg={obs.bg}, bank={obs.bank}, "
                        f"row=0x{obs.row:x}, col=0x{obs.col:x})"
                    )
                else:
                    self.cov.hit("dfi_addr_match")
                self.stats["dfi_rd_checked"] += 1

        elif obs.kind == "WRDATA":
            exp_ecc = RsSecdedModel.secded72_encode(obs.wrdata)
            if obs.wrdata_ecc != exp_ecc:
                self._fail(
                    f"DFI WRDATA ECC mismatch: data=0x{obs.wrdata:016x} "
                    f"got_ecc=0x{obs.wrdata_ecc:02x} != golden=0x{exp_ecc:02x}"
                )
            else:
                self.cov.hit("secded_encode_match")
            self.stats["secded_beats_checked"] += 1

    def _handle_fault(self, ev: dict):
        self.stats["fi_events"] += 1
        self.fi_events.append(ev)
        if ev["type"] == "FI_MC":
            tgt = ev["target"]
            if tgt in (1, 2):
                if (ev["fault_cause"] & (1 << 7)) == 0:
                    self._fail(f"DRM SEU fault injection (target={tgt}) did not raise o_fault_cause[7]: got 0x{ev['fault_cause']:03x}")
                else:
                    self.cov.hit("fi_seu_drm")
            elif tgt == 3:
                if (ev["fault_cause"] & (1 << 3)) == 0:
                    self._fail(f"Timing rail SEU (target=3) did not raise o_fault_cause[3]: got 0x{ev['fault_cause']:03x}")
                else:
                    self.cov.hit("fi_seu_rcd")

    def _drain_all(self):
        while True:
            ok, item = self.axi_fifo.try_get()
            if not ok:
                break
            self._handle_axi(item)
        while True:
            ok, item = self.dfi_fifo.try_get()
            if not ok:
                break
            self._handle_dfi(item)
        while True:
            ok, item = self.fault_fifo.try_get()
            if not ok:
                break
            self._handle_fault(item)

    async def run_phase(self):
        dut = cocotb.top
        while True:
            await RisingEdge(dut.clk_axi)
            self._drain_all()

    def check_phase(self):
        super().check_phase()
        self._drain_all()

        # Tự kiểm định mô hình vàng AES-256-XTS (KAT + roundtrip 64B) và SECDED/RS(18,16)
        try:
            AesXts256Model.verify_kat()
            k1 = bytes((self.rng.getrandbits(8) for _ in range(32)))
            k2 = bytes((self.rng.getrandbits(8) for _ in range(32)))
            pt64 = bytes((self.rng.getrandbits(8) for _ in range(64)))
            model = AesXts256Model(k1, k2)
            ct64 = model.encrypt_line_64b(pt64, addr=0x2000_0440, asid=2, epoch=5)
            dec64 = model.decrypt_line_64b(ct64, addr=0x2000_0440, asid=2, epoch=5)
            if dec64 != pt64:
                self._fail("AES-256-XTS 64B encrypt/decrypt roundtrip mismatch")
            else:
                self.cov.hit("aes_xts_kat_roundtrip")
        except Exception as exc:
            self._fail(f"AES-XTS golden model failure: {exc}")

        try:
            RsSecdedModel.verify_selftest()
        except Exception as exc:
            self._fail(f"RS/SEC-DED golden selftest failure: {exc}")

        if len(self.observed_bgs) >= 8:
            self.cov.hit("bg_sweep_8")
        if len(self.observed_banks) >= 4:
            self.cov.hit("bank_sweep_4")

        if self.stats["dfi_wr_checked"] == 0:
            self._fail("No DFI_WR commands observed on DFI bus")
        if self.stats["secded_beats_checked"] == 0:
            self._fail("No DFI_WRDATA ECC beats observed")

        ConfigDB().set(None, "*", "MC_SB_ERRORS", list(self.errors))
        ConfigDB().set(None, "*", "MC_SB_STATS", dict(self.stats))
        for line in self.cov.format_lines():
            self.logger.info(line)
        try:
            seed = ConfigDB().get(None, "", "UVM_SEED")
            seed_json_path = ConfigDB().get(None, "", "SEED_JSON_PATH")
            root_dir = ConfigDB().get(None, "", "ROOT_DIR")
            from tb.uvm.common.report_json import write_seed_report

            write_seed_report(
                out_path=seed_json_path,
                env="mc",
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
            self.logger.error(f"[UVM_FAIL] env=mc seed={seed} errors={self.errors[:5]}")
            raise AssertionError(f"McScoreboard failed (seed={seed}) with {len(self.errors)} errors: {self.errors[:5]}")
