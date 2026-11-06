// File: addr_mapper_ddr5.sv
// Chức năng: Ánh xạ địa chỉ tuyến tính AXI4 sang Rank/BG/Bank/Row/Col kết hợp bộ xáo trộn ngẫu nhiên SCARF.
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
    input  logic                      cfg_bank_coloring_en,
    input  logic [1:0]                cfg_mapping_mode,

    // Cấu hình xáo trộn địa chỉ bảo mật (SCARF Cryptographic Address Randomization)
    input  logic                      cfg_scramble_en,
    input  logic [1:0]                cfg_scramble_mode, // 0: Tắt, 1: LFSR, 2: SCARF 1-chu kỳ
    input  logic [63:0]               cfg_scramble_seed,

    // Request from Frontend / CDC
    input  logic                      i_req_valid,
    output logic                      o_req_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_req_id,
    // Định danh miền bảo mật tách khỏi i_req_id: với lệnh đọc i_req_id mang ROB tag, không phải tenant.
    input  logic [AXI_ID_WIDTH-1:0]   i_req_tenant,
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
    output logic [AXI_QOS_WIDTH-1:0]  o_cmd_qos,
    output logic                      o_busy
);

    // Byte offset within 64-byte burst (handled by PHY/Data path)
    /* verilator lint_off UNUSEDSIGNAL */
    wire [5:0] unused_byte_offset = i_req_addr[5:0];
    /* verilator lint_on UNUSEDSIGNAL */

    //=========================================================================
    // Pipeline ánh xạ: tầng giải mã (bank coloring/hash BG) + SCARF Feistel 10 vòng chia 2 vòng/tầng.
    // Toàn tuyến dừng cùng lúc khi đầu ra bị giữ (en = 0), nên thứ tự lệnh và mọi lệnh đều được bảo toàn;
    // độ trễ cố định 1 + SCARF_LAT chu kỳ kể cả khi SCARF tắt (không có đường tắt làm đảo thứ tự).
    //=========================================================================
    localparam int SCARF_RPS = 2;
    localparam int SCARF_LAT = (10 + SCARF_RPS - 1) / SCARF_RPS;

    logic out_valid;
    wire  en = !out_valid || i_cmd_ready;
    assign o_req_ready = en;

    // Cột theo word 8 byte: bỏ addr[5:3] làm hai word cùng dòng 64B trùng một ô DRAM
    wire [COL_WIDTH-1:0] dec_col = i_req_addr[COL_WIDTH+2:3];

    wire [BG_WIDTH-1:0]   dec_bg;
    wire [BANK_WIDTH-1:0] dec_bank;
    domain_bank_coloring #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_bank_coloring (
        .cfg_bank_coloring_en (cfg_bank_coloring_en),
        .cfg_mapping_mode     (cfg_mapping_mode),
        .cfg_is_ddr5          (cfg_is_ddr5),
        .i_req_id             (i_req_tenant),
        .i_req_addr           (i_req_addr),
        .o_bg                 (dec_bg),
        .o_bank               (dec_bank)
    );

    // Row Address: Upper address bits padded / truncated to ROW_WIDTH
    localparam int RAW_ROW_BITS = (AXI_ADDR_WIDTH > 18) ? (AXI_ADDR_WIDTH - 18) : 1;
    wire [RAW_ROW_BITS-1:0] raw_row = (AXI_ADDR_WIDTH > 18) ? i_req_addr[AXI_ADDR_WIDTH-1:18] : '0;
    wire [ROW_WIDTH-1:0]    dec_row = {{(ROW_WIDTH > RAW_ROW_BITS ? (ROW_WIDTH - RAW_ROW_BITS) : 0){1'b0}}, raw_row};

    // Tầng 0: thanh ghi giải mã. Sideband mỗi tầng: {valid, id, is_write, bg, bank, col, len, qos}
    localparam int SB_W = 1 + AXI_ID_WIDTH + 1 + BG_WIDTH + BANK_WIDTH + COL_WIDTH + 8 + AXI_QOS_WIDTH;
    logic [SB_W-2:0]      sb_pay [0:SCARF_LAT];
    logic [SCARF_LAT:0]   sb_vld;
    logic [ROW_WIDTH-1:0] d_row;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)  sb_vld <= '0;
        else if (en) sb_vld <= {sb_vld[SCARF_LAT-1:0], i_req_valid};
    end
    always_ff @(posedge clk)
        if (en) begin
            sb_pay[0] <= {i_req_id, i_req_is_write, dec_bg, dec_bank, dec_col, i_req_len, i_req_qos};
            d_row     <= dec_row;
        end
    wire [BG_WIDTH-1:0]   d_bg   = sb_pay[0][BANK_WIDTH + COL_WIDTH + 8 + AXI_QOS_WIDTH +: BG_WIDTH];
    wire [BANK_WIDTH-1:0] d_bank = sb_pay[0][COL_WIDTH + 8 + AXI_QOS_WIDTH +: BANK_WIDTH];

    // Tầng 1..SCARF_LAT: SCARF phá quy luật vật lý của ZenHammer/Phoenix; sideband đi song song cùng độ trễ
    wire [ROW_WIDTH-1:0]  scarf_row;
    wire [BANK_WIDTH-1:0] scarf_bank;
    wire                  scarf_on = cfg_scramble_en && (cfg_scramble_mode == 2'b10);
    scarf_dram_randomizer #(
        .ROW_WIDTH   (ROW_WIDTH),
        .BANK_WIDTH  (BANK_WIDTH),
        .TWEAK_WIDTH (16),
        .ROUNDS      (10),
        .RPS         (SCARF_RPS)
    ) u_scarf_randomizer (
        .clk               (clk),
        .rst_n             (rst_n),
        .cfg_scramble_en   (scarf_on),
        .cfg_scramble_seed (cfg_scramble_seed),
        .i_en              (en),
        .i_tweak           ({{(16-BG_WIDTH){1'b0}}, d_bg}),
        .i_row             (d_row),
        .i_bank            (d_bank),
        .o_scrambled_row   (scarf_row),
        .o_scrambled_bank  (scarf_bank)
    );

    for (genvar k = 0; k < SCARF_LAT; k++) begin : g_side
        always_ff @(posedge clk)
            if (en) sb_pay[k+1] <= sb_pay[k];
    end

    wire [SB_W-2:0] q = sb_pay[SCARF_LAT];
    assign out_valid      = sb_vld[SCARF_LAT];
    assign o_cmd_valid    = out_valid;
    assign {o_cmd_id, o_cmd_is_write, o_cmd_bg} = q[SB_W-2 -: AXI_ID_WIDTH + 1 + BG_WIDTH];
    assign o_cmd_col      = q[8 + AXI_QOS_WIDTH +: COL_WIDTH];
    assign o_cmd_len      = q[AXI_QOS_WIDTH +: 8];
    assign o_cmd_qos      = q[AXI_QOS_WIDTH-1:0];
    // Khi Bank Coloring bật, bank được giữ nguyên để phân vùng xác định; SCARF chỉ hoán vị Row
    assign o_cmd_bank     = cfg_bank_coloring_en ? q[COL_WIDTH + 8 + AXI_QOS_WIDTH +: BANK_WIDTH] : scarf_bank;
    assign o_cmd_row      = scarf_row;
    assign o_busy         = |sb_vld;

endmodule
