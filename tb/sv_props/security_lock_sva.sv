// File: security_lock_sva.sv
// Chức năng: Tập thuộc tính SVA cho bất biến khóa bảo mật H-4 và kiểm soát keys_valid H-5.

`timescale 1ns / 1ps

`ifndef __ICARUS__

interface security_lock_sva (
    input logic clk,
    input logic rst_n,

    // Giao diện CSR
    input logic        sec_locked,
    input logic        enc_enable,
    input logic        soft_reset,
    input logic        keys_valid,
    input logic        pipe_in_valid,

    // Giao diện APB
    input logic        psel,
    input logic        penable,
    input logic [2:0]  pprot,
    input logic        pslverr
);

    // -------------------------------------------------------------------------
    // SVA 2: Sau khi sec_locked, enc_enable và soft_reset không bao giờ bị đổi (Finding H-4)
    // -------------------------------------------------------------------------
    property p_sec_locked_stable_enc;
        @(posedge clk) disable iff (!rst_n)
        sec_locked |-> $stable(enc_enable);
    endproperty

    property p_sec_locked_soft_reset_zero;
        @(posedge clk) disable iff (!rst_n)
        sec_locked |-> (soft_reset == 1'b0);
    endproperty

    property p_sec_locked_monotonic;
        @(posedge clk) disable iff (!rst_n)
        sec_locked |=> sec_locked;
    endproperty

    assert property (p_sec_locked_stable_enc)
        else $error("[SVA_ERR] enc_enable altered after security lock");

    assert property (p_sec_locked_soft_reset_zero)
        else $error("[SVA_ERR] soft_reset triggered after security lock");

    assert property (p_sec_locked_monotonic)
        else $error("[SVA_ERR] Security lock deasserted: must be fail-closed monotonic");

    // -------------------------------------------------------------------------
    // SVA 3: !keys_valid |-> !pipe_in_valid (Finding H-5)
    // -------------------------------------------------------------------------
    property p_keys_guard_pipeline;
        @(posedge clk) disable iff (!rst_n)
        !keys_valid |-> !pipe_in_valid;
    endproperty

    assert property (p_keys_guard_pipeline)
        else $error("[SVA_ERR] Pipeline transaction allowed while keys are invalid");

    // -------------------------------------------------------------------------
    // Finding H-5: APB Non-Secure Transaction Rejection (pprot[1]=1)
    // -------------------------------------------------------------------------
    property p_apb_non_secure_reject;
        @(posedge clk) disable iff (!rst_n)
        (psel && penable && pprot[1]) |-> pslverr;
    endproperty

    assert property (p_apb_non_secure_reject)
        else $error("[SVA_ERR] Non-secure APB access not rejected with PSLVERR");

endinterface

`endif
