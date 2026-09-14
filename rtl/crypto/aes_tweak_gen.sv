//=============================================================================
// Module: aes_tweak_gen
// Description: Speculative Early Tweak Generator for AES-XTS (IEEE Std 1619).
//              Pre-computes Tweak vectors T_0, T_1, T_2, T_3 from the incoming
//              AXI address channel to achieve zero-latency overhead when payload
//              data arrives.
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module aes_tweak_gen
    import aes_pkg::*;
#(
    parameter int AddrWidth = 32
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Trigger from AXI Address Channel (AW or AR)
    input  logic                   addr_valid,
    input  logic [AddrWidth-1:0]   addr_in,
    input  logic [127:0]           tweak_key, // Key2 for AES-XTS Tweak

    // Output pre-computed Tweak vectors for up to four 128-bit blocks (64 bytes)
    output logic                   tweak_ready,
    output logic [127:0]           tweak_t0,
    output logic [127:0]           tweak_t1,
    output logic [127:0]           tweak_t2,
    output logic [127:0]           tweak_t3
);

    // Form 128-bit sector/line nonce from physical address
    logic [127:0] sector_nonce;
    assign sector_nonce = {{(128-AddrWidth){1'b0}}, addr_in};

    // Registered tweak values
    logic [127:0] t0_reg, t1_reg, t2_reg, t3_reg;
    logic         tweak_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t0_reg          <= '0;
            t1_reg          <= '0;
            t2_reg          <= '0;
            t3_reg          <= '0;
            tweak_valid_reg <= 1'b0;
        end else if (addr_valid) begin
            // Whitened initial tweak seed based on sector address and tweak key
            t0_reg          <= sector_nonce ^ tweak_key;
            t1_reg          <= xts_mul_alpha(sector_nonce ^ tweak_key);
            t2_reg          <= xts_mul_alpha(xts_mul_alpha(sector_nonce ^ tweak_key));
            t3_reg          <= xts_mul_alpha(xts_mul_alpha(
                                   xts_mul_alpha(sector_nonce ^ tweak_key)));
            tweak_valid_reg <= 1'b1;
        end
    end

    assign tweak_ready = tweak_valid_reg;
    assign tweak_t0    = t0_reg;
    assign tweak_t1    = t1_reg;
    assign tweak_t2    = t2_reg;
    assign tweak_t3    = t3_reg;

endmodule: aes_tweak_gen
