//=============================================================================
// File:        ddr5_cmd_engine.sv
// Chức năng:   Kiểm soát định thời JEDEC DDR5/DDR4, phát xung lệnh DFI và theo dõi trạng thái các Bank.
//=============================================================================
`timescale 1ns / 1ps

module ddr5_cmd_engine #(
    parameter int BG_COUNT        = 8,
    parameter int BG_WIDTH        = $clog2(BG_COUNT),
    parameter int BANK_COUNT      = 4,
    parameter int BANK_WIDTH      = $clog2(BANK_COUNT),
    parameter int ROW_WIDTH       = 17,
    parameter int COL_WIDTH       = 10,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int ROB_PTR_WIDTH   = 5,

    // JEDEC Timing Parameters (in ddr clock cycles, configurable)
    parameter int T_RCD           = 6,  // Row-to-Column delay (ACT to RD/WR)
    parameter int T_RP            = 6,  // Row precharge delay (PRE to ACT)
    parameter int T_RAS           = 14, // Row active time (ACT to PRE)
    parameter int T_CCD_L         = 4,  // Same BG column delay
    parameter int T_CCD_S         = 2,  // Diff BG column delay
    parameter int T_CL            = 8,  // CAS Read Latency
    parameter int ROWPRESS_THRESH_DEFAULT = 5000
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    //-------------------------------------------------------------------------
    // Command Input from slack_aware_arbiter
    //-------------------------------------------------------------------------
    input  logic                                         i_cmd_valid,
    input  logic                                         i_cmd_is_write,
    input  logic [AXI_ID_WIDTH-1:0]                      i_cmd_id,
    input  logic [BG_WIDTH-1:0]                          i_cmd_bg,
    input  logic [BANK_WIDTH-1:0]                        i_cmd_bank,
    input  logic [ROW_WIDTH-1:0]                         i_cmd_row,
    input  logic [COL_WIDTH-1:0]                         i_cmd_col,
    input  logic [AXI_LEN_WIDTH-1:0]                     i_cmd_len,
    input  logic [ROB_PTR_WIDTH-1:0]                     i_cmd_tag,
    input  logic                                         i_cmd_is_mitigation,

    //-------------------------------------------------------------------------
    // RowPress Attack Monitoring & Telemetry Interface
    //-------------------------------------------------------------------------
    input  logic [15:0]                                  cfg_rowpress_thresh,
    output logic                                         o_rowpress_alert,
    output logic [BG_WIDTH-1:0]                          o_rowpress_bg,
    output logic [BANK_WIDTH-1:0]                        o_rowpress_bank,
    output logic [ROW_WIDTH-1:0]                         o_rowpress_row,
    output logic [15:0]                                  o_rowpress_alert_cnt,

    //-------------------------------------------------------------------------
    // Readiness & Slack Telemetry to Arbiter
    //-------------------------------------------------------------------------
    output logic [BG_COUNT-1:0]                          o_bg_ready,
    output logic                                         o_engine_ready,
    output logic                                         o_slack_cycle,

    //-------------------------------------------------------------------------
    // DFI / DRAM Physical Command Interface
    //-------------------------------------------------------------------------
    output logic [2:0]                                   o_dfi_cmd,     // 0=NOP, 1=ACT, 2=PRE, 3=RD, 4=WR, 5=REF
    output logic [BG_WIDTH-1:0]                          o_dfi_bg,
    output logic [BANK_WIDTH-1:0]                        o_dfi_bank,
    output logic [ROW_WIDTH-1:0]                         o_dfi_row,
    output logic [COL_WIDTH-1:0]                         o_dfi_col,

    //-------------------------------------------------------------------------
    // DRAM Read Data Return Path (to reorder_buffer_rob)
    //-------------------------------------------------------------------------
    output logic                                         o_wb_valid,
    output logic [ROB_PTR_WIDTH-1:0]                     o_wb_tag,
    output logic [AXI_DATA_WIDTH-1:0]                    o_wb_data,
    output logic [1:0]                                   o_wb_resp,
    output logic                                         o_wb_last
);

    // DFI Command Encodings
    localparam logic [2:0] CMD_NOP = 3'b000;
    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_PRE = 3'b010;
    localparam logic [2:0] CMD_RD  = 3'b011;
    localparam logic [2:0] CMD_WR  = 3'b100;
    localparam logic [2:0] CMD_REF = 3'b101;

    //=========================================================================
    // Bank State Tracking Table (8 BG x 4 Banks = 32 Banks)
    //=========================================================================
    logic [ROW_WIDTH-1:0] open_row   [BG_COUNT][BANK_COUNT];
    logic                 bank_open  [BG_COUNT][BANK_COUNT];
    logic [4:0]           rcd_timer  [BG_COUNT][BANK_COUNT];
    logic [4:0]           rp_timer   [BG_COUNT][BANK_COUNT];
    logic [4:0]           ras_timer  [BG_COUNT][BANK_COUNT];
    logic [15:0]          act_duration [BG_COUNT][BANK_COUNT];
    wire  [15:0]          effective_rp_thresh = (cfg_rowpress_thresh != 16'd0) ? cfg_rowpress_thresh : 16'(ROWPRESS_THRESH_DEFAULT);

    // Bank-Group level timing
    logic [3:0]           ccd_timer  [BG_COUNT];
    logic [2:0]           ccd_s_timer;

    // Command Pipeline Registers
    logic                 busy;
    logic [2:0]           step_state; // 0=IDLE, 1=WAIT_PRE, 2=ACT, 3=WAIT_RCD, 4=COL_CMD

    // Latched Active Transaction
    logic                 lat_is_write;
    logic [BG_WIDTH-1:0]  lat_bg;
    logic [BANK_WIDTH-1:0]lat_bank;
    logic [ROW_WIDTH-1:0] lat_row;
    logic [COL_WIDTH-1:0] lat_col;
    logic [AXI_LEN_WIDTH-1:0] lat_len;
    logic [ROB_PTR_WIDTH-1:0] lat_tag;
    logic                 lat_is_mitigation;

    // Ready calculations
    always_comb begin
        for (int bg = 0; bg < BG_COUNT; bg++) begin
            o_bg_ready[bg] = (ccd_timer[bg] == '0) && (ccd_s_timer == '0);
        end
    end

    assign o_engine_ready = !busy;
    assign o_slack_cycle  = !busy && (o_dfi_cmd == CMD_NOP);

    //=========================================================================
    // Read Return Latency Simulation Pipeline
    // Shifts read requests through T_CL cycles to emulate DRAM read data return
    //=========================================================================
    localparam int PIPE_DEPTH = 16;
    logic [PIPE_DEPTH-1:0]                      pipe_valid;
    logic [PIPE_DEPTH-1:0][ROB_PTR_WIDTH-1:0]   pipe_tag;
    logic [PIPE_DEPTH-1:0][AXI_LEN_WIDTH-1:0]   pipe_len;
    logic [PIPE_DEPTH-1:0][AXI_DATA_WIDTH-1:0]  pipe_data;
    logic [PIPE_DEPTH-1:0]                      pipe_last;

    // Multi-beat burst generation for read writeback
    logic                 burst_active;
    logic [ROB_PTR_WIDTH-1:0] burst_tag;
    logic [AXI_LEN_WIDTH-1:0] burst_len;
    logic [AXI_LEN_WIDTH-1:0] burst_cnt;
    logic [AXI_DATA_WIDTH-1:0]burst_base_data;

    // Wire outputs to writeback interface
    assign o_wb_valid = burst_active;
    assign o_wb_tag   = burst_tag;
    assign o_wb_data  = burst_base_data + AXI_DATA_WIDTH'(burst_cnt);
    assign o_wb_resp  = 2'b00; // OKAY
    assign o_wb_last  = (burst_cnt == burst_len);

    //=========================================================================
    // Main Timing and Command Sequencer FSM
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy              <= 1'b0;
            step_state        <= '0;
            o_dfi_cmd         <= CMD_NOP;
            o_dfi_bg          <= '0;
            o_dfi_bank        <= '0;
            o_dfi_row         <= '0;
            o_dfi_col         <= '0;

            lat_is_write      <= 1'b0;
            lat_bg            <= '0;
            lat_bank          <= '0;
            lat_row           <= '0;
            lat_col           <= '0;
            lat_len           <= '0;
            lat_tag           <= '0;
            lat_is_mitigation <= 1'b0;

            ccd_s_timer       <= '0;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                ccd_timer[bg] <= '0;
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    bank_open[bg][bk] <= 1'b0;
                    open_row[bg][bk]  <= '0;
                    rcd_timer[bg][bk] <= '0;
                    rp_timer[bg][bk]  <= '0;
                    ras_timer[bg][bk] <= '0;
                end
            end

            pipe_valid        <= '0;
            for (int p = 0; p < PIPE_DEPTH; p++) begin
                pipe_tag[p]   <= '0;
                pipe_len[p]   <= '0;
                pipe_data[p]  <= '0;
                pipe_last[p]  <= 1'b0;
            end

            burst_active      <= 1'b0;
            burst_tag         <= '0;
            burst_len         <= '0;
            burst_cnt         <= '0;
            burst_base_data   <= '0;

            o_rowpress_alert     <= 1'b0;
            o_rowpress_bg        <= '0;
            o_rowpress_bank      <= '0;
            o_rowpress_row       <= '0;
            o_rowpress_alert_cnt <= 16'd0;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    act_duration[bg][bk] <= 16'd0;
                end
            end
        end else begin
            // 1. Decrement timers
            if (ccd_s_timer > '0) ccd_s_timer <= ccd_s_timer - 1'b1;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                if (ccd_timer[bg] > '0) ccd_timer[bg] <= ccd_timer[bg] - 1'b1;
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    if (rcd_timer[bg][bk] > '0) rcd_timer[bg][bk] <= rcd_timer[bg][bk] - 1'b1;
                    if (rp_timer[bg][bk]  > '0) rp_timer[bg][bk]  <= rp_timer[bg][bk] - 1'b1;
                    if (ras_timer[bg][bk] > '0) ras_timer[bg][bk] <= ras_timer[bg][bk] - 1'b1;
                end
            end

            // RowPress Attack Monitoring: track cumulative duration of open banks
            o_rowpress_alert <= 1'b0;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    if (bank_open[bg][bk]) begin
                        if (act_duration[bg][bk] < 16'hFFFF) begin
                            act_duration[bg][bk] <= act_duration[bg][bk] + 1'b1;
                        end
                        if (act_duration[bg][bk] == effective_rp_thresh) begin
                            o_rowpress_alert     <= 1'b1;
                            o_rowpress_bg        <= bg[BG_WIDTH-1:0];
                            o_rowpress_bank      <= bk[BANK_WIDTH-1:0];
                            o_rowpress_row       <= open_row[bg][bk];
                            o_rowpress_alert_cnt <= o_rowpress_alert_cnt + 1'b1;
                        end
                    end else begin
                        act_duration[bg][bk] <= 16'd0;
                    end
                end
            end

            // Default DFI output to NOP each cycle unless driven
            o_dfi_cmd <= CMD_NOP;

            // 2. Shift read latency pipeline (default step)
            for (int p = PIPE_DEPTH-1; p > 0; p--) begin
                pipe_valid[p] <= pipe_valid[p-1];
                pipe_tag[p]   <= pipe_tag[p-1];
                pipe_len[p]   <= pipe_len[p-1];
                pipe_data[p]  <= pipe_data[p-1];
                pipe_last[p]  <= pipe_last[p-1];
            end
            pipe_valid[0] <= 1'b0;

            // 3. Command Sequencer FSM
            if (!busy) begin
                if (i_cmd_valid) begin
                    lat_is_write      <= i_cmd_is_write;
                    lat_bg            <= i_cmd_bg;
                    lat_bank          <= i_cmd_bank;
                    lat_row           <= i_cmd_row;
                    lat_col           <= i_cmd_col;
                    lat_len           <= i_cmd_len;
                    lat_tag           <= i_cmd_tag;
                    lat_is_mitigation <= i_cmd_is_mitigation;

                    if (i_cmd_is_mitigation) begin
                        // Mitigation command: execute targeted precharge & activate
                        o_dfi_cmd         <= CMD_REF;
                        o_dfi_bg          <= i_cmd_bg;
                        o_dfi_bank        <= i_cmd_bank;
                        o_dfi_row         <= i_cmd_row;
                        busy              <= 1'b0;
                    end else if (bank_open[i_cmd_bg][i_cmd_bank] && (open_row[i_cmd_bg][i_cmd_bank] == i_cmd_row)) begin
                        // ROW HIT: Bank is already open to desired row!
                        // Issue RD/WR immediately if CCD timers expired
                        o_dfi_cmd         <= i_cmd_is_write ? CMD_WR : CMD_RD;
                        o_dfi_bg          <= i_cmd_bg;
                        o_dfi_bank        <= i_cmd_bank;
                        o_dfi_row         <= i_cmd_row;
                        o_dfi_col         <= i_cmd_col;
                        ccd_timer[i_cmd_bg] <= 4'(T_CCD_L);
                        ccd_s_timer         <= 3'(T_CCD_S);

                        // If read, start latency shift pipe
                        if (!i_cmd_is_write) begin
                            pipe_valid[0] <= 1'b1;
                            pipe_tag[0]   <= i_cmd_tag;
                            pipe_len[0]   <= i_cmd_len;
                            pipe_data[0]  <= {32'hAAAA_0000, 16'h0000, i_cmd_row[15:0]};
                            pipe_last[0]  <= 1'b1;
                        end
                        busy <= 1'b0;
                    end else if (bank_open[i_cmd_bg][i_cmd_bank]) begin
                        // ROW CONFLICT: Different row open, must PRE then ACT then CAS
                        busy              <= 1'b1;
                        step_state        <= 3'd1; // Issue PRE
                        o_dfi_cmd         <= CMD_PRE;
                        o_dfi_bg          <= i_cmd_bg;
                        o_dfi_bank        <= i_cmd_bank;
                        bank_open[i_cmd_bg][i_cmd_bank] <= 1'b0;
                        rp_timer[i_cmd_bg][i_cmd_bank]  <= 5'(T_RP);
                    end else begin
                        // ROW MISS: Bank closed, issue ACT then CAS
                        busy              <= 1'b1;
                        step_state        <= 3'd3; // Wait for RCD after ACT
                        o_dfi_cmd         <= CMD_ACT;
                        o_dfi_bg          <= i_cmd_bg;
                        o_dfi_bank        <= i_cmd_bank;
                        o_dfi_row         <= i_cmd_row;
                        bank_open[i_cmd_bg][i_cmd_bank] <= 1'b1;
                        open_row[i_cmd_bg][i_cmd_bank]  <= i_cmd_row;
                        rcd_timer[i_cmd_bg][i_cmd_bank] <= 5'(T_RCD);
                        ras_timer[i_cmd_bg][i_cmd_bank] <= 5'(T_RAS);
                    end
                end
            end else begin
                // FSM multi-cycle progression
                case (step_state)
                    3'd1: begin // Wait for RP then ACT
                        if (rp_timer[lat_bg][lat_bank] == '0) begin
                            o_dfi_cmd         <= CMD_ACT;
                            o_dfi_bg          <= lat_bg;
                            o_dfi_bank        <= lat_bank;
                            o_dfi_row         <= lat_row;
                            bank_open[lat_bg][lat_bank] <= 1'b1;
                            open_row[lat_bg][lat_bank]  <= lat_row;
                            rcd_timer[lat_bg][lat_bank] <= 5'(T_RCD);
                            ras_timer[lat_bg][lat_bank] <= 5'(T_RAS);
                            step_state        <= 3'd3;
                        end
                    end

                    3'd3: begin // Wait for RCD then RD/WR
                        if (rcd_timer[lat_bg][lat_bank] == '0 && ccd_timer[lat_bg] == '0) begin
                            o_dfi_cmd         <= lat_is_write ? CMD_WR : CMD_RD;
                            o_dfi_bg          <= lat_bg;
                            o_dfi_bank        <= lat_bank;
                            o_dfi_row         <= lat_row;
                            o_dfi_col         <= lat_col;
                            ccd_timer[lat_bg] <= 4'(T_CCD_L);
                            ccd_s_timer       <= 3'(T_CCD_S);

                            if (!lat_is_write) begin
                                pipe_valid[0] <= 1'b1;
                                pipe_tag[0]   <= lat_tag;
                                pipe_len[0]   <= lat_len;
                                pipe_data[0]  <= {32'hAAAA_0000, 16'h0000, lat_row[15:0]};
                                pipe_last[0]  <= 1'b1;
                            end

                            busy       <= 1'b0;
                            step_state <= 3'd0;
                        end
                    end

                    default: begin
                        busy       <= 1'b0;
                        step_state <= 3'd0;
                    end
                endcase
            end

            // 4. Handle Read Writeback Burst Generator
            if (!burst_active) begin
                if (pipe_valid[T_CL-1]) begin
                    burst_active    <= 1'b1;
                    burst_tag       <= pipe_tag[T_CL-1];
                    burst_len       <= pipe_len[T_CL-1];
                    burst_cnt       <= '0;
                    burst_base_data <= pipe_data[T_CL-1];
                end
            end else begin
                if (burst_cnt == burst_len) begin
                    burst_active <= 1'b0;
                    burst_cnt    <= '0;
                end else begin
                    burst_cnt    <= burst_cnt + 1'b1;
                end
            end
        end
    end

    // Unused input signals sink
    logic _unused_sink;
    assign _unused_sink = &{1'b0, i_cmd_id, pipe_last[PIPE_DEPTH-1], lat_is_mitigation, 1'b0};

endmodule
