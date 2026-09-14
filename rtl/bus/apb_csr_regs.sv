//=============================================================================
// Module:      apb_csr_regs
// Description: APB4 Control and Status Registers (CSR) for Secure DDR5 Controller.
//              Provides register-mapped access for:
//              - AES-256 Keys (K1 cipher key, K2 tweak key)
//              - Security Lockdown (DPA/tamper protection: zeroized key readback)
//              - Encryption Enable / Bypass Control
//              - Hardware Performance Telemetry Counters (Cycles, Blocks, Stalls)
// Standard:    AMBA APB v2.0 (APB4) / SystemVerilog IEEE 1800-2017
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
    input  logic                 pipeline_stall_active  // High when pipe is stalled
);

    // Register Address Offsets
    localparam logic [AddrWidth-1:0] AddrCtrl        = 12'h000;
    localparam logic [AddrWidth-1:0] AddrStatus      = 12'h004;
    localparam logic [AddrWidth-1:0] AddrSecLock    = 12'h008;
    localparam logic [AddrWidth-1:0] AddrKey1Base   = 12'h010; // 0x010 .. 0x02C (8 regs)
    localparam logic [AddrWidth-1:0] AddrKey2Base   = 12'h030; // 0x030 .. 0x04C (8 regs)
    localparam logic [AddrWidth-1:0] AddrPerfCycles = 12'h060;
    localparam logic [AddrWidth-1:0] AddrPerfBlocks = 12'h064;
    localparam logic [AddrWidth-1:0] AddrPerfStalls = 12'h068;

    // Security Lock Magic Value
    localparam logic [31:0] SecLockMagic = 32'hA55A_0001;

    // Internal Registers
    logic [31:0] reg_ctrl;
    logic        reg_sec_locked;
    logic [31:0] reg_key1 [8];
    logic [31:0] reg_key2 [8];
    logic [7:0]  key1_loaded_mask;
    logic [7:0]  key2_loaded_mask;

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
            reg_ctrl         <= 32'h0000_0009; // Default: enc_enable=1, auto_tweak_en=1
            reg_sec_locked   <= 1'b0;
            key1_loaded_mask <= 8'h00;
            key2_loaded_mask <= 8'h00;
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
