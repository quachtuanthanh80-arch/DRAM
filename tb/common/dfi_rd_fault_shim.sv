// File:      dfi_rd_fault_shim.sv
// Chức năng: Shim tiêm lỗi đường dữ liệu đọc DFI giữa dram_model và DUT (bỏ/chèn/trễ/sớm beat, lật bit dữ liệu/ECC theo FI-38..FI-48).
`timescale 1ns / 1ps

module dfi_rd_fault_shim #(
    parameter int DATA_W = 64,
    parameter int ECC_W  = 8,
    parameter int RL     = 9
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [2:0]        i_dfi_cmd,
    input  logic              i_rddata_valid,
    input  logic [DATA_W-1:0] i_rddata,
    input  logic [ECC_W-1:0]  i_rddata_ecc = '0,
    output logic              o_rddata_valid,
    output logic [DATA_W-1:0] o_rddata,
    output logic [ECC_W-1:0]  o_rddata_ecc
);
    localparam logic [2:0] CMD_RD = 3'd3;

    // Lịch bỏ beat: bỏ drop_cnt beat sau khi đã cho qua drop_skip beat hợp lệ
    int              drop_skip;
    int              drop_cnt;

    // Lịch chèn beat thừa ngay ở chu kỳ hiện tại
    bit              ins_valid;
    logic [DATA_W-1:0] ins_data;
    logic [ECC_W-1:0]  ins_ecc;

    // Lịch làm trễ 1 chu kỳ cho beat hợp lệ kế tiếp
    bit              dly_arm;
    bit              dly_hold_v;
    logic [DATA_W-1:0] dly_hold_d;
    logic [ECC_W-1:0]  dly_hold_e;

    // Lịch phát sớm 1 chu kỳ cho beat đầu của lệnh RD kế tiếp (hoặc sau adv_cnt chu kỳ)
    bit              adv_arm_on_rd;
    int              adv_timer;
    bit              adv_drop_real;
    logic [DATA_W-1:0] adv_data;
    logic [ECC_W-1:0]  adv_ecc;

    // Lịch XOR lỗi dữ liệu/ECC trên beat hợp lệ sau xor_skip beat
    int              xor_skip;
    int              xor_cnt;
    logic [DATA_W-1:0] xor_data;
    logic [ECC_W-1:0]  xor_ecc;

    int              total_dropped;
    int              total_inserted;
    int              total_delayed;
    int              total_advanced;
    int              total_corrupted;

    task automatic clear_all();
        drop_skip      = 0;
        drop_cnt       = 0;
        ins_valid      = 0;
        ins_data       = '0;
        ins_ecc        = '0;
        dly_arm        = 0;
        dly_hold_v     = 0;
        adv_arm_on_rd  = 0;
        adv_timer      = -1;
        adv_drop_real  = 0;
        xor_skip       = 0;
        xor_cnt        = 0;
        xor_data       = '0;
        xor_ecc        = '0;
    endtask

    // Bỏ n_drop beat sau khi để qua n_skip beat thật
    task automatic arm_drop(input int n_skip, input int n_drop = 1);
        drop_skip = n_skip;
        drop_cnt  = n_drop;
    endtask

    // Chèn một beat thừa trong chu kỳ hiện tại (gọi ở negedge clk)
    task automatic arm_insert_now(input logic [DATA_W-1:0] d = 64'hDEAD_BEEF_CAFE_F00D, input logic [ECC_W-1:0] e = 8'h00);
        ins_valid = 1'b1;
        ins_data  = d;
        ins_ecc   = e;
    endtask

    // Làm trễ beat hợp lệ kế tiếp 1 chu kỳ (FI-40)
    task automatic arm_delay_next();
        dly_arm = 1'b1;
    endtask

    // Phát sớm beat 0 của lệnh RD kế tiếp 1 chu kỳ (tại E + RL - 1) và nuốt beat 0 thật tại E + RL (FI-41)
    task automatic arm_advance_next_rd(input logic [DATA_W-1:0] d = 64'hA5A5_5A5A_1234_5678, input logic [ECC_W-1:0] e = 8'h00);
        adv_arm_on_rd = 1'b1;
        adv_data      = d;
        adv_ecc       = e;
    endtask

    // Tiêm lỗi XOR vào dữ liệu/ECC sau n_skip beat hợp lệ (FI-44..FI-47)
    task automatic arm_xor(input int n_skip, input logic [DATA_W-1:0] d_xor, input logic [ECC_W-1:0] e_xor, input int n_beats = 1);
        xor_skip = n_skip;
        xor_cnt  = n_beats;
        xor_data = d_xor;
        xor_ecc  = e_xor;
    endtask

    // Tính tổ hợp cho đầu ra của chu kỳ hiện tại, cập nhật trạng thái ở cạnh lên
    logic              pass_v;
    logic [DATA_W-1:0] pass_d;
    logic [ECC_W-1:0]  pass_e;

    always_comb begin
        pass_v = i_rddata_valid;
        pass_d = i_rddata;
        pass_e = i_rddata_ecc;

        if (adv_timer == 0) begin
            pass_v = 1'b1;
            pass_d = adv_data;
            pass_e = adv_ecc;
        end else if (i_rddata_valid && adv_drop_real) begin
            pass_v = 1'b0;
        end else if (dly_hold_v) begin
            pass_v = 1'b1;
            pass_d = dly_hold_d;
            pass_e = dly_hold_e;
        end else if (i_rddata_valid && dly_arm) begin
            pass_v = 1'b0;
        end else if (i_rddata_valid && (drop_cnt > 0) && (drop_skip == 0)) begin
            pass_v = 1'b0;
        end else if (ins_valid && !i_rddata_valid) begin
            pass_v = 1'b1;
            pass_d = ins_data;
            pass_e = ins_ecc;
        end

        if (pass_v && !ins_valid && (xor_cnt > 0) && (xor_skip == 0)) begin
            pass_d = pass_d ^ xor_data;
            pass_e = pass_e ^ xor_ecc;
        end

        o_rddata_valid = pass_v;
        o_rddata       = pass_d;
        o_rddata_ecc   = pass_e;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_all();
            total_dropped   = 0;
            total_inserted  = 0;
            total_delayed   = 0;
            total_advanced  = 0;
            total_corrupted = 0;
        end else begin
            if (adv_timer == 0) begin
                adv_timer     = -1;
                adv_drop_real = 1'b1;
                total_advanced++;
            end else if (adv_timer > 0) begin
                adv_timer--;
            end

            if (i_dfi_cmd == CMD_RD && adv_arm_on_rd) begin
                adv_arm_on_rd = 1'b0;
                adv_timer     = (RL >= 2) ? (RL - 2) : 0;
            end

            if (i_rddata_valid && adv_drop_real) begin
                adv_drop_real = 1'b0;
            end else if (dly_hold_v) begin
                dly_hold_v = 1'b0;
                if (i_rddata_valid) begin
                    dly_hold_v = 1'b1;
                    dly_hold_d = i_rddata;
                    dly_hold_e = i_rddata_ecc;
                end
            end else if (i_rddata_valid && dly_arm) begin
                dly_arm    = 1'b0;
                dly_hold_v = 1'b1;
                dly_hold_d = i_rddata;
                dly_hold_e = i_rddata_ecc;
                total_delayed++;
            end else if (i_rddata_valid && (drop_cnt > 0)) begin
                if (drop_skip > 0) begin
                    drop_skip--;
                end else begin
                    drop_cnt--;
                    total_dropped++;
                end
            end else if (ins_valid && !i_rddata_valid) begin
                ins_valid = 1'b0;
                total_inserted++;
            end else begin
                ins_valid = 1'b0;
            end

            if (pass_v && (xor_cnt > 0)) begin
                if (xor_skip > 0) begin
                    xor_skip--;
                end else begin
                    xor_cnt--;
                    total_corrupted++;
                end
            end
        end
    end
endmodule

