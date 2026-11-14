# Tập uvm_sequence kiểm chứng từng góc biên (corner ID) cho Q-Shield mc_env và csr_env
import random
from pyuvm import ConfigDB, uvm_sequence

from tb.uvm.common.seq_item import ApbSeqItem, AxiSeqItem, FaultSeqItem


def _make_axi(rng: random.Random, op: str, addr: int, corner_id: str, length: int = 0, **kwargs) -> AxiSeqItem:
    item = AxiSeqItem(f"{corner_id}_{op}_{addr:x}")
    item.randomize_with(rng, op=op, addr=addr, length=length, corner_id=corner_id, **kwargs)
    return item


class C_H2_BgBankSweepSeq(uvm_sequence):
    """[H-2] Quét đủ 8 Bank Group (addr[8:6]) và 4 Bank (addr[17:16]) ở cả ghi lẫn đọc."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        base = 0x0001_0000
        # 8 Bank Group: addr[8:6] = 0..7 (moi BG cach 64B = 0x40)
        addrs = [base + (bg << 6) for bg in range(8)]
        # 4 Bank: addr[17:16] = 1..3 (bank 0 da co o tren)
        addrs += [base + (bk << 16) for bk in range(1, 4)]
        for a in addrs:
            w = _make_axi(rng, "WRITE", a, "C_H2_BG_BANK_SWEEP", rand_backpressure=False)
            await self.start_item(w)
            await self.finish_item(w)
        for a in addrs:
            r = _make_axi(rng, "READ", a, "C_H2_BG_BANK_SWEEP", rand_backpressure=False)
            await self.start_item(r)
            await self.finish_item(r)


class C_H3_RandomRreadySeq(uvm_sequence):
    """[H-3 / Spec §10 #3] Burst đa beat với BREADY và RREADY giật backpressure ngẫu nhiên."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        cov = ConfigDB().get(None, "", "MC_COV_TRACKER")
        for i in range(2):
            addr = 0x0002_0000 + i * 0x100
            w = _make_axi(rng, "WRITE", addr, "C_H3_RAND_RREADY", length=3, rand_backpressure=True)
            await self.start_item(w)
            await self.finish_item(w)
            cov.hit("rand_bready_stall")
            r = _make_axi(rng, "READ", addr, "C_H3_RAND_RREADY", length=3, rand_backpressure=True)
            await self.start_item(r)
            await self.finish_item(r)
            cov.hit("rand_rready_stall")


class C_M2_PartialWstrbRmwSeq(uvm_sequence):
    """[M-2] Ghi WSTRB từng phần (0x01, 0x80, 0x0F, ngẫu nhiên) sau khi khởi tạo nền 0xFF rồi đọc đối chiếu."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        addr = 0x0003_0000
        # Khoi tao ca 64B word truoc de dram_model va golden byte memory khop 100% moi byte
        w_init = _make_axi(rng, "WRITE", addr, "C_M2_INIT", length=0, rand_backpressure=False)
        await self.start_item(w_init)
        await self.finish_item(w_init)
        for mask in (0x01, 0xF0, rng.randint(1, 254)):
            w_part = _make_axi(rng, "WRITE", addr, "C_M2_PARTIAL_WSTRB", length=0, partial_wstrb=True)
            w_part.wstrb_list = [mask]
            await self.start_item(w_part)
            await self.finish_item(w_part)
        r = _make_axi(rng, "READ", addr, "C_M2_PARTIAL_WSTRB", length=0, rand_backpressure=False)
        await self.start_item(r)
        await self.finish_item(r)


class C_M3_Boundary4kbSeq(uvm_sequence):
    """[M-3 / T52] Giao dịch sát biên 4KB và vượt biên 4KB (burst splitter tách thành 64B chunks đọc/ghi chính xác)."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        # Sat bien: 0x4FF8 + 8B = 0x5000 (nam tron trong 1 trang 4KB)
        w_ok = _make_axi(rng, "WRITE", 0x0004_0FF8, "C_M3_ADJ_4KB", length=0, rand_backpressure=False)
        await self.start_item(w_ok)
        await self.finish_item(w_ok)
        r_ok = _make_axi(rng, "READ", 0x0004_0FF8, "C_M3_ADJ_4KB", length=0, rand_backpressure=False)
        await self.start_item(r_ok)
        await self.finish_item(r_ok)
        # Vuot bien 4KB: 0x4FF0 + 32B (len=3) = 0x5010 (axi_burst_splitter tach 2 chunk qua ranh 4KB)
        w_split = _make_axi(rng, "WRITE", 0x0004_0FF0, "C_M3_CROSS_4KB", length=3, rand_backpressure=False)
        await self.start_item(w_split)
        await self.finish_item(w_split)
        r_split = _make_axi(rng, "READ", 0x0004_0FF0, "C_M3_CROSS_4KB", length=3, rand_backpressure=False)
        await self.start_item(r_split)
        await self.finish_item(r_split)


class C_L2_RawHazardSeq(uvm_sequence):
    """[L-2 / Spec §9] Ghi rồi đọc tức thì cùng một địa chỉ để kiểm tra chuyển tiếp/bảo toàn thứ tự RAW."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        cov = ConfigDB().get(None, "", "MC_COV_TRACKER")
        addr = 0x0005_0080
        for _ in range(3):
            w = _make_axi(rng, "WRITE", addr, "C_L2_RAW_HAZARD", length=1, rand_backpressure=False)
            await self.start_item(w)
            await self.finish_item(w)
            r = _make_axi(rng, "READ", addr, "C_L2_RAW_HAZARD", length=1, rand_backpressure=False)
            await self.start_item(r)
            await self.finish_item(r)
            cov.hit("raw_same_addr")


class C_SEC10_SkewedAwWSeq(uvm_sequence):
    """[Spec §10 #1,#2] Lệch pha AW trước W và W trước AW."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        cov = ConfigDB().get(None, "", "MC_COV_TRACKER")
        for idx, skew in enumerate((4, -3)):
            addr = 0x0006_0000 + idx * 0x40
            w = _make_axi(rng, "WRITE", addr, "C_SEC10_SKEWED_AW_W", length=1, skew_aw_w=True)
            w.aw_delay = 1
            w.w_delay = skew
            await self.start_item(w)
            await self.finish_item(w)
            cov.hit("aw_w_skew")
            r = _make_axi(rng, "READ", addr, "C_SEC10_SKEWED_AW_W", length=1, rand_backpressure=False)
            await self.start_item(r)
            await self.finish_item(r)


class C_SEC10_ResetMidBurstSeq(uvm_sequence):
    """[Spec §10 #15] Kéo reset đồng bộ giữa burst đang phát rồi phục hồi giao dịch sạch sau reset."""

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        rst_item = _make_axi(rng, "RESET_MID_BURST", 0x0007_0000, "C_SEC10_RESET_MID_BURST", length=3)
        rst_item.reset_after_beats = 2
        await self.start_item(rst_item)
        await self.finish_item(rst_item)
        # Giao dich phuc hoi sau reset
        w_post = _make_axi(rng, "WRITE", 0x0007_0040, "C_SEC10_POST_RESET", length=0, rand_backpressure=False)
        await self.start_item(w_post)
        await self.finish_item(w_post)
        r_post = _make_axi(rng, "READ", 0x0007_0040, "C_SEC10_POST_RESET", length=0, rand_backpressure=False)
        await self.start_item(r_post)
        await self.finish_item(r_post)


class C_RT05_FaultInjectSeuSeq(uvm_sequence):
    """[T-RT05] Bơm lỗi SEU ($deposit) vào DRM và thanh ghi timing rồi kiểm tra cờ fault_cause."""

    async def body(self):
        for tgt, val, cid in ((1, 0x01, "C_RT05_SEU_DRM_BLKPA"), (3, 0x02, "C_RT05_SEU_RCD_Z")):
            f = FaultSeqItem(cid)
            f.corner_id = cid
            f.mode = 1
            f.target = tgt
            f.val = val
            f.clear_after = True
            await self.start_item(f)
            await self.finish_item(f)


class McRandomStressSeq(uvm_sequence):
    """Chuỗi ngẫu nhiên có ràng buộc theo UVM_SEED kiểm chứng ECC, AddrMap và bộ nhớ byte."""

    def __init__(self, name="mc_rand_seq", num_pairs: int = 5):
        super().__init__(name)
        self.num_pairs = num_pairs

    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")
        for i in range(self.num_pairs):
            bg = rng.randint(0, 7)
            bk = rng.randint(0, 3)
            row_part = rng.randint(1, 7)
            addr = 0x0008_0000 + (row_part << 18) + (bk << 16) + (bg << 6)
            length = rng.choice([0, 1, 3])
            w = _make_axi(rng, "WRITE", addr, f"RAND_FULL_{i}", length=length, rand_backpressure=True)
            await self.start_item(w)
            await self.finish_item(w)
            if rng.random() < 0.5:
                wp = _make_axi(
                    rng, "WRITE", addr, f"RAND_PART_{i}", length=0, partial_wstrb=True, rand_backpressure=True
                )
                await self.start_item(wp)
                await self.finish_item(wp)
            r = _make_axi(rng, "READ", addr, f"RAND_READ_{i}", length=length, rand_backpressure=True)
            await self.start_item(r)
            await self.finish_item(r)


class _CsrApbSubSeq(uvm_sequence):
    async def body(self):
        rng = ConfigDB().get(None, "", "UVM_RNG")

        # 1. Ghi key1[0] va scramble_seed_l roi doc lai phai ra 0 (write-only zero readback)
        for addr in (0x010, 0x104):
            w = ApbSeqItem(f"wo_wr_{addr:x}")
            w.op, w.addr, w.wdata, w.pstrb, w.pprot = "WRITE", addr, rng.getrandbits(32), 0xF, 0b000
            await self.start_item(w)
            await self.finish_item(w)
            r = ApbSeqItem(f"wo_rd_{addr:x}")
            r.op, r.addr, r.pprot = "READ", addr, 0b000
            await self.start_item(r)
            await self.finish_item(r)

        # 2. Ghi EXT_CONFIG (0x100) bat cfg_parity_check_en (bit 12) bang PSTRB tung phan
        w_ext_lo = ApbSeqItem("ext_pstrb_lo")
        w_ext_lo.op, w_ext_lo.addr, w_ext_lo.wdata, w_ext_lo.pstrb, w_ext_lo.pprot = (
            "WRITE",
            0x100,
            0x0000_0005,
            0b0001,
            0b000,
        )
        await self.start_item(w_ext_lo)
        await self.finish_item(w_ext_lo)

        w_ext_hi = ApbSeqItem("ext_pstrb_b1")
        w_ext_hi.op, w_ext_hi.addr, w_ext_hi.wdata, w_ext_hi.pstrb, w_ext_hi.pprot = (
            "WRITE",
            0x100,
            0x0000_1000,
            0b0010,
            0b000,
        )
        await self.start_item(w_ext_hi)
        await self.finish_item(w_ext_hi)

        r_ext = ApbSeqItem("ext_rd")
        r_ext.op, r_ext.addr, r_ext.pprot = "READ", 0x100, 0b000
        await self.start_item(r_ext)
        await self.finish_item(r_ext)

        # 3. Non-secure pprot[1]=1 phai bi chan va tra PSLVERR=1
        ns_wr = ApbSeqItem("ns_pprot_wr")
        ns_wr.op, ns_wr.addr, ns_wr.wdata, ns_wr.pstrb, ns_wr.pprot = (
            "WRITE",
            0x100,
            0xFFFF_FFFF,
            0xF,
            0b010,
        )
        await self.start_item(ns_wr)
        await self.finish_item(ns_wr)

        # 4. Khoa SecLock bang magic 0xA55A_0001
        lk = ApbSeqItem("seclock_wr")
        lk.op, lk.addr, lk.wdata, lk.pstrb, lk.pprot = "WRITE", 0x008, 0xA55A_0001, 0xF, 0b000
        await self.start_item(lk)
        await self.finish_item(lk)


class _CsrFaultSubSeq(uvm_sequence):
    async def body(self):
        # 5. Bom loi $deposit vao rail TMR (crypto_profile & sec_locked) qua FaultAgent
        for tgt in (1, 0):
            fi = FaultSeqItem(f"csr_tmr_fi_{tgt}")
            fi.corner_id = "C_CSR_TMR_DEPOSIT"
            fi.target = tgt
            fi.val = 0x01
            await self.start_item(fi)
            await self.finish_item(fi)


class C_CSR_CornerSeq(uvm_sequence):
    """Kiểm chứng APB4 CSR: pstrb từng phần, EXT_CONFIG[12], write-only secrets, pprot PSLVERR, SecLock và TMR $deposit."""

    async def body(self):
        apb_seqr = ConfigDB().get(None, "", "CSR_APB_SEQR")
        fi_seqr = ConfigDB().get(None, "", "CSR_FI_SEQR")
        await _CsrApbSubSeq("csr_apb_subseq").start(apb_seqr)
        await _CsrFaultSubSeq("csr_fi_subseq").start(fi_seqr)
