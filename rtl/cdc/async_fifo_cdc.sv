//=============================================================================
// File:        async_fifo_cdc.sv
// Chức năng:   FIFO bất đồng bộ đồng bộ hóa con trỏ mã Gray qua miền xung nhịp AXI và DRAM/DFI.
//=============================================================================
`timescale 1ns / 1ps

module async_fifo_cdc #(
    parameter int DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 4   // Depth = 2^ADDR_WIDTH (default 16)
) (
    // Write Domain (e.g. clk_axi = 250 MHz)
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    output logic                  walmost_full,

    // Read Domain (e.g. clk_ddr = 400 MHz)
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,
    output logic                  ralmost_empty
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Dual-port Memory Array
    logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Pointers
    logic [ADDR_WIDTH:0] wbin, rbin;
    logic [ADDR_WIDTH:0] wgray, rgray;
    logic [ADDR_WIDTH:0] wgray_next, rgray_next;
    logic [ADDR_WIDTH:0] wbin_next, rbin_next;

    // Synchronizer Registers
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] wq1_rgray, wq2_rgray;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] rq1_wgray, rq2_wgray;

    // Write pointer to memory write address
    wire [ADDR_WIDTH-1:0] waddr = wbin[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] raddr = rbin[ADDR_WIDTH-1:0];

    // Memory Write
    always_ff @(posedge wclk) begin
        if (winc && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

    // Memory Read
    assign rdata = mem[raddr];

    //-------------------------------------------------------------------------
    // Synchronize Read Pointer into Write Clock Domain
    //-------------------------------------------------------------------------
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wq1_rgray <= '0;
            wq2_rgray <= '0;
        end else begin
            wq1_rgray <= rgray;
            wq2_rgray <= wq1_rgray;
        end
    end

    //-------------------------------------------------------------------------
    // Synchronize Write Pointer into Read Clock Domain
    //-------------------------------------------------------------------------
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rq1_wgray <= '0;
            rq2_wgray <= '0;
        end else begin
            rq1_wgray <= wgray;
            rq2_wgray <= rq1_wgray;
        end
    end

    //-------------------------------------------------------------------------
    // Write Domain Logic & Full Generation
    //-------------------------------------------------------------------------
    logic [ADDR_WIDTH:0] winc_ext;
    assign winc_ext   = {{(ADDR_WIDTH){1'b0}}, (winc & ~wfull)};
    assign wbin_next  = wbin + winc_ext;
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;

    wire wfull_val = (wgray_next == {~wq2_rgray[ADDR_WIDTH:ADDR_WIDTH-1], wq2_rgray[ADDR_WIDTH-2:0]});

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin   <= '0;
            wgray  <= '0;
            wfull  <= 1'b0;
        end else begin
            wbin   <= wbin_next;
            wgray  <= wgray_next;
            wfull  <= wfull_val;
        end
    end

    // Almost full: (wbin - synchronized rbin) >= DEPTH - 2
    logic [ADDR_WIDTH:0] rbin_synced_in_wclk;
    // Gray to Binary for rgray
    always_comb begin
        rbin_synced_in_wclk[ADDR_WIDTH] = wq2_rgray[ADDR_WIDTH];
        for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
            rbin_synced_in_wclk[i] = rbin_synced_in_wclk[i+1] ^ wq2_rgray[i];
        end
    end
    wire [ADDR_WIDTH:0] afull_threshold = (ADDR_WIDTH+1)'(DEPTH - 2);
    assign walmost_full = ((wbin_next - rbin_synced_in_wclk) >= afull_threshold);

    //-------------------------------------------------------------------------
    // Read Domain Logic & Empty Generation
    //-------------------------------------------------------------------------
    logic [ADDR_WIDTH:0] rinc_ext;
    assign rinc_ext   = {{(ADDR_WIDTH){1'b0}}, (rinc & ~rempty)};
    assign rbin_next  = rbin + rinc_ext;
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    wire rempty_val = (rgray_next == rq2_wgray);

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= '0;
            rgray  <= '0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rgray  <= rgray_next;
            rempty <= rempty_val;
        end
    end

    // Almost empty: (synchronized wbin - rbin) <= 1
    logic [ADDR_WIDTH:0] wbin_synced_in_rclk;
    always_comb begin
        wbin_synced_in_rclk[ADDR_WIDTH] = rq2_wgray[ADDR_WIDTH];
        for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
            wbin_synced_in_rclk[i] = wbin_synced_in_rclk[i+1] ^ rq2_wgray[i];
        end
    end
    assign ralmost_empty = ((wbin_synced_in_rclk - rbin_next) <= (ADDR_WIDTH+1)'(1));

endmodule
