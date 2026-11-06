// File:        tb_axi_ddr5_mc_top_400.sv
// Chức năng:   Wrapper 400 MHz (TB_TCK_PS = 2500) cho tb_axi_ddr5_mc_top theo T-RT04 (verification_plan §5.3).
`timescale 1ns / 1ps

module tb_axi_ddr5_mc_top_400;
    tb_axi_ddr5_mc_top #(.TB_TCK_PS(2500)) u_tb();
endmodule

