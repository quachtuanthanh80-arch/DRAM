// File: qshield_meta_layout.sv
// Chức năng: Ánh xạ địa chỉ bộ nhớ cho Counter Block, MAC Line và Bonsai Merkle Tree.

`timescale 1ns / 1ps

module qshield_meta_layout #(
    parameter logic [63:0] PROT_BASE  = 64'h0000_0000_0000_0000,
    parameter logic [63:0] PROT_LINES = 64'd1048576, // 64 MiB (1048576 lines of 64B)
    parameter int          TREE_ARITY = 8
)(
    // Giao diện tra cứu dòng dữ liệu
    input  logic [63:0] i_addr,
    output logic [63:0] o_line_idx,
    output logic [63:0] o_cb_addr,
    output logic [5:0]  o_cb_slot,
    output logic [63:0] o_ml_addr,
    output logic [2:0]  o_ml_slot,
    output logic        o_is_prot,
    output logic        o_is_meta,

    // Giao diện tra cứu node cây Bonsai Merkle Tree
    input  logic [3:0]  i_tn_level,
    input  logic [31:0] i_tn_index,
    output logic [63:0] o_tn_addr,
    output logic [2:0]  o_tn_slot
);

    // Tính toán biên địa chỉ vùng dữ liệu và metadata
    localparam logic [63:0] PROT_BYTES = PROT_LINES * 64;
    localparam logic [63:0] PROT_END   = PROT_BASE + PROT_BYTES;
    localparam logic [63:0] META_BASE  = PROT_END;

    // Vùng 1: Counter Blocks (64B mỗi CB phủ 64 dòng)
    localparam logic [63:0] NUM_CB   = PROT_LINES / 64;
    localparam logic [63:0] CB_BYTES = NUM_CB * 64;
    localparam logic [63:0] CB_BASE  = META_BASE;

    // Vùng 2: MAC Lines (64B mỗi ML chứa 8 MAC 64-bit)
    localparam logic [63:0] NUM_ML   = PROT_LINES / 8;
    localparam logic [63:0] ML_BYTES = NUM_ML * 64;
    localparam logic [63:0] ML_BASE  = CB_BASE + CB_BYTES;

    // Vùng 3: Tree Nodes (Bonsai Merkle Tree 8-ary phủ các CB)
    localparam logic [63:0] TN_BASE = ML_BASE + ML_BYTES;

    // Số node từng cấp trong DRAM cho cây 8-ary
    localparam logic [63:0] TN_L1_COUNT = NUM_CB / 8;
    localparam logic [63:0] TN_L2_COUNT = TN_L1_COUNT / 8;
    localparam logic [63:0] TN_L3_COUNT = TN_L2_COUNT / 8;
    localparam logic [63:0] TN_L4_COUNT = (TN_L3_COUNT > 8) ? (TN_L3_COUNT / 8) : ((TN_L3_COUNT > 1) ? TN_L3_COUNT / 8 : 64'd0);

    localparam logic [63:0] TN_L1_OFFSET = 64'd0;
    localparam logic [63:0] TN_L2_OFFSET = TN_L1_COUNT;
    localparam logic [63:0] TN_L3_OFFSET = TN_L1_OFFSET + TN_L1_COUNT + TN_L2_COUNT;
    localparam logic [63:0] TN_L4_OFFSET = TN_L3_OFFSET + TN_L3_COUNT;
    localparam logic [63:0] TOTAL_TN     = TN_L4_OFFSET + TN_L4_COUNT;
    localparam logic [63:0] TN_BYTES     = TOTAL_TN * 64;
    localparam logic [63:0] META_END     = TN_BASE + TN_BYTES;

    // Phân rã địa chỉ dòng dữ liệu
    wire [63:0] rel_addr = i_addr - PROT_BASE;
    wire [63:0] line_idx = rel_addr >> 6;

    assign o_line_idx = line_idx;
    assign o_is_prot  = (i_addr >= PROT_BASE) && (i_addr < PROT_END);
    assign o_is_meta  = (i_addr >= META_BASE) && (i_addr < META_END);

    // Ánh xạ Counter Block và MAC Line
    assign o_cb_addr  = CB_BASE + ((line_idx >> 6) << 6);
    assign o_cb_slot  = line_idx[5:0];

    assign o_ml_addr  = ML_BASE + ((line_idx >> 3) << 6);
    assign o_ml_slot  = line_idx[2:0];

    // Ánh xạ node cây Bonsai Merkle Tree
    assign o_tn_slot  = i_tn_index[2:0];

    always_comb begin
        case (i_tn_level)
            4'd1:    o_tn_addr = TN_BASE + ((TN_L1_OFFSET + {32'd0, i_tn_index}) << 6);
            4'd2:    o_tn_addr = TN_BASE + ((TN_L2_OFFSET + {32'd0, i_tn_index}) << 6);
            4'd3:    o_tn_addr = TN_BASE + ((TN_L3_OFFSET + {32'd0, i_tn_index}) << 6);
            4'd4:    o_tn_addr = TN_BASE + ((TN_L4_OFFSET + {32'd0, i_tn_index}) << 6);
            default: o_tn_addr = TN_BASE;
        endcase
    end

endmodule
