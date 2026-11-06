// File:        tb_e2e_scoreboard_400.sv
// Chức năng:   Wrapper 400 MHz (TB_TCK_PS = 2500) cho tb_e2e_scoreboard theo T-RT04 (verification_plan §5.3).
`timescale 1ns / 1ps

module tb_e2e_scoreboard_400;
    tb_e2e_scoreboard #(.TB_TCK_PS(2500)) u_tb();
endmodule

