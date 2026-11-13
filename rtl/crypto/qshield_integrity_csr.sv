// File: qshield_integrity_csr.sv
// Chức năng: Khối thanh ghi CSR điều khiển toàn vẹn, bảo vệ chống replay và giám sát hiệu năng theo APB.

`timescale 1ns / 1ps

module qshield_integrity_csr #(
    parameter int APB_ADDR_WIDTH = 8,
    parameter int APB_DATA_WIDTH = 32
)(
    input  logic                      pclk,
    input  logic                      presetn,

    // Giao diện APB4 Slave
    input  logic                      psel,
    input  logic                      penable,
    input  logic                      pwrite,
    input  logic [APB_ADDR_WIDTH-1:0] paddr,
    input  logic [APB_DATA_WIDTH-1:0] pwdata,
    input  logic [2:0]                pprot,
    output logic [APB_DATA_WIDTH-1:0] prdata,
    output logic                      pready,
    output logic                      pslverr,

    // Tín hiệu khóa bảo mật toàn diện từ TMR
    input  logic                      i_sec_locked,

    // Tín hiệu điều khiển xuất ra Bridge & BMT Engine
    output logic                      o_integ_enable,
    output logic                      o_meta_init_start,
    input  logic                      i_meta_init_done,
    output logic                      o_meta_flush_start,
    input  logic                      i_meta_flush_done,

    output logic [63:0]               o_prot_base,
    output logic [5:0]                o_prot_lines_log2,
    output logic [255:0]              o_k3,
    output logic                      o_k3_valid,

    // Tín hiệu trạng thái & bộ đếm hiệu năng nhập từ phần cứng
    input  logic [63:0]               i_tree_root,
    input  logic [31:0]               i_integrity_fail_cnt,
    input  logic [31:0]               i_tree_fail_cnt,
    input  logic [31:0]               i_reencrypt_events,
    input  logic [31:0]               i_mc_hit_cnt,
    input  logic [31:0]               i_mc_miss_cnt,
    input  logic [31:0]               i_meta_rd_cnt,
    input  logic [31:0]               i_meta_wr_cnt
);

    // Địa chỉ thanh ghi APB
    localparam logic [7:0] ADDR_INTEG_CTRL       = 8'h00;
    localparam logic [7:0] ADDR_PROT_BASE_LO     = 8'h04;
    localparam logic [7:0] ADDR_PROT_BASE_HI     = 8'h08;
    localparam logic [7:0] ADDR_PROT_LINES_LOG2  = 8'h0C;
    localparam logic [7:0] ADDR_K3_0             = 8'h10;
    localparam logic [7:0] ADDR_K3_7             = 8'h2C;
    localparam logic [7:0] ADDR_K3_VALID         = 8'h30;
    localparam logic [7:0] ADDR_TREE_ROOT_LO     = 8'h34;
    localparam logic [7:0] ADDR_TREE_ROOT_HI     = 8'h38;
    localparam logic [7:0] ADDR_INTEG_FAIL_CNT   = 8'h3C;
    localparam logic [7:0] ADDR_TREE_FAIL_CNT    = 8'h40;
    localparam logic [7:0] ADDR_REENCRYPT_EVENTS = 8'h44;
    localparam logic [7:0] ADDR_MC_HIT_CNT       = 8'h48;
    localparam logic [7:0] ADDR_MC_MISS_CNT      = 8'h4C;
    localparam logic [7:0] ADDR_META_RD_CNT      = 8'h50;
    localparam logic [7:0] ADDR_META_WR_CNT      = 8'h54;

    logic        reg_integ_enable;
    logic        reg_init_start;
    logic        reg_flush_start;
    logic [63:0] reg_prot_base;
    logic [5:0]  reg_prot_lines_log2;
    logic [255:0] reg_k3;
    logic [7:0]  k3_loaded_mask;

    assign o_integ_enable     = reg_integ_enable;
    assign o_meta_init_start  = reg_init_start;
    assign o_meta_flush_start = reg_flush_start;
    assign o_prot_base        = reg_prot_base;
    assign o_prot_lines_log2  = reg_prot_lines_log2;
    assign o_k3               = reg_k3;
    assign o_k3_valid         = (k3_loaded_mask == 8'hFF);

    assign pready = 1'b1;

    wire apb_wr = psel && penable && pwrite;
    wire apb_rd = psel && !pwrite;

    // Phản hồi lỗi truy cập (SLVERR) khi ghi lúc đã khóa hoặc truy cập không hợp lệ
    always_comb begin
        pslverr = 1'b0;
        if (apb_wr && i_sec_locked) begin
            pslverr = 1'b1; // Khóa bảo mật: cấm ghi đè cấu hình
        end else if (apb_rd && (paddr >= ADDR_K3_0 && paddr <= ADDR_K3_7)) begin
            pslverr = 1'b1; // Khóa K3 write-only: cấm đọc ngược
        end
    end

    // Xử lý ghi cấu hình qua APB
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_integ_enable    <= 1'b0;
            reg_init_start      <= 1'b0;
            reg_flush_start     <= 1'b0;
            reg_prot_base       <= 64'h0;
            reg_prot_lines_log2 <= 6'd12; // Mặc định 4096 dòng (2^12)
            reg_k3              <= 256'h0;
            k3_loaded_mask      <= 8'h0;
        end else begin
            // Xung điều khiển tự xóa sau 1 chu kỳ
            if (reg_init_start)  reg_init_start  <= 1'b0;
            if (reg_flush_start) reg_flush_start <= 1'b0;

            if (apb_wr && !i_sec_locked) begin
                case (paddr)
                    ADDR_INTEG_CTRL: begin
                        reg_integ_enable <= pwdata[0];
                        if (pwdata[1]) reg_init_start  <= 1'b1;
                        if (pwdata[2]) reg_flush_start <= 1'b1;
                    end
                    ADDR_PROT_BASE_LO:     reg_prot_base[31:0]       <= pwdata;
                    ADDR_PROT_BASE_HI:     reg_prot_base[63:32]      <= pwdata;
                    ADDR_PROT_LINES_LOG2:  reg_prot_lines_log2       <= pwdata[5:0];
                    default: begin
                        if (paddr >= ADDR_K3_0 && paddr <= ADDR_K3_7) begin
                            int word_idx;
                            word_idx = (paddr - ADDR_K3_0) >> 2;
                            reg_k3[word_idx*32 +: 32] <= pwdata;
                            k3_loaded_mask[word_idx]   <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

    // Xử lý đọc thanh ghi qua APB
    always_comb begin
        prdata = 32'h0;
        if (apb_rd) begin
            case (paddr)
                ADDR_INTEG_CTRL:       prdata = {29'h0, reg_flush_start, reg_init_start, reg_integ_enable};
                ADDR_PROT_BASE_LO:     prdata = reg_prot_base[31:0];
                ADDR_PROT_BASE_HI:     prdata = reg_prot_base[63:32];
                ADDR_PROT_LINES_LOG2:  prdata = {26'h0, reg_prot_lines_log2};
                ADDR_K3_VALID:         prdata = {31'h0, (k3_loaded_mask == 8'hFF)};
                ADDR_TREE_ROOT_LO:     prdata = i_tree_root[31:0];
                ADDR_TREE_ROOT_HI:     prdata = i_tree_root[63:32];
                ADDR_INTEG_FAIL_CNT:   prdata = i_integrity_fail_cnt;
                ADDR_TREE_FAIL_CNT:    prdata = i_tree_fail_cnt;
                ADDR_REENCRYPT_EVENTS: prdata = i_reencrypt_events;
                ADDR_MC_HIT_CNT:       prdata = i_mc_hit_cnt;
                ADDR_MC_MISS_CNT:      prdata = i_mc_miss_cnt;
                ADDR_META_RD_CNT:      prdata = i_meta_rd_cnt;
                ADDR_META_WR_CNT:      prdata = i_meta_wr_cnt;
                default:               prdata = 32'h0;
            endcase
        end
    end

endmodule
