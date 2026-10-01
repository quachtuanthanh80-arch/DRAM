// aes_ctr_keystream.sv
// Bo tinh toan truoc keystream che do AES-CTR triet tieu do tre doc cho bo nho DRAM

`timescale 1ns / 1ps

module aes_ctr_keystream
    import aes_pkg::*;
#(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 128,
    parameter int FIFO_DEPTH  = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao tiep khoi tao khoa tu APB CSR
    input  logic                   cfg_ctr_en,
    input  logic [255:0]           cfg_aes_key,
    input  logic [63:0]            cfg_nonce,

    // Kich hoat tinh toan truoc keystream ngay khi nhan duoc dia chi (AR/AW phase)
    input  logic                   i_req_valid,
    output logic                   o_req_ready,
    input  logic [ADDR_WIDTH-1:0]  i_req_addr,
    input  logic [31:0]            i_req_counter,

    // Giao tiep phat keystream san sang cho khoi doc/ghi du lieu
    output logic                   o_keystream_valid,
    input  logic                   i_keystream_ready,
    output logic [DATA_WIDTH-1:0]  o_keystream,

    // Giao dien xu ly truc tiep du lieu XOR 0-cycle
    input  logic                   i_data_valid,
    output logic                   o_data_valid,
    input  logic [DATA_WIDTH-1:0]  i_data,
    output logic [DATA_WIDTH-1:0]  o_data
);

    // Dinh dang khoi Counter 128-bit: {Nonce[63:0], Addr[31:0], Counter[31:0]}
    logic [127:0] ctr_block;
    assign ctr_block = {cfg_nonce, i_req_addr, i_req_counter};

    // Co che pipeline/iterative tao keystream tu khoi CTR
    // Tinh toan truoc keystream trong thoi gian cho DRAM latency (tRCD + tCL)
    logic [127:0] generated_keystream;
    logic         keystream_computed_valid;

    // FSM don gian gia lap pipeline tinh toan keystream voi khoa 256-bit
    logic [3:0]   round_cnt_q;
    logic         computing_q;
    logic [127:0] state_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_cnt_q              <= '0;
            computing_q              <= 1'b0;
            state_q                  <= '0;
            keystream_computed_valid <= 1'b0;
            generated_keystream      <= '0;
        end else if (cfg_ctr_en) begin
            keystream_computed_valid <= 1'b0;
            if (!computing_q && i_req_valid && o_req_ready) begin
                computing_q <= 1'b1;
                round_cnt_q <= 4'd14; // 14 vong cho AES-256
                // Khoi tao state bang phep AddRoundKey dau tien
                state_q     <= ctr_block ^ cfg_aes_key[127:0];
            end else if (computing_q) begin
                if (round_cnt_q > 4'd1) begin
                    round_cnt_q <= round_cnt_q - 1'b1;
                    // Bien doi vong thu gon bang phep quay va XOR khoa
                    state_q     <= {state_q[119:0], state_q[127:120]} ^ cfg_aes_key[255:128];
                end else begin
                    computing_q              <= 1'b0;
                    keystream_computed_valid <= 1'b1;
                    generated_keystream      <= state_q ^ cfg_aes_key[127:0];
                end
            end
        end else begin
            computing_q              <= 1'b0;
            keystream_computed_valid <= 1'b0;
        end
    end

    // Keystream Buffer FIFO (Do sau 4-entry giu san keystream da tinh truoc)
    logic [DATA_WIDTH-1:0] fifo_mem [FIFO_DEPTH];
    logic [1:0]            fifo_wr_ptr;
    logic [1:0]            fifo_rd_ptr;
    logic [2:0]            fifo_count;

    wire fifo_full  = (fifo_count == 3'(unsigned'(FIFO_DEPTH)));
    wire fifo_empty = (fifo_count == 3'd0);

    assign o_req_ready       = !fifo_full && !computing_q;
    assign o_keystream_valid = !fifo_empty;
    assign o_keystream       = fifo_mem[fifo_rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_count  <= '0;
            for (int i = 0; i < FIFO_DEPTH; i++) begin
                fifo_mem[i] <= '0;
            end
        end else if (cfg_ctr_en) begin
            // Day keystream moi tinh duoc vao FIFO
            if (keystream_computed_valid && !fifo_full) begin
                fifo_mem[fifo_wr_ptr] <= generated_keystream;
                fifo_wr_ptr           <= fifo_wr_ptr + 1'b1;
            end

            // Lay keystream ra khi duoc tieu thu boi pipeline du lieu
            if (i_keystream_ready && !fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            end

            // Cap nhat so luong entry trong FIFO
            case ({keystream_computed_valid && !fifo_full, i_keystream_ready && !fifo_empty})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: ; // Khong doi khi ca hai cung xay ra hoac khong co gi
            endcase
        end else begin
            fifo_count <= '0;
        end
    end

    // Phep XOR du lieu tuc thoi 0-cycle khi du lieu DRAM ve
    always_comb begin
        if (cfg_ctr_en) begin
            o_data_valid = i_data_valid && o_keystream_valid;
            o_data       = i_data ^ o_keystream;
        end else begin
            o_data_valid = i_data_valid;
            o_data       = i_data;
        end
    end

endmodule
