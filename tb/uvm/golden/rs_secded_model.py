# Mô hình tham chiếu độc lập SEC-DED Hamming (72,64) và Reed-Solomon RS(18,16) trên GF(2^8).

def _parity64(val: int) -> int:
    return val.bit_count() & 1


class RsSecdedModel:
    """Mô hình Python thuần kiểm chứng mã ECC SEC-DED (72,64) và RS(18,16) GF(2^8)."""

    # Ma tran kiem tra chan le Hamming mo rong (72,64) voi dao bit kiem tra 0xAA chong toan 0/1
    SECDED_MASKS = (
        0xAB55_5555_56AA_AD5B,
        0xCD99_9999_9B33_366D,
        0xF1E1_E1E1_E3C3_C78E,
        0x01FE_01FE_03FC_07F0,
        0x01FF_FE00_03FF_F800,
        0x01FF_FFFF_FC00_0000,
        0xFE00_0000_0000_0000,
    )
    SECDED_INV = 0xAA

    # Bang syndrome cho tung bit du lieu 0..63 (vị trí Hamming bo luy thua 2)
    DATA_SYN = tuple(
        pos
        for pos in range(0x80 | 3, 0x80 | 72)
        if ((pos & 0x7F) & ((pos & 0x7F) - 1)) != 0
    )

    RS_POLY = 0x11D
    RS_ALPHAS = tuple(
        pow_val
        for pow_val in [1]
    )

    @classmethod
    def secded72_encode(cls, data64: int) -> int:
        d = data64 & ((1 << 64) - 1)
        ecc = 0
        for i, mask in enumerate(cls.SECDED_MASKS):
            ecc |= _parity64(d & mask) << i
        p_all = _parity64(d) ^ _parity64(ecc & 0x7F)
        ecc |= p_all << 7
        return (ecc ^ cls.SECDED_INV) & 0xFF

    @classmethod
    def secded72_syndrome(cls, data64: int, stored_ecc: int) -> int:
        d = data64 & ((1 << 64) - 1)
        e = (stored_ecc ^ cls.SECDED_INV) & 0xFF
        syn = 0
        for i, mask in enumerate(cls.SECDED_MASKS):
            bit = ((e >> i) & 1) ^ _parity64(d & mask)
            syn |= bit << i
        syn |= (_parity64(d) ^ _parity64(e)) << 7
        return syn & 0xFF

    @classmethod
    def secded72_decode(cls, data64: int, stored_ecc: int) -> tuple[int, bool, bool]:
        """Trả về (corrected_data64, ce_detected, ue_detected)."""
        d = data64 & ((1 << 64) - 1)
        syn = cls.secded72_syndrome(d, stored_ecc)
        if syn == 0:
            return d, False, False
        ce = bool((syn & 0x80) and ((syn & 0x7F) <= 71))
        if ce:
            for j, ds in enumerate(cls.DATA_SYN):
                if syn == ds:
                    d ^= 1 << j
                    break
            return d, True, False
        return d, False, True

    @staticmethod
    def gf256_mul(a: int, b: int) -> int:
        p = 0
        x = a & 0xFF
        for i in range(8):
            if (b >> i) & 1:
                p ^= x
            msb = x & 0x80
            x = (x << 1) & 0xFF
            if msb:
                x ^= 0x1D
        return p

    @classmethod
    def rs_alphas(cls) -> list[int]:
        vals = [1]
        for _ in range(1, 18):
            vals.append(cls.gf256_mul(vals[-1], 2))
        return vals

    @classmethod
    def rs18_16_encode(cls, data_symbols: list[int]) -> list[int]:
        """Mã hóa 16 symbol 8-bit thành 18 symbol RS(18,16) trên GF(2^8), d=3."""
        if len(data_symbols) != 16:
            raise ValueError("RS(18,16) expects 16 data symbols")
        alphas = cls.rs_alphas()
        a_sum = 0
        b_sum = 0
        for d, al in zip(data_symbols, alphas[:16]):
            a_sum ^= d & 0xFF
            b_sum ^= cls.gf256_mul(d & 0xFF, al)
        # K = (alpha^16 + alpha^17)^-1 = 0xF9 trong GF(2^8) voi poly 0x11D
        p17 = cls.gf256_mul(b_sum ^ cls.gf256_mul(a_sum, alphas[16]), 0xF9)
        p16 = a_sum ^ p17
        return [x & 0xFF for x in data_symbols] + [p16, p17]

    @classmethod
    def rs18_16_syndrome(cls, cw_symbols: list[int]) -> tuple[int, int]:
        if len(cw_symbols) != 18:
            raise ValueError("RS(18,16) codeword expects 18 symbols")
        alphas = cls.rs_alphas()
        s0 = 0
        s1 = 0
        for c, al in zip(cw_symbols, alphas):
            s0 ^= c & 0xFF
            s1 ^= cls.gf256_mul(c & 0xFF, al)
        return s0, s1

    @classmethod
    def verify_selftest(cls) -> None:
        # Kiem tra 1-bit flip -> CE, 2-bit flip -> UE, all-zeros stored -> UE, va RS syndrome=0
        val = 0x0123_4567_89AB_CDEF
        ecc = cls.secded72_encode(val)
        c, ce, ue = cls.secded72_decode(val ^ (1 << 19), ecc)
        if not (ce and not ue and c == val):
            raise AssertionError("SEC-DED 1-bit error correction failed")
        _, ce2, ue2 = cls.secded72_decode(val ^ (1 << 3) ^ (1 << 41), ecc)
        if not (ue2 and not ce2):
            raise AssertionError("SEC-DED 2-bit error detection failed")
        _, _, ue_zero = cls.secded72_decode(0, 0)
        if not ue_zero:
            raise AssertionError("SEC-DED all-zero trapping check failed")
        cw = cls.rs18_16_encode([(i * 19 + 5) & 0xFF for i in range(16)])
        if cls.rs18_16_syndrome(cw) != (0, 0):
            raise AssertionError("RS(18,16) non-zero syndrome on clean codeword")
