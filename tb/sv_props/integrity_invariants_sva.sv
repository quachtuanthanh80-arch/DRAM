// File: integrity_invariants_sva.sv
// Chức năng: Tập thuộc tính SVA cho 4 bất biến toàn vẹn BMT/Security theo D14 và spec mục 5, 6, 9.

`timescale 1ns / 1ps

`ifndef __ICARUS__

interface integrity_invariants_sva #(
    parameter int MC_WAYS    = 4,
    parameter int MAJOR_W   = 64,
    parameter int MINOR_W   = 7
)(
    input logic        clk,
    input logic        rst_n,

    // Giao diện BMT Nonce Freshness
    input logic [2:0]              tree_level,
    input logic                    commit_valid,
    input logic [MAJOR_W+MINOR_W-1:0] full_counter,
    input logic [MAJOR_W+MINOR_W-1:0] past_counter,

    // Giao diện MAC Failure Isolation
    input logic        rd_stream_active,
    input logic        rd_stream_fail,
    input logic [1:0]  s_axi_rresp,
    input logic [63:0] s_axi_rdata,

    // Giao diện Metadata Cache Pinning
    input logic [$clog2(MC_WAYS):0] set_pinned_count,
    input logic [MC_WAYS-1:0]       way_pinned_mask,

    // Giao diện Tree Root Invariance
    input logic        root_update_fire,
    input logic [63:0] tree_root
);

    // -------------------------------------------------------------------------
    // Bất biến 1: Nonce Freshness & Không dùng lại (L, major, minor) [H-8, D14]
    // Mỗi khi commit ghi, bộ đếm tăng nghiêm ngặt; bộ 3 (L, major, minor) là duy nhất.
    // -------------------------------------------------------------------------
    property p_nonce_freshness_monotonic;
        @(posedge clk) disable iff (!rst_n)
        commit_valid |-> (full_counter > past_counter);
    endproperty

    property p_nonce_unique_tuple;
        @(posedge clk) disable iff (!rst_n)
        commit_valid |-> ({tree_level, full_counter} != {tree_level, past_counter});
    endproperty

    assert property (p_nonce_freshness_monotonic)
        else $error("[SVA_ERR] Nonce freshness violated: counter did not monotonically advance");

    assert property (p_nonce_unique_tuple)
        else $error("[SVA_ERR] Reused (L, major, minor) tuple detected on commit");

    // -------------------------------------------------------------------------
    // Bất biến 2: MAC Failure Isolation & Non-speculative Release [D14, spec mục 6]
    // Khi MAC sai hoặc BMT fail, phản hồi AXI R luôn trả SLVERR và cấm rò rỉ bản rõ.
    // -------------------------------------------------------------------------
    property p_mac_fail_slverr;
        @(posedge clk) disable iff (!rst_n)
        (rd_stream_active && rd_stream_fail) |-> (s_axi_rresp == 2'b10);
    endproperty

    property p_mac_fail_zero_data;
        @(posedge clk) disable iff (!rst_n)
        (rd_stream_active && rd_stream_fail) |-> (s_axi_rdata == 64'h0);
    endproperty

    assert property (p_mac_fail_slverr)
        else $error("[SVA_ERR] MAC failure did not return AXI SLVERR");

    assert property (p_mac_fail_zero_data)
        else $error("[SVA_ERR] Plaintext leakage detected on MAC verification failure");

    // -------------------------------------------------------------------------
    // Bất biến 3: Metadata Cache Deadlock Freedom [spec mục 5]
    // Số way bị ghim trong mọi set luôn nhỏ hơn MC_WAYS (tối thiểu 1 way tự do).
    // -------------------------------------------------------------------------
    property p_meta_cache_not_all_pinned;
        @(posedge clk) disable iff (!rst_n)
        (set_pinned_count <= (MC_WAYS - 1)) && (!(&way_pinned_mask));
    endproperty

    assert property (p_meta_cache_not_all_pinned)
        else $error("[SVA_ERR] All metadata cache ways pinned: potential deadlock");

    // -------------------------------------------------------------------------
    // Bất biến 4: Tree Root Invariance [spec mục 9]
    // Gốc cây Merkle trên chip chỉ đổi khi có sự kiện đẩy node mức cao nhất.
    // -------------------------------------------------------------------------
    property p_tree_root_invariance;
        @(posedge clk) disable iff (!rst_n)
        !root_update_fire |=> $stable(tree_root);
    endproperty

    assert property (p_tree_root_invariance)
        else $error("[SVA_ERR] Tree root modified outside of highest-level root update event");

endinterface

`endif
