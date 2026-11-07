// File:        rst_sync.sv
// Chức năng:   Cầu đồng bộ reset xác lập bất đồng bộ và giải phóng đồng bộ (Asynch Assert, Synch Deassert).
`timescale 1ns / 1ps

module rst_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n
);

`ifndef SYNTHESIS
    initial begin
        if (STAGES < 2)
            $fatal(1, "SA-E04: rst_sync STAGES=%0d must be >= 2 for metastability synchronization", STAGES);
    end
`endif

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
