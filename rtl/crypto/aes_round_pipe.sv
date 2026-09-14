//=============================================================================
// Module: aes_round_pipe
// Description: Fully Pipelined AES Round Slice (Single Stage Register Slice).
//              Integrates SubBytes (16x S-Boxes in parallel), ShiftRows,
//              MixColumns, and AddRoundKey into a single clock cycle pipeline.
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module aes_round_pipe
    import aes_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // Pipeline control
    input  logic         in_valid,
    output logic         in_ready,
    input  logic         is_final_round,

    // Data and Key inputs
    input  logic [127:0] state_in,
    input  logic [127:0] round_key,

    // Output stage
    output logic         out_valid,
    input  logic         out_ready,
    output logic [127:0] state_out
);

    // 1. SubBytes Transformation (16 S-Boxes in parallel)
    logic [127:0] subbytes_raw;
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_sbox
            aes_sbox u_sbox (
                .in_byte (state_in[i*8 +: 8]),
                .out_byte(subbytes_raw[i*8 +: 8])
            );
        end
    endgenerate

    // 2. ShiftRows Transformation
    aes_block_t shifted_state;
    assign shifted_state = shift_rows(aes_block_t'(subbytes_raw));

    // 3. MixColumns Transformation (4 Columns in parallel)
    logic [127:0] mixed_raw;
    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : gen_mixcol
            assign mixed_raw[c*32 +: 32] = is_final_round ?
                shifted_state.matrix[c] :
                mix_single_column(shifted_state.matrix[c]);
        end
    endgenerate

    // 4. AddRoundKey Transformation
    logic [127:0] round_result;
    assign round_result = mixed_raw ^ round_key;

    // 5. Pipeline Register Stage
    logic [127:0] state_reg;
    logic         valid_reg;

    assign in_ready = out_ready || !valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= '0;
            valid_reg <= 1'b0;
        end else if (in_ready) begin
            valid_reg <= in_valid;
            if (in_valid) begin
                state_reg <= round_result;
            end
        end
    end

    assign out_valid = valid_reg;
    assign state_out = state_reg;

endmodule: aes_round_pipe
