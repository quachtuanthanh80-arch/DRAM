//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// Module Name: rst_sync
// Description: Multi-Stage Asynchronous Assert, Synchronous Deassert Reset Bridge.
//              Prevents metastability during reset deassertion across domains.
// Standard:    Synthesizable SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module rst_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n
);

    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_reg;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            sync_reg <= '0;
        end else begin
            sync_reg <= {sync_reg[STAGES-2:0], 1'b1};
        end
    end

    assign sync_rst_n = sync_reg[STAGES-1];

endmodule
