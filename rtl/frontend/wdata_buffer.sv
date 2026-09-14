//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// Module Name: wdata_buffer
// Description: Decoupled Write Request Staging Buffer.
//              Synchronizes and stages independent AMBA AXI4 AW (Address)
//              and W (Data) channels. Decouples timing and guarantees that
//              write commands dispatched downstream have corresponding data
//              ready or staged, avoiding downstream DRAM bus stalls.
// Standard:    AMBA AXI4 / Synthesizable SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module wdata_buffer #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_QOS_WIDTH   = 4,
    parameter int BUFFER_DEPTH    = 32, // Staging data FIFO depth (beats)
    parameter int CMD_FIFO_DEPTH  = 8   // Command staging FIFO depth
) (
    input  logic                          clk_axi,
    input  logic                          aresetn_axi,

    //-------------------------------------------------------------------------
    // From axi_slave_frontend (AW & W Channels)
    //-------------------------------------------------------------------------
    // AW Staged Input
    input  logic                          i_wr_addr_valid,
    output logic                          o_wr_addr_ready,
    input  logic [AXI_ID_WIDTH-1:0]       i_wr_addr_id,
    input  logic [AXI_ADDR_WIDTH-1:0]     i_wr_addr,
    input  logic [7:0]                    i_wr_len,
    input  logic [2:0]                    i_wr_size,
    input  logic [1:0]                    i_wr_burst,
    input  logic [AXI_QOS_WIDTH-1:0]      i_wr_qos,
    input  logic                          i_wr_addr_cross_4kb,

    // W Staged Stream
    input  logic                          i_wr_data_valid,
    output logic                          o_wr_data_ready,
    input  logic [AXI_DATA_WIDTH-1:0]     i_wr_data,
    input  logic [AXI_DATA_WIDTH/8-1:0]   i_wr_strb,
    input  logic                          i_wr_last,

    //-------------------------------------------------------------------------
    // Downstream to CDC Write FIFO / Core
    //-------------------------------------------------------------------------
    // Synchronized Write Command
    output logic                          o_cmd_valid,
    input  logic                          i_cmd_ready,
    output logic [AXI_ID_WIDTH-1:0]       o_cmd_id,
    output logic [AXI_ADDR_WIDTH-1:0]     o_cmd_addr,
    output logic [7:0]                    o_cmd_len,
    output logic [2:0]                    o_cmd_size,
    output logic [1:0]                    o_cmd_burst,
    output logic [AXI_QOS_WIDTH-1:0]      o_cmd_qos,
    output logic                          o_cmd_cross_4kb,

    // Synchronized Write Data Stream
    output logic                          o_data_valid,
    input  logic                          i_data_ready,
    output logic [AXI_DATA_WIDTH-1:0]     o_data,
    output logic [AXI_DATA_WIDTH/8-1:0]   o_strb,
    output logic                          o_last
);

    //=========================================================================
    // 1. Write Command FIFO (Stages AW entries)
    //=========================================================================
    localparam int CMD_W = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + AXI_QOS_WIDTH + 1;
    localparam int CMD_PTR_W = $clog2(CMD_FIFO_DEPTH);

    logic [CMD_W-1:0] cmd_mem [CMD_FIFO_DEPTH-1:0];
    logic [CMD_PTR_W:0] cmd_wr_ptr, cmd_rd_ptr;
    logic cmd_full, cmd_empty;

    wire [CMD_W-1:0] cmd_in = {
        i_wr_addr_id,
        i_wr_addr,
        i_wr_len,
        i_wr_size,
        i_wr_burst,
        i_wr_qos,
        i_wr_addr_cross_4kb
    };

    assign cmd_full  = (cmd_wr_ptr[CMD_PTR_W] != cmd_rd_ptr[CMD_PTR_W]) &&
                       (cmd_wr_ptr[CMD_PTR_W-1:0] == cmd_rd_ptr[CMD_PTR_W-1:0]);
    assign cmd_empty = (cmd_wr_ptr == cmd_rd_ptr);

    assign o_wr_addr_ready = !cmd_full;

    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            cmd_wr_ptr <= '0;
        end else if (i_wr_addr_valid && !cmd_full) begin
            cmd_mem[cmd_wr_ptr[CMD_PTR_W-1:0]] <= cmd_in;
            cmd_wr_ptr <= cmd_wr_ptr + 1'b1;
        end
    end

    wire [CMD_W-1:0] cmd_out = cmd_mem[cmd_rd_ptr[CMD_PTR_W-1:0]];

    assign {
        o_cmd_id,
        o_cmd_addr,
        o_cmd_len,
        o_cmd_size,
        o_cmd_burst,
        o_cmd_qos,
        o_cmd_cross_4kb
    } = cmd_out;

    assign o_cmd_valid = !cmd_empty;

    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            cmd_rd_ptr <= '0;
        end else if (o_cmd_valid && i_cmd_ready) begin
            cmd_rd_ptr <= cmd_rd_ptr + 1'b1;
        end
    end

    //=========================================================================
    // 2. Write Data FIFO (Stages W beats)
    //=========================================================================
    localparam int DATA_W = AXI_DATA_WIDTH + (AXI_DATA_WIDTH / 8) + 1;
    localparam int DATA_PTR_W = $clog2(BUFFER_DEPTH);

    logic [DATA_W-1:0] data_mem [BUFFER_DEPTH-1:0];
    logic [DATA_PTR_W:0] data_wr_ptr, data_rd_ptr;
    logic data_full, data_empty;

    wire [DATA_W-1:0] data_in = {i_wr_data, i_wr_strb, i_wr_last};

    assign data_full  = (data_wr_ptr[DATA_PTR_W] != data_rd_ptr[DATA_PTR_W]) &&
                        (data_wr_ptr[DATA_PTR_W-1:0] == data_rd_ptr[DATA_PTR_W-1:0]);
    assign data_empty = (data_wr_ptr == data_rd_ptr);

    assign o_wr_data_ready = !data_full;

    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            data_wr_ptr <= '0;
        end else if (i_wr_data_valid && !data_full) begin
            data_mem[data_wr_ptr[DATA_PTR_W-1:0]] <= data_in;
            data_wr_ptr <= data_wr_ptr + 1'b1;
        end
    end

    wire [DATA_W-1:0] data_out = data_mem[data_rd_ptr[DATA_PTR_W-1:0]];
    assign {o_data, o_strb, o_last} = data_out;
    assign o_data_valid = !data_empty;

    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            data_rd_ptr <= '0;
        end else if (o_data_valid && i_data_ready) begin
            data_rd_ptr <= data_rd_ptr + 1'b1;
        end
    end

endmodule
