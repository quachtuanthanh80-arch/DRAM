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

    // Operand Isolation (Vo Minh Huan et al., HCMUTE):
    // Clamps inputs to zero when transaction is not valid to prevent useless dynamic switching
    wire [DataWidth-1:0]  iso_data_in  = valid_in ? data_in  : '0;
    wire [TweakWidth-1:0] iso_tweak_in = valid_in ? tweak_in : '0;

    assign pre_whitened  = enc_enable ? (iso_data_in ^ iso_tweak_in) : iso_data_in;
    assign initial_state = enc_enable ? (pre_whitened ^ round_keys[0]) : pre_whitened;

    localparam int MidRound = NumRounds / 2;
    localparam int S0PackW  = 128 + TweakWidth + DataWidth + MetaWidth + 1;
    localparam int MidPackW = 128 + TweakWidth + DataWidth + MetaWidth + 1;
    localparam int OutPackW = DataWidth + MetaWidth;

    // Intermediate pipeline wires
    logic [127:0] stage_state [NumRounds + 1];
    logic         stage_valid [NumRounds + 1];
    logic         stage_ready [NumRounds + 1];

    // Pipeline delay registers for Tweak, Data (bypass), Meta, and Mode
    logic [TweakWidth-1:0] tweak_pipe [NumRounds + 1];
    logic [DataWidth-1:0]  data_pipe  [NumRounds + 1];
    logic [MetaWidth-1:0]  meta_pipe  [NumRounds + 1];
    logic                  bypass_pipe[NumRounds + 1];

    logic [MetaWidth-1:0]  s0_meta, mid_meta;
    logic                  s0_bypass, mid_bypass;
    logic [DataWidth-1:0]  s0_data, mid_data;
    logic [TweakWidth-1:0] s0_tweak, mid_tweak;
    logic                  s0_skid_busy, mid_skid_busy, out_skid_busy;

    logic [127:0] r_mid_state;
    logic         r_mid_valid;
    logic         r_mid_ready;

    // Tầng 0 dùng đệm trượt 2 mức để ready_in xuất trực tiếp từ FF, ngắt chuỗi ready tổ hợp 14 vòng AES
    aes_xts_skid_stage #(
        .Width (S0PackW)
    ) u_s0_skid (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (valid_in),
        .s_ready (ready_in),
        .s_data  ({meta_in, ~enc_enable, iso_data_in, iso_tweak_in, initial_state}),
        .m_valid (stage_valid[0]),
        .m_ready (stage_ready[0]),
        .m_data  ({s0_meta, s0_bypass, s0_data, s0_tweak, stage_state[0]}),
        .busy    (s0_skid_busy)
    );

    // Instantiate Pipelined AES Rounds 1 to NumRounds
    genvar r;
    generate
        for (r = 1; r <= NumRounds; r++) begin : gen_rounds
            localparam bit IsFinal = (r == NumRounds);
            logic [127:0] round_out_st;
            logic         round_out_v;
            logic         round_out_r;

            aes_round_pipe u_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (stage_valid[r-1]),
                .in_ready      (stage_ready[r-1]),
                .is_final_round(IsFinal),
                .state_in      (stage_state[r-1]),
                .round_key     (round_keys[r]),
                .out_valid     (round_out_v),
                .out_ready     (round_out_r),
                .state_out     (round_out_st)
            );

            if (r == MidRound) begin : gen_mid_tap
                assign r_mid_state = round_out_st;
                assign r_mid_valid = round_out_v;
                assign round_out_r = r_mid_ready;
            end else begin : gen_direct_stage
                assign stage_state[r] = round_out_st;
                assign stage_valid[r] = round_out_v;
                assign round_out_r    = stage_ready[r];
            end

            // Delay register for sideband data (Tweak, Plaintext Data, Meta)
            // Fine-Grain Clock Gating / Enable: only toggles when stage contains valid data
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tweak_pipe[r]  <= '0;
                    data_pipe[r]   <= '0;
                    meta_pipe[r]   <= '0;
                    bypass_pipe[r] <= 1'b0;
                end else if (stage_ready[r-1] && stage_valid[r-1]) begin
                    if (r == 1) begin
                        tweak_pipe[r]  <= s0_tweak;
                        data_pipe[r]   <= s0_data;
                        meta_pipe[r]   <= s0_meta;
                        bypass_pipe[r] <= s0_bypass;
                    end else if (r == MidRound + 1) begin
                        tweak_pipe[r]  <= mid_tweak;
                        data_pipe[r]   <= mid_data;
                        meta_pipe[r]   <= mid_meta;
                        bypass_pipe[r] <= mid_bypass;
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

    // Cắt đôi đường lan truyền ready giữa nửa đầu và nửa sau của 14 vòng AES
    aes_xts_skid_stage #(
        .Width (MidPackW)
    ) u_mid_skid (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (r_mid_valid),
        .s_ready (r_mid_ready),
        .s_data  ({meta_pipe[MidRound], bypass_pipe[MidRound], data_pipe[MidRound], tweak_pipe[MidRound], r_mid_state}),
        .m_valid (stage_valid[MidRound]),
        .m_ready (stage_ready[MidRound]),
        .m_data  ({mid_meta, mid_bypass, mid_data, mid_tweak, stage_state[MidRound]}),
        .busy    (mid_skid_busy)
    );

    // Post-whitening:
    // If bypass: return original data_pipe.
    // If encrypt: stage_state XOR delayed tweak.
    logic [127:0] final_cipher;
    assign final_cipher = bypass_pipe[NumRounds] ?
                          data_pipe[NumRounds] :
                          (stage_state[NumRounds] ^ tweak_pipe[NumRounds]);

    // Đệm trượt đầu ra cách ly ready_out (từ cầu AXI) khỏi đường ready trong pipeline mã hóa
    aes_xts_skid_stage #(
        .Width (OutPackW)
    ) u_out_skid (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (stage_valid[NumRounds]),
        .s_ready (stage_ready[NumRounds]),
        .s_data  ({meta_pipe[NumRounds], final_cipher}),
        .m_valid (valid_out),
        .m_ready (ready_out),
        .m_data  ({meta_out, data_out}),
        .busy    (out_skid_busy)
    );

    // Compute lane busy status (bao gồm cả thanh ghi đệm trong các tầng skid)
    logic any_valid;
    always_comb begin
        any_valid = r_mid_valid | s0_skid_busy | mid_skid_busy | out_skid_busy;
        for (int i = 0; i <= NumRounds; i++) begin
            any_valid |= stage_valid[i];
        end
    end
    assign lane_busy = any_valid;

endmodule: aes_xts_lane


//-----------------------------------------------------------------------------
// Module: aes_xts_skid_stage
// Cơ chế: Bộ đệm trượt 2 tầng ngắt chuỗi lan truyền tổ hợp out_ready -> in_ready.
//-----------------------------------------------------------------------------
module aes_xts_skid_stage #(
    parameter int Width = 144
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             s_valid,
    output logic             s_ready,
    input  logic [Width-1:0] s_data,
    output logic             m_valid,
    input  logic             m_ready,
    output logic [Width-1:0] m_data,
    output logic             busy
);
    logic [Width-1:0] skid_data_q;
    logic             skid_valid_q;

    // Xuất s_ready trực tiếp từ FF để cô lập mạng ready giữa các cụm vòng AES
    assign s_ready = ~skid_valid_q;
    assign busy    = m_valid || skid_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid      <= 1'b0;
            m_data       <= '0;
            skid_valid_q <= 1'b0;
            skid_data_q  <= '0;
        end else begin
            if (m_ready || !m_valid) begin
                if (skid_valid_q) begin
                    m_valid      <= 1'b1;
                    m_data       <= skid_data_q;
                    skid_valid_q <= 1'b0;
                end else begin
                    m_valid <= s_valid;
                    if (s_valid) begin
                        m_data <= s_data;
                    end
                end
            end else if (s_valid && s_ready) begin
                skid_valid_q <= 1'b1;
                skid_data_q  <= s_data;
            end
        end
    end
endmodule: aes_xts_skid_stage
