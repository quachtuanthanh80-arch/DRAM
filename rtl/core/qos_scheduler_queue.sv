//=============================================================================
// File Name   : qos_scheduler_queue.sv
// Project     : Q-Shield DDR5 Memory Controller
// Description : Per-Bank-Group QoS Command Queues with Starvation Prevention
//               and Slack-Aware Priority Scheduling.
// Standard    : IEEE 1800-2017 SystemVerilog (Synthesizable & Formal Clean)
//=============================================================================

`timescale 1ns / 1ps

/* verilator lint_off UNUSEDPARAM */
module qos_scheduler_queue #(
    parameter int AXI_ID_WIDTH     = 4,
    parameter int AXI_QOS_WIDTH    = 4,
    parameter int NUM_BG           = 8,
    parameter int BG_WIDTH          = 3,
    parameter int QUEUE_DEPTH      = 4,
    parameter int BANK_WIDTH       = 2,
    parameter int ROW_WIDTH        = 16,
    parameter int COL_WIDTH        = 10,
    parameter int STARVATION_LIMIT = 64
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    // Ingress from Frontend / SDC Filter
    input  logic                                         i_cmd_valid,
    input  logic [AXI_ID_WIDTH-1:0]                      i_cmd_id,
    input  logic                                         i_cmd_is_write,
    input  logic [$clog2(NUM_BG)-1:0]                    i_cmd_bg,
    input  logic [BANK_WIDTH-1:0]                        i_cmd_bank,
    input  logic [ROW_WIDTH-1:0]                         i_cmd_row,
    input  logic [COL_WIDTH-1:0]                         i_cmd_col,
    input  logic [7:0]                                   i_cmd_len,
    input  logic [AXI_QOS_WIDTH-1:0]                     i_cmd_qos,
    input  logic                                         i_cmd_throttled,
    output logic                                         o_cmd_ready,

    // Egress Candidates per Bank Group to Arbiter
    output logic [NUM_BG-1:0]                            o_cand_valid,
    output logic [NUM_BG*AXI_ID_WIDTH-1:0]               o_cand_id,
    output logic [NUM_BG-1:0]                            o_cand_is_write,
    output logic [NUM_BG*BANK_WIDTH-1:0]                 o_cand_bank,
    output logic [NUM_BG*ROW_WIDTH-1:0]                  o_cand_row,
    output logic [NUM_BG*COL_WIDTH-1:0]                  o_cand_col,
    output logic [NUM_BG*8-1:0]                          o_cand_len,
    output logic [NUM_BG*AXI_QOS_WIDTH-1:0]              o_cand_qos,
    output logic [NUM_BG-1:0]                            o_cand_throttled,
    output logic [NUM_BG-1:0]                            o_cand_starved,
    output logic [NUM_BG*$clog2(QUEUE_DEPTH)-1:0]        o_cand_entry_idx,

    // Issue Feedback from Backend Arbiter
    input  logic                                         i_issue_grant_valid,
    input  logic [$clog2(NUM_BG)-1:0]                    i_issue_grant_bg,
    input  logic [$clog2(QUEUE_DEPTH)-1:0]               i_issue_grant_idx
);

    localparam int TOTAL_ENTRIES = NUM_BG * QUEUE_DEPTH;
    localparam int BG_W          = $clog2(NUM_BG);
    localparam int IDX_W         = $clog2(QUEUE_DEPTH);

    // Parallel 1D Logic Arrays for Synthesis & Formal
    logic [TOTAL_ENTRIES-1:0]                    q_valid;
    logic [AXI_ID_WIDTH-1:0]  q_id               [TOTAL_ENTRIES-1:0];
    logic                     q_is_write         [TOTAL_ENTRIES-1:0];
    logic [BANK_WIDTH-1:0]    q_bank             [TOTAL_ENTRIES-1:0];
    logic [ROW_WIDTH-1:0]     q_row              [TOTAL_ENTRIES-1:0];
    logic [COL_WIDTH-1:0]     q_col              [TOTAL_ENTRIES-1:0];
    logic [7:0]               q_len              [TOTAL_ENTRIES-1:0];
    logic [AXI_QOS_WIDTH-1:0] q_qos              [TOTAL_ENTRIES-1:0];
    logic [TOTAL_ENTRIES-1:0]                    q_throttled;
    logic [7:0]               q_age              [TOTAL_ENTRIES-1:0];

    // Status: full per BG
    logic [NUM_BG-1:0] bg_queue_full;
    always_comb begin
        for (int bg = 0; bg < NUM_BG; bg++) begin
            bg_queue_full[bg] = 1'b1;
            for (int e = 0; e < QUEUE_DEPTH; e++) begin
                if (!q_valid[bg * QUEUE_DEPTH + e]) begin
                    bg_queue_full[bg] = 1'b0;
                end
            end
        end
    end

    // Ready if target Bank Group queue has at least 1 free slot
    assign o_cmd_ready = !bg_queue_full[i_cmd_bg];

    // Find free slot for ingress
    logic [IDX_W-1:0] free_slot_idx;
    logic             free_slot_found;
    always_comb begin
        free_slot_found = 1'b0;
        free_slot_idx   = '0;
        for (int e = 0; e < QUEUE_DEPTH; e++) begin
            if (!free_slot_found && !q_valid[i_cmd_bg * QUEUE_DEPTH + e]) begin
                free_slot_found = 1'b1;
                free_slot_idx   = IDX_W'(e);
            end
        end
    end

    // Sequential Queue Management: Enqueue, Dequeue, Age increment
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_valid     <= '0;
            q_throttled <= '0;
            for (int i = 0; i < TOTAL_ENTRIES; i++) begin
                q_id[i]       <= '0;
                q_is_write[i] <= 1'b0;
                q_bank[i]     <= '0;
                q_row[i]      <= '0;
                q_col[i]      <= '0;
                q_len[i]      <= '0;
                q_qos[i]      <= '0;
                q_age[i]      <= 8'd0;
            end
        end else begin
            // 1. Dequeue on Grant
            if (i_issue_grant_valid) begin
                q_valid[i_issue_grant_bg * QUEUE_DEPTH + 32'(i_issue_grant_idx)] <= 1'b0;
            end

            // 2. Enqueue incoming command
            if (i_cmd_valid && o_cmd_ready && free_slot_found) begin
                q_valid[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]     <= 1'b1;
                q_id[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]        <= i_cmd_id;
                q_is_write[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]  <= i_cmd_is_write;
                q_bank[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]      <= i_cmd_bank;
                q_row[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_row;
                q_col[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_col;
                q_len[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_len;
                q_qos[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_qos;
                q_throttled[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)] <= i_cmd_throttled;
                q_age[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= 8'd0;
            end

            // 3. Age increment for all waiting entries (saturating at 255)
            for (int bg = 0; bg < NUM_BG; bg++) begin
                for (int e = 0; e < QUEUE_DEPTH; e++) begin
                    int s_idx;
                    bit is_deq;
                    bit is_enq;
                    s_idx = bg * QUEUE_DEPTH + e;
                    is_deq = (i_issue_grant_valid && (i_issue_grant_bg == BG_W'(bg)) && (i_issue_grant_idx == IDX_W'(e)));
                    is_enq = (i_cmd_valid && o_cmd_ready && free_slot_found && (i_cmd_bg == BG_W'(bg)) && (free_slot_idx == IDX_W'(e)));

                    if (q_valid[s_idx] && !is_deq && !is_enq) begin
                        if (q_age[s_idx] != 8'hFF) begin
                            q_age[s_idx] <= q_age[s_idx] + 1'b1;
                        end
                    end
                end
            end
        end
    end

    //=========================================================================
    // Arbitration Helper Function
    //=========================================================================
    function automatic logic is_better(
        input logic [7:0]               cand_age,
        input logic                     cand_throttled,
        input logic [AXI_QOS_WIDTH-1:0] cand_qos,
        input logic [7:0]               best_age,
        input logic                     best_throttled,
        input logic [AXI_QOS_WIDTH-1:0] best_qos
    );
        logic cand_starved;
        logic best_starved;
        begin
            cand_starved = (cand_age >= STARVATION_LIMIT[7:0]);
            best_starved = (best_age >= STARVATION_LIMIT[7:0]);

            if (cand_starved && !best_starved)
                is_better = 1'b1;
            else if (!cand_starved && best_starved)
                is_better = 1'b0;
            else if (!cand_throttled && best_throttled)
                is_better = 1'b1;
            else if (cand_throttled && !best_throttled)
                is_better = 1'b0;
            else if (cand_qos > best_qos)
                is_better = 1'b1;
            else if (cand_qos == best_qos && cand_age > best_age)
                is_better = 1'b1;
            else
                is_better = 1'b0;
        end
    endfunction

    //=========================================================================
    // Per-Bank-Group Candidate Selection
    //=========================================================================
    always_comb begin
        o_cand_valid     = '0;
        o_cand_id        = '0;
        o_cand_is_write  = '0;
        o_cand_bank      = '0;
        o_cand_row       = '0;
        o_cand_col       = '0;
        o_cand_len       = '0;
        o_cand_qos       = '0;
        o_cand_throttled = '0;
        o_cand_starved   = '0;
        o_cand_entry_idx = '0;

        for (int bg = 0; bg < NUM_BG; bg++) begin
            logic [IDX_W-1:0] best_e;
            logic             cand_found;
            best_e     = '0;
            cand_found = 1'b0;

            for (int e = 0; e < QUEUE_DEPTH; e++) begin
                if (q_valid[bg * QUEUE_DEPTH + e]) begin
                    if (!cand_found) begin
                        best_e     = IDX_W'(e);
                        cand_found = 1'b1;
                    end else begin
                        if (is_better(q_age[bg * QUEUE_DEPTH + e], q_throttled[bg * QUEUE_DEPTH + e], q_qos[bg * QUEUE_DEPTH + e],
                                      q_age[bg * QUEUE_DEPTH + 32'(best_e)], q_throttled[bg * QUEUE_DEPTH + 32'(best_e)], q_qos[bg * QUEUE_DEPTH + 32'(best_e)])) begin
                            best_e = IDX_W'(e);
                        end
                    end
                end
            end

            if (cand_found) begin
                o_cand_valid[bg]                                 = 1'b1;
                o_cand_entry_idx[bg*IDX_W +: IDX_W]              = best_e;
                o_cand_id[bg*AXI_ID_WIDTH +: AXI_ID_WIDTH]       = q_id[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_is_write[bg]                              = q_is_write[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_bank[bg*BANK_WIDTH +: BANK_WIDTH]         = q_bank[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_row[bg*ROW_WIDTH +: ROW_WIDTH]            = q_row[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_col[bg*COL_WIDTH +: COL_WIDTH]            = q_col[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_len[bg*8 +: 8]                            = q_len[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_qos[bg*AXI_QOS_WIDTH +: AXI_QOS_WIDTH]    = q_qos[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_throttled[bg]                             = q_throttled[bg * QUEUE_DEPTH + 32'(best_e)];
                o_cand_starved[bg]                               = (q_age[bg * QUEUE_DEPTH + 32'(best_e)] >= STARVATION_LIMIT[7:0]);
            end
        end
    end

endmodule
