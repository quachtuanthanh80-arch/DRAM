// scrambler_formal.sv
// Wrapper kiem chung hinh thuc tinh doi xung Scramble-Descramble cho bus_scrambler

`timescale 1ns / 1ps

module scrambler_formal #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 18,
    parameter int LFSR_WIDTH = 64
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  cfg_scramble_en,
    input  logic                  cfg_reseed,
    input  logic [LFSR_WIDTH-1:0] cfg_seed,
    input  logic                  step_en,
    input  logic [DATA_WIDTH-1:0] orig_data,
    input  logic [ADDR_WIDTH-1:0] orig_addr
);

    logic [DATA_WIDTH-1:0] scr_data, descr_data;
    logic [ADDR_WIDTH-1:0] scr_addr, descr_addr;

    // Khoi 1: Scrambler (chieu ghi)
    bus_scrambler #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) u_scrambler (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_scramble_en(cfg_scramble_en),
        .cfg_reseed(cfg_reseed),
        .cfg_seed(cfg_seed),
        .step_en(step_en),
        .i_data(orig_data),
        .o_data(scr_data),
        .i_addr(orig_addr),
        .o_addr(scr_addr),
        .o_lfsr_state(lfsr_state_mon)
    );

    logic [LFSR_WIDTH-1:0] lfsr_state_mon;

    // Khoi 2: Descrambler (chieu doc, cung trang thai LFSR)
    bus_scrambler #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) u_descrambler (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_scramble_en(cfg_scramble_en),
        .cfg_reseed(cfg_reseed),
        .cfg_seed(cfg_seed),
        .step_en(step_en),
        .i_data(scr_data),
        .o_data(descr_data),
        .i_addr(scr_addr),
        .o_addr(descr_addr),
        .o_lfsr_state(lfsr_state_descr)
    );

    logic [LFSR_WIDTH-1:0] lfsr_state_descr;

`ifdef FORMAL
    // Dinh nghia reset ban dau
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    // Inductive Invariant: 2 khoi dong nhat co chung trang thai seed va nhip nhay
    always_comb begin
        if (rst_n) begin
            assume (lfsr_state_mon == lfsr_state_descr);

            // 1. Tinh dong nhat: Giai ma sau khi ma hoa phai luon bang du lieu goc
            a_data_identity: assert (descr_data == orig_data);
            a_addr_identity: assert (descr_addr == orig_addr);

            // 2. Tinh chat bypass: Khi tat scramble thi output bang truc tiep input
            if (!cfg_scramble_en) begin
                a_bypass_data: assert (scr_data == orig_data);
                a_bypass_addr: assert (scr_addr == orig_addr);
            end

            // 3. Bat bien LFSR: Khong bao gio bi ket o trang thai toan 0
            a_non_zero_lfsr: assert (|lfsr_state_mon);
        end
    end
`endif

endmodule
