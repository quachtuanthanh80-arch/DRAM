# Bộ test pyuvm cho mc_env: chạy mọi corner sequence + constrained-random và ghi báo cáo JSON
import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
import pyuvm
from pyuvm import ConfigDB

from tb.uvm.common.base_test import BaseQShieldTest
from tb.uvm.envs import McEnv
from tb.uvm.sequences import (
    C_H2_BgBankSweepSeq,
    C_H3_RandomRreadySeq,
    C_M2_PartialWstrbRmwSeq,
    C_M3_Boundary4kbSeq,
    C_L2_RawHazardSeq,
    C_SEC10_SkewedAwWSeq,
    C_SEC10_ResetMidBurstSeq,
    C_RT05_FaultInjectSeuSeq,
    McRandomStressSeq,
)


@pyuvm.test()
class McCornerSuiteTest(BaseQShieldTest):
    """Bài test UVM chính trên axi_ddr5_mc_top với đầy đủ các góc biên, FaultAgent và mô hình vàng."""

    ENV_NAME = "mc"

    def build_phase(self):
        super().build_phase()
        self.env = McEnv("mc_env", self)

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top
        cocotb.start_soon(Clock(dut.clk_axi, 4000, unit="ps").start())
        dut.aresetn_axi.value = 0
        await ClockCycles(dut.clk_axi, 10)
        dut.aresetn_axi.value = 1
        await ClockCycles(dut.clk_axi, 10)

        axi_seqr = self.env.axi_agent.seqr
        fault_seqr = self.env.fault_agent.seqr

        # 1. Cac kich ban corner ID doc lap
        for seq_cls in (
            C_H2_BgBankSweepSeq,
            C_H3_RandomRreadySeq,
            C_M2_PartialWstrbRmwSeq,
            C_M3_Boundary4kbSeq,
            C_L2_RawHazardSeq,
            C_SEC10_SkewedAwWSeq,
            C_SEC10_ResetMidBurstSeq,
        ):
            await seq_cls(seq_cls.__name__).start(axi_seqr)

        # 2. Chuoi ngau nhien co rang buoc theo UVM_SEED
        await McRandomStressSeq("mc_rand_stress", num_pairs=5).start(axi_seqr)

        # 3. Cho toan bo lenh DFI & DRAM xa het truoc khi bom loi SEU cuoi phien
        await ClockCycles(dut.clk_axi, 80)
        await C_RT05_FaultInjectSeuSeq("C_RT05_FaultInjectSeuSeq").start(fault_seqr)
        await ClockCycles(dut.clk_axi, 20)
        self.drop_objection()

    def check_phase(self):
        super().check_phase()
