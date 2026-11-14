# Mô hình tham chiếu ánh xạ địa chỉ DDR5/DDR4 và SCARF Feistel viết độc lập bằng Python thuần.

class AddrMapModel:
    """Ánh xạ AXI (addr, tenant_id) -> (bg, bank, row, col) khớp kiến trúc Q-Shield."""

    SCARF_SBOX = (0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD, 0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2)

    @classmethod
    def _feistel_f(cls, r_in: int, rkey: int, twk: int) -> int:
        mixed = (r_in ^ (twk & 0x3FF) ^ (((rkey & 0xFF) << 2) | (rkey & 0x3))) & 0x3FF
        s0 = cls.SCARF_SBOX[mixed & 0xF]
        s1 = cls.SCARF_SBOX[(mixed >> 4) & 0xF]
        top2 = ((mixed >> 8) & 0x3) ^ ((((s0 >> 1) & 1) << 1) | (s0 & 1))
        sub = s0 | (s1 << 4) | (top2 << 8)
        part_a = ((sub & 0xFF) << 1) | ((sub >> 9) & 1)
        part_b = ((sub & 0xF) << 5) | ((sub >> 4) & 0x1F)
        return (part_a ^ part_b) & 0x1FF

    @classmethod
    def _feistel_g(cls, l_in: int, rkey: int, twk: int) -> int:
        l10 = ((l_in & 1) << 9) | (l_in & 0x1FF)
        rk10 = (((rkey & 0x3) << 8) | (rkey & 0xFF)) & 0x3FF
        mixed = (l10 ^ (twk & 0x3FF) ^ rk10) & 0x3FF
        s0 = cls.SCARF_SBOX[mixed & 0xF]
        s1 = cls.SCARF_SBOX[(mixed >> 4) & 0xF]
        top2 = ((mixed >> 8) & 0x3) ^ ((((s1 >> 1) & 1) << 1) | ((s0 >> 2) & 1))
        sub = s0 | (s1 << 4) | (top2 << 8)
        part_a = ((sub & 0x7F) << 3) | ((sub >> 7) & 0x7)
        part_b = ((sub & 0x1F) << 5) | ((sub >> 5) & 0x1F)
        return (part_a ^ part_b) & 0x3FF

    @classmethod
    def scarf_permute(cls, row: int, bank: int, bg_tweak: int, seed: int, version: int = 0) -> tuple[int, int]:
        raw = ((bank & 0x3) << 17) | (row & 0x1FFFF)
        l_val = raw & 0x1FF
        r_val = (raw >> 9) & 0x3FF
        twk = (bg_tweak ^ version) & 0xFFFF
        for rnd in range(10):
            rkey = ((seed >> ((rnd * 6) % 56)) & 0xFF) ^ (rnd & 0xFF)
            if rnd % 2 == 0:
                l_val = (l_val ^ cls._feistel_f(r_val, rkey, twk)) & 0x1FF
            else:
                r_val = (r_val ^ cls._feistel_g(l_val, rkey, twk)) & 0x3FF
        out = (r_val << 9) | l_val
        return (out & 0x1FFFF), ((out >> 17) & 0x3)

    @classmethod
    def map_addr(
        cls,
        addr: int,
        tenant_id: int = 0,
        is_ddr5: bool = True,
        bank_coloring_en: bool = False,
        mapping_mode: int = 0,
        scramble_en: bool = False,
        scramble_mode: int = 0,
        scramble_seed: int = 0xA5A5_5A5A_0123_4567,
    ) -> tuple[int, int, int, int]:
        """Trả về (bg, bank, row, col) tương ứng DFI word-column của axi_ddr5_mc_top."""
        col = (addr >> 3) & 0x1FFF
        std_bank = (addr >> 16) & 0x3
        row = (addr >> 18) & 0x3FFF  # AXI_ADDR_WIDTH=32 -> 14-bit zero-extended to 17-bit

        if mapping_mode == 1:  # Intel Core/Xeon XOR
            if is_ddr5:
                selected_bg = ((addr >> 6) & 0x7) ^ ((addr >> 13) & 0x7) ^ ((addr >> 19) & 0x7)
            else:
                selected_bg = (((addr >> 6) & 0x3) ^ ((addr >> 13) & 0x3) ^ ((addr >> 19) & 0x3)) & 0x3
        elif mapping_mode == 2:  # AMD Zen UMC GF(2)
            b0 = ((addr >> 6) ^ (addr >> 12) ^ (addr >> 18) ^ (addr >> 22)) & 1
            b1 = ((addr >> 7) ^ (addr >> 13) ^ (addr >> 19) ^ (addr >> 23)) & 1
            b2 = ((addr >> 8) ^ (addr >> 14) ^ (addr >> 20) ^ (addr >> 24)) & 1
            amd = b0 | (b1 << 1) | (b2 << 2)
            selected_bg = amd if is_ddr5 else (amd & 0x3)
        else:  # Standard XOR interleaving
            if is_ddr5:
                selected_bg = ((addr >> 6) & 0x7) ^ ((addr >> 18) & 0x7)
            else:
                selected_bg = (((addr >> 6) & 0x3) ^ ((addr >> 18) & 0x3)) & 0x3

        if bank_coloring_en:
            tid = (tenant_id >> 2) & 0x3
            bg = ((tid << 1) | (selected_bg & 1)) if is_ddr5 else tid
        else:
            bg = selected_bg

        if scramble_en and scramble_mode == 2:
            sc_row, sc_bank = cls.scarf_permute(row, std_bank, bg, scramble_seed)
            out_bank = std_bank if bank_coloring_en else sc_bank
            return bg & 0x7, out_bank & 0x3, sc_row & 0x1FFFF, col & 0x1FFF

        return bg & 0x7, std_bank & 0x3, row & 0x1FFFF, col & 0x1FFF
