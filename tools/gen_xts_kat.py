from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

SBOX = [0] * 256


def _init_sbox():
    p = q = 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        x = q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4)
        SBOX[p] = (x ^ 0x63) & 0xFF
        if p == 1:
            break
    SBOX[0] = 0x63


_init_sbox()


def expand_key_256(key):
    rcon = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]
    w = [list(key[4 * i:4 * i + 4]) for i in range(8)]
    for i in range(8, 60):
        t = list(w[i - 1])
        if i % 8 == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= rcon[i // 8 - 1]
        elif i % 8 == 4:
            t = [SBOX[b] for b in t]
        w.append([a ^ b for a, b in zip(w[i - 8], t)])
    return [bytes(sum(w[4 * r:4 * r + 4], [])) for r in range(15)]


def le128(b):
    return int.from_bytes(b, "little")


def sv128(b):
    v = le128(b)
    return "{" + ", ".join(f"32'h{(v >> (96 - 32 * k)) & 0xFFFFFFFF:08x}" for k in range(4)) + "}"


def gf_mul_alpha(t):
    v = le128(t)
    carry = v >> 127
    v = ((v << 1) & ((1 << 128) - 1)) ^ (0x87 if carry else 0)
    return v.to_bytes(16, "little")


def aes_ecb(key, block):
    e = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return e.update(block) + e.finalize()


# FIPS-197 C.3 key: check the expansion against the round keys already hard-coded in tb_aes_xts_pipe.sv
fips_rk = expand_key_256(bytes(range(32)))
assert le128(fips_rk[2]) == 0x9cc072a593ce7fa998c476a19fc273a5, hex(le128(fips_rk[2]))
assert le128(fips_rk[14]) == 0x36de686d3cc21a37e97909bfcc79fc24, hex(le128(fips_rk[14]))

key1 = bytes.fromhex("2718281828459045235360287471352662497757247093699959574966967627")
key2 = bytes.fromhex("3141592653589793238462643383279502884197169399375105820974944592")
sector = 0xFF
tweak_iv = sector.to_bytes(16, "little")
pt = bytes(range(64))

ref = Cipher(algorithms.AES(key1 + key2), modes.XTS(tweak_iv)).encryptor()
ct_ref = ref.update(pt) + ref.finalize()

t = aes_ecb(key2, tweak_iv)
tweaks, ct_manual = [], b""
for j in range(4):
    p = pt[16 * j:16 * j + 16]
    x = bytes(a ^ b for a, b in zip(p, t))
    c = bytes(a ^ b for a, b in zip(aes_ecb(key1, x), t))
    tweaks.append(t)
    ct_manual += c
    t = gf_mul_alpha(t)
assert ct_manual == ct_ref, "manual XTS != OpenSSL XTS"

rk = expand_key_256(key1)
print("// round keys key1")
for r, k in enumerate(rk):
    print(f"xts_rk[{r}] = {sv128(k)};")
for j in range(4):
    print(f"xts_pt[{j}] = {sv128(pt[16*j:16*j+16])};")
    print(f"xts_tw[{j}] = {sv128(tweaks[j])};")
    print(f"xts_ct[{j}] = {sv128(ct_ref[16*j:16*j+16])};")
print("// ct_ref hex:", ct_ref.hex())
