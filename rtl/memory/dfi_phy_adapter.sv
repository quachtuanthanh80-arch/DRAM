//=============================================================================
// Module Name: dfi_phy_adapter
// Description: DFI 5.0 (DRAM Future Interface) Protocol Adapter.
//              Bridges DDR5 Subchannel Memory Controller commands (ACT, PRE, RD, WR)
//              to standard DFI 5.0 PHY signals:
//              - Control Bus: dfi_address, dfi_bank, dfi_bank_group, dfi_cs_n,
//                             dfi_act_n, dfi_ras_n, dfi_cas_n, dfi_we_n
//              - Write Data Bus: dfi_wrdata_en, dfi_wrdata, dfi_wrdata_mask
//              - Read Data Bus:  dfi_rddata_en, dfi_rddata, dfi_rddata_valid
// Standard:    DFI 5.0 Specification / Synthesizable SystemVerilog (IEEE 1800-2017)
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
    input  logic                 dfi_rddata_valid
);

    // Command Decoding
    localparam logic [2:0] CmdNop = 3'b000;
    localparam logic [2:0] CmdAct = 3'b001;
    localparam logic [2:0] CmdPre = 3'b010;
    localparam logic [2:0] CmdRd  = 3'b011;
    localparam logic [2:0] CmdWr  = 3'b100;

    assign cmd_ready = 1'b1; // Zero wait state command acceptance

    // Tag tracking shift register for read requests
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
            tag_pipeline[0] <= (cmd_valid && cmd_type == CmdRd) ? cmd_tag : 16'h0;

            if (cmd_valid) begin
                dfi_address    <= cmd_addr;
                dfi_bank       <= cmd_ba;
                dfi_bank_group <= cmd_bg;
                dfi_cs_n       <= 1'b0; // Active Chip Select

                case (cmd_type)
                    CmdAct: begin
                        dfi_act_n <= 1'b0; // ACTIVATE command pin active low
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
