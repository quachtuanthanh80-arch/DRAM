# test_domain_bank_coloring.py
# Kiem tra cac che do anh xa GF(2) (Standard, Intel, AMD Zen) va cach ly Bank Coloring da mien Tenant

import cocotb
from cocotb.triggers import Timer
import random

@cocotb.test()
async def test_mapping_modes(dut):
    """Kiem tra cac che do anh xa dia chi kien truc: Standard, Intel va AMD Zen tren DDR5"""
    dut.cfg_bank_coloring_en.value = 0
    dut.cfg_is_ddr5.value = 1
    dut.i_req_id.value = 0

    # 1. Mode 0: Standard XOR Interleaving
    dut.cfg_mapping_mode.value = 0
    for _ in range(20):
        addr = random.randint(0, (1 << 32) - 1)
        dut.i_req_addr.value = addr
        await Timer(1, unit="ns")

        b6_8 = (addr >> 6) & 0x7
        b18_20 = (addr >> 18) & 0x7
        exp_bg = b6_8 ^ b18_20
        act_bg = int(dut.o_bg.value)
        assert act_bg == exp_bg, f"Standard mode mismatch: addr={hex(addr)}, exp={exp_bg}, act={act_bg}"

    # 2. Mode 1: Intel-style Hash
    dut.cfg_mapping_mode.value = 1
    for _ in range(20):
        addr = random.randint(0, (1 << 32) - 1)
        dut.i_req_addr.value = addr
        await Timer(1, unit="ns")

        b6_8 = (addr >> 6) & 0x7
        b13_15 = (addr >> 13) & 0x7
        b19_21 = (addr >> 19) & 0x7
        exp_bg = b6_8 ^ b13_15 ^ b19_21
        act_bg = int(dut.o_bg.value)
        assert act_bg == exp_bg, f"Intel mode mismatch: addr={hex(addr)}, exp={exp_bg}, act={act_bg}"

    # 3. Mode 2: AMD Zen-style GF(2) Matrix Hash
    dut.cfg_mapping_mode.value = 2
    for _ in range(20):
        addr = random.randint(0, (1 << 32) - 1)
        dut.i_req_addr.value = addr
        await Timer(1, unit="ns")

        bit0 = ((addr >> 6) & 1) ^ ((addr >> 12) & 1) ^ ((addr >> 18) & 1) ^ ((addr >> 22) & 1)
        bit1 = ((addr >> 7) & 1) ^ ((addr >> 13) & 1) ^ ((addr >> 19) & 1) ^ ((addr >> 23) & 1)
        bit2 = ((addr >> 8) & 1) ^ ((addr >> 14) & 1) ^ ((addr >> 20) & 1) ^ ((addr >> 24) & 1)
        exp_bg = (bit2 << 2) | (bit1 << 1) | bit0
        act_bg = int(dut.o_bg.value)
        assert act_bg == exp_bg, f"AMD Zen mode mismatch: addr={hex(addr)}, exp={exp_bg}, act={act_bg}"

@cocotb.test()
async def test_bank_coloring_isolation(dut):
    """Kiem tra cach ly Bank Coloring: 4 Tenant so huu 4 vung Bank Group doc lap tuyet doi"""
    dut.cfg_bank_coloring_en.value = 1
    dut.cfg_is_ddr5.value = 1
    dut.cfg_mapping_mode.value = 0

    tenant_bgs = {0: set(), 1: set(), 2: set(), 3: set()}

    for tenant in range(4):
        # AXI ID co 2 bit cao la tenant ID
        req_id = (tenant << 2) | random.randint(0, 3)
        dut.i_req_id.value = req_id

        for _ in range(50):
            addr = random.randint(0, (1 << 32) - 1)
            dut.i_req_addr.value = addr
            await Timer(1, unit="ns")

            bg = int(dut.o_bg.value)
            tenant_bgs[tenant].add(bg)

    # Kiem tra phan bo Bank Group theo thiet ke
    assert tenant_bgs[0].issubset({0, 1}), f"Tenant 0 leaked outside BG 0,1: {tenant_bgs[0]}"
    assert tenant_bgs[1].issubset({2, 3}), f"Tenant 1 leaked outside BG 2,3: {tenant_bgs[1]}"
    assert tenant_bgs[2].issubset({4, 5}), f"Tenant 2 leaked outside BG 4,5: {tenant_bgs[2]}"
    assert tenant_bgs[3].issubset({6, 7}), f"Tenant 3 leaked outside BG 6,7: {tenant_bgs[3]}"

    # Kiem tra giao giua cac tap Bank Group phai la tap rong (Zero Collision)
    all_tenants = [tenant_bgs[0], tenant_bgs[1], tenant_bgs[2], tenant_bgs[3]]
    for i in range(4):
        for j in range(i + 1, 4):
            overlap = all_tenants[i].intersection(all_tenants[j])
            assert len(overlap) == 0, f"Cross-tenant bank group collision between Tenant {i} and {j}: {overlap}"
