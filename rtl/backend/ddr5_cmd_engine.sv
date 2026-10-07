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
    input  logic [1:0]                                   cfg_rowpress_curve = 2'b00, // 0: Static, 1: Conservative, 2: Standard, 3: Aggressive
    input  logic [15:0]                                  cfg_tras_max_thresh = 16'd28000, // 70us clamping at 400MHz
    output logic                                         o_rowpress_alert,
    output logic [BG_WIDTH-1:0]                          o_rowpress_bg,
    output logic [BANK_WIDTH-1:0]                        o_rowpress_bank,
    output logic [ROW_WIDTH-1:0]                         o_rowpress_row,
    output logic [15:0]                                  o_rowpress_alert_cnt,
    output logic                                         o_tras_clamped_alert,
    output logic [15:0]                                  o_tras_clamped_cnt,

    //-------------------------------------------------------------------------
    // JEDEC PRAC / QPRAC Alert-Back-Off (ABO) Physical Handshake Interface
    //-------------------------------------------------------------------------
    input  logic                                         i_dram_abo_alert = 1'b0,
    output logic                                         o_abo_active,
    output logic [15:0]                                  o_abo_alert_cnt,
    output logic [BG_WIDTH-1:0]                          o_abo_bg,
    output logic [BANK_WIDTH-1:0]                        o_abo_bank,
    output logic [ROW_WIDTH-1:0]                         o_abo_row,

    //-------------------------------------------------------------------------
    // Autonomous JEDEC DDR5 RFM Generator Interface (McSee Finding Defense)
    //-------------------------------------------------------------------------
    input  logic [7:0]                                   cfg_raammt_thresh = 8'd32,
    output logic [15:0]                                  o_rfm_auto_cnt,
    output logic                                         o_rfm_active,

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

    // RowPress Non-Linear Dynamic Threshold Function (ISCA'23 & Chronus HPCA'25 model)
    function automatic logic [15:0] calc_dyn_rowpress_thresh(
        input logic [15:0] base_th,
        input logic [1:0]  curve,
        input logic [15:0] duration
    );
        logic [15:0] th;
        case (curve)
            2'b00: th = base_th; // 0: Static Baseline
            2'b01: begin // 1: Conservative Decay (75% -> 50% -> 25%)
                if (duration > 16'd4000)      th = (base_th >> 2);
                else if (duration > 16'd2000) th = (base_th >> 1);
                else if (duration > 16'd1000) th = base_th - (base_th >> 2);
                else                          th = base_th;
            end
            2'b10: begin // 2: Standard Decay (Chronus HPCA'25 Industrial Model)
                if (duration > 16'd3000)      th = (base_th >> 3);
                else if (duration > 16'd1500) th = (base_th >> 2);
                else if (duration > 16'd800)  th = (base_th >> 1);
                else if (duration > 16'd400)  th = base_th - (base_th >> 2);
                else                          th = base_th;
            end
            2'b11: begin // 3: Aggressive High-Duty Cycle (Sub-10nm DRAM Model)
                if (duration > 16'd2000)      th = 16'd128;
                else if (duration > 16'd1000) th = (base_th >> 3);
                else if (duration > 16'd500)  th = (base_th >> 2);
                else if (duration > 16'd200)  th = (base_th >> 1);
                else                          th = base_th;
            end
            default: th = base_th;
        endcase
        if (base_th < 16'd64)
            calc_dyn_rowpress_thresh = th;
        else if (th < 16'd64)
            calc_dyn_rowpress_thresh = 16'd64;
        else
            calc_dyn_rowpress_thresh = th;
    endfunction

    // PRAC / QPRAC Alert-Back-Off (ABO) Edge Detector & State
    logic                 dram_abo_d;

    // McSee Defense: Autonomous Rolling ACT counters and RFM requests
    logic [7:0]           rolling_act_cnt [BG_COUNT];
    logic [BG_COUNT-1:0]  rfm_req;

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

    assign o_engine_ready = !busy && !o_abo_active && !i_dram_abo_alert;
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

            o_tras_clamped_alert <= 1'b0;
            o_tras_clamped_cnt   <= 16'd0;
            o_rfm_auto_cnt       <= 16'd0;
            o_rfm_active         <= 1'b0;
            rfm_req              <= '0;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                rolling_act_cnt[bg] <= 8'd0;
            end

            dram_abo_d           <= 1'b0;
            o_abo_active         <= 1'b0;
            o_abo_alert_cnt      <= 16'd0;
            o_abo_bg             <= '0;
            o_abo_bank           <= '0;
            o_abo_row            <= '0;

            for (int bg = 0; bg < BG_COUNT; bg++) begin
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    act_duration[bg][bk] <= 16'd0;
                end
            end
        end else begin
            o_tras_clamped_alert <= 1'b0;
            o_rfm_active         <= 1'b0;

            // Track rolling ACT count for autonomous RFM (McSee defense)
            if (o_dfi_cmd == CMD_ACT) begin
                if (rolling_act_cnt[o_dfi_bg] < 8'hFF) begin
                    rolling_act_cnt[o_dfi_bg] <= rolling_act_cnt[o_dfi_bg] + 1'b1;
                    if (rolling_act_cnt[o_dfi_bg] + 1'b1 >= (cfg_raammt_thresh != 8'd0 ? cfg_raammt_thresh : 8'd32)) begin
                        rfm_req[o_dfi_bg] <= 1'b1;
                    end
                end
            end
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

            // PRAC / QPRAC Alert-Back-Off (ABO) Handshake Processing
            dram_abo_d <= i_dram_abo_alert;
            if (i_dram_abo_alert && !dram_abo_d) begin
                o_abo_active    <= 1'b1;
                o_abo_alert_cnt <= o_abo_alert_cnt + 1'b1;
                o_abo_bg        <= lat_bg;
                o_abo_bank      <= lat_bank;
                o_abo_row       <= (bank_open[lat_bg][lat_bank]) ? open_row[lat_bg][lat_bank] : lat_row;
            end else if (!i_dram_abo_alert) begin
                o_abo_active    <= 1'b0;
            end

            // RowPress Attack Monitoring: track cumulative duration of open banks with dynamic LUT
            o_rowpress_alert <= 1'b0;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    if (bank_open[bg][bk]) begin
                        logic [15:0] current_dyn_thresh;
                        current_dyn_thresh = calc_dyn_rowpress_thresh(effective_rp_thresh, cfg_rowpress_curve, act_duration[bg][bk]);
                        if (act_duration[bg][bk] < 16'hFFFF) begin
                            act_duration[bg][bk] <= act_duration[bg][bk] + 1'b1;
                        end
                        if (act_duration[bg][bk] == current_dyn_thresh) begin
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
            if (!busy && (!o_abo_active && !i_dram_abo_alert || i_cmd_is_mitigation)) begin
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
                        // ROW MISS: Bank closed, issue ACT then CAS (respecting tRP recovery if still active)
                        if (rp_timer[i_cmd_bg][i_cmd_bank] > '0) begin
                            busy       <= 1'b1;
                            step_state <= 3'd1; // Wait for RP then ACT
                        end else begin
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
                    // Idle / Slack cycle: check RowPress tRAS_max auto-precharge clamping and autonomous RFM
                    logic                  found_clamp;
                    logic [BG_WIDTH-1:0]   clamp_target_bg;
                    logic [BANK_WIDTH-1:0] clamp_target_bank;
                    logic                  found_rfm;
                    logic [BG_WIDTH-1:0]   rfm_target_bg;

                    found_clamp       = 1'b0;
                    clamp_target_bg   = '0;
                    clamp_target_bank = '0;
                    found_rfm         = 1'b0;
                    rfm_target_bg     = '0;

                    if (cfg_tras_max_thresh != 16'd0) begin
                        for (int bg = 0; bg < BG_COUNT; bg++) begin
                            for (int bk = 0; bk < BANK_COUNT; bk++) begin
                                if (bank_open[bg][bk] && (act_duration[bg][bk] >= cfg_tras_max_thresh) && !found_clamp) begin
                                    found_clamp       = 1'b1;
                                    clamp_target_bg   = bg[BG_WIDTH-1:0];
                                    clamp_target_bank = bk[BANK_WIDTH-1:0];
                                end
                            end
                        end
                    end

                    for (int bg = 0; bg < BG_COUNT; bg++) begin
                        if (rfm_req[bg] && !found_rfm) begin
                            found_rfm     = 1'b1;
                            rfm_target_bg = bg[BG_WIDTH-1:0];
                        end
                    end

                    if (found_clamp) begin
                        o_dfi_cmd                                        <= CMD_PRE;
                        o_dfi_bg                                         <= clamp_target_bg;
                        o_dfi_bank                                       <= clamp_target_bank;
                        bank_open[clamp_target_bg][clamp_target_bank]    <= 1'b0;
                        rp_timer[clamp_target_bg][clamp_target_bank]     <= 5'(T_RP);
                        act_duration[clamp_target_bg][clamp_target_bank] <= 16'd0;
                        o_tras_clamped_alert                             <= 1'b1;
                        o_tras_clamped_cnt                               <= o_tras_clamped_cnt + 1'b1;
                    end else if (found_rfm) begin
                        o_dfi_cmd                      <= CMD_REF;
                        o_dfi_bg                       <= rfm_target_bg;
                        o_dfi_bank                     <= '0;
                        rfm_req[rfm_target_bg]         <= 1'b0;
                        rolling_act_cnt[rfm_target_bg] <= 8'd0;
                        o_rfm_auto_cnt                 <= o_rfm_auto_cnt + 1'b1;
                        o_rfm_active                   <= 1'b1;
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

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
        if ($past(rst_n))  assume (rst_n);
    end

    // 1. Trạng thái sau reset: Engine sẵn sàng, không phát xung lệnh DFI
    always_comb begin
        if (!rst_n) begin
            assert (!busy);
            if (!i_dram_abo_alert) assert (o_engine_ready);
            assert (o_dfi_cmd == CMD_NOP);
            assert (!o_rowpress_alert);
        end
    end

    // 2. Tính toàn vẹn lệnh DFI: Khi phát lệnh RD/WR, Bank mục tiêu bắt buộc phải đang mở và đúng hàng
    always_comb begin
        if (rst_n) begin
            if (o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR) begin
                assert (bank_open[o_dfi_bg][o_dfi_bank]);
                assert (open_row[o_dfi_bg][o_dfi_bank] == o_dfi_row);
            end
        end
    end

    // 3. Tuân thủ định thời JEDEC tRCD và tCCD: Khi phát lệnh RD/WR, bộ đếm tCCD_L và tCCD_S được nạp đúng thông số JEDEC
    always_comb begin
        if (rst_n) begin
            if (o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR) begin
                assert (ccd_timer[o_dfi_bg] == 4'(T_CCD_L));
                assert (ccd_s_timer == 3'(T_CCD_S));
            end
        end
    end

    // 4. Tuân thủ định thời JEDEC tRP và tRCD: Khi ACT được nạp tRCD, khi PRE được nạp tRP
    always_comb begin
        if (rst_n) begin
            if (o_dfi_cmd == CMD_ACT) begin
                assert (rcd_timer[o_dfi_bg][o_dfi_bank] == 5'(T_RCD));
            end
            if (o_dfi_cmd == CMD_PRE) begin
                assert (rp_timer[o_dfi_bg][o_dfi_bank] == 5'(T_RP));
            end
        end
    end

    // 5. Chuyển trạng thái Bank: Sau ACT bank mở, sau PRE bank đóng
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(o_dfi_cmd == CMD_ACT)) begin
                assert (bank_open[$past(o_dfi_bg)][$past(o_dfi_bank)]);
                assert (open_row[$past(o_dfi_bg)][$past(o_dfi_bank)] == $past(o_dfi_row));
            end
            if ($past(o_dfi_cmd == CMD_PRE)) begin
                assert (!bank_open[$past(o_dfi_bg)][$past(o_dfi_bank)]);
            end
        end
    end

    // 6. Chống Deadlock FSM: step_state luôn nằm trong các trạng thái hợp lệ
    always_comb begin
        if (rst_n) begin
            assert (step_state == 3'd0 || step_state == 3'd1 || step_state == 3'd3);
            if (!busy) begin
                assert (step_state == 3'd0);
            end
        end
    end

    // 7. PRAC / QPRAC Alert-Back-Off: Khi co tin hieu alert, o_abo_active duoc kich hoat tuc thoi
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(i_dram_abo_alert && !dram_abo_d)) begin
                assert (o_abo_active);
            end
        end
    end

    // 8. RowPress Dynamic LUT Bounds: dynamic threshold luon >= 64 khi base >= 64
    always_comb begin
        if (rst_n) begin
            if (effective_rp_thresh >= 16'd64) begin
                assert (calc_dyn_rowpress_thresh(effective_rp_thresh, cfg_rowpress_curve, 16'd5000) >= 16'd64);
            end
        end
    end

    // Cover properties đo lường khả năng kích hoạt toàn bộ tập lệnh DFI
    always_ff @(posedge clk) begin
        cover (o_dfi_cmd == CMD_ACT);
        cover (o_dfi_cmd == CMD_PRE);
        cover (o_dfi_cmd == CMD_RD);
        cover (o_dfi_cmd == CMD_WR);
        cover (o_dfi_cmd == CMD_REF);
        cover (o_rowpress_alert);
        cover (o_slack_cycle);
        cover (o_abo_active);
    end
`endif

endmodule
