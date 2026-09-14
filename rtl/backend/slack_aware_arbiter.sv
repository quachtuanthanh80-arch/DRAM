//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// File:        slack_aware_arbiter.sv
// Description: Multi-Bank Group Slack-Aware Arbiter.
//              - Selects among 8 Bank Group candidates from qos_scheduler_queue.
//              - Evaluates bank ready status (timing slack) to eliminate $t_{CCD_L}$ bubbles.
//              - 4-Tier Hierarchical Arbitration:
//                1. Anti-Starvation aged commands (Emergency priority)
//                2. High-QoS unthrottled normal traffic with BG rotation
//                3. Throttled RowHammer traffic (Graceful Degradation)
//                4. Slack-time opportunistic Targeted Mitigation / Scrubbing injection
// Standards:   JEDEC DDR5 (JESD79-5), DDR4 (JESD79-4), Synthesizable SystemVerilog.
//=============================================================================

`timescale 1ns / 1ps

module slack_aware_arbiter #(
    parameter int BG_COUNT        = 8,
    parameter int BG_WIDTH        = $clog2(BG_COUNT),
    parameter int BANK_WIDTH      = 2,
    parameter int ROW_WIDTH       = 17,
    parameter int COL_WIDTH       = 10,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int QUEUE_PTR_WIDTH = 3
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    //-------------------------------------------------------------------------
    // Candidates from 8 Bank Group Queues
    //-------------------------------------------------------------------------
    input  logic [BG_COUNT-1:0]                          i_cand_valid,
    input  logic [BG_COUNT*AXI_ID_WIDTH-1:0]             i_cand_id,
    input  logic [BG_COUNT-1:0]                          i_cand_is_write,
    input  logic [BG_COUNT*BANK_WIDTH-1:0]               i_cand_bank,
    input  logic [BG_COUNT*ROW_WIDTH-1:0]                i_cand_row,
    input  logic [BG_COUNT*COL_WIDTH-1:0]                i_cand_col,
    input  logic [BG_COUNT*AXI_LEN_WIDTH-1:0]            i_cand_len,
    input  logic [BG_COUNT*4-1:0]                        i_cand_qos,
    input  logic [BG_COUNT-1:0]                          i_cand_throttled,
    input  logic [BG_COUNT-1:0]                          i_cand_starved,
    input  logic [BG_COUNT*QUEUE_PTR_WIDTH-1:0]          i_cand_queue_idx,

    //-------------------------------------------------------------------------
    // Timing & Readiness from DDR5 Command Engine
    //-------------------------------------------------------------------------
    input  logic [BG_COUNT-1:0]                          i_bg_ready,
    input  logic                                         i_engine_ready,
    input  logic                                         i_slack_cycle,

    //-------------------------------------------------------------------------
    // Mitigation / ECC Scrubbing Injection Interface
    //-------------------------------------------------------------------------
    input  logic                                         i_mitigation_req,
    input  logic [BG_WIDTH-1:0]                          i_mitigation_bg,
    input  logic [BANK_WIDTH-1:0]                        i_mitigation_bank,
    input  logic [ROW_WIDTH-1:0]                         i_mitigation_row,
    output logic                                         o_mitigation_grant,

    //-------------------------------------------------------------------------
    // Grant feedback to qos_scheduler_queue (to dequeue winning entry)
    //-------------------------------------------------------------------------
    output logic                                         o_issue_grant_valid,
    output logic [BG_WIDTH-1:0]                          o_issue_grant_bg,
    output logic [QUEUE_PTR_WIDTH-1:0]                   o_issue_grant_idx,

    //-------------------------------------------------------------------------
    // Dispatched Command to ddr5_cmd_engine
    //-------------------------------------------------------------------------
    output logic                                         o_cmd_valid,
    output logic                                         o_cmd_is_write,
    output logic [AXI_ID_WIDTH-1:0]                      o_cmd_id,
    output logic [BG_WIDTH-1:0]                          o_cmd_bg,
    output logic [BANK_WIDTH-1:0]                        o_cmd_bank,
    output logic [ROW_WIDTH-1:0]                         o_cmd_row,
    output logic [COL_WIDTH-1:0]                         o_cmd_col,
    output logic [AXI_LEN_WIDTH-1:0]                     o_cmd_len,
    output logic                                         o_cmd_is_mitigation
);

    //=========================================================================
    // Internal Signals & Bit Unpacking
    //=========================================================================
    logic [AXI_ID_WIDTH-1:0]    cand_id       [BG_COUNT];
    logic [BANK_WIDTH-1:0]      cand_bank     [BG_COUNT];
    logic [ROW_WIDTH-1:0]       cand_row      [BG_COUNT];
    logic [COL_WIDTH-1:0]       cand_col      [BG_COUNT];
    logic [AXI_LEN_WIDTH-1:0]   cand_len      [BG_COUNT];
    logic [3:0]                 cand_qos      [BG_COUNT];
    logic [QUEUE_PTR_WIDTH-1:0] cand_queue_idx[BG_COUNT];

    always_comb begin
        for (int bg = 0; bg < BG_COUNT; bg++) begin
            cand_id[bg]        = i_cand_id[bg*AXI_ID_WIDTH +: AXI_ID_WIDTH];
            cand_bank[bg]      = i_cand_bank[bg*BANK_WIDTH +: BANK_WIDTH];
            cand_row[bg]       = i_cand_row[bg*ROW_WIDTH +: ROW_WIDTH];
            cand_col[bg]       = i_cand_col[bg*COL_WIDTH +: COL_WIDTH];
            cand_len[bg]       = i_cand_len[bg*AXI_LEN_WIDTH +: AXI_LEN_WIDTH];
            cand_qos[bg]       = i_cand_qos[bg*4 +: 4];
            cand_queue_idx[bg] = i_cand_queue_idx[bg*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH];
        end
    end

    // Mask candidates with Bank Group timing readiness
    wire [BG_COUNT-1:0] eligible_cand = i_cand_valid & i_bg_ready;

    // Round-Robin state for fairness when QoS levels tie
    logic [BG_WIDTH-1:0] last_served_bg;

    //=========================================================================
    // 4-Tier Selection Logic
    //=========================================================================
    logic                winner_found;
    logic [BG_WIDTH-1:0] winner_bg;
    logic [BG_WIDTH-1:0] cur_bg;
    logic [3:0]          max_qos;

    always_comb begin
        winner_found = 1'b0;
        winner_bg    = '0;
        cur_bg       = '0;
        max_qos      = '0;

        // Tier 1: Check Starved Candidates (Emergency Boost)
        for (int i = 0; i < BG_COUNT; i++) begin
            cur_bg = BG_WIDTH'((int'(last_served_bg) + 1 + i) % BG_COUNT);
            if (eligible_cand[cur_bg] && i_cand_starved[cur_bg] && !winner_found) begin
                winner_found = 1'b1;
                winner_bg    = cur_bg;
            end
        end

        // Tier 2: Unthrottled Normal Traffic (Highest QoS wins; RR on tie)
        if (!winner_found) begin
            max_qos = 4'd0;
            for (int i = 0; i < BG_COUNT; i++) begin
                cur_bg = BG_WIDTH'((int'(last_served_bg) + 1 + i) % BG_COUNT);
                if (eligible_cand[cur_bg] && !i_cand_throttled[cur_bg]) begin
                    if (!winner_found || (cand_qos[cur_bg] > max_qos)) begin
                        winner_found = 1'b1;
                        winner_bg    = cur_bg;
                        max_qos      = cand_qos[cur_bg];
                    end
                end
            end
        end

        // Tier 3: Throttled RowHammer Traffic (Degraded service)
        if (!winner_found) begin
            max_qos = 4'd0;
            for (int i = 0; i < BG_COUNT; i++) begin
                cur_bg = BG_WIDTH'((int'(last_served_bg) + 1 + i) % BG_COUNT);
                if (eligible_cand[cur_bg] && i_cand_throttled[cur_bg]) begin
                    if (!winner_found || (cand_qos[cur_bg] > max_qos)) begin
                        winner_found = 1'b1;
                        winner_bg    = cur_bg;
                        max_qos      = cand_qos[cur_bg];
                    end
                end
            end
        end
    end

    // Tier 4: Opportunity Slack Injection
    wire can_issue_user_cmd = winner_found && i_engine_ready;
    wire can_issue_mitigation = !winner_found && i_slack_cycle && i_mitigation_req && i_engine_ready;

    // Grant back to mitigation source
    assign o_mitigation_grant = can_issue_mitigation;

    // Dequeue grant back to winning Bank Group queue
    assign o_issue_grant_valid = can_issue_user_cmd;
    assign o_issue_grant_bg    = winner_bg;
    assign o_issue_grant_idx   = cand_queue_idx[winner_bg];

    // Output command multiplexing to DDR5 Command Engine
    always_comb begin
        if (can_issue_user_cmd) begin
            o_cmd_valid         = 1'b1;
            o_cmd_is_write      = i_cand_is_write[winner_bg];
            o_cmd_id            = cand_id[winner_bg];
            o_cmd_bg            = winner_bg;
            o_cmd_bank          = cand_bank[winner_bg];
            o_cmd_row           = cand_row[winner_bg];
            o_cmd_col           = cand_col[winner_bg];
            o_cmd_len           = cand_len[winner_bg];
            o_cmd_is_mitigation = 1'b0;
        end else if (can_issue_mitigation) begin
            o_cmd_valid         = 1'b1;
            o_cmd_is_write      = 1'b0; // Mitigation typically treated as refresh/precharge
            o_cmd_id            = '0;
            o_cmd_bg            = i_mitigation_bg;
            o_cmd_bank          = i_mitigation_bank;
            o_cmd_row           = i_mitigation_row;
            o_cmd_col           = '0;
            o_cmd_len           = '0;
            o_cmd_is_mitigation = 1'b1;
        end else begin
            o_cmd_valid         = 1'b0;
            o_cmd_is_write      = 1'b0;
            o_cmd_id            = '0;
            o_cmd_bg            = '0;
            o_cmd_bank          = '0;
            o_cmd_row           = '0;
            o_cmd_col           = '0;
            o_cmd_len           = '0;
            o_cmd_is_mitigation = 1'b0;
        end
    end

    // Sequential update of round-robin state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_served_bg <= '0;
        end else begin
            if (can_issue_user_cmd) begin
                last_served_bg <= winner_bg;
            end
        end
    end

endmodule
