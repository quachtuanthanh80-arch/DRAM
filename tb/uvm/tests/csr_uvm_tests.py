# Bộ test pyuvm cho csr_env: kiểm chứng apb_csr_regs và TMR bằng $deposit
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import pyuvm
from pyuvm import ConfigDB

from tb.uvm.common.base_test import BaseQShieldTest
from tb.uvm.envs import CsrEnv
from tb.uvm.sequences import C_CSR_CornerSeq


@pyuvm.test()
class CsrCornerSuiteTest(BaseQShieldTest):
    """Bài test UVM trên apb_csr_regs với APB4 pprot/pstrb, SecLock và FaultAgent $deposit."""

    ENV_NAME = "csr"

    def build_phase(self):
        super().build_phase()
        self.env = CsrEnv("csr_env", self)

    def connect_phase(self):
        super().connect_phase()
        ConfigDB().set(None, "*", "CSR_APB_SEQR", self.env.apb_agent.seqr)
        ConfigDB().set(None, "*", "CSR_FI_SEQR", self.env.fault_agent.seqr)

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top
        cocotb.start_soon(Clock(dut.pclk, 4000, unit="ps").start())
        dut.presetn.value = 0
        await ClockCycles(dut.pclk, 8)
        dut.presetn.value = 1
        await ClockCycles(dut.pclk, 6)

        await C_CSR_CornerSeq("C_CSR_CornerSeq").start(None)
        await ClockCycles(dut.pclk, 15)
        self.drop_objection()

    def check_phase(self):
        super().check_phase()
