// File:      aes256_key_expand.sv
// Chức năng: Mở rộng khoá AES-256 theo FIPS-197 (60 word, 15 khoá vòng), tính lặp một word mỗi chu kỳ khi khoá đổi.
`timescale 1ns / 1ps

module aes256_key_expand (
    input  logic         clk,
    input  logic         rst_n,
    // Quy ước byte giống aes_block_t của các vòng: byte i của khoá nằm ở i_key[8i+7:8i]
    input  logic [255:0] i_key,
    output logic         o_valid,
    // Khoá vòng r ở o_round_keys[r*128 +: 128] (vector phẳng: cổng mảng unpacked không mang được giá trị qua Icarus)
    output logic [15*128-1:0] o_round_keys
);

    // Lặp 1 word/chu kỳ (52 chu kỳ) thay vì tổ hợp: chuỗi 13 SubWord nối tiếp không đạt 400 MHz, và khoá chỉ đổi
    // khi nạp lại. Trong lúc tính, o_valid = 0 để đường mã hoá không dùng khoá vòng dở dang (fail-closed).
    logic [31:0]  w_mem [60];
    logic [31:0]  win   [8];     // cửa sổ trượt: win[7] = w[i-1], win[0] = w[i-8]
    logic [5:0]   idx;
    logic         busy;
    logic [255:0] key_q;
    logic         key_seen;

    // RotWord trên word {b3,b2,b1,b0} (b0 = byte đầu ở bit thấp) cho {b0,b3,b2,b1}
    wire  [31:0]  rot_in  = (idx[2:0] == 3'd0) ? {win[7][7:0], win[7][31:8]} : win[7];
    logic [31:0]  sub_out;
    for (genvar b = 0; b < 4; b++) begin : g_sbox
        aes_sbox u_sbox (.in_byte(rot_in[b*8 +: 8]), .out_byte(sub_out[b*8 +: 8]));
    end

    logic [7:0] rcon;
    always_comb begin
        case (idx[5:3])
            3'd1: rcon = 8'h01; 3'd2: rcon = 8'h02; 3'd3: rcon = 8'h04; 3'd4: rcon = 8'h08;
            3'd5: rcon = 8'h10; 3'd6: rcon = 8'h20; 3'd7: rcon = 8'h40; default: rcon = 8'h00;
        endcase
    end

    logic [31:0] temp;
    always_comb begin
        if (idx[2:0] == 3'd0)      temp = sub_out ^ {24'h0, rcon};
        else if (idx[2:0] == 3'd4) temp = sub_out;
        else                       temp = win[7];
    end
    wire [31:0] w_new = win[0] ^ temp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            o_valid  <= 1'b0;
            idx      <= '0;
            key_q    <= '0;
            key_seen <= 1'b0;
            for (int k = 0; k < 8; k++) win[k] <= '0;
        end else if (!key_seen || i_key != key_q) begin
            key_q    <= i_key;
            key_seen <= 1'b1;
            busy     <= 1'b1;
            o_valid  <= 1'b0;
            idx      <= 6'd8;
            for (int k = 0; k < 8; k++) win[k] <= i_key[k*32 +: 32];
        end else if (busy) begin
            for (int k = 0; k < 7; k++) win[k] <= win[k + 1];
            win[7] <= w_new;
            if (idx == 6'd59) begin
                busy    <= 1'b0;
                o_valid <= 1'b1;
            end else begin
                idx <= idx + 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n && (!key_seen || i_key != key_q)) begin
            for (int k = 0; k < 8; k++) w_mem[k] <= i_key[k*32 +: 32];
        end else if (busy) begin
            w_mem[idx] <= w_new;
        end
    end

    for (genvar r = 0; r < 15; r++) begin : g_rk
        assign o_round_keys[r*128 +: 128] = {w_mem[4*r + 3], w_mem[4*r + 2], w_mem[4*r + 1], w_mem[4*r]};
    end

endmodule
