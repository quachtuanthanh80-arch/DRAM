//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// File:        reorder_buffer_rob.sv
// Description: Out-of-Order Tracking & In-Order Retirement Reorder Buffer (ROB)
//              with integrated Read-After-Write (RAW) Hazard Detection.
//              - Allocates tags for in-flight DRAM Read requests.
//              - Detects RAW collisions against active write transactions.
//              - Receives out-of-order DRAM data writebacks via allocated tags.
//              - Guarantees strict AXI in-order data return per ID / FIFO.
//              - Zero-bubble output skid buffer for full 1-beat/cycle burst throughput.
// Standards:   AXI4 Protocol (ARM IHI 0022E), IEEE 1800-2017 SystemVerilog.
//=============================================================================

`timescale 1ns / 1ps

module reorder_buffer_rob #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int ROB_DEPTH       = 32,
    parameter int ROB_PTR_WIDTH   = $clog2(ROB_DEPTH),
    parameter int MAX_BURST_BEATS = 8,
    parameter int BURST_IDX_WIDTH = $clog2(MAX_BURST_BEATS),
    parameter int MAX_WR_TRACK    = 8
)(
    input  logic                                  clk,
    input  logic                                  rst_n,

    //-------------------------------------------------------------------------
    // Allocation Interface (from Dispatch / Frontend)
    //-------------------------------------------------------------------------
    input  logic                                  i_alloc_valid,
    input  logic [AXI_ID_WIDTH-1:0]               i_alloc_id,
    input  logic [AXI_ADDR_WIDTH-1:0]             i_alloc_addr,
    input  logic [AXI_LEN_WIDTH-1:0]              i_alloc_len,
    output logic                                  o_alloc_ready,
    output logic [ROB_PTR_WIDTH-1:0]              o_alloc_tag,

    //-------------------------------------------------------------------------
    // RAW Hazard Detection Interface
    //-------------------------------------------------------------------------
    input  logic [MAX_WR_TRACK-1:0]               i_wr_active_valid,
    input  logic [MAX_WR_TRACK*AXI_ADDR_WIDTH-1:0]i_wr_active_addr,
    output logic                                  o_raw_hazard,
    output logic [MAX_WR_TRACK-1:0]               o_raw_match_mask,

    //-------------------------------------------------------------------------
    // DRAM Read Data Writeback Interface (from DDR5 Data Return Engine)
    //-------------------------------------------------------------------------
    input  logic                                  i_wb_valid,
    input  logic [ROB_PTR_WIDTH-1:0]              i_wb_tag,
    input  logic [AXI_DATA_WIDTH-1:0]             i_wb_data,
    input  logic [1:0]                            i_wb_resp,
    input  logic                                  i_wb_last,

    //-------------------------------------------------------------------------
    // AXI4 R-Channel Interface (Out to AXI Master)
    //-------------------------------------------------------------------------
    output logic                                  o_rvalid,
    output logic [AXI_ID_WIDTH-1:0]               o_rid,
    output logic [AXI_DATA_WIDTH-1:0]             o_rdata,
    output logic [1:0]                            o_rresp,
    output logic                                  o_rlast,
    input  logic                                  i_rready,

    //-------------------------------------------------------------------------
    // Buffer Status Telemetry
    //-------------------------------------------------------------------------
    output logic                                  o_rob_empty,
    output logic                                  o_rob_full,
    output logic [ROB_PTR_WIDTH:0]                o_rob_count
);

    //=========================================================================
    // Internal Data Structures
    //=========================================================================
    // Metadata per entry
    logic [ROB_DEPTH-1:0]                      entry_valid;
    logic [ROB_DEPTH-1:0][AXI_ID_WIDTH-1:0]    entry_id;
    logic [ROB_DEPTH-1:0][BURST_IDX_WIDTH:0]   entry_len;      // truncated to max burst beats
    logic [ROB_DEPTH-1:0][BURST_IDX_WIDTH:0]   entry_wb_count; // counts received beats (0..MAX_BURST_BEATS)
    logic [ROB_DEPTH-1:0]                      entry_wb_done;

    // Payload storage (ROB_DEPTH entries x MAX_BURST_BEATS data words)
    logic [AXI_DATA_WIDTH-1:0] payload_data [ROB_DEPTH][MAX_BURST_BEATS];
    logic [1:0]                payload_resp [ROB_DEPTH][MAX_BURST_BEATS];

    // Pointers & Occupancy
    logic [ROB_PTR_WIDTH-1:0]  alloc_ptr;
    logic [ROB_PTR_WIDTH-1:0]  retire_ptr;
    logic [BURST_IDX_WIDTH:0]  retire_beat;
    logic [ROB_PTR_WIDTH:0]    occupancy_count;

    assign o_rob_empty   = (occupancy_count == '0);
    assign o_rob_full    = (occupancy_count >= ROB_DEPTH[ROB_PTR_WIDTH:0]);
    assign o_rob_count   = occupancy_count;
    assign o_alloc_ready = !o_rob_full;
    assign o_alloc_tag   = alloc_ptr;

    //=========================================================================
    // RAW Hazard Detection Logic (Combinational)
    // Checks incoming Read address against all active in-flight writes
    // (64-byte Cacheline granularity: addr[AXI_ADDR_WIDTH-1:6])
    //=========================================================================
    logic [MAX_WR_TRACK-1:0] raw_match_comb;
    always_comb begin
        raw_match_comb = '0;
        for (int k = 0; k < MAX_WR_TRACK; k++) begin
            if (i_wr_active_valid[k]) begin
                // Compare cacheline tag (bits [AXI_ADDR_WIDTH-1 : 6])
                if (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] == i_alloc_addr[AXI_ADDR_WIDTH-1:6]) begin
                    raw_match_comb[k] = 1'b1;
                end
            end
        end
    end

    assign o_raw_match_mask = raw_match_comb;
    assign o_raw_hazard     = |raw_match_comb;

    //=========================================================================
    // Slot Allocation Process
    //=========================================================================
    wire alloc_fire = i_alloc_valid && o_alloc_ready && !o_raw_hazard;

    // Truncate i_alloc_len safely to maximum supported burst beats
    wire [BURST_IDX_WIDTH:0] clamped_alloc_len =
        (i_alloc_len >= AXI_LEN_WIDTH'(MAX_BURST_BEATS)) ?
        (BURST_IDX_WIDTH + 1)'(MAX_BURST_BEATS - 1) :
        i_alloc_len[BURST_IDX_WIDTH:0];

    //=========================================================================
    // Internal Read Retirement Signals (Pre-Skid Buffer)
    //=========================================================================
    logic                      core_rvalid;
    logic [AXI_ID_WIDTH-1:0]   core_rid;
    logic [AXI_DATA_WIDTH-1:0] core_rdata;
    logic [1:0]                core_rresp;
    logic                      core_rlast;
    logic                      core_rready;

    // Condition to emit next beat from head of ROB:
    // Oldest entry at retire_ptr must be valid and have data beat ready
    wire retire_entry_has_beat = entry_valid[retire_ptr] &&
                                 (retire_beat < entry_wb_count[retire_ptr]);

    wire [BURST_IDX_WIDTH-1:0] retire_beat_idx = retire_beat[BURST_IDX_WIDTH-1:0];

    assign core_rvalid = retire_entry_has_beat;
    assign core_rid    = entry_id[retire_ptr];
    assign core_rdata  = payload_data[retire_ptr][retire_beat_idx];
    assign core_rresp  = payload_resp[retire_ptr][retire_beat_idx];
    assign core_rlast  = (retire_beat == entry_len[retire_ptr]);

    wire retire_beat_fire  = core_rvalid && core_rready;
    wire retire_entry_done = retire_beat_fire && core_rlast;
    wire [BURST_IDX_WIDTH:0] tag_wb_cnt = entry_wb_count[i_wb_tag];
    wire [BURST_IDX_WIDTH-1:0] wb_beat_idx = tag_wb_cnt[BURST_IDX_WIDTH-1:0];

    //=========================================================================
    // Sequential State Update
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alloc_ptr        <= '0;
            retire_ptr       <= '0;
            retire_beat      <= '0;
            occupancy_count  <= '0;
            entry_valid      <= '0;
            entry_wb_done    <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entry_id[i]       <= '0;
                entry_len[i]      <= '0;
                entry_wb_count[i] <= '0;
            end
        end else begin
            // 1. Allocation
            if (alloc_fire) begin
                entry_valid[alloc_ptr]      <= 1'b1;
                entry_id[alloc_ptr]         <= i_alloc_id;
                entry_len[alloc_ptr]        <= clamped_alloc_len;
                entry_wb_count[alloc_ptr]   <= '0;
                entry_wb_done[alloc_ptr]    <= 1'b0;
                alloc_ptr                   <= alloc_ptr + 1'b1;
            end

            // 2. Writeback Reception from DRAM
            if (i_wb_valid && entry_valid[i_wb_tag]) begin
                for (int d = 0; d < ROB_DEPTH; d++) begin
                    if (d == i_wb_tag) begin
                        for (int b = 0; b < MAX_BURST_BEATS; b++) begin
                            if (b == wb_beat_idx) begin
                                payload_data[d][b] <= i_wb_data;
                                payload_resp[d][b] <= i_wb_resp;
                            end
                        end
                    end
                end
                entry_wb_count[i_wb_tag]                                               <= entry_wb_count[i_wb_tag] + 1'b1;
                if (i_wb_last || (entry_wb_count[i_wb_tag] >= entry_len[i_wb_tag])) begin
                    entry_wb_done[i_wb_tag] <= 1'b1;
                end
            end

            // 3. Retirement from Head
            if (retire_beat_fire) begin
                if (core_rlast) begin
                    entry_valid[retire_ptr]   <= 1'b0;
                    entry_wb_done[retire_ptr] <= 1'b0;
                    retire_beat               <= '0;
                    retire_ptr                <= retire_ptr + 1'b1;
                end else begin
                    retire_beat               <= retire_beat + 1'b1;
                end
            end

            // 4. Track Occupancy
            case ({alloc_fire, retire_entry_done})
                2'b10: occupancy_count <= occupancy_count + 1'b1;
                2'b01: occupancy_count <= occupancy_count - 1'b1;
                default: occupancy_count <= occupancy_count;
            endcase
        end
    end

    //=========================================================================
    // Zero-Bubble Forward-Registered Skid Buffer on AXI R-Channel
    // Canonical 2-register slice decoupling upstream and downstream handshakes.
    //=========================================================================
    localparam int R_PAYLOAD_W = AXI_ID_WIDTH + AXI_DATA_WIDTH + 2 + 1;

    wire [R_PAYLOAD_W-1:0] core_payload = {core_rid, core_rdata, core_rresp, core_rlast};
    logic [R_PAYLOAD_W-1:0] out_payload;

    logic                   skid_valid;
    logic [R_PAYLOAD_W-1:0] skid_payload;
    logic                   reg_rvalid;

    assign core_rready = !skid_valid;
    assign o_rvalid    = reg_rvalid;
    assign {o_rid, o_rdata, o_rresp, o_rlast} = out_payload;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rvalid   <= 1'b0;
            out_payload  <= '0;
            skid_valid   <= 1'b0;
            skid_payload <= '0;
        end else begin
            if (i_rready || !reg_rvalid) begin
                if (skid_valid) begin
                    reg_rvalid   <= 1'b1;
                    out_payload  <= skid_payload;
                    skid_valid   <= 1'b0;
                end else begin
                    reg_rvalid   <= core_rvalid;
                    out_payload  <= core_payload;
                end
            end else if (core_rvalid && core_rready) begin
                skid_valid   <= 1'b1;
                skid_payload <= core_payload;
            end
        end
    end

    // Unused bits sink for clean lint
    logic _unused_sink;
    assign _unused_sink = &{1'b0, i_alloc_addr[5:0], entry_wb_done, 1'b0};

    //=========================================================================
    // Formal & Assertions
    //=========================================================================
`ifdef SYSTEMVERILOG_ASSERTIONS
    // Check no allocation when full
    assert property (@(posedge clk) disable iff (!rst_n)
        (i_alloc_valid && o_rob_full) |-> !alloc_fire
    ) else $error("ROB: Allocation occurred while buffer was FULL!");

    // Check writeback tag validity
    assert property (@(posedge clk) disable iff (!rst_n)
        i_wb_valid |-> entry_valid[i_wb_tag]
    ) else $error("ROB: Received DRAM writeback for an invalid/unallocated tag!");
`endif


    //=========================================================================
    // Hardware Formal Verification (SymbiYosys / SVA)
    //=========================================================================
`ifdef FORMAL
    initial begin
        assume (!rst_n);
    end

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    // Property 1: Reset state
    always_comb begin
        if (!rst_n) begin
            assert (alloc_ptr == '0);
            assert (retire_ptr == '0);
            assert (o_rob_count == '0);
            assert (o_rob_empty);
            assert (!o_rob_full);
            assert (!o_rvalid);
        end
    end

    // Property 2: Capacity Invariant
    always_comb begin
        if (rst_n) begin
            assert (o_rob_count <= ROB_DEPTH);
            assert (o_rob_full == (o_rob_count == ROB_DEPTH));
            assert (o_rob_empty == (o_rob_count == '0));
            assert (o_alloc_ready == !o_rob_full);
        end
    end

    // Property 3: In-Order Retirement Guard
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if (retire_entry_done) begin
                assert (entry_valid[retire_ptr]);
                assert (entry_wb_done[retire_ptr]);
            end
        end
    end

    // Property 4: RAW Hazard Soundness
    always_comb begin
        if (rst_n) begin
            for (int k = 0; k < MAX_WR_TRACK; k++) begin
                if (i_wr_active_valid[k] &&
                    (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] == i_alloc_addr[AXI_ADDR_WIDTH-1:6])) begin
                    assert (o_raw_hazard);
                end
            end
        end
    end
`endif

endmodule
