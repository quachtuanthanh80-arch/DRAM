# Môi trường pyuvm cho kiểm chứng APB CSR & TMR (ApbAgent + FaultAgent + CsrScoreboard)
from pyuvm import uvm_env

from tb.uvm.agents import ApbAgent, FaultAgent
from .csr_scoreboard import CsrScoreboard


class CsrEnv(uvm_env):
    """Môi trường csr_env kết nối ApbAgent và FaultAgent vào CsrScoreboard."""

    def build_phase(self):
        super().build_phase()
        self.apb_agent = ApbAgent("apb_agent", self)
        self.fault_agent = FaultAgent("fault_agent", self)
        self.scoreboard = CsrScoreboard("scoreboard", self)

    def connect_phase(self):
        super().connect_phase()
        self.apb_agent.ap.connect(self.scoreboard.apb_fifo.analysis_export)
        self.fault_agent.ap.connect(self.scoreboard.fault_fifo.analysis_export)
