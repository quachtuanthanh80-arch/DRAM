//=============================================================================
// Module Name: async_fifo_cdc
// Description: Dual-Clock Asynchronous FIFO with Gray-Code Pointer Synchronization
//              for Clock Domain Crossing (CDC) between AXI4 (250 MHz) and
//              DDR5 Controller / PHY (400 MHz).
// Standard:    Clifford Cummings Dual-Clock Asynchronous FIFO Architecture
//              Synthesizable SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module async_fifo_cdc #(
    parameter int DataWidth = 144, // 128-bit Data + 16-bit Meta
    parameter int Depth     = 16   // Must be power of 2
) (
    // Write Domain (e.g. clk_axi = 250 MHz)
    input  logic                 wclk,
    input  logic                 wrst_n,
    input  logic                 winc,
    input  logic [DataWidth-1:0] wdata,
    output logic                 wfull,
    output logic                 walmost_full,

    // Read Domain (e.g. clk_ddr = 400 MHz)
    input  logic                 rclk,
    input  logic                 rrst_n,
    input  logic                 rinc,
    output logic [DataWidth-1:0] rdata,
    output logic                 rempty,
    output logic                 ralmost_empty
);

    localparam int AddrWidth = $clog2(Depth);

    // Memory Array (Inferred as Distributed LUT RAM or Block RAM)
    logic [DataWidth-1:0] mem [Depth];

    // Binary and Gray Pointers
    logic [AddrWidth:0] wptr_bin, wptr_gray;
    logic [AddrWidth:0] rptr_bin, rptr_gray;

    // Synchronized Pointers across CDC boundary
    logic [AddrWidth:0] rptr_gray_sync1, rptr_gray_sync2;
    logic [AddrWidth:0] wptr_gray_sync1, wptr_gray_sync2;

    //-------------------------------------------------------------------------
    // 1. Dual-Port Memory Write & Read
    //-------------------------------------------------------------------------
    always_ff @(posedge wclk) begin
        if (winc && !wfull) begin
            mem[wptr_bin[AddrWidth-1:0]] <= wdata;
        end
    end

    // Direct asynchronous read output from memory for minimal latency
    assign rdata = mem[rptr_bin[AddrWidth-1:0]];

    //-------------------------------------------------------------------------
    // 2. Write Domain Logic
    //-------------------------------------------------------------------------
    logic [AddrWidth:0] wptr_bin_next;
    logic [AddrWidth:0] wptr_gray_next;

    assign wptr_bin_next  = wptr_bin + (AddrWidth+1)'(winc && !wfull);
    assign wptr_gray_next = wptr_bin_next ^ (wptr_bin_next >> 1);

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
        end else begin
            wptr_bin  <= wptr_bin_next;
            wptr_gray <= wptr_gray_next;
        end
    end

    // 2-Stage Synchronizer: Read Gray Pointer -> Write Clock Domain
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rptr_gray_sync1 <= '0;
            rptr_gray_sync2 <= '0;
        end else begin
            rptr_gray_sync1 <= rptr_gray;
            rptr_gray_sync2 <= rptr_gray_sync1;
        end
    end

    // Full condition: MSBs inverted, rest identical (standard Gray CDC check)
    logic wfull_val;
    assign wfull_val = (wptr_gray_next == {~rptr_gray_sync2[AddrWidth:AddrWidth-1],
                                            rptr_gray_sync2[AddrWidth-2:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wfull <= 1'b0;
        end else begin
            wfull <= wfull_val;
        end
    end

    // Write domain almost full indicator (1 slot remaining)
    assign walmost_full = wfull;

    //-------------------------------------------------------------------------
    // 3. Read Domain Logic
    //-------------------------------------------------------------------------
    logic [AddrWidth:0] rptr_bin_next;
    logic [AddrWidth:0] rptr_gray_next;

    assign rptr_bin_next  = rptr_bin + (AddrWidth+1)'(rinc && !rempty);
    assign rptr_gray_next = rptr_bin_next ^ (rptr_bin_next >> 1);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
        end else begin
            rptr_bin  <= rptr_bin_next;
            rptr_gray <= rptr_gray_next;
        end
    end

    // 2-Stage Synchronizer: Write Gray Pointer -> Read Clock Domain
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wptr_gray_sync1 <= '0;
            wptr_gray_sync2 <= '0;
        end else begin
            wptr_gray_sync1 <= wptr_gray;
            wptr_gray_sync2 <= wptr_gray_sync1;
        end
    end

    // Empty condition: Read Gray pointer matches synchronized Write Gray pointer
    logic rempty_val;
    assign rempty_val = (rptr_gray_next == wptr_gray_sync2);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1'b1;
        end else begin
            rempty <= rempty_val;
        end
    end

    assign ralmost_empty = rempty;

endmodule: async_fifo_cdc
