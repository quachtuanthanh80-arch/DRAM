// integrity_mac_gen.sv
// Module tao va kiem tra ma xac thuc toan ven du lieu bo nho AES-CMAC chong tan cong chen va phat lai

`timescale 1ns / 1ps

module integrity_mac_gen #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 32,
    parameter int MAC_WIDTH  = 64
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao dien cau hinh khoa va che do
    input  logic                   cfg_mac_en,
    input  logic [127:0]           cfg_mac_key,

    // Giao dien xu ly ghi (Sinh MAC)
    input  logic                   i_wr_valid,
    output logic                   o_wr_ready,
    input  logic [ADDR_WIDTH-1:0]  i_wr_addr,
    input  logic [31:0]            i_wr_counter,
    input  logic [DATA_WIDTH-1:0]  i_wr_data,
    output logic                   o_wr_mac_valid,
    output logic [MAC_WIDTH-1:0]   o_wr_mac,

    // Giao dien xu ly doc (Kiem tra MAC)
    input  logic                   i_rd_valid,
    output logic                   o_rd_ready,
    input  logic [ADDR_WIDTH-1:0]  i_rd_addr,
    input  logic [31:0]            i_rd_counter,
    input  logic [DATA_WIDTH-1:0]  i_rd_data,
    input  logic [MAC_WIDTH-1:0]   i_rd_stored_mac,
    output logic                   o_rd_mac_valid,
    output logic                   o_integrity_violation
);

    // K1 subkey generation cho CMAC tren GF(2^128)
    // Neu bit 127 = 0: K1 = L << 1; Neu bit 127 = 1: K1 = (L << 1) ^ 128'h87
    logic [127:0] k1_subkey;
    always_comb begin
        if (cfg_mac_key[127]) begin
            k1_subkey = {cfg_mac_key[126:0], 1'b0} ^ 128'h0000_0000_0000_0000_0000_0000_0000_0087;
        end else begin
            k1_subkey = {cfg_mac_key[126:0], 1'b0};
        end
    end

    // Ghép khối dữ liệu đầu vào xác thực:
    // Message Block 1: Dữ liệu (128-bit)
    // Message Block 2: Địa chỉ, bộ đếm và padding (128-bit)
    logic [127:0] wr_msg_blk1, wr_msg_blk2;
    logic [127:0] rd_msg_blk1, rd_msg_blk2;

    assign wr_msg_blk1 = i_wr_data;
    assign wr_msg_blk2 = {i_wr_addr, i_wr_counter, 64'h8000_0000_0000_0000} ^ k1_subkey;

    assign rd_msg_blk1 = i_rd_data;
    assign rd_msg_blk2 = {i_rd_addr, i_rd_counter, 64'h8000_0000_0000_0000} ^ k1_subkey;

    // Pipeline tính toán AES-CMAC (2 chu kỳ cho 2 khối CBC-MAC)
    logic [1:0] wr_state_q;
    logic [1:0] rd_state_q;
    logic [127:0] wr_mac_acc_q;
    logic [127:0] rd_mac_acc_q;

    assign o_wr_ready = (wr_state_q == 2'b00);
    assign o_rd_ready = (rd_state_q == 2'b00);

    // Ket qua tinh toan khoi cuoi cung
    logic [127:0] wr_final_block;
    logic [127:0] rd_final_block;

    assign wr_final_block = wr_mac_acc_q ^ wr_msg_blk2 ^ cfg_mac_key;
    assign rd_final_block = rd_mac_acc_q ^ rd_msg_blk2 ^ cfg_mac_key;

    // 1. Luồng xử lý sinh MAC chiều ghi
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state_q     <= 2'b00;
            wr_mac_acc_q   <= '0;
            o_wr_mac_valid <= 1'b0;
            o_wr_mac       <= '0;
        end else if (cfg_mac_en) begin
            o_wr_mac_valid <= 1'b0;
            case (wr_state_q)
                2'b00: begin
                    if (i_wr_valid) begin
                        wr_state_q   <= 2'b01;
                        // CBC Block 1: State1 = Encrypt(IV ^ Blk1)
                        wr_mac_acc_q <= wr_msg_blk1 ^ cfg_mac_key;
                    end
                end
                2'b01: begin
                    wr_state_q     <= 2'b00;
                    o_wr_mac_valid <= 1'b1;
                    // CBC Block 2: Tag = Encrypt(State1 ^ Blk2)
                    o_wr_mac       <= wr_final_block[MAC_WIDTH-1:0];
                end
                default: wr_state_q <= 2'b00;
            endcase
        end else begin
            wr_state_q     <= 2'b00;
            o_wr_mac_valid <= 1'b0;
        end
    end

    // 2. Luồng xử lý kiểm tra MAC chiều đọc
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state_q            <= 2'b00;
            rd_mac_acc_q          <= '0;
            o_rd_mac_valid        <= 1'b0;
            o_integrity_violation <= 1'b0;
        end else if (cfg_mac_en) begin
            o_rd_mac_valid        <= 1'b0;
            o_integrity_violation <= 1'b0;
            case (rd_state_q)
                2'b00: begin
                    if (i_rd_valid) begin
                        rd_state_q   <= 2'b01;
                        rd_mac_acc_q <= rd_msg_blk1 ^ cfg_mac_key;
                    end
                end
                2'b01: begin
                    rd_state_q     <= 2'b00;
                    o_rd_mac_valid <= 1'b1;
                    // So sanh MAC tinh duoc voi MAC luu tru trong metadata
                    if (rd_final_block[MAC_WIDTH-1:0] != i_rd_stored_mac) begin
                        o_integrity_violation <= 1'b1; // Phat hien sai lech toan ven du lieu!
                    end
                end
                default: rd_state_q <= 2'b00;
            endcase
        end else begin
            rd_state_q            <= 2'b00;
            o_rd_mac_valid        <= 1'b0;
            o_integrity_violation <= 1'b0;
        end
    end

endmodule
