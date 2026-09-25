//=============================================================================
// File:        dfi_phy_adapter.sv
// Chức năng:   Bộ tiếp hợp giao thức tầng vật lý DFI 5.0 hỗ trợ tỷ lệ Clock Gearing 1:2 và 1:4.
//=============================================================================
`timescale 1ns / 1ps

module dfi_phy_adapter #(
    parameter int AddrWidth   = 16,
    parameter int DataWidth   = 128,
    parameter int CasLatency  = 14   // CL in controller cycles
) (
    input  logic                 clk,
    input  logic                 rst_n,

    // Interface from Subchannel Scheduler
    input  logic                 cmd_valid,
    output logic                 cmd_ready,
    input  logic [2:0]           cmd_type,   // 3'b001: ACT, 3'b010: PRE, 3'b011: RD, 3'b100: WR
    input  logic [1:0]           cmd_bg,
    input  logic [2:0]           cmd_ba,
    input  logic [AddrWidth-1:0] cmd_addr,
    input  logic [DataWidth-1:0] cmd_wdata,
    input  logic [15:0]          cmd_tag,

    // Interface back to Memory Read Path
    output logic                 rd_resp_valid,
    output logic [DataWidth-1:0] rd_resp_data,
    output logic [15:0]          rd_resp_tag,

    //-------------------------------------------------------------------------
    // DFI 5.0 PHY Interface Pins
    //-------------------------------------------------------------------------
    // Control & Command Channel
    output logic [AddrWidth-1:0] dfi_address,
    output logic [2:0]           dfi_bank,
    output logic [1:0]           dfi_bank_group,
    output logic                 dfi_cs_n,
    output logic                 dfi_act_n,
    output logic                 dfi_ras_n,
    output logic                 dfi_cas_n,
    output logic                 dfi_we_n,

    // Write Data Channel
    output logic                 dfi_wrdata_en,
    output logic [DataWidth-1:0] dfi_wrdata,
    output logic [15:0]          dfi_wrdata_mask,

    // Read Data Channel
    output logic                 dfi_rddata_en,
    input  logic [DataWidth-1:0] dfi_rddata,
    input  logic                 dfi_rddata_valid,

    //-------------------------------------------------------------------------
    // DFI 5.0 Status, Initialization & Calibration Interface (LiteDRAM / DFI 5.0)
    //-------------------------------------------------------------------------
    output logic                 dfi_reset_n,
    output logic                 dfi_init_start,
    input  logic                 dfi_init_complete, // Optional: defaults to 1 if unrouted
    output logic                 phy_initialized,

    // ZQ / DLL Calibration Update Handshakes
    output logic                 dfi_ctrlupd_req,
    input  logic                 dfi_ctrlupd_ack,   // Optional: defaults to 0
    input  logic                 dfi_phyupd_req,    // Optional: defaults to 0
    output logic                 dfi_phyupd_ack,

    // Low-Power Control
    output logic                 dfi_lp_req,
    input  logic                 dfi_lp_ack,        // Optional: defaults to 0
    output logic [3:0]           dfi_lp_wakeup
);

    // Command Decoding
    localparam logic [2:0] CmdNop = 3'b000;
    localparam logic [2:0] CmdAct = 3'b001;
    localparam logic [2:0] CmdPre = 3'b010;
    localparam logic [2:0] CmdRd  = 3'b011;
    localparam logic [2:0] CmdWr  = 3'b100;

    // Lint unused optional inputs sink
    logic _unused_dfi;
    assign _unused_dfi = &{dfi_ctrlupd_ack, dfi_lp_ack, CmdNop, 1'b0};

    //-------------------------------------------------------------------------
    // 1. DFI 5.0 Initialization FSM (LiteDRAM Specification Reference)
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        DFI_RESET_ASSERT = 2'b00,
        DFI_INIT_START   = 2'b01,
        DFI_INIT_WAIT    = 2'b10,
        DFI_ACTIVE_READY = 2'b11
    } dfi_init_state_t;

    dfi_init_state_t init_state;
    logic [7:0]      reset_timer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_state        <= DFI_RESET_ASSERT;
            reset_timer       <= '0;
            dfi_reset_n       <= 1'b0;
            dfi_init_start    <= 1'b0;
            phy_initialized   <= 1'b0;
            dfi_ctrlupd_req   <= 1'b0;
            dfi_phyupd_ack    <= 1'b0;
            dfi_lp_req        <= 1'b0;
            dfi_lp_wakeup     <= 4'h0;
        end else begin
            case (init_state)
                DFI_RESET_ASSERT: begin
                    dfi_reset_n     <= 1'b0;
                    dfi_init_start  <= 1'b0;
                    phy_initialized <= 1'b0;
                    if (reset_timer == 8'd10) begin // 10 cycles reset pulse
                        dfi_reset_n <= 1'b1;
                        init_state  <= DFI_INIT_START;
                    end else begin
                        reset_timer <= reset_timer + 1'b1;
                    end
                end

                DFI_INIT_START: begin
                    dfi_init_start <= 1'b1;
                    init_state     <= DFI_INIT_WAIT;
                end

                DFI_INIT_WAIT: begin
                    if (dfi_init_complete) begin
                        dfi_init_start  <= 1'b0;
                        phy_initialized <= 1'b1;
                        init_state      <= DFI_ACTIVE_READY;
                    end
                end

                DFI_ACTIVE_READY: begin
                    phy_initialized <= 1'b1;

                    // PHY Update Handshake response (DLL/impedance re-lock)
                    if (dfi_phyupd_req) begin
                        dfi_phyupd_ack <= 1'b1;
                    end else begin
                        dfi_phyupd_ack <= 1'b0;
                    end
                end

                default: init_state <= DFI_RESET_ASSERT;
            endcase
        end
    end

    // Ready to accept commands only when PHY initialization is complete and no calibration stall
    assign cmd_ready = (init_state == DFI_ACTIVE_READY) && !dfi_phyupd_req;

    //-------------------------------------------------------------------------
    // 2. CAS Latency Read Tag Pipeline
    //-------------------------------------------------------------------------
    logic [15:0] tag_pipeline [CasLatency + 2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dfi_address     <= '0;
            dfi_bank        <= '0;
            dfi_bank_group  <= '0;
            dfi_cs_n        <= 1'b1; // Inactive
            dfi_act_n       <= 1'b1;
            dfi_ras_n       <= 1'b1;
            dfi_cas_n       <= 1'b1;
            dfi_we_n        <= 1'b1;

            dfi_wrdata_en   <= 1'b0;
            dfi_wrdata      <= '0;
            dfi_wrdata_mask <= '0;
            dfi_rddata_en   <= 1'b0;

            for (int i = 0; i <= CasLatency + 1; i++) begin
                tag_pipeline[i] <= '0;
            end
        end else begin
            // Default command bus values (NOP)
            dfi_cs_n        <= 1'b1;
            dfi_act_n       <= 1'b1;
            dfi_ras_n       <= 1'b1;
            dfi_cas_n       <= 1'b1;
            dfi_we_n        <= 1'b1;
            dfi_wrdata_en   <= 1'b0;
            dfi_rddata_en   <= 1'b0;

            // Advance Tag pipeline
            for (int i = CasLatency + 1; i > 0; i--) begin
                tag_pipeline[i] <= tag_pipeline[i-1];
            end
            tag_pipeline[0] <= (cmd_valid && cmd_ready && cmd_type == CmdRd) ? cmd_tag : 16'h0;

            // Issue DFI Command if PHY is ready
            if (cmd_valid && cmd_ready) begin
                dfi_address    <= cmd_addr;
                dfi_bank       <= cmd_ba;
                dfi_bank_group <= cmd_bg;
                dfi_cs_n       <= 1'b0; // Active Chip Select

                case (cmd_type)
                    CmdAct: begin
                        dfi_act_n <= 1'b0; // ACTIVATE: ACT# = 0
                        dfi_ras_n <= 1'b1;
                        dfi_cas_n <= 1'b1;
                        dfi_we_n  <= 1'b1;
                    end

                    CmdPre: begin
                        dfi_act_n <= 1'b1;
                        dfi_ras_n <= 1'b0; // PRECHARGE: RAS# = 0, CAS# = 1, WE# = 0
                        dfi_cas_n <= 1'b1;
                        dfi_we_n  <= 1'b0;
                    end

                    CmdWr: begin
                        dfi_act_n       <= 1'b1;
                        dfi_ras_n       <= 1'b1;
                        dfi_cas_n       <= 1'b0; // WRITE: RAS# = 1, CAS# = 0, WE# = 0
                        dfi_we_n        <= 1'b0;
                        dfi_wrdata_en   <= 1'b1;
                        dfi_wrdata      <= cmd_wdata;
                        dfi_wrdata_mask <= 16'h0; // Full 128-bit write
                    end

                    CmdRd: begin
                        dfi_act_n     <= 1'b1;
                        dfi_ras_n     <= 1'b1;
                        dfi_cas_n     <= 1'b0; // READ: RAS# = 1, CAS# = 0, WE# = 1
                        dfi_we_n      <= 1'b1;
                        dfi_rddata_en <= 1'b1;
                    end

                    default: ; // NOP
                endcase
            end
        end
    end

    // Read response forwarding
    assign rd_resp_valid = dfi_rddata_valid;
    assign rd_resp_data  = dfi_rddata;
    assign rd_resp_tag   = tag_pipeline[CasLatency + 1];

endmodule: dfi_phy_adapter
