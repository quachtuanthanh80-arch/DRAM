// split_counter_table.sv
// Bang quan ly bo dem Major-Minor chong tan cong phat lai va chong tran cho bao mat DRAM

`timescale 1ns / 1ps

module split_counter_table #(
    parameter int NUM_PAGES        = 128, // 128 trang 4KB = 512KB khong gian bo dem truc tiep
    parameter int PAGE_IDX_WIDTH   = $clog2(NUM_PAGES),
    parameter int MAJOR_WIDTH      = 7,
    parameter int MINOR_WIDTH      = 25
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Giao dien tra cuu va cap nhat bo dem
    input  logic                      i_req_valid,
    input  logic                      i_req_is_write,
    input  logic [PAGE_IDX_WIDTH-1:0] i_req_page_idx,

    // Gia tri bo dem hop nhat 32-bit: {Major[6:0], Minor[24:0]}
    output logic                      o_counter_valid,
    output logic [31:0]               o_unified_counter,

    // Canh bao tran bo dem can ma hoa lai toan bo trang
    output logic                      o_page_reseed_req,
    output logic [PAGE_IDX_WIDTH-1:0] o_page_reseed_idx
);

    // Mảng lưu trữ Major Counter (7-bit) đặt trên On-Chip SRAM/Registers
    logic [MAJOR_WIDTH-1:0] major_counters_q [NUM_PAGES];

    // Mảng lưu trữ Minor Counter (25-bit) cho mỗi trang
    logic [MINOR_WIDTH-1:0] minor_counters_q [NUM_PAGES];

    // Ngưỡng bão hòa của Minor Counter trước khi chuyển giao cho Major Counter
    localparam logic [MINOR_WIDTH-1:0] MINOR_MAX = {MINOR_WIDTH{1'b1}};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_counter_valid   <= 1'b0;
            o_unified_counter <= '0;
            o_page_reseed_req <= 1'b0;
            o_page_reseed_idx <= '0;
            for (int p = 0; p < NUM_PAGES; p++) begin
                major_counters_q[p] <= '0;
                minor_counters_q[p] <= '0;
            end
        end else begin
            o_page_reseed_req <= 1'b0;
            o_counter_valid   <= i_req_valid;

            if (i_req_valid) begin
                // Tra cuu gia tri bo dem hien tai
                o_unified_counter <= {major_counters_q[i_req_page_idx], minor_counters_q[i_req_page_idx]};

                // Neu la thao tac ghi (Write), tang bo dem Minor len 1 de bao ve chong phat lai
                if (i_req_is_write) begin
                    if (minor_counters_q[i_req_page_idx] == MINOR_MAX) begin
                        // Minor counter tran: Tang Major counter va reset Minor
                        minor_counters_q[i_req_page_idx] <= '0;
                        major_counters_q[i_req_page_idx] <= major_counters_q[i_req_page_idx] + 1'b1;
                        o_page_reseed_req                <= 1'b1;
                        o_page_reseed_idx                <= i_req_page_idx;
                    end else begin
                        minor_counters_q[i_req_page_idx] <= minor_counters_q[i_req_page_idx] + 1'b1;
                    end
                end
            end
        end
    end

endmodule
