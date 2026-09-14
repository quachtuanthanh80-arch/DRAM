# ==============================================================================
# SECURE DDR5 CONTROLLER TIMING CONSTRAINTS
# Target: AMD Zynq UltraScale+ (xczu7ev-ffvc1156-2-e)
# ==============================================================================

# Clock 1: AXI4 Bus Clock @ 250 MHz (Period = 4.000 ns)
create_clock -period 4.000 -name clk_axi [get_ports clk_axi]

# Clock 2: DDR5 Controller / DFI Clock @ 400 MHz (Period = 2.500 ns)
create_clock -period 2.500 -name clk_ddr [get_ports clk_ddr]

# Clock Domain Crossing (CDC) Grouping:
# asynchronous FIFOs handle data synchronisation via Gray-code pointers and 2-FF sync
set_clock_groups -asynchronous -group [get_clocks clk_axi] -group [get_clocks clk_ddr]

# Input / Output delay modeling for out-of-context synthesis
set_input_delay -clock clk_axi -max 0.800 [get_ports {s_axi_* s_apb_*}]
set_input_delay -clock clk_axi -min 0.200 [get_ports {s_axi_* s_apb_*}]

set_output_delay -clock clk_axi -max 0.800 [get_ports {s_axi_* s_apb_*}]
set_output_delay -clock clk_axi -min 0.200 [get_ports {s_axi_* s_apb_*}]

set_input_delay -clock clk_ddr -max 0.500 [get_ports {dfi_*_rddata* dfi_*_rddata_valid}]
set_input_delay -clock clk_ddr -min 0.100 [get_ports {dfi_*_rddata* dfi_*_rddata_valid}]

set_output_delay -clock clk_ddr -max 0.500 [get_ports {dfi_*_address* dfi_*_bank* dfi_*_cmd* dfi_*_wrdata* dfi_*_wrdata_en}]
set_output_delay -clock clk_ddr -min 0.100 [get_ports {dfi_*_address* dfi_*_bank* dfi_*_cmd* dfi_*_wrdata* dfi_*_wrdata_en}]
