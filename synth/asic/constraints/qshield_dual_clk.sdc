#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# File:        qshield_dual_clk.sdc
# Description: Synopsys Design Constraints (SDC) for Dual-Clock ASIC Target
#              - Clock 1 (AXI Bus Host Domain): 250 MHz (T = 4.00 ns)
#              - Clock 2 (DDR/DFI Memory Domain): 400 MHz (T = 2.50 ns)
# Technology:  Nangate 45nm / TSMC 28nm / ASAP7 Compatible
# Standards:   AMBA AXI4 (IHI 0022E), JEDEC DDR5 (JESD79-5), DFI 5.0
#=============================================================================

#-----------------------------------------------------------------------------
# 1. Operating Conditions & Environmental Units
#-----------------------------------------------------------------------------
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA

#-----------------------------------------------------------------------------
# 2. Clock Definitions
#-----------------------------------------------------------------------------
# Host AXI4 Bus Clock: 250 MHz -> Period = 4.00 ns, 50% Duty Cycle
create_clock -name clk_axi \
             -period 4.00 \
             -waveform {0.00 2.00} \
             [get_ports clk_axi]

# Backend Memory / DFI 5.0 PHY Clock: 400 MHz -> Period = 2.50 ns, 50% Duty Cycle
create_clock -name clk_ddr \
             -period 2.50 \
             -waveform {0.00 1.25} \
             [get_ports clk_ddr]

#-----------------------------------------------------------------------------
# 3. Clock Uncertainty, Jitter & Transition Slew
#-----------------------------------------------------------------------------
# Jitter & Margin: 150 ps for setup, 50 ps for hold
set_clock_uncertainty -setup 0.150 [get_clocks clk_axi]
set_clock_uncertainty -hold  0.050 [get_clocks clk_axi]

set_clock_uncertainty -setup 0.100 [get_clocks clk_ddr]
set_clock_uncertainty -hold  0.040 [get_clocks clk_ddr]

# Clock transition / slew rate (pre-CTS estimate)
set_clock_transition 0.080 [all_clocks]

#-----------------------------------------------------------------------------
# 4. Asynchronous Clock Domain Crossing (CDC) Groups
#-----------------------------------------------------------------------------
# CRITICAL: clk_axi and clk_ddr are completely asynchronous.
# All crossings are synchronized via Gray-code pointer Async FIFOs (async_fifo_cdc.sv).
# Declare asynchronous clock groups to prevent false-path timing analysis across domains.
set_clock_groups -asynchronous \
                 -group [get_clocks clk_axi] \
                 -group [get_clocks clk_ddr]

#-----------------------------------------------------------------------------
# 5. Input / Output Delays for AXI4 Host Interface (clk_axi domain)
#-----------------------------------------------------------------------------
# Assume 30% of clock period budget for external board/interconnect flight time
set AXI_IN_MAX  1.200
set AXI_IN_MIN  0.200
set AXI_OUT_MAX 1.000
set AXI_OUT_MIN 0.150

# AXI4 Write Address & Data Inputs
set_input_delay -clock clk_axi -max $AXI_IN_MAX [get_ports {s_axi_aw* s_axi_w*}]
set_input_delay -clock clk_axi -min $AXI_IN_MIN [get_ports {s_axi_aw* s_axi_w*}]

# AXI4 Read Address Inputs
set_input_delay -clock clk_axi -max $AXI_IN_MAX [get_ports s_axi_ar*]
set_input_delay -clock clk_axi -min $AXI_IN_MIN [get_ports s_axi_ar*]

# AXI4 Handshake Ready/Valid Cross-Signals
set_input_delay -clock clk_axi -max $AXI_IN_MAX [get_ports {s_axi_bready s_axi_rready}]
set_input_delay -clock clk_axi -min $AXI_IN_MIN [get_ports {s_axi_bready s_axi_rready}]

# AXI4 Outputs (Responses, Data, Ready Handshakes)
set_output_delay -clock clk_axi -max $AXI_OUT_MAX [get_ports {s_axi_awready s_axi_wready s_axi_arready}]
set_output_delay -clock clk_axi -min $AXI_OUT_MIN [get_ports {s_axi_awready s_axi_wready s_axi_arready}]
set_output_delay -clock clk_axi -max $AXI_OUT_MAX [get_ports {s_axi_b* s_axi_r*}]
set_output_delay -clock clk_axi -min $AXI_OUT_MIN [get_ports {s_axi_b* s_axi_r*}]

#-----------------------------------------------------------------------------
# 6. Input / Output Delays for DFI 5.0 Memory Interface (clk_ddr domain)
#-----------------------------------------------------------------------------
# Tight timing budget for high-speed DFI PHY communication (400 MHz = 2.5 ns)
set DFI_OUT_MAX 0.750
set DFI_OUT_MIN 0.100

# DFI Command, Bank, Bank-Group, Row, Column Outputs
set_output_delay -clock clk_ddr -max $DFI_OUT_MAX [get_ports {dfi_cmd* dfi_bg* dfi_bank* dfi_row* dfi_col*}]
set_output_delay -clock clk_ddr -min $DFI_OUT_MIN [get_ports {dfi_cmd* dfi_bg* dfi_bank* dfi_row* dfi_col*}]

#-----------------------------------------------------------------------------
# 7. Static Configuration & Telemetry Ports (False Paths)
#-----------------------------------------------------------------------------
# Configuration signals are quasi-static (programmed during boot/init)
set_false_path -from [get_ports {cfg_is_ddr5 cfg_dual_hash_en cfg_rh_threshold* cfg_window_size*}]
set_false_path -to   [get_ports {o_throttled_events* o_ecc_single_err_cnt* o_ecc_double_err_cnt*}]

# Asynchronous Reset Pins are synchronized internally via rst_sync
set_false_path -from [get_ports {aresetn_axi aresetn_ddr}]

#-----------------------------------------------------------------------------
# 8. Drive & Load Modeling (Nangate 45nm standard library reference)
#-----------------------------------------------------------------------------
# Driving cell for inputs: Inverter drive equivalent (INV_X4)
set_driving_cell -lib_cell INV_X4 [all_inputs -no_clocks]

# Output load: 0.03 pF (30 fF standard cell interconnect/pad model)
set_load 0.030 [all_outputs]

# Set maximum transition to enforce steep edge rates
set_max_transition 0.250 [current_design]
set_max_fanout 16 [current_design]
