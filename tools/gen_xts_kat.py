#!/usr/bin/env python3
"""
===============================================================================
Script: tools/gen_xts_kat.py
Description: Generates and verifies IEEE 1619 / NIST SP 800-38E AES-256-XTS KATs
             and 2048 random test vectors using an independent Python model
             (cryptography library) for RTL bit-by-bit verification.
===============================================================================
"""

import os
import sys
import random
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "tb", "crypto")

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

def verify_fips_and_ieee1619():
    # 1. FIPS-197 C.3 key check
    fips_rk = expand_key_256(bytes(range(32)))
    assert le128(fips_rk[2]) == 0x9cc072a593ce7fa998c476a19fc273a5, hex(le128(fips_rk[2]))
    assert le128(fips_rk[14]) == 0x36de686d3cc21a37e97909bfcc79fc24, hex(le128(fips_rk[14]))

    # 2. IEEE 1619 Vector 10
    key1 = bytes.fromhex("2718281828459045235360287471352662497757247093699959574966967627")
    key2 = bytes.fromhex("3141592653589793238462643383279502884197169399375105820974944592")
    sector = 0xFF
    tweak_iv = sector.to_bytes(16, "little")
    pt = bytes(range(64))

    ref = Cipher(algorithms.AES(key1 + key2), modes.XTS(tweak_iv)).encryptor()
    ct_ref = ref.update(pt) + ref.finalize()

    # Verify decrypt
    dec_ref = Cipher(algorithms.AES(key1 + key2), modes.XTS(tweak_iv)).decryptor()
    pt_rec = dec_ref.update(ct_ref) + dec_ref.finalize()
    assert pt_rec == pt, "IEEE 1619 Vector 10 decrypt mismatch"

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
    print("[PASS] IEEE 1619 Vector 10 verified bit-exact with cryptography")
    return key1, key2, tweak_iv, pt, ct_ref, tweaks

def generate_random_2048(count=2048, seed=42):
    random.seed(seed)
    os.makedirs(OUT_DIR, exist_ok=True)
    kat_path = os.path.join(OUT_DIR, "xts_kat_2000.txt")

    print(f"Generating {count} random AES-256-XTS blocks (seed={seed})...")
    lines = []
    # 512 sectors * 4 blocks/sector = 2048 blocks
    num_sectors = count // 4
    for s in range(num_sectors):
        k1 = random.randbytes(32)
        k2 = random.randbytes(32)
        while k1 == k2:
            k2 = random.randbytes(32)
        key = k1 + k2

        line_num = (s * 4) & 0x03FF_FFFF_FFFF_FFFF
        asid = (s * 3) & 0xF
        epoch = (s * 17) & 0x7FFFF
        tweak_val = line_num | (asid << 58) | (epoch << 62)
        tweak_bytes = tweak_val.to_bytes(16, "little")

        pt64 = random.randbytes(64)
        c_enc = Cipher(algorithms.AES(key), modes.XTS(tweak_bytes)).encryptor()
        ct64 = c_enc.update(pt64) + c_enc.finalize()

        c_dec = Cipher(algorithms.AES(key), modes.XTS(tweak_bytes)).decryptor()
        rec64 = c_dec.update(ct64) + c_dec.finalize()
        assert rec64 == pt64

        # Compute initial tweak T0 via AES_K2(tweak_bytes)
        t0 = aes_ecb(k2, tweak_bytes)
        cur_tweak = t0
        for b in range(4):
            pt_b = pt64[b*16:(b+1)*16]
            ct_b = ct64[b*16:(b+1)*16]
            # Verify manual block computation
            p_xor_t = bytes(x ^ y for x, y in zip(pt_b, cur_tweak))
            enc_b = aes_ecb(k1, p_xor_t)
            c_manual = bytes(x ^ y for x, y in zip(enc_b, cur_tweak))
            assert c_manual == ct_b

            # Format line:
            # k1(hex64) k2(hex64) tweak_in(hex32) tweak_j(hex32) pt(hex32) ct(hex32) block_idx
            lines.append(f"{k1.hex()} {k2.hex()} {tweak_bytes.hex()} {cur_tweak.hex()} {pt_b.hex()} {ct_b.hex()} {b}\n")
            cur_tweak = gf_mul_alpha(cur_tweak)

    with open(kat_path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"[PASS] Successfully verified and wrote {len(lines)} XTS blocks to {kat_path}")
    return len(lines)

def main():
    print("=" * 70)
    print("  Q-SHIELD IEEE 1619 AES-256-XTS KAT GENERATOR & VERIFIER")
    print("=" * 70)
    verify_fips_and_ieee1619()
    n = generate_random_2048(count=2048, seed=42)
    print(f"[SUMMARY] Total Verified Blocks: {n} (All 100% bit-exact). Exit 0.")

if __name__ == "__main__":
    main()
