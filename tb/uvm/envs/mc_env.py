# Môi trường pyuvm chính cho Q-Shield Memory Controller (AXI + DFI/DRAM + Fault + Scoreboard)
from pyuvm import uvm_env

from tb.uvm.agents import AxiAgent, DfiDramAgent, FaultAgent
from .mc_scoreboard import McScoreboard


class McEnv(uvm_env):
    """Môi trường mc_env kết nối AxiAgent, DfiDramAgent, FaultAgent vào McScoreboard."""

    def build_phase(self):
        super().build_phase()
        self.axi_agent = AxiAgent("axi_agent", self)
        self.dfi_agent = DfiDramAgent("dfi_agent", self)
        self.fault_agent = FaultAgent("fault_agent", self)
        self.scoreboard = McScoreboard("scoreboard", self)

    def connect_phase(self):
        super().connect_phase()
        self.axi_agent.ap.connect(self.scoreboard.axi_fifo.analysis_export)
        self.dfi_agent.ap.connect(self.scoreboard.dfi_fifo.analysis_export)
        self.fault_agent.ap.connect(self.scoreboard.fault_fifo.analysis_export)
