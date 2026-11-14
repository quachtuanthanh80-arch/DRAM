# Định nghĩa các uvm_sequence_item cho AXI4, APB4, DFI/DRAM và Fault Injection
import random
from pyuvm import uvm_sequence_item


class AxiSeqItem(uvm_sequence_item):
    """Giao dịch AXI4 64-bit với độ trễ AW/W/B/AR/R, WSTRB và backpressure ngẫu nhiên."""

    def __init__(self, name="axi_item"):
        super().__init__(name)
        self.op = "WRITE"  # WRITE | READ | RESET_MID_BURST
        self.corner_id = "RAND"
        self.tx_id = 0
        self.addr = 0
        self.length = 0  # AxLEN (0 -> 1 beat)
        self.size = 3    # 8B beat
        self.burst = 1   # INCR
        self.qos = 4
        self.wdata_list = [0]
        self.wstrb_list = [0xFF]
        # Điều khiển tách pha & backpressure (aw_delay / w_delay âm nghĩa là W phát trước AW)
        self.aw_delay = 0
        self.w_delay = 0
        self.w_inter_beat_delay = 0
        self.ar_delay = 0
        self.bready_rand_en = False
        self.rready_rand_en = False
        self.reset_after_beats = 1
        # Kết quả quan sát từ bus
        self.bresp = 0
        self.rdata_list = []
        self.rresp_list = []

    @property
    def crosses_4kb(self) -> bool:
        total_bytes = (self.length + 1) << self.size
        return ((self.addr & 0xFFF) + total_bytes) > 4096

    def randomize_with(
        self,
        rng: random.Random,
        op: str = "WRITE",
        addr: int = 0x1000,
        length: int = 0,
        corner_id: str = "RAND",
        partial_wstrb: bool = False,
        rand_backpressure: bool = True,
        skew_aw_w: bool = False,
    ):
        self.op = op
        self.corner_id = corner_id
        self.tx_id = rng.randint(0, 15)
        self.addr = addr & ~0x7
        self.length = length
        self.size = 3
        self.burst = 1
        self.qos = rng.randint(0, 15)
        self.aw_delay = rng.randint(0, 3) if not skew_aw_w else rng.choice([0, 2, 4])
        self.w_delay = rng.randint(0, 3) if not skew_aw_w else rng.choice([-3, 0, 3, 5])
        self.w_inter_beat_delay = rng.randint(0, 1) if rand_backpressure else 0
        self.ar_delay = rng.randint(0, 2)
        self.bready_rand_en = rand_backpressure
        self.rready_rand_en = rand_backpressure
        beats = self.length + 1
        self.wdata_list = [rng.getrandbits(64) for _ in range(beats)]
        if partial_wstrb:
            self.wstrb_list = [rng.randint(1, 254) for _ in range(beats)]
        else:
            self.wstrb_list = [0xFF for _ in range(beats)]
        return self


class ApbSeqItem(uvm_sequence_item):
    """Giao dịch APB4 với pprot[2:0] và pstrb[3:0] có kiểm soát/ngẫu nhiên."""

    def __init__(self, name="apb_item"):
        super().__init__(name)
        self.op = "WRITE"  # WRITE | READ
        self.corner_id = "CSR"
        self.addr = 0
        self.wdata = 0
        self.pstrb = 0xF
        self.pprot = 0b000
        self.setup_delay = 0
        self.rdata = 0
        self.pslverr = 0

    @property
    def expects_pslverr(self) -> bool:
        return bool((self.pprot >> 1) & 1)


class DfiObsItem(uvm_sequence_item):
    """Gói quan sát giao thức DFI và trạng thái dram_model / dfi_jedec_checker."""

    def __init__(self, name="dfi_obs"):
        super().__init__(name)
        self.kind = "CMD"  # CMD | WRDATA | STATUS
        self.cmd = 0
        self.bg = 0
        self.bank = 0
        self.row = 0
        self.col = 0
        self.length = 0
        self.wrdata = 0
        self.wrdata_mask = 0
        self.wrdata_ecc = 0
        self.dram_err_total = 0
        self.jedec_viol_cnt = 0
        self.cycle = 0


class FaultSeqItem(uvm_sequence_item):
    """Lệnh bơm lỗi SEU ($deposit), Stuck-at (force/release) hoặc Glitch qua FaultAgent."""

    def __init__(self, name="fault_item"):
        super().__init__(name)
        self.corner_id = "C_RT05_FAULT_INJECT"
        self.mode = 1       # 1=SEU, 2=STUCK, 3=GLITCH
        self.target = 0     # mc: 0=RAA,1=DRM blkp_a,2=DRM inj_oh,3=rcd_z ; csr: 0=rail0_sec_locked,1=rail0_crypto_profile
        self.val = 0x01
        self.dur = 2
        self.clear_after = True
        self.expected_fault_mask = 0
        self.observed_fault_cause = 0
        self.observed_glitch = 0
        self.observed_tmr_alert = 0
        self.observed_sec_fault_status = 0
