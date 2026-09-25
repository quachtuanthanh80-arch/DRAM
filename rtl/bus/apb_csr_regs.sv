//=============================================================================
// File:        apb_csr_regs.sv
// Chức năng:   Khối thanh ghi APB4 CSR điều khiển cấu hình an toàn, khóa bảo mật và thu thập số liệu đo xa.
//=============================================================================
`timescale 1ns / 1ps

module apb_csr_regs #(
    parameter int AddrWidth = 12,
    parameter int DataWidth = 32
)(
    input  logic                 pclk,
    input  logic                 presetn,

    // APB4 Slave Interface
    input  logic [AddrWidth-1:0] paddr,
    input  logic                 psel,
    input  logic                 penable,
    input  logic                 pwrite,
    input  logic [DataWidth-1:0] pwdata,
    input  logic [3:0]           pstrb,
    input  logic [2:0]           pprot,
    output logic                 pready,
    output logic [DataWidth-1:0] prdata,
    output logic                 pslverr,

    // Core Control & Security Outputs
    output logic                 enc_enable,
    output logic                 soft_reset,
    output logic                 perf_cnt_en,
    output logic                 auto_tweak_en,
    output logic                 sec_locked,
    output logic [255:0]         key1_data,    // K1: 256-bit AES Cipher Key
    output logic [255:0]         key2_data,    // K2: 256-bit AES Tweak Key
    output logic                 keys_valid,

    // Core Status Inputs
    input  logic                 pipe_busy,
    input  logic [7:0]           core_status_flags,
    input  logic                 block_encrypted_pulse, // Pulse when 1 block passes pipe
    input  logic                 pipeline_stall_active, // High when pipe is stalled

    // SDC & Security Configuration Outputs
    output logic [15:0]          cfg_sdc_thresh,
    output logic [15:0]          cfg_window_size,
    output logic [15:0]          cfg_scrub_interval,
    output logic [15:0]          cfg_rowpress_thresh,
    output logic                 cfg_drm_en,
    output logic                 cfg_drm_victim2_en,
    output logic                 cfg_ate_en,
    output logic [3:0]           cfg_ate_alpha_shift,

    // Hardware Telemetry Inputs
    input  logic [31:0]          telem_accesses,
    input  logic [31:0]          telem_throttles,
    input  logic [15:0]          ecc_single_err_cnt,
    input  logic [15:0]          ecc_double_err_cnt,
    input  logic [15:0]          rowpress_alert_cnt,
    input  logic [15:0]          ate_dynamic_thresh
);

    // Register Address Offsets
    localparam logic [AddrWidth-1:0] AddrCtrl           = 12'h000;
    localparam logic [AddrWidth-1:0] AddrStatus         = 12'h004;
    localparam logic [AddrWidth-1:0] AddrSecLock       = 12'h008;
    localparam logic [AddrWidth-1:0] AddrKey1Base      = 12'h010; // 0x010 .. 0x02C (8 regs)
    localparam logic [AddrWidth-1:0] AddrKey2Base      = 12'h030; // 0x030 .. 0x04C (8 regs)
    localparam logic [AddrWidth-1:0] AddrPerfCycles    = 12'h060;
    localparam logic [AddrWidth-1:0] AddrPerfBlocks    = 12'h064;
    localparam logic [AddrWidth-1:0] AddrPerfStalls    = 12'h068;
    localparam logic [AddrWidth-1:0] AddrSdcThresh     = 12'h070;
    localparam logic [AddrWidth-1:0] AddrWindowSize    = 12'h074;
    localparam logic [AddrWidth-1:0] AddrScrubInterval = 12'h078;
    localparam logic [AddrWidth-1:0] AddrRowPressThresh= 12'h07C;
    localparam logic [AddrWidth-1:0] AddrDrmConfig     = 12'h080;
    localparam logic [AddrWidth-1:0] AddrAteConfig     = 12'h084;
    localparam logic [AddrWidth-1:0] AddrTelemAccess   = 12'h090;
    localparam logic [AddrWidth-1:0] AddrTelemThrtl    = 12'h094;
    localparam logic [AddrWidth-1:0] AddrEccSingle     = 12'h098;
    localparam logic [AddrWidth-1:0] AddrEccDouble     = 12'h09C;
    localparam logic [AddrWidth-1:0] AddrRowPressAlert = 12'h0A0;
    localparam logic [AddrWidth-1:0] AddrAteDynThresh  = 12'h0A4;
    localparam logic [AddrWidth-1:0] AddrVersionId     = 12'h0FC;

    // Security Lock Magic Value
    localparam logic [31:0] SecLockMagic = 32'hA55A_0001;

    // Internal Registers
    logic [31:0] reg_ctrl;
    logic        reg_sec_locked;
    logic [31:0] reg_key1 [8];
    logic [31:0] reg_key2 [8];
    logic [7:0]  key1_loaded_mask;
    logic [7:0]  key2_loaded_mask;

    // SDC, DRM, ATE & Security Control Registers
    logic [31:0] reg_sdc_thresh;
    logic [31:0] reg_window_size;
    logic [31:0] reg_scrub_interval;
    logic [31:0] reg_rowpress_thresh;
    logic [31:0] reg_drm_config;
    logic [31:0] reg_ate_config;

    // Performance Counters
    logic [31:0] perf_cycles;
    logic [31:0] perf_blocks;
    logic [31:0] perf_stalls;

    // APB Protocol Decoding
    logic apb_write_req;
    logic apb_read_req;

    assign apb_write_req = psel && penable && pwrite;
    assign apb_read_req  = psel && !pwrite; // Can evaluate during setup or access phase
    assign pready        = 1'b1;            // Zero-wait-state APB slave
    assign pslverr       = 1'b0;            // Always succeed on valid map

    // Drive Core Control Signals
    assign enc_enable    = reg_ctrl[0];
    assign soft_reset    = reg_ctrl[1];
    assign perf_cnt_en   = reg_ctrl[2];
    assign auto_tweak_en = reg_ctrl[3];
    assign sec_locked    = reg_sec_locked;

    // Drive SDC & Security Configuration Outputs
    assign cfg_sdc_thresh      = reg_sdc_thresh[15:0];
    assign cfg_window_size     = reg_window_size[15:0];
    assign cfg_scrub_interval  = reg_scrub_interval[15:0];
    assign cfg_rowpress_thresh = reg_rowpress_thresh[15:0];
    assign cfg_drm_en          = reg_drm_config[0];
    assign cfg_drm_victim2_en  = reg_drm_config[1];
    assign cfg_ate_en          = reg_ate_config[0];
    assign cfg_ate_alpha_shift = reg_ate_config[7:4];

    assign keys_valid    = (&key1_loaded_mask) && (&key2_loaded_mask);

    // Concatenate 32-bit registers into 256-bit keys (Big-Endian word layout)
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            key1_data[(7-i)*32 +: 32] = reg_key1[i];
            key2_data[(7-i)*32 +: 32] = reg_key2[i];
        end
    end

    // Byte strobe helper function
    function automatic logic [31:0] apply_strb(
        input logic [31:0] orig_val,
        input logic [31:0] new_val,
        input logic [3:0]  strobe
    );
        logic [31:0] res;
        res[ 7: 0] = strobe[0] ? new_val[ 7: 0] : orig_val[ 7: 0];
        res[15: 8] = strobe[1] ? new_val[15: 8] : orig_val[15: 8];
        res[23:16] = strobe[2] ? new_val[23:16] : orig_val[23:16];
        res[31:24] = strobe[3] ? new_val[31:24] : orig_val[31:24];
        return res;
    endfunction

    // Key index wires derived from paddr
    logic [2:0] key1_idx;
    logic [2:0] key2_idx;
    assign key1_idx = 3'((paddr - AddrKey1Base) >> 2);
    assign key2_idx = 3'((paddr - AddrKey2Base) >> 2);

    // APB Write Register Process
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_ctrl            <= 32'h0000_0009; // Default: enc_enable=1, auto_tweak_en=1
            reg_sec_locked      <= 1'b0;
            key1_loaded_mask    <= 8'h00;
            key2_loaded_mask    <= 8'h00;
            reg_sdc_thresh      <= 32'd2048;
            reg_window_size     <= 32'd3900;
            reg_scrub_interval  <= 32'd1000;
            reg_rowpress_thresh <= 32'd5000;
            reg_drm_config      <= 32'h0000_0003; // Default: drm_en=1, victim2_en=1
            reg_ate_config      <= 32'h0000_0041; // Default: ate_en=1, alpha_shift=4
            for (int i = 0; i < 8; i++) begin
                reg_key1[i] <= 32'h0;
                reg_key2[i] <= 32'h0;
            end
        end else begin
            // Soft reset auto-clearing
            if (reg_ctrl[1]) begin
                reg_ctrl[1] <= 1'b0;
            end

            if (apb_write_req) begin
                case (paddr)
                    AddrCtrl: begin
                        reg_ctrl <= apply_strb(reg_ctrl, pwdata, pstrb);
                    end

                    AddrSecLock: begin
                        if (pwdata == SecLockMagic) begin
                            reg_sec_locked <= 1'b1;
                        end
                    end

                    AddrSdcThresh: begin
                        reg_sdc_thresh <= apply_strb(reg_sdc_thresh, pwdata, pstrb);
                    end

                    AddrWindowSize: begin
                        reg_window_size <= apply_strb(reg_window_size, pwdata, pstrb);
                    end

                    AddrScrubInterval: begin
                        reg_scrub_interval <= apply_strb(reg_scrub_interval, pwdata, pstrb);
                    end

                    AddrRowPressThresh: begin
                        reg_rowpress_thresh <= apply_strb(reg_rowpress_thresh, pwdata, pstrb);
                    end

                    AddrDrmConfig: begin
                        reg_drm_config <= apply_strb(reg_drm_config, pwdata, pstrb);
                    end

                    AddrAteConfig: begin
                        reg_ate_config <= apply_strb(reg_ate_config, pwdata, pstrb);
                    end

                    default: begin
                        // Key 1 registers (0x010 - 0x02C)
                        if (paddr >= AddrKey1Base && paddr <= 12'h02C) begin
                            if (!reg_sec_locked) begin
                                reg_key1[key1_idx] <= apply_strb(reg_key1[key1_idx], pwdata, pstrb);
                                key1_loaded_mask[key1_idx] <= 1'b1;
                            end
                        end
                        // Key 2 registers (0x030 - 0x04C)
                        else if (paddr >= AddrKey2Base && paddr <= 12'h04C) begin
                            if (!reg_sec_locked) begin
                                reg_key2[key2_idx] <= apply_strb(reg_key2[key2_idx], pwdata, pstrb);
                                key2_loaded_mask[key2_idx] <= 1'b1;
                            end
                        end
                    end
                endcase
            end
        end
    end

    // APB Read Multiplexer
    always_comb begin
        prdata = 32'h0;
        case (paddr)
            AddrCtrl: begin
                prdata = reg_ctrl;
            end

            AddrStatus: begin
                prdata = {
                    24'h0,
                    core_status_flags[3:0],
                    keys_valid,
                    reg_sec_locked,
                    perf_cnt_en,
                    pipe_busy
                };
            end

            AddrSecLock: begin
                prdata = {31'h0, reg_sec_locked};
            end

            AddrPerfCycles: begin
                prdata = perf_cycles;
            end

            AddrPerfBlocks: begin
                prdata = perf_blocks;
            end

            AddrPerfStalls: begin
                prdata = perf_stalls;
            end

            AddrSdcThresh: begin
                prdata = reg_sdc_thresh;
            end

            AddrWindowSize: begin
                prdata = reg_window_size;
            end

            AddrScrubInterval: begin
                prdata = reg_scrub_interval;
            end

            AddrRowPressThresh: begin
                prdata = reg_rowpress_thresh;
            end

            AddrDrmConfig: begin
                prdata = reg_drm_config;
            end

            AddrAteConfig: begin
                prdata = reg_ate_config;
            end

            AddrTelemAccess: begin
                prdata = telem_accesses;
            end

            AddrTelemThrtl: begin
                prdata = telem_throttles;
            end

            AddrEccSingle: begin
                prdata = {16'h0, ecc_single_err_cnt};
            end

            AddrEccDouble: begin
                prdata = {16'h0, ecc_double_err_cnt};
            end

            AddrRowPressAlert: begin
                prdata = {16'h0, rowpress_alert_cnt};
            end

            AddrAteDynThresh: begin
                prdata = {16'h0, ate_dynamic_thresh};
            end

            AddrVersionId: begin
                prdata = 32'h5153_4844; // ASCII "QSHD"
            end

            default: begin
                // Read Key 1: If locked, return 32'h0 for tamper/DPA defense!
                if (paddr >= AddrKey1Base && paddr <= 12'h02C) begin
                    prdata = reg_sec_locked ? 32'h0 : reg_key1[key1_idx];
                end
                // Read Key 2: If locked, return 32'h0
                else if (paddr >= AddrKey2Base && paddr <= 12'h04C) begin
                    prdata = reg_sec_locked ? 32'h0 : reg_key2[key2_idx];
                end else begin
                    prdata = 32'hDEAD_BEEF; // Unmapped address
                end
            end
        endcase
    end

    // Hardware Telemetry Performance Counters
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            perf_cycles <= 32'h0;
            perf_blocks <= 32'h0;
            perf_stalls <= 32'h0;
        end else begin
            if (reg_ctrl[1]) begin // Soft reset clears counters
                perf_cycles <= 32'h0;
                perf_blocks <= 32'h0;
                perf_stalls <= 32'h0;
            end else if (perf_cnt_en) begin
                perf_cycles <= perf_cycles + 32'd1;

                if (block_encrypted_pulse) begin
                    perf_blocks <= perf_blocks + 32'd1;
                end

                if (pipeline_stall_active) begin
                    perf_stalls <= perf_stalls + 32'd1;
                end
            end
        end
    end

    // Lint unused signal sink
    logic _unused_apb;
    assign _unused_apb = &{pprot, apb_read_req, core_status_flags[7:4], 1'b0};

endmodule: apb_csr_regs
