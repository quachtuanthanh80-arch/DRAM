// split_counter_table.sv
// Bang bo dem phan tach Major-Minor 1024 trang 4KB chong replay attack va ho tro CTR pre-computation

`timescale 1ns / 1ps

module split_counter_table #(
    parameter int TABLE_DEPTH      = 64,
    parameter int PAGE_ADDR_WIDTH  = $clog2(TABLE_DEPTH), // 6 bits for 64 pages
    parameter int ADDR_WIDTH       = 34,
    parameter int MAJOR_WIDTH      = 64,
    parameter int MINOR_WIDTH      = 7
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // Giao dien Pre-computation Lookup (Doc & Ghi som)
    input  logic                         i_lookup_valid,
    input  logic                         i_lookup_is_write, // 1: Tinh truoc cho Write (dung Minor + 1)
    input  logic [7:0]                   i_lookup_key_id,
    input  logic [18:0]                  i_lookup_epoch_nonce,
    input  logic [ADDR_WIDTH-1:0]        i_lookup_addr,

    output logic                         o_lookup_valid,
    output logic [127:0]                 o_ctr_blocks [4],  // 4 khoi 128-bit cho 512-bit cache line
    output logic [MAJOR_WIDTH-1:0]       o_major_ctr,
    output logic [MINOR_WIDTH-1:0]       o_minor_ctr,

    // Giao dien Commit / Cap nhat bo dem khi Lenh Ghi hoan tat
    input  logic                         i_commit_valid,
    input  logic [ADDR_WIDTH-1:0]        i_commit_addr,

    // Canh bao tran Minor Counter (Major Roll-over can Re-encryption toan bo trang 4KB)
    output logic                         o_major_roll_alert,
    output logic [PAGE_ADDR_WIDTH-1:0]   o_major_roll_page
);

    // Phan ra dia chi: 4KB Page = 64 lines x 64B line
    // [5:0]  : Byte offset (6 bits)
    // [11:6] : Line index trong page (6 bits, 0..63)
    // [21:12]: Page index (10 bits, 0..1023)
    // [33:22]: Upper physical address tag (12 bits)
    wire [5:0]                 lookup_line_idx = i_lookup_addr[11:6];
    wire [PAGE_ADDR_WIDTH-1:0] lookup_page_idx = i_lookup_addr[12 +: PAGE_ADDR_WIDTH];

    wire [5:0]                 commit_line_idx = i_commit_addr[11:6];
    wire [PAGE_ADDR_WIDTH-1:0] commit_page_idx = i_commit_addr[12 +: PAGE_ADDR_WIDTH];

    // Bang luu tru Major Counter (64-bit) cho moi trang 4KB
    logic [MAJOR_WIDTH-1:0] major_table [TABLE_DEPTH];

    // Bang luu tru 64 Minor Counter (7-bit) cho moi trang 4KB
    logic [MINOR_WIDTH-1:0] minor_table [TABLE_DEPTH][64];

    localparam logic [MINOR_WIDTH-1:0] MINOR_MAX = {MINOR_WIDTH{1'b1}}; // 7'd127

    // Giai ma gia tri bo dem can dung cho Lookup
    logic [MAJOR_WIDTH-1:0] cur_major;
    logic [MINOR_WIDTH-1:0] cur_minor;
    logic [MINOR_WIDTH-1:0] eff_minor;

    always_comb begin
        cur_major = major_table[lookup_page_idx];
        cur_minor = minor_table[lookup_page_idx][lookup_line_idx];

        // Neu la Write Pre-computation: Dung gia tri ke tiep (Minor + 1)
        if (i_lookup_is_write) begin
            eff_minor = (cur_minor == MINOR_MAX) ? '0 : (cur_minor + 1'b1);
        end else begin
            eff_minor = cur_minor;
        end
    end

    // Ghep khoi CTR 128-bit theo dac ta toan hoc:
    // CTR_Block[127:0] = {KeyID[7:0], Epoch_Nonce[18:0], Phys_Addr[33:6], Major_Ctr[63:0], Minor_Ctr[6:0], SubBlock_Idx[1:0]}
    // Do rong: 8 + 19 + 28 + 64 + 7 + 2 = 128 bits
    wire [27:0] line_phys_addr = i_lookup_addr[33:6];

    assign o_lookup_valid = i_lookup_valid;
    assign o_major_ctr    = cur_major;
    assign o_minor_ctr    = eff_minor;

    genvar b;
    generate
        for (b = 0; b < 4; b++) begin : gen_ctr_blocks
            assign o_ctr_blocks[b] = {
                i_lookup_key_id,
                i_lookup_epoch_nonce,
                line_phys_addr,
                cur_major,
                eff_minor,
                b[1:0]
            };
        end
    endgenerate

    // Khoi tao bo nho SRAM mo phong trong initial block (tranh tao 65,536 flip-flop co async reset)
    initial begin
        for (int p = 0; p < TABLE_DEPTH; p++) begin
            major_table[p] = '0;
            for (int l = 0; l < 64; l++) begin
                minor_table[p][l] = '0;
            end
        end
    end

    // Tien trinh cap nhat bo dem tren chieu Ghi (Write Commit FSM)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_major_roll_alert <= 1'b0;
            o_major_roll_page  <= '0;
        end else begin
            o_major_roll_alert <= 1'b0;

            if (i_commit_valid) begin
                if (minor_table[commit_page_idx][commit_line_idx] == MINOR_MAX) begin
                    // Tran Minor Counter: Tang Major Counter va reset toan bo 64 Minor Counter cua Page
                    major_table[commit_page_idx] <= major_table[commit_page_idx] + 1'b1;
                    for (int l = 0; l < 64; l++) begin
                        minor_table[commit_page_idx][l] <= '0;
                    end
                    o_major_roll_alert <= 1'b1;
                    o_major_roll_page  <= commit_page_idx;
                end else begin
                    minor_table[commit_page_idx][commit_line_idx] <= minor_table[commit_page_idx][commit_line_idx] + 1'b1;
                end
            end
        end
    end

endmodule
