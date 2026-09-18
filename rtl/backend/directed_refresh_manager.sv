//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// Module Name: directed_refresh_manager
// Description: Proactive Directed Refresh Manager (DRM).
//              - Inspired by SOTA DREAM (ISCA'25) architecture.
//              - Protects adjacent victim rows (Row +/- 1, Row +/- 2) when an
//                aggressor row threshold is tripped by SDC filter or RowPress.
//              - Queues victim rows and arbitrates with ECC patrol scrubbing.
//              - Injects targeted refreshes during opportunistic slack cycles.
// Standard:    Synthesizable SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module directed_refresh_manager #(
    parameter int BG_WIDTH    = 3,
    parameter int BANK_WIDTH  = 2,
    parameter int ROW_WIDTH   = 17,
    parameter int QUEUE_DEPTH = 8
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Configuration
    input  logic                   cfg_drm_en,        // 1: Enable directed refresh
    input  logic                   cfg_victim2_en,    // 1: Refresh row +/- 2 in addition to +/- 1

    // Aggressor Alert from SDC Resilient Filter
    input  logic                   i_sdc_req,
    input  logic [BG_WIDTH-1:0]    i_sdc_bg,
    input  logic [BANK_WIDTH-1:0]  i_sdc_bank,
    input  logic [ROW_WIDTH-1:0]   i_sdc_row,

    // Aggressor Alert from RowPress Monitor
    input  logic                   i_rp_req,
    input  logic [BG_WIDTH-1:0]    i_rp_bg,
    input  logic [BANK_WIDTH-1:0]  i_rp_bank,
    input  logic [ROW_WIDTH-1:0]   i_rp_row,

    // ECC Patrol Scrubber Input (Lower Priority)
    input  logic                   i_scrub_req,
    input  logic [BG_WIDTH-1:0]    i_scrub_bg,
    input  logic [BANK_WIDTH-1:0]  i_scrub_bank,
    input  logic [ROW_WIDTH-1:0]   i_scrub_row,
    output logic                   o_scrub_grant,

    // Interface to slack_aware_arbiter
    output logic                   o_mitigation_req,
    output logic [BG_WIDTH-1:0]    o_mitigation_bg,
    output logic [BANK_WIDTH-1:0]  o_mitigation_bank,
    output logic [ROW_WIDTH-1:0]   o_mitigation_row,
    input  logic                   i_mitigation_grant,

    // Telemetry
    output logic [15:0]            o_drm_ref_count,
    output logic                   o_queue_full
);

    localparam int PTR_W = $clog2(QUEUE_DEPTH);

    // Victim Queue Storage
    logic [BG_WIDTH-1:0]   q_bg   [QUEUE_DEPTH];
    logic [BANK_WIDTH-1:0] q_bank [QUEUE_DEPTH];
    logic [ROW_WIDTH-1:0]  q_row  [QUEUE_DEPTH];

    logic [PTR_W:0] wr_ptr;
    logic [PTR_W:0] rd_ptr;
    wire [PTR_W:0]  count = wr_ptr - rd_ptr;

    wire queue_empty = (count == '0);
    wire queue_full  = (count >= QUEUE_DEPTH[PTR_W:0]);
    assign o_queue_full = queue_full;

    // Pulse edge detector for requests
    logic sdc_req_d, rp_req_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdc_req_d <= 1'b0;
            rp_req_d  <= 1'b0;
        end else begin
            sdc_req_d <= i_sdc_req;
            rp_req_d  <= i_rp_req;
        end
    end
    wire sdc_pulse = i_sdc_req && !sdc_req_d;
    wire rp_pulse  = i_rp_req  && !rp_req_d;

    // Active aggressor selection (SDC has priority over RowPress)
    wire                   aggr_valid = (sdc_pulse || rp_pulse) && cfg_drm_en;
    wire [BG_WIDTH-1:0]    aggr_bg    = sdc_pulse ? i_sdc_bg   : i_rp_bg;
    wire [BANK_WIDTH-1:0]  aggr_bank  = sdc_pulse ? i_sdc_bank : i_rp_bank;
    wire [ROW_WIDTH-1:0]   aggr_row   = sdc_pulse ? i_sdc_row  : i_rp_row;

    // Multi-cycle injection generator for victim rows (+1, -1, +2, -2)
    logic [2:0]            inj_state;
    logic [BG_WIDTH-1:0]   inj_bg;
    logic [BANK_WIDTH-1:0] inj_bank;
    logic [ROW_WIDTH-1:0]  inj_row;
    logic                  inj_victim2;

    wire [PTR_W-1:0] wr_idx = wr_ptr[PTR_W-1:0];
    wire [PTR_W-1:0] rd_idx = rd_ptr[PTR_W-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr          <= '0;
            rd_ptr          <= '0;
            inj_state       <= 3'd0;
            inj_bg          <= '0;
            inj_bank        <= '0;
            inj_row         <= '0;
            inj_victim2     <= 1'b0;
            o_drm_ref_count <= 16'd0;
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                q_bg[i]   <= '0;
                q_bank[i] <= '0;
                q_row[i]  <= '0;
            end
        end else begin
            // 1. Dequeue on mitigation grant when serving DRM queue
            if (i_mitigation_grant && !queue_empty) begin
                rd_ptr          <= rd_ptr + 1'b1;
                o_drm_ref_count <= o_drm_ref_count + 1'b1;
            end

            // 2. Multi-victim enqueue sequencer
            case (inj_state)
                3'd0: begin
                    if (aggr_valid && (count < (QUEUE_DEPTH[PTR_W:0] - 4))) begin
                        // Enqueue Victim 1: Row + 1
                        q_bg[wr_idx]   <= aggr_bg;
                        q_bank[wr_idx] <= aggr_bank;
                        q_row[wr_idx]  <= aggr_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1};
                        wr_ptr         <= wr_ptr + 1'b1;

                        inj_bg      <= aggr_bg;
                        inj_bank    <= aggr_bank;
                        inj_row     <= aggr_row;
                        inj_victim2 <= cfg_victim2_en;
                        inj_state   <= 3'd1;
                    end
                end

                3'd1: begin
                    // Enqueue Victim 2: Row - 1
                    q_bg[wr_idx]   <= inj_bg;
                    q_bank[wr_idx] <= inj_bank;
                    q_row[wr_idx]  <= inj_row - {{(ROW_WIDTH-1){1'b0}}, 1'b1};
                    wr_ptr         <= wr_ptr + 1'b1;

                    if (inj_victim2) begin
                        inj_state <= 3'd2;
                    end else begin
                        inj_state <= 3'd0;
                    end
                end

                3'd2: begin
                    // Enqueue Victim 3: Row + 2
                    q_bg[wr_idx]   <= inj_bg;
                    q_bank[wr_idx] <= inj_bank;
                    q_row[wr_idx]  <= inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd2};
                    wr_ptr         <= wr_ptr + 1'b1;
                    inj_state      <= 3'd3;
                end

                3'd3: begin
                    // Enqueue Victim 4: Row - 2
                    q_bg[wr_idx]   <= inj_bg;
                    q_bank[wr_idx] <= inj_bank;
                    q_row[wr_idx]  <= inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd2};
                    wr_ptr         <= wr_ptr + 1'b1;
                    inj_state      <= 3'd0;
                end

                default: inj_state <= 3'd0;
            endcase
        end
    end

    // Arbitration between Directed Refresh and ECC Patrol Scrubbing
    always_comb begin
        if (!queue_empty) begin
            // Directed Refresh has highest priority
            o_mitigation_req  = 1'b1;
            o_mitigation_bg   = q_bg[rd_idx];
            o_mitigation_bank = q_bank[rd_idx];
            o_mitigation_row  = q_row[rd_idx];
            o_scrub_grant     = 1'b0;
        end else if (i_scrub_req) begin
            // ECC Scrubber when no directed refreshes pending
            o_mitigation_req  = 1'b1;
            o_mitigation_bg   = i_scrub_bg;
            o_mitigation_bank = i_scrub_bank;
            o_mitigation_row  = i_scrub_row;
            o_scrub_grant     = i_mitigation_grant;
        end else begin
            o_mitigation_req  = 1'b0;
            o_mitigation_bg   = '0;
            o_mitigation_bank = '0;
            o_mitigation_row  = '0;
            o_scrub_grant     = 1'b0;
        end
    end

endmodule: directed_refresh_manager
