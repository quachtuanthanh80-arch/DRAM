//=============================================================================
// File:        adaptive_threshold_engine.sv
// Chức năng:   Động cơ lọc số EWMA tự thích ứng điều chỉnh ngưỡng kích hoạt động ATE theo tải thực tế.
//=============================================================================
`timescale 1ns / 1ps

module adaptive_threshold_engine #(
    parameter int COUNT_WIDTH    = 16,
    parameter int ALPHA_SHIFT_DEF = 4,   // EWMA factor alpha = 1 / 16
    parameter int WINDOW_CYCLES  = 1024 // Periodic sampling window
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Configuration
    input  logic                   cfg_ate_en,
    input  logic [3:0]             cfg_alpha_shift,
    input  logic [COUNT_WIDTH-1:0] cfg_base_thresh,
    input  logic [COUNT_WIDTH-1:0] cfg_max_thresh,

    // Real-Time Telemetry from SDC Filter
    input  logic [31:0]            i_telemetry_accesses,
    input  logic [31:0]            i_telemetry_throttles,

    // Dynamic Threshold Output to SDC Filter
    output logic [COUNT_WIDTH-1:0] o_dynamic_thresh,
    output logic [15:0]            o_sample_epochs
);

    // Internal Registers
    logic [COUNT_WIDTH-1:0] dynamic_thresh_reg;
    logic [15:0]            epoch_counter;
    logic [15:0]            window_timer;

    // Previous telemetry snapshot for delta calculation
    logic [31:0] prev_accesses;
    logic [31:0] prev_throttles;

    wire [3:0] alpha_shift = (cfg_alpha_shift != 4'd0) ? cfg_alpha_shift : 4'(ALPHA_SHIFT_DEF);
    wire [COUNT_WIDTH-1:0] base_thresh = (cfg_base_thresh != '0) ? cfg_base_thresh : 16'd2048;
    wire [COUNT_WIDTH-1:0] max_thresh  = (cfg_max_thresh != '0)  ? cfg_max_thresh  : 16'd8192;

    assign o_dynamic_thresh = (cfg_ate_en && (epoch_counter != 16'd0)) ? dynamic_thresh_reg : base_thresh;
    assign o_sample_epochs  = epoch_counter;

    localparam int WINDOW_LIMIT = WINDOW_CYCLES - 1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dynamic_thresh_reg <= 16'd2048;
            epoch_counter      <= 16'd0;
            window_timer       <= 16'd0;
            prev_accesses      <= 32'd0;
            prev_throttles     <= 32'd0;
        end else begin
            if (!cfg_ate_en) begin
                dynamic_thresh_reg <= base_thresh;
                epoch_counter      <= 16'd0;
                window_timer       <= 16'd0;
                prev_accesses      <= i_telemetry_accesses;
                prev_throttles     <= i_telemetry_throttles;
            end else begin
                if (int'(window_timer) >= WINDOW_LIMIT) begin
                    // Sample Epoch Triggered
                    logic [31:0] delta_access;
                    logic [31:0] delta_thrtl;
                    logic [COUNT_WIDTH-1:0] curr_thresh;
                    logic [COUNT_WIDTH-1:0] step_up;
                    logic [COUNT_WIDTH-1:0] step_dn;

                    delta_access = i_telemetry_accesses - prev_accesses;
                    delta_thrtl  = i_telemetry_throttles - prev_throttles;

                    prev_accesses  <= i_telemetry_accesses;
                    prev_throttles <= i_telemetry_throttles;
                    window_timer   <= 16'd0;
                    epoch_counter  <= epoch_counter + 1'b1;

                    // Reference threshold for this epoch's adaptation
                    curr_thresh = (epoch_counter == 16'd0) ? base_thresh : dynamic_thresh_reg;

                    // EWMA step calculations
                    step_up = (max_thresh - curr_thresh) >> alpha_shift;
                    step_dn = (curr_thresh - base_thresh) >> alpha_shift;
                    if (step_up == '0) step_up = 16'd1;
                    if (step_dn == '0) step_dn = 16'd1;

                    // If throttle rate > 3.125% (delta_thrtl > delta_access >> 5) and >= 4 throttles:
                    // Relax threshold (increase)
                    if ((delta_thrtl > (delta_access >> 5)) && (delta_thrtl >= 32'd4)) begin
                        if ((curr_thresh + step_up) <= max_thresh) begin
                            dynamic_thresh_reg <= curr_thresh + step_up;
                        end else begin
                            dynamic_thresh_reg <= max_thresh;
                        end
                    end
                    // Otherwise, if throttles are negligible: tighten threshold towards baseline
                    else if (delta_thrtl <= 32'd2) begin
                        if (curr_thresh > (base_thresh + step_dn)) begin
                            dynamic_thresh_reg <= curr_thresh - step_dn;
                        end else begin
                            dynamic_thresh_reg <= base_thresh;
                        end
                    end else begin
                        dynamic_thresh_reg <= curr_thresh;
                    end
                end else begin
                    window_timer <= window_timer + 1'b1;
                    if (epoch_counter == 16'd0) begin
                        dynamic_thresh_reg <= base_thresh;
                    end
                end
            end
        end
    end

endmodule: adaptive_threshold_engine
