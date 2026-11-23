# Q-Shield ASIC PPA Report — Status: Withdrawn / Pending Measurement

**Design Top:** `axi_ddr5_mc_top` (canonical core) and `axi_ddr5_mc_secure_top` (secure wrapper)  
**Status:** **Withdrawn (2026-11). No ASIC synthesis run in this repository produced the previously listed tables.**

---

## Reason for Withdrawal

1. **No ASIC Synthesis Logs**: The earlier multi-PDK tables (Nangate 45nm, SkyWater 130nm, IHP SG13G2 130nm, GF180MCU 180nm) and gate-equivalent / frequency / power figures were not backed by any synthesis or place-and-route report in this repository and were withdrawn.
2. **Unverified Literature Comparison Rows**: The earlier Section 3 Nangate 45nm SOTA comparison table (`Standard Insecure MC`, `BlockHammer`, `CoMeT`, `MORDOR`) was removed because its gate-equivalent, frequency, and dynamic-power values did not exist in the cited source PDFs, and two citations carried incorrect author/venue attributions (CoMeT is Bostancı et al., HPCA 2024; MORDOR is Makeenkova et al., 2026).

---

## Measured Hardware Implementation Results Available Today

Post-route FPGA implementation reports on Xilinx `xczu7ev-ffvc1156-2-e` (Vivado 2026.1, post-T86/T88 RTL) are archived in:
- [`reports/paper/fpga/t89/fpga_ppa_summary.md`](../../../reports/paper/fpga/t89/fpga_ppa_summary.md) (`axi_ddr5_mc_top` @ `4.200 ns` / `238.10 MHz`, `WNS +0.076 ns`; `axi_ddr5_mc_secure_top` @ `4.150 ns` / `240.96 MHz`, `WNS +0.018 ns`, `165,776` LUTs, `110,405` FFs, `7.5` BRAM, `4.301 W` vectorless)
- [`reports/paper/fpga/t92/fpga_ppa_summary.md`](../../../reports/paper/fpga/t92/fpga_ppa_summary.md) (`axi_ddr5_mc_top` fine sweep: `3.900 ns` / `256.41 MHz` confirmed upper bound not yet swept below `3.900 ns`, `WNS +0.014 ns`, `62,699` LUTs, `44,485` FFs, `1.645 W` vectorless)

ASIC area, power, and timing figures will only be added after an OpenROAD Nangate45 synthesis and place-and-route run produces verifiable logs in `reports/paper/asic/`.
