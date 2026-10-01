// bus_scrambler.sv
// Module xao tron bus du lieu va dia chi DRAM bang Galois LFSR song song chong snooping

`timescale 1ns / 1ps

module bus_scrambler #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 18,
    parameter int LFSR_WIDTH = 64,
    // Da thuc toi dai Galois 64-bit: x^64 + x^63 + x^61 + x^60 + 1
    parameter logic [LFSR_WIDTH-1:0] POLY = 64'hD800_0000_0000_0000
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao tiep cau hinh tu APB CSR
    input  logic                   cfg_scramble_en,
    input  logic                   cfg_reseed,
    input  logic [LFSR_WIDTH-1:0]  cfg_seed,

    // Tin hieu dieu khien buoc nhay trang thai LFSR
    input  logic                   step_en,

    // Giao dien bus du lieu & dia chi vao/ra
    input  logic [DATA_WIDTH-1:0]  i_data,
    output logic [DATA_WIDTH-1:0]  o_data,
    input  logic [ADDR_WIDTH-1:0]  i_addr,
    output logic [ADDR_WIDTH-1:0]  o_addr,

    // Giam sat trang thai LFSR cho Formal Verification va Telemetry
    output logic [LFSR_WIDTH-1:0]  o_lfsr_state
);

    // Thanh ghi luu trang thai hien tai cua LFSR
    logic [LFSR_WIDTH-1:0] lfsr_state_q;
    logic [LFSR_WIDTH-1:0] lfsr_next;

    assign o_lfsr_state = lfsr_state_q;

    // Tinh toan buoc nhay Galois LFSR song song 1 chu ky
    // Co che Galois: Bit thap nhat dich ra lam feedback cho cac tap points
    always_comb begin
        if (lfsr_state_q[0]) begin
            lfsr_next = (lfsr_state_q >> 1) ^ POLY;
        end else begin
            lfsr_next = (lfsr_state_q >> 1);
        end
    end

    // Cap nhat thanh ghi trang thai theo xung clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khoi tao gia tri seed mac dinh khac 0 de tranh trang thai kẹt 0
            lfsr_state_q <= 64'hACE1_CAFE_BABE_0001;
        end else if (cfg_reseed) begin
            // Re-seed tu CSR: Neu seed nap vao la 0 thi fallback ve seed an toan
            lfsr_state_q <= (|cfg_seed) ? cfg_seed : 64'hACE1_CAFE_BABE_0001;
        end else if (cfg_scramble_en && step_en) begin
            lfsr_state_q <= lfsr_next;
        end
    end

    // Tao mat na xao tron (Keystream) mo rong cho du lieu 128-bit va dia chi
    logic [DATA_WIDTH-1:0] data_mask;
    logic [ADDR_WIDTH-1:0] addr_mask;

    always_comb begin
        // Mo rong hoac cat 64-bit LFSR phu hop voi DATA_WIDTH tham so hoa
        logic [127:0] wide_lfsr;
        wide_lfsr = {~lfsr_state_q, lfsr_state_q};
        data_mask = wide_lfsr[DATA_WIDTH-1:0];
        addr_mask = lfsr_state_q[ADDR_WIDTH-1:0];

        // Zero-latency XOR: Neu tat tinh nang scramble thi bypass truc tiep
        if (cfg_scramble_en) begin
            o_data = i_data ^ data_mask;
            o_addr = i_addr ^ addr_mask;
        end else begin
            o_data = i_data;
            o_addr = i_addr;
        end
    end

endmodule
