# Mô hình tham chiếu AES-256-XTS (IEEE 1619-2018 & FIPS-197) viết độc lập bằng Python thuần.

SBOX = (
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
)

INV_SBOX = tuple(SBOX.index(i) for i in range(256))
RCON = (0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36)


def _xtime(a: int) -> int:
    return ((a << 1) ^ 0x1B) & 0xFF if (a & 0x80) else (a << 1) & 0xFF


def _gmul(a: int, b: int) -> int:
    res = 0
    for _ in range(8):
        if b & 1:
            res ^= a
        a = _xtime(a)
        b >>= 1
    return res


def aes256_expand_key(key_bytes: bytes) -> list[bytes]:
    """Mở rộng khóa AES-256 (32 byte -> 15 khóa vòng x 16 byte)."""
    if len(key_bytes) != 32:
        raise ValueError("AES-256 key must be 32 bytes")
    words = [list(key_bytes[4 * i : 4 * (i + 1)]) for i in range(8)]
    for i in range(8, 60):
        temp = words[i - 1][:]
        if i % 8 == 0:
            temp = [SBOX[temp[(j + 1) % 4]] for j in range(4)]
            temp[0] ^= RCON[i // 8 - 1]
        elif i % 8 == 4:
            temp = [SBOX[b] for b in temp]
        words.append([words[i - 8][j] ^ temp[j] for j in range(4)])
    return [bytes(sum(words[4 * r : 4 * (r + 1)], [])) for r in range(15)]


def _add_round_key(state: list[int], rk: bytes) -> None:
    for i in range(16):
        state[i] ^= rk[i]


def _shift_rows(s: list[int]) -> list[int]:
    return [
        s[0], s[5], s[10], s[15],
        s[4], s[9], s[14], s[3],
        s[8], s[13], s[2], s[7],
        s[12], s[1], s[6], s[11],
    ]


def _inv_shift_rows(s: list[int]) -> list[int]:
    return [
        s[0], s[13], s[10], s[7],
        s[4], s[1], s[14], s[11],
        s[8], s[5], s[2], s[15],
        s[12], s[9], s[6], s[3],
    ]


def _mix_columns(s: list[int]) -> list[int]:
    out = [0] * 16
    for c in range(4):
        b0, b1, b2, b3 = s[4 * c : 4 * c + 4]
        out[4 * c + 0] = _xtime(b0) ^ _xtime(b1) ^ b1 ^ b2 ^ b3
        out[4 * c + 1] = b0 ^ _xtime(b1) ^ _xtime(b2) ^ b2 ^ b3
        out[4 * c + 2] = b0 ^ b1 ^ _xtime(b2) ^ _xtime(b3) ^ b3
        out[4 * c + 3] = _xtime(b0) ^ b0 ^ b1 ^ b2 ^ _xtime(b3)
    return out


def _inv_mix_columns(s: list[int]) -> list[int]:
    out = [0] * 16
    for c in range(4):
        b0, b1, b2, b3 = s[4 * c : 4 * c + 4]
        out[4 * c + 0] = _gmul(b0, 0x0E) ^ _gmul(b1, 0x0B) ^ _gmul(b2, 0x0D) ^ _gmul(b3, 0x09)
        out[4 * c + 1] = _gmul(b0, 0x09) ^ _gmul(b1, 0x0E) ^ _gmul(b2, 0x0B) ^ _gmul(b3, 0x0D)
        out[4 * c + 2] = _gmul(b0, 0x0D) ^ _gmul(b1, 0x09) ^ _gmul(b2, 0x0E) ^ _gmul(b3, 0x0B)
        out[4 * c + 3] = _gmul(b0, 0x0B) ^ _gmul(b1, 0x0D) ^ _gmul(b2, 0x09) ^ _gmul(b3, 0x0E)
    return out


def aes256_encrypt_block(block16: bytes, round_keys: list[bytes]) -> bytes:
    s = list(block16)
    _add_round_key(s, round_keys[0])
    for r in range(1, 14):
        s = [SBOX[b] for b in s]
        s = _shift_rows(s)
        s = _mix_columns(s)
        _add_round_key(s, round_keys[r])
    s = [SBOX[b] for b in s]
    s = _shift_rows(s)
    _add_round_key(s, round_keys[14])
    return bytes(s)


def aes256_decrypt_block(block16: bytes, round_keys: list[bytes]) -> bytes:
    s = list(block16)
    _add_round_key(s, round_keys[14])
    for r in range(13, 0, -1):
        s = _inv_shift_rows(s)
        s = [INV_SBOX[b] for b in s]
        _add_round_key(s, round_keys[r])
        s = _inv_mix_columns(s)
    s = _inv_shift_rows(s)
    s = [INV_SBOX[b] for b in s]
    _add_round_key(s, round_keys[0])
    return bytes(s)


def gf128_mul_alpha(tweak16: bytes) -> bytes:
    """Nhân alpha (x) trong GF(2^128) theo IEEE 1619-2018: little-endian, x^128 + x^7 + x^2 + x + 1."""
    val = int.from_bytes(tweak16, "little")
    msb = (val >> 127) & 1
    val = (val << 1) & ((1 << 128) - 1)
    if msb:
        val ^= 0x87
    return val.to_bytes(16, "little")


class AesXts256Model:
    """Mô hình tham chiếu IEEE 1619-2018 AES-256-XTS độc lập cho Q-Shield."""

    # NIST FIPS-197 Appendix C.3 AES-256 KAT & IEEE 1619 GF(2^128) vector kiểm định
    FIPS197_KEY = bytes(range(32))
    FIPS197_PT = bytes(i * 0x11 for i in range(16))
    FIPS197_CT = bytes.fromhex("8ea2b7ca516745bfeafc49904b496089")

    def __init__(self, k1: bytes, k2: bytes):
        self.rk1 = aes256_expand_key(k1)
        self.rk2 = aes256_expand_key(k2)

    @staticmethod
    def build_tweak_iv(addr: int, asid: int, epoch: int) -> bytes:
        line_num = (addr >> 6) & ((1 << 58) - 1)
        iv_int = line_num | ((asid & 0xF) << 58) | ((epoch & ((1 << 19) - 1)) << 62)
        return iv_int.to_bytes(16, "little")

    def encrypt_line_64b(self, pt64: bytes, addr: int, asid: int = 0, epoch: int = 0) -> bytes:
        if len(pt64) != 64:
            raise ValueError("Cache line must be 64 bytes")
        tweak = aes256_encrypt_block(self.build_tweak_iv(addr, asid, epoch), self.rk2)
        out = bytearray()
        for j in range(4):
            p = pt64[16 * j : 16 * (j + 1)]
            x = bytes(a ^ b for a, b in zip(p, tweak))
            c_mid = aes256_encrypt_block(x, self.rk1)
            out.extend(a ^ b for a, b in zip(c_mid, tweak))
            tweak = gf128_mul_alpha(tweak)
        return bytes(out)

    def decrypt_line_64b(self, ct64: bytes, addr: int, asid: int = 0, epoch: int = 0) -> bytes:
        if len(ct64) != 64:
            raise ValueError("Cache line must be 64 bytes")
        tweak = aes256_encrypt_block(self.build_tweak_iv(addr, asid, epoch), self.rk2)
        out = bytearray()
        for j in range(4):
            c = ct64[16 * j : 16 * (j + 1)]
            x = bytes(a ^ b for a, b in zip(c, tweak))
            p_mid = aes256_decrypt_block(x, self.rk1)
            out.extend(a ^ b for a, b in zip(p_mid, tweak))
            tweak = gf128_mul_alpha(tweak)
        return bytes(out)

    @classmethod
    def verify_kat(cls) -> None:
        rk = aes256_expand_key(cls.FIPS197_KEY)
        ct = aes256_encrypt_block(cls.FIPS197_PT, rk)
        if ct != cls.FIPS197_CT:
            raise AssertionError(f"AES-256 KAT mismatch: got {ct.hex()} != {cls.FIPS197_CT.hex()}")
        pt = aes256_decrypt_block(ct, rk)
        if pt != cls.FIPS197_PT:
            raise AssertionError("AES-256 decrypt KAT mismatch")
        # Kiem dinh GF(2^128) * alpha theo da thuc 0x87 va XTS 64B roundtrip
        t_msb = (1 << 127).to_bytes(16, "little")
        if gf128_mul_alpha(t_msb) != (0x87).to_bytes(16, "little"):
            raise AssertionError("GF(2^128) alpha carry reduction mismatch")
        model = cls(bytes(range(32)), bytes(range(32, 64)))
        sample = bytes((i * 13 + 7) & 0xFF for i in range(64))
        c = model.encrypt_line_64b(sample, 0x0010_0400, asid=3, epoch=0x123)
        if c == sample:
            raise AssertionError("AES-XTS output matched plaintext")
        if model.decrypt_line_64b(c, 0x0010_0400, asid=3, epoch=0x123) != sample:
            raise AssertionError("AES-XTS roundtrip mismatch")
