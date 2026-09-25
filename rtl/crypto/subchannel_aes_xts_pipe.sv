//=============================================================================
// File:        subchannel_aes_xts_pipe.sv
// Chức năng:   Đường ống tăng tốc mật mã AES-256-XTS 14 tầng bảo vệ dữ liệu hai kênh con DDR5.
//=============================================================================
`timescale 1ns / 1ps

module subchannel_aes_xts_pipe
    import aes_pkg::*;
#(
    parameter int NumRounds  = 14, // 14 for AES-256, 10 for AES-128
    parameter int DataWidth  = 128,
    parameter int TweakWidth = 128,
    parameter int MetaWidth  = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Global Mode Control
    input  logic                   enc_enable, // 1: AES-XTS encryption, 0: bypass
    output logic                   pipe_busy,  // High when pipelines hold data

    // Pre-expanded Round Keys (Index 0 through NumRounds)
    input  logic [127:0]           round_keys [NumRounds + 1],

    //-------------------------------------------------------------------------
    // Subchannel A (Lane A) Interface
    //-------------------------------------------------------------------------
    input  logic                   lane_a_valid_in,
    output logic                   lane_a_ready_in,
    input  logic [DataWidth-1:0]   lane_a_data_in,
    input  logic [TweakWidth-1:0]  lane_a_tweak_in,
    input  logic [MetaWidth-1:0]   lane_a_meta_in,

    output logic                   lane_a_valid_out,
    input  logic                   lane_a_ready_out,
    output logic [DataWidth-1:0]   lane_a_data_out,
    output logic [MetaWidth-1:0]   lane_a_meta_out,

    //-------------------------------------------------------------------------
    // Subchannel B (Lane B) Interface
    //-------------------------------------------------------------------------
    input  logic                   lane_b_valid_in,
    output logic                   lane_b_ready_in,
    input  logic [DataWidth-1:0]   lane_b_data_in,
    input  logic [TweakWidth-1:0]  lane_b_tweak_in,
    input  logic [MetaWidth-1:0]   lane_b_meta_in,

    output logic                   lane_b_valid_out,
    input  logic                   lane_b_ready_out,
    output logic [DataWidth-1:0]   lane_b_data_out,
    output logic [MetaWidth-1:0]   lane_b_meta_out
);

    // Busy indication across either lane
    logic lane_a_busy;
    logic lane_b_busy;
    assign pipe_busy = lane_a_busy | lane_b_busy;

    //-------------------------------------------------------------------------
    // Lane A Instance (Subchannel A)
    //-------------------------------------------------------------------------
    aes_xts_lane #(
        .NumRounds (NumRounds),
        .DataWidth (DataWidth),
        .TweakWidth(TweakWidth),
        .MetaWidth (MetaWidth)
    ) u_lane_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .enc_enable (enc_enable),
        .lane_busy  (lane_a_busy),
        .round_keys (round_keys),

        .valid_in   (lane_a_valid_in),
        .ready_in   (lane_a_ready_in),
        .data_in    (lane_a_data_in),
        .tweak_in   (lane_a_tweak_in),
        .meta_in    (lane_a_meta_in),

        .valid_out  (lane_a_valid_out),
        .ready_out  (lane_a_ready_out),
        .data_out   (lane_a_data_out),
        .meta_out   (lane_a_meta_out)
    );

    //-------------------------------------------------------------------------
    // Lane B Instance (Subchannel B)
    //-------------------------------------------------------------------------
    aes_xts_lane #(
        .NumRounds (NumRounds),
        .DataWidth (DataWidth),
        .TweakWidth(TweakWidth),
        .MetaWidth (MetaWidth)
    ) u_lane_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .enc_enable (enc_enable),
        .lane_busy  (lane_b_busy),
        .round_keys (round_keys),

        .valid_in   (lane_b_valid_in),
        .ready_in   (lane_b_ready_in),
        .data_in    (lane_b_data_in),
        .tweak_in   (lane_b_tweak_in),
        .meta_in    (lane_b_meta_in),

        .valid_out  (lane_b_valid_out),
        .ready_out  (lane_b_ready_out),
        .data_out   (lane_b_data_out),
        .meta_out   (lane_b_meta_out)
    );

endmodule: subchannel_aes_xts_pipe


//=============================================================================
// Helper Module: aes_xts_lane
// Description:   Single-Lane 14-Stage Fully Pipelined AES-XTS Data Path.
//=============================================================================

module aes_xts_lane
    import aes_pkg::*;
#(
    parameter int NumRounds  = 14,
    parameter int DataWidth  = 128,
    parameter int TweakWidth = 128,
    parameter int MetaWidth  = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   enc_enable,
    output logic                   lane_busy,

    input  logic [127:0]           round_keys [NumRounds + 1],

    input  logic                   valid_in,
    output logic                   ready_in,
    input  logic [DataWidth-1:0]   data_in,
    input  logic [TweakWidth-1:0]  tweak_in,
    input  logic [MetaWidth-1:0]   meta_in,

    output logic                   valid_out,
    input  logic                   ready_out,
    output logic [DataWidth-1:0]   data_out,
    output logic [MetaWidth-1:0]   meta_out
);

    // Initial Whitening (Pre-XOR with Tweak) + Round 0 AddRoundKey
    logic [127:0] pre_whitened;
    logic [127:0] initial_state;

    assign pre_whitened  = enc_enable ? (data_in ^ tweak_in) : data_in;
    assign initial_state = enc_enable ? (pre_whitened ^ round_keys[0]) : pre_whitened;

    // Intermediate pipeline wires
    logic [127:0] stage_state [NumRounds + 1];
    logic         stage_valid [NumRounds + 1];
    logic         stage_ready [NumRounds + 1];

    // Pipeline delay registers for Tweak, Data (bypass), Meta, and Mode
    logic [TweakWidth-1:0] tweak_pipe [NumRounds + 1];
    logic [DataWidth-1:0]  data_pipe  [NumRounds + 1];
    logic [MetaWidth-1:0]  meta_pipe  [NumRounds + 1];
    logic                  bypass_pipe[NumRounds + 1];

    assign stage_state[0] = initial_state;
    assign stage_valid[0] = valid_in;
    assign ready_in       = stage_ready[0];

    // Instantiate Pipelined AES Rounds 1 to NumRounds
    genvar r;
    generate
        for (r = 1; r <= NumRounds; r++) begin : gen_rounds
            localparam bit IsFinal = (r == NumRounds);

            aes_round_pipe u_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (stage_valid[r-1]),
                .in_ready      (stage_ready[r-1]),
                .is_final_round(IsFinal),
                .state_in      (stage_state[r-1]),
                .round_key     (round_keys[r]),
                .out_valid     (stage_valid[r]),
                .out_ready     (stage_ready[r]),
                .state_out     (stage_state[r])
            );

            // Delay register for sideband data (Tweak, Plaintext Data, Meta)
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tweak_pipe[r]  <= '0;
                    data_pipe[r]   <= '0;
                    meta_pipe[r]   <= '0;
                    bypass_pipe[r] <= 1'b0;
                end else if (stage_ready[r-1]) begin
                    if (r == 1) begin
                        tweak_pipe[r]  <= tweak_in;
                        data_pipe[r]   <= data_in;
                        meta_pipe[r]   <= meta_in;
                        bypass_pipe[r] <= ~enc_enable;
                    end else begin
                        tweak_pipe[r]  <= tweak_pipe[r-1];
                        data_pipe[r]   <= data_pipe[r-1];
                        meta_pipe[r]   <= meta_pipe[r-1];
                        bypass_pipe[r] <= bypass_pipe[r-1];
                    end
                end
            end
        end
    endgenerate

    // Output stage ready connection
    assign stage_ready[NumRounds] = ready_out;

    // Post-whitening:
    // If bypass: return original data_pipe.
    // If encrypt: stage_state XOR delayed tweak.
    logic [127:0] final_cipher;
    assign final_cipher = bypass_pipe[NumRounds] ?
                          data_pipe[NumRounds] :
                          (stage_state[NumRounds] ^ tweak_pipe[NumRounds]);

    assign valid_out = stage_valid[NumRounds];
    assign data_out  = final_cipher;
    assign meta_out  = meta_pipe[NumRounds];

    // Compute lane busy status
    logic any_valid;
    always_comb begin
        any_valid = 1'b0;
        for (int i = 0; i <= NumRounds; i++) begin
            any_valid |= stage_valid[i];
        end
    end
    assign lane_busy = any_valid;

endmodule: aes_xts_lane
