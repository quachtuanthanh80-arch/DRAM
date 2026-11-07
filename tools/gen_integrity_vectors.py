#!/usr/bin/env python3
"""Q-Shield Integrity Architecture Reference Model and Test Vector Generator.
Generates reference calculations for:
  1. qshield_meta_layout: memory mapping of Counter Blocks, MAC Lines, and Bonsai Merkle Tree.
  2. qshield_counter_unit: split-counter increment, major rollover, and XTS tweak generation.
  3. qshield_mac_unit: Carter-Wegman MAC over GF(2^128) and Bonsai Merkle Tree node hashing.
Seed-fixed, bit-exact and synthesizable validation.
"""
import math
import random
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]

PROT_BASE_DEFAULT = 0
PROT_LINES_DEFAULT = 1 << 20  # 1048576 lines = 64 MiB
TREE_ARITY = 8
GHASH_R = 0xE1000000000000000000000000000000


def ghash_mul(X, Y):
    """Multiplication in GF(2^128) per NIST SP 800-38D Algorithm 1."""
    V = Y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    Z = 0
    for i in range(128):
        bit = (X >> (127 - i)) & 1
        if bit:
            Z ^= V
        if (V & 1) == 0:
            V >>= 1
        else:
            V = (V >> 1) ^ GHASH_R
    return Z & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF


def ghash_512(blocks_128, H):
    """Computes GHASH over 4 128-bit blocks (512-bit data) + 1 length block."""
    assert len(blocks_128) == 4
    Y = 0
    for blk in blocks_128:
        Y = ghash_mul(Y ^ blk, H)
    len_block = (0 << 64) | 512  # len(AAD)=0, len(C)=512 bits
    Y = ghash_mul(Y ^ len_block, H)
    return Y


def make_mask_data(k3_bytes, major, minor, line_idx):
    """Mask M = AES256_K3(0x01 || major[63:0] || minor[6:0] || line_idx[48:0])."""
    # 8-bit domain separator 0x01, 64-bit major, 7-bit minor, 49-bit line_idx = 128 bits
    inp = (
        (0x01 << 120) |
        ((major & 0xFFFFFFFFFFFFFFFF) << 56) |
        ((minor & 0x7F) << 49) |
        (line_idx & ((1 << 49) - 1))
    )
    inp_bytes = inp.to_bytes(16, "big")
    cipher = Cipher(algorithms.AES(k3_bytes), modes.ECB())
    enc = cipher.encryptor()
    out = enc.update(inp_bytes) + enc.finalize()
    return int.from_bytes(out, "big")


def make_mask_node(k3_bytes, level, node_idx):
    """Mask M = AES256_K3(0x02 || level[3:0] || node_idx[59:0] || pad[56:0])."""
    inp = (
        (0x02 << 120) |
        ((level & 0x0F) << 116) |
        ((node_idx & ((1 << 60) - 1)) << 56)
    )
    inp_bytes = inp.to_bytes(16, "big")
    cipher = Cipher(algorithms.AES(k3_bytes), modes.ECB())
    enc = cipher.encryptor()
    out = enc.update(inp_bytes) + enc.finalize()
    return int.from_bytes(out, "big")


def compute_tag(blocks_128, H, mask):
    ghash_val = ghash_512(blocks_128, H)
    tag128 = ghash_val ^ mask
    tag64 = (tag128 >> 64) & 0xFFFFFFFFFFFFFFFF
    return tag64, tag128, ghash_val


class MetaLayoutModel:
    def __init__(self, prot_base=PROT_BASE_DEFAULT, prot_lines=PROT_LINES_DEFAULT):
        self.prot_base = prot_base
        self.prot_lines = prot_lines
        self.line_bytes = 64
        self.prot_bytes = self.prot_lines * self.line_bytes
        self.prot_end = self.prot_base + self.prot_bytes
        
        self.meta_base = self.prot_end
        
        # 1. Counter Blocks (CB)
        self.num_cb = self.prot_lines // 64
        self.cb_bytes = self.num_cb * 64
        self.cb_base = self.meta_base
        
        # 2. MAC Lines (ML)
        self.num_ml = self.prot_lines // 8
        self.ml_bytes = self.num_ml * 64
        self.ml_base = self.cb_base + self.cb_bytes
        
        # 3. Tree Nodes (TN)
        self.tn_base = self.ml_base + self.ml_bytes
        self.level_counts = []
        cur = self.num_cb
        while cur > 1:
            nxt = math.ceil(cur / TREE_ARITY)
            self.level_counts.append(nxt)
            cur = nxt
            if nxt <= TREE_ARITY:
                break
        
        self.tree_levels = len(self.level_counts)
        self.level_offsets = [0] * (self.tree_levels + 1)
        accum = 0
        for lvl in range(1, self.tree_levels + 1):
            self.level_offsets[lvl] = accum
            accum += self.level_counts[lvl - 1]
            
        self.total_tn_nodes = accum
        self.tn_bytes = self.total_tn_nodes * 64
        self.meta_end = self.tn_base + self.tn_bytes
        self.total_meta_bytes = self.meta_end - self.meta_base
        self.overhead_pct = (self.total_meta_bytes / self.prot_bytes) * 100.0

    def print_summary(self):
        print("================================================================================")
        print("  [META_LAYOUT] Q-SHIELD METADATA LAYOUT & MERKLE TREE SUMMARY")
        print("================================================================================")
        print(f"Protected Region : 0x{self.prot_base:016X} .. 0x{self.prot_end:016X} ({self.prot_bytes / (1<<20):.2f} MiB, {self.prot_lines} lines)")
        print(f"Metadata Base    : 0x{self.meta_base:016X}")
        print(f"  Counter Blocks : 0x{self.cb_base:016X} .. 0x{self.ml_base:016X} ({self.num_cb} CBs, {self.cb_bytes / 1024:.2f} KiB)")
        print(f"  MAC Lines      : 0x{self.ml_base:016X} .. 0x{self.tn_base:016X} ({self.num_ml} MLs, {self.ml_bytes / (1<<20):.2f} MiB)")
        print(f"  Tree Nodes     : 0x{self.tn_base:016X} .. 0x{self.meta_end:016X} ({self.total_tn_nodes} nodes, {self.tn_bytes / 1024:.2f} KiB)")
        for lvl in range(1, self.tree_levels + 1):
            cnt = self.level_counts[lvl - 1]
            off = self.level_offsets[lvl]
            print(f"    - Level {lvl}: {cnt:6d} nodes (DRAM offset: +0x{off*64:08X}, {cnt*64/1024:7.2f} KiB)")
        print(f"Total Metadata   : {self.total_meta_bytes} bytes ({self.total_meta_bytes / (1<<20):.4f} MiB)")
        print(f"Metadata Overhead: {self.overhead_pct:.4f} %")
        print("================================================================================")

    def is_protected(self, addr):
        return self.prot_base <= addr < self.prot_end

    def is_metadata(self, addr):
        return self.meta_base <= addr < self.meta_end

    def line_index(self, addr):
        return (addr - self.prot_base) // self.line_bytes

    def cb_addr_and_slot(self, L):
        cb_idx = L // 64
        slot = L % 64
        return (self.cb_base + cb_idx * 64, slot)

    def ml_addr_and_slot(self, L):
        ml_idx = L // 8
        slot = L % 8
        return (self.ml_base + ml_idx * 64, slot)

    def tn_addr_and_slot(self, level, idx):
        assert 1 <= level <= self.tree_levels
        assert idx < self.level_counts[level - 1]
        base_node = self.level_offsets[level] + idx
        return (self.tn_base + base_node * 64, idx % 8)


class CounterUnitModel:
    @staticmethod
    def parse_cb(cb_bytes_or_int):
        if isinstance(cb_bytes_or_int, int):
            val = cb_bytes_or_int
        elif isinstance(cb_bytes_or_int, bytes):
            val = int.from_bytes(cb_bytes_or_int, "little")
        else:
            raise TypeError("Expected int or bytes")
        
        major = (val >> 448) & 0xFFFFFFFFFFFFFFFF
        minors = [(val >> (i * 7)) & 0x7F for i in range(64)]
        return major, minors

    @staticmethod
    def pack_cb(major, minors):
        assert len(minors) == 64
        val = (major & 0xFFFFFFFFFFFFFFFF) << 448
        for i, m in enumerate(minors):
            val |= (m & 0x7F) << (i * 7)
        return val

    @classmethod
    def apply_counter(cls, cb_val, line_idx, asid=0, inc=True):
        major, minors = cls.parse_cb(cb_val)
        slot = line_idx % 64
        cur_minor = minors[slot]
        
        if inc:
            if cur_minor == 127:
                overflow = 1
                new_major = (major + 1) & 0xFFFFFFFFFFFFFFFF
                new_minors = [0] * 64
                eff_major = new_major
                eff_minor = 0
            else:
                overflow = 0
                new_major = major
                new_minors = list(minors)
                new_minors[slot] = cur_minor + 1
                eff_major = major
                eff_minor = cur_minor + 1
        else:
            overflow = 0
            new_major = major
            new_minors = list(minors)
            eff_major = major
            eff_minor = cur_minor

        new_cb_val = cls.pack_cb(new_major, new_minors)
        tweak = (
            ((eff_major & 0xFFFFFFFFFFFFFFFF) << 64) |
            ((eff_minor & 0x7F) << 57) |
            ((asid & 0x0F) << 53) |
            (line_idx & ((1 << 53) - 1))
        )
        return new_cb_val, tweak, overflow


def verify_ghash_against_cryptography(n_vectors=1000):
    print(f"Verifying GHASH against cryptography AESGCM ({n_vectors} vectors)...")
    random.seed(1337)
    
    for i in range(n_vectors):
        key = random.randbytes(32)
        nonce = random.randbytes(12)
        # random 64-byte plaintext (4 128-bit blocks)
        pt = random.randbytes(64)
        
        aesgcm = AESGCM(key)
        ct_with_tag = aesgcm.encrypt(nonce, pt, None)
        ct = ct_with_tag[:-16]
        tag_expected = ct_with_tag[-16:].hex()
        
        # Subkey H = AES256_K(0)
        cipher = Cipher(algorithms.AES(key), modes.ECB())
        enc = cipher.encryptor()
        H = int.from_bytes(enc.update(bytes(16)) + enc.finalize(), "big")
        
        blocks = [
            int.from_bytes(ct[0:16], "big"),
            int.from_bytes(ct[16:32], "big"),
            int.from_bytes(ct[32:48], "big"),
            int.from_bytes(ct[48:64], "big")
        ]
        ghash_out = ghash_512(blocks, H)
        
        J0 = nonce + b"\x00\x00\x00\x01"
        enc2 = cipher.encryptor()
        mask = int.from_bytes(enc2.update(J0) + enc2.finalize(), "big")
        tag_calc = f"{ghash_out ^ mask:032x}"
        assert tag_calc == tag_expected, f"Mismatch at vector {i}"
        
    print(f"[PASS] All {n_vectors} GHASH vectors match cryptography AESGCM bit-exact.")


def generate_mac_test_vectors():
    print("Generating MAC test vectors for lines (>= 2000) and nodes (>= 1000)...")
    random.seed(777)
    k3_bytes = bytes.fromhex("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF")
    cipher = Cipher(algorithms.AES(k3_bytes), modes.ECB())
    enc = cipher.encryptor()
    H = int.from_bytes(enc.update(bytes(16)) + enc.finalize(), "big")
    
    vec_path = ROOT / "build" / "mac_vectors.txt"
    with open(vec_path, "w", encoding="utf-8") as f:
        f.write(f"# K3={k3_bytes.hex()} H={H:032x}\n")
        f.write("# TYPE C0 C1 C2 C3 MASK TAG64\n")
        
        # 1. 2000 line vectors
        for i in range(2000):
            c0 = random.randint(0, (1 << 128) - 1)
            c1 = random.randint(0, (1 << 128) - 1)
            c2 = random.randint(0, (1 << 128) - 1)
            c3 = random.randint(0, (1 << 128) - 1)
            major = random.randint(0, (1 << 64) - 1)
            minor = random.randint(0, 127)
            line_idx = i
            mask = make_mask_data(k3_bytes, major, minor, line_idx)
            tag64, _, _ = compute_tag([c0, c1, c2, c3], H, mask)
            f.write(f"LINE {c0:032x} {c1:032x} {c2:032x} {c3:032x} {mask:032x} {tag64:016x}\n")
            
        # 2. 1000 node vectors
        for i in range(1000):
            b0 = random.randint(0, (1 << 128) - 1)
            b1 = random.randint(0, (1 << 128) - 1)
            b2 = random.randint(0, (1 << 128) - 1)
            b3 = random.randint(0, (1 << 128) - 1)
            level = random.randint(1, 4)
            node_idx = i
            mask = make_mask_node(k3_bytes, level, node_idx)
            tag64, _, _ = compute_tag([b0, b1, b2, b3], H, mask)
            f.write(f"NODE {b0:032x} {b1:032x} {b2:032x} {b3:032x} {mask:032x} {tag64:016x}\n")
            
    print(f"[PASS] Successfully wrote 3000 vectors to {vec_path}")
    
    # 3. Test: Address A and Address A + 4GB produce different tags
    addr_A = 0x0000_1000
    addr_B = addr_A + (4 << 30) # A + 4 GiB
    line_A = addr_A // 64
    line_B = addr_B // 64
    c_fixed = [0x11111111_22222222_33333333_44444444] * 4
    mask_A = make_mask_data(k3_bytes, 1, 10, line_A)
    mask_B = make_mask_data(k3_bytes, 1, 10, line_B)
    tag_A, _, _ = compute_tag(c_fixed, H, mask_A)
    tag_B, _, _ = compute_tag(c_fixed, H, mask_B)
    assert tag_A != tag_B, "Tag collision between address A and A + 4GB!"
    print(f"[PASS] Address A (0x{addr_A:X}) tag=0x{tag_A:016X} != Address A+4GB (0x{addr_B:X}) tag=0x{tag_B:016X}")


def main():
    layout = MetaLayoutModel()
    layout.print_summary()
    
    print("Generating validation vectors for tb_qshield_meta_layout...")
    vec_path = ROOT / "build" / "meta_layout_vectors.txt"
    vec_path.parent.mkdir(parents=True, exist_ok=True)
    
    random.seed(42)
    test_lines = [
        0, 1, 63, 64, 65, 127, 128,
        layout.prot_lines - 65, layout.prot_lines - 64, layout.prot_lines - 1
    ]
    for _ in range(10000 - len(test_lines)):
        test_lines.append(random.randint(0, layout.prot_lines - 1))
        
    with open(vec_path, "w", encoding="utf-8") as f:
        f.write("# Format: line_idx addr cb_addr cb_slot ml_addr ml_slot\n")
        for L in test_lines:
            addr = layout.prot_base + L * 64
            cb_addr, cb_slot = layout.cb_addr_and_slot(L)
            ml_addr, ml_slot = layout.ml_addr_and_slot(L)
            f.write(f"{L:016X} {addr:016X} {cb_addr:016X} {cb_slot:02X} {ml_addr:016X} {ml_slot:02X}\n")
            
    print(f"Wrote {len(test_lines)} layout vectors to {vec_path}")
    
    verify_ghash_against_cryptography(1000)
    generate_mac_test_vectors()
    generate_cache_test_vectors(50000)


class CacheLine:
    def __init__(self):
        self.valid = False
        self.dirty = False
        self.verified = False
        self.pinned = False
        self.tag = 0
        self.addr = 0


class MetaCacheModel:
    def __init__(self, num_sets=16, num_ways=4):
        self.num_sets = num_sets
        self.num_ways = num_ways
        self.sets = [[CacheLine() for _ in range(num_ways)] for _ in range(num_sets)]
        self.plru = [0] * num_sets  # 3 bits per set: b0, b1, b2
        self.hit_cnt = 0
        self.miss_cnt = 0
        self.evict_cnt = 0
        self.wb_cnt = 0

    def _get_set_tag(self, addr):
        set_idx = (addr >> 6) & (self.num_sets - 1)
        tag = addr >> (6 + 4) # 16 sets = 4 bits
        return set_idx, tag

    def _update_plru(self, set_idx, way):
        b0 = (self.plru[set_idx] >> 2) & 1
        b1 = (self.plru[set_idx] >> 1) & 1
        b2 = self.plru[set_idx] & 1
        if way == 0:
            b0 = 1; b1 = 1
        elif way == 1:
            b0 = 1; b1 = 0
        elif way == 2:
            b0 = 0; b2 = 1
        elif way == 3:
            b0 = 0; b2 = 0
        self.plru[set_idx] = (b0 << 2) | (b1 << 1) | b2

    def _select_victim(self, set_idx):
        lines = self.sets[set_idx]
        # 1. First look for an invalid, unpinned way
        for w in range(self.num_ways):
            if not lines[w].valid and not lines[w].pinned:
                return w
        # 2. PLRU tree selection
        b0 = (self.plru[set_idx] >> 2) & 1
        b1 = (self.plru[set_idx] >> 1) & 1
        b2 = self.plru[set_idx] & 1
        cand = (2 if b2 == 0 else 3) if b0 == 1 else (0 if b1 == 0 else 1)
        if not lines[cand].pinned:
            return cand
        # 3. If PLRU candidate is pinned, choose first unpinned way
        for w in range(self.num_ways):
            if not lines[w].pinned:
                return w
        raise RuntimeError(f"Set {set_idx} has all ways pinned! Invariant violated.")

    def lookup(self, addr, pin=False):
        set_idx, tag = self._get_set_tag(addr)
        lines = self.sets[set_idx]
        for w in range(self.num_ways):
            if lines[w].valid and lines[w].tag == tag:
                self.hit_cnt += 1
                self._update_plru(set_idx, w)
                pinned_cnt = sum(1 for line in lines if line.pinned)
                if pin and pinned_cnt < (self.num_ways - 1):
                    lines[w].pinned = True
                return True, w, lines[w].dirty, lines[w].verified, lines[w].pinned
        self.miss_cnt += 1
        return False, 0, False, False, False

    def fill(self, addr, verified=True, pin=False):
        set_idx, tag = self._get_set_tag(addr)
        lines = self.sets[set_idx]
        victim_w = self._select_victim(set_idx)
        victim = lines[victim_w]
        
        evict_valid = 0
        evict_dirty = 0
        evict_addr = 0
        if victim.valid:
            evict_valid = 1
            evict_dirty = 1 if victim.dirty else 0
            evict_addr = victim.addr
            self.evict_cnt += 1
            if victim.dirty:
                self.wb_cnt += 1

        pinned_cnt = sum(1 for line in lines if line.pinned)
        should_pin = pin and (pinned_cnt < (self.num_ways - 1))

        victim.valid = True
        victim.dirty = False
        victim.verified = verified
        victim.pinned = should_pin
        victim.tag = tag
        victim.addr = addr & ~63

        self._update_plru(set_idx, victim_w)
        return victim_w, evict_valid, evict_dirty, evict_addr

    def update(self, addr, dirty=True):
        set_idx, tag = self._get_set_tag(addr)
        lines = self.sets[set_idx]
        for w in range(self.num_ways):
            if lines[w].valid and lines[w].tag == tag:
                lines[w].dirty = dirty
                self._update_plru(set_idx, w)
                return True, w
        return False, 0

    def unpin(self, addr):
        set_idx, tag = self._get_set_tag(addr)
        lines = self.sets[set_idx]
        for w in range(self.num_ways):
            if lines[w].valid and lines[w].tag == tag:
                lines[w].pinned = False
                return True, w
        return False, 0


def generate_cache_test_vectors(num_ops=50000):
    print(f"Generating {num_ops} random metadata cache test vectors (seed=12345)...")
    random.seed(12345)
    cache = MetaCacheModel(num_sets=16, num_ways=4)
    
    vec_path = ROOT / "build" / "meta_cache_vectors.txt"
    # Addresses from a pool of 128 cache lines (oversubscribing the 64-line cache by 2x)
    addr_pool = [0x04000000 + i * 64 for i in range(128)]
    
    with open(vec_path, "w", encoding="utf-8") as f:
        f.write("# OP ADDR PIN DIRTY EXP_HIT EXP_WAY EXP_EVICT_VALID EXP_EVICT_DIRTY EXP_EVICT_ADDR\n")
        
        for _ in range(num_ops):
            r = random.random()
            addr = random.choice(addr_pool)
            
            if r < 0.45: # 45% Lookup
                pin = 1 if random.random() < 0.2 else 0
                hit, way, dirty, ver, is_pin = cache.lookup(addr, pin=bool(pin))
                f.write(f"0 {addr:016x} {pin} 0 {1 if hit else 0} {way} 0 0 0\n")
            elif r < 0.75: # 30% Fill
                pin = 1 if random.random() < 0.15 else 0
                way, ev_val, ev_dirty, ev_addr = cache.fill(addr, verified=True, pin=bool(pin))
                f.write(f"1 {addr:016x} {pin} 0 0 {way} {ev_val} {ev_dirty} {ev_addr:016x}\n")
            elif r < 0.90: # 15% Update (mark dirty)
                hit, way = cache.update(addr, dirty=True)
                f.write(f"2 {addr:016x} 0 1 {1 if hit else 0} {way} 0 0 0\n")
            else: # 10% Unpin
                hit, way = cache.unpin(addr)
                f.write(f"3 {addr:016x} 0 0 {1 if hit else 0} {way} 0 0 0\n")
                
    print(f"[PASS] Successfully wrote {num_ops} cache vectors to {vec_path}")
    print(f"Stats: hits={cache.hit_cnt} misses={cache.miss_cnt} evictions={cache.evict_cnt} writebacks={cache.wb_cnt}")


if __name__ == "__main__":
    main()
