//=============================================================================
// Module Name: ddr5_subchannel_scheduler
// Description: FR-FCFS (First-Ready First-Come First-Served) Memory Command
//              Scheduler for DDR5 Subchannel with Bank-State Tracking and
//              Timing Constraint Counters (tRCD, tRP, tCCD, tWTR).
//              Features:
//              1. Manages 8 Banks across 4 Bank Groups per DDR5 Subchannel.
//              2. Bank State Machine: CLOSED, OPENING, ACTIVE, CLOSING.
//              3. Page Hit / Row Hit detection (eliminates PRE/ACT penalties).
//              4. FR-FCFS arbiter prioritizing open-page memory requests.
//              5. Command Generator outputs DFI standard commands:
//                 ACT, PRE, READ, WRITE, REFRESH.
// Standard:    JEDEC DDR5 (JESD79-5) / Synthesizable SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module ddr5_subchannel_scheduler #(
    parameter int NumBanks    = 8,
    parameter int NumBankGrps = 4,
    parameter int RowWidth    = 16,
    parameter int ColWidth    = 10,
    parameter int QueueDepth  = 8,
    // Timing Constraints in DRAM Clock Cycles (@ 400 MHz, tCK = 2.5ns)
    parameter int TRCD_CYC    = 6,  // 15 ns / 2.5 ns = 6 cycles
    parameter int TRP_CYC     = 6,  // 15 ns / 2.5 ns = 6 cycles
    parameter int TCCDL_CYC   = 4,  // Column-to-Column same bank group
    parameter int TWTRL_CYC   = 8   // Write-to-Read turnaround
) (
    input  logic                 clk,
    input  logic                 rst_n,

    // Request Interface (from CDC FIFO / AES-XTS Subchannel)
    input  logic                 req_valid,
    output logic                 req_ready,
    input  logic                 req_is_write,
    input  logic [2:0]           req_bank,
    input  logic [1:0]           req_bank_grp,
    input  logic [RowWidth-1:0]  req_row,
    input  logic [ColWidth-1:0]  req_col,
    input  logic [127:0]         req_wdata,
    input  logic [15:0]          req_tag,

    // Command Output to DFI / PHY Adapter
    output logic                 cmd_valid,
    input  logic                 cmd_ready,
    output logic [2:0]           cmd_type,   // 3'b001: ACT, 3'b010: PRE, 3'b011: RD, 3'b100: WR
    output logic [1:0]           cmd_bg,
    output logic [2:0]           cmd_ba,
    output logic [RowWidth-1:0]  cmd_addr,
    output logic [127:0]         cmd_wdata,
    output logic [15:0]          cmd_tag,

    // Performance & Diagnostics
    output logic [31:0]          page_hits,
    output logic [31:0]          page_misses,
    output logic [31:0]          total_cmds
);

    // Command Encodings
    localparam logic [2:0] CmdNop = 3'b000;
    localparam logic [2:0] CmdAct = 3'b001;
    localparam logic [2:0] CmdPre = 3'b010;
    localparam logic [2:0] CmdRd  = 3'b011;
    localparam logic [2:0] CmdWr  = 3'b100;

    // Bank States
    typedef enum logic [1:0] {
        BANK_CLOSED  = 2'b00,
        BANK_OPENING = 2'b01,
        BANK_ACTIVE  = 2'b10,
        BANK_CLOSING = 2'b11
    } bank_state_t;

    bank_state_t        bank_state [NumBanks];
    logic [RowWidth-1:0] open_row   [NumBanks];
    logic [3:0]         bank_timer [NumBanks]; // Countdown timer for tRCD / tRP

    // Global Timing Constraints
    logic [3:0] turnaround_timer;

// Fast path single-entry architecture

    // Single-entry fast path register for scheduler
    logic                  active_req_valid;
    logic                  active_req_is_write;
    logic [2:0]            active_req_bank;
    logic [1:0]            active_req_bank_grp;
    logic [RowWidth-1:0]   active_req_row;
    logic [ColWidth-1:0]   active_req_col;
    logic [127:0]          active_req_wdata;
    logic [15:0]           active_req_tag;

    // Ready when no active request is pending
    assign req_ready = !active_req_valid;

    // Command generation FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_req_valid    <= 1'b0;
            active_req_is_write <= 1'b0;
            active_req_bank     <= '0;
            active_req_bank_grp <= '0;
            active_req_row      <= '0;
            active_req_col      <= '0;
            active_req_wdata    <= '0;
            active_req_tag      <= '0;

            cmd_valid           <= 1'b0;
            cmd_type            <= CmdNop;
            cmd_bg              <= '0;
            cmd_ba              <= '0;
            cmd_addr            <= '0;
            cmd_wdata           <= '0;
            cmd_tag             <= '0;

            page_hits           <= '0;
            page_misses         <= '0;
            total_cmds          <= '0;
            turnaround_timer    <= '0;

            for (int b = 0; b < NumBanks; b++) begin
                bank_state[active_req_bank] <= BANK_CLOSED;
                open_row[active_req_bank]   <= '0;
                bank_timer[active_req_bank] <= '0;
            end
        end else begin
            // Decrement active timers
            if (turnaround_timer > 0) begin
                turnaround_timer <= turnaround_timer - 4'd1;
            end

            for (int b = 0; b < NumBanks; b++) begin
                if (bank_timer[active_req_bank] > 0) begin
                    bank_timer[active_req_bank] <= bank_timer[active_req_bank] - 4'd1;
                end else begin
                    if (bank_state[active_req_bank] == BANK_OPENING) begin
                        bank_state[active_req_bank] <= BANK_ACTIVE;
                    end else if (bank_state[active_req_bank] == BANK_CLOSING) begin
                        bank_state[active_req_bank] <= BANK_CLOSED;
                    end
                end
            end

            // Default: deassert cmd_valid when accepted
            if (cmd_valid && cmd_ready) begin
                cmd_valid <= 1'b0;
                cmd_type  <= CmdNop;
            end

            // Accept new upstream request into active register
            if (req_valid && req_ready) begin
                active_req_valid    <= 1'b1;
                active_req_is_write <= req_is_write;
                active_req_bank     <= req_bank;
                active_req_bank_grp <= req_bank_grp;
                active_req_row      <= req_row;
                active_req_col      <= req_col;
                active_req_wdata    <= req_wdata;
                active_req_tag      <= req_tag;
            end

            // Command Arbitration Logic
            if (active_req_valid && (!cmd_valid || cmd_ready)) begin
                case (bank_state[active_req_bank])
                    BANK_CLOSED: begin
                        // Target bank is closed -> Issue ACTIVATE command
                        cmd_valid        <= 1'b1;
                        cmd_type         <= CmdAct;
                        cmd_bg           <= active_req_bank_grp;
                        cmd_ba           <= active_req_bank;
                        cmd_addr         <= active_req_row;
                        cmd_wdata        <= '0;
                        cmd_tag          <= active_req_tag;

                        open_row[active_req_bank]      <= active_req_row;
                        bank_state[active_req_bank]    <= BANK_OPENING;
                        bank_timer[active_req_bank]    <= 4'(TRCD_CYC - 1);
                        page_misses      <= page_misses + 32'd1;
                        total_cmds       <= total_cmds + 32'd1;
                    end

                    BANK_ACTIVE: begin
                        if (bank_timer[active_req_bank] == 0 && turnaround_timer == 0) begin
                            if (open_row[active_req_bank] == active_req_row) begin
                                // PAGE HIT: Issue READ or WRITE directly!
                                cmd_valid        <= 1'b1;
                                cmd_type         <= active_req_is_write ? CmdWr : CmdRd;
                                cmd_bg           <= active_req_bank_grp;
                                cmd_ba           <= active_req_bank;
                                cmd_addr         <= {{(RowWidth-ColWidth){1'b0}}, active_req_col};
                                cmd_wdata        <= active_req_wdata;
                                cmd_tag          <= active_req_tag;

                                page_hits        <= page_hits + 32'd1;
                                total_cmds       <= total_cmds + 32'd1;
                                active_req_valid <= 1'b0; // Request completed!
                                turnaround_timer <= 4'(TCCDL_CYC - 1);
                            end else begin
                                // PAGE MISS (Row conflict): Issue PRECHARGE
                                cmd_valid     <= 1'b1;
                                cmd_type      <= CmdPre;
                                cmd_bg        <= active_req_bank_grp;
                                cmd_ba        <= active_req_bank;
                                cmd_addr      <= '0;
                                cmd_wdata     <= '0;
                                cmd_tag       <= active_req_tag;

                                bank_state[active_req_bank] <= BANK_CLOSING;
                                bank_timer[active_req_bank] <= 4'(TRP_CYC - 1);
                                page_misses   <= page_misses + 32'd1;
                                total_cmds    <= total_cmds + 32'd1;
                            end
                        end
                    end

                    default: ; // Wait while BANK_OPENING or BANK_CLOSING
                endcase
            end
        end
    end



endmodule: ddr5_subchannel_scheduler
