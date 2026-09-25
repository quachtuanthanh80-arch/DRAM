//=============================================================================
// File:        addr_mapper_ddr5.sv
// Chức năng:   Ánh xạ địa chỉ tuyến tính AXI4 sang Rank/BG/Bank/Row/Col với kỹ thuật băm xen kẽ Modulo-3.
//=============================================================================
`timescale 1ns / 1ps

module addr_mapper_ddr5 #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_QOS_WIDTH  = 4,
    parameter int ROW_WIDTH      = 17,
    parameter int COL_WIDTH      = 10,
    parameter int BG_WIDTH       = 3,  // 3 bits for DDR5 (8 BG), 2 bits used for DDR4 (4 BG)
    parameter int BANK_WIDTH     = 2   // 4 Banks per BG
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Runtime DRAM Mode: 1 = DDR5 (8 BG), 0 = DDR4 (4 BG)
    input  logic                      cfg_is_ddr5,

    // Request from Frontend / CDC
    input  logic                      i_req_valid,
    output logic                      o_req_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_req_id,
    input  logic                      i_req_is_write,
    input  logic [AXI_ADDR_WIDTH-1:0] i_req_addr,
    input  logic [7:0]                i_req_len,
    input  logic [AXI_QOS_WIDTH-1:0]  i_req_qos,

    // Decoded Command to SDC Filter / Scheduler
    output logic                      o_cmd_valid,
    input  logic                      i_cmd_ready,
    output logic [AXI_ID_WIDTH-1:0]   o_cmd_id,
    output logic                      o_cmd_is_write,
    output logic [BG_WIDTH-1:0]       o_cmd_bg,
    output logic [BANK_WIDTH-1:0]     o_cmd_bank,
    output logic [ROW_WIDTH-1:0]      o_cmd_row,
    output logic [COL_WIDTH-1:0]      o_cmd_col,
    output logic [7:0]                o_cmd_len,
    output logic [AXI_QOS_WIDTH-1:0]  o_cmd_qos
);

    // Byte offset within 64-byte burst (handled by PHY/Data path)
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] unused_byte_offset = i_req_addr[5:0];
    /* verilator lint_on UNUSEDSIGNAL */

    // Skid Buffer / Stage Register
    logic                      cmd_valid_reg;
    logic [AXI_ID_WIDTH-1:0]   cmd_id_reg;
    logic                      cmd_is_write_reg;
    logic [BG_WIDTH-1:0]       cmd_bg_reg;
    logic [BANK_WIDTH-1:0]     cmd_bank_reg;
    logic [ROW_WIDTH-1:0]      cmd_row_reg;
    logic [COL_WIDTH-1:0]      cmd_col_reg;
    logic [7:0]                cmd_len_reg;
    logic [AXI_QOS_WIDTH-1:0]  cmd_qos_reg;

    assign o_req_ready = !cmd_valid_reg || i_cmd_ready;

    // Decoding Combinational Logic
    // Column address: Addr[15:6] (10 bits)
    wire [COL_WIDTH-1:0] dec_col = i_req_addr[COL_WIDTH+5:6];

    // Bank within Bank Group: 2 bits
    wire [BANK_WIDTH-1:0] dec_bank = i_req_addr[17:16];

    // Bank Group XOR-Interleaving:
    // For DDR5: 8 Bank Groups (3 bits: [2:0]). XOR upper address bits to scatter sequential bursts
    wire [2:0] bg_ddr5 = i_req_addr[8:6] ^ i_req_addr[20:18];
    // For DDR4: 4 Bank Groups (2 bits: [1:0])
    wire [2:0] bg_ddr4 = {1'b0, (i_req_addr[7:6] ^ i_req_addr[19:18])};

    wire [BG_WIDTH-1:0] dec_bg = cfg_is_ddr5 ? bg_ddr5 : bg_ddr4;

    // Row Address: Upper address bits padded / truncated to ROW_WIDTH
    localparam int RAW_ROW_BITS = (AXI_ADDR_WIDTH > 18) ? (AXI_ADDR_WIDTH - 18) : 1;
    wire [RAW_ROW_BITS-1:0] raw_row = (AXI_ADDR_WIDTH > 18) ? i_req_addr[AXI_ADDR_WIDTH-1:18] : '0;
    wire [ROW_WIDTH-1:0]    dec_row = {{(ROW_WIDTH > RAW_ROW_BITS ? (ROW_WIDTH - RAW_ROW_BITS) : 0){1'b0}}, raw_row};

    // Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_valid_reg    <= 1'b0;
            cmd_id_reg       <= '0;
            cmd_is_write_reg <= 1'b0;
            cmd_bg_reg       <= '0;
            cmd_bank_reg     <= '0;
            cmd_row_reg      <= '0;
            cmd_col_reg      <= '0;
            cmd_len_reg      <= '0;
            cmd_qos_reg      <= '0;
        end else if (o_req_ready) begin
            cmd_valid_reg <= i_req_valid;
            if (i_req_valid) begin
                cmd_id_reg       <= i_req_id;
                cmd_is_write_reg <= i_req_is_write;
                cmd_bg_reg       <= dec_bg;
                cmd_bank_reg     <= dec_bank;
                cmd_row_reg      <= dec_row;
                cmd_col_reg      <= dec_col;
                cmd_len_reg      <= i_req_len;
                cmd_qos_reg      <= i_req_qos;
            end
        end
    end

    assign o_cmd_valid    = cmd_valid_reg;
    assign o_cmd_id       = cmd_id_reg;
    assign o_cmd_is_write = cmd_is_write_reg;
    assign o_cmd_bg       = cmd_bg_reg;
    assign o_cmd_bank     = cmd_bank_reg;
    assign o_cmd_row      = cmd_row_reg;
    assign o_cmd_col      = cmd_col_reg;
    assign o_cmd_len      = cmd_len_reg;
    assign o_cmd_qos      = cmd_qos_reg;

endmodule
