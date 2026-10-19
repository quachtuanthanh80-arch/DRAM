// aes_ctr_keystream.sv
// Dong co tinh toan truoc Keystream AES-256-CTR 512-bit voi bo nho dem Tag Buffer 16 entry triet tieu do tre 0-cycle

`timescale 1ns / 1ps

module aes_ctr_keystream
    import aes_pkg::*;
#(
    parameter int TAG_WIDTH   = 5,
    parameter int TAG_ENTRIES = 16,
    parameter int NumRounds   = 14
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // Che do va Khoa ma hoa
    input  logic                         cfg_ctr_en,
    input  logic [127:0]                 round_keys [NumRounds + 1],

    // Giao dien Yeu cau Tinh toan truoc Keystream (Kich hoat tu Address Decoder hoac Scheduler)
    input  logic                         i_precomp_valid,
    output logic                         o_precomp_ready,
    input  logic [TAG_WIDTH-1:0]         i_precomp_tag,
    input  logic [127:0]                 i_precomp_ctr_blocks [4],

    // Giao dien Tra cuu & Khum ma Doc 0-cycle (Read Data XOR Path)
    input  logic                         i_rd_valid,
    output logic                         o_rd_ready,
    input  logic [TAG_WIDTH-1:0]         i_rd_tag,
    input  logic [511:0]                 i_rd_data,
    output logic                         o_rd_valid,
    input  logic                         i_rd_pop,
    output logic [511:0]                 o_rd_data,
    output logic                         o_rd_hit,

    // Giao dien Tra cuu & Ma hoa Ghi 0-cycle (Write Data XOR Path)
    input  logic                         i_wr_valid,
    output logic                         o_wr_ready,
    input  logic [TAG_WIDTH-1:0]         i_wr_tag,
    input  logic [511:0]                 i_wr_data,
    output logic                         o_wr_valid,
    input  logic                         i_wr_pop,
    output logic [511:0]                 o_wr_data,
    output logic                         o_wr_hit
);

    // Bo nho dem Keystream theo Tag (CAM / Dual-port RAM 16 entry)
    logic [511:0]         tag_keystream_mem [TAG_ENTRIES];
    logic [TAG_ENTRIES-1:0] tag_valid_q;
    logic [TAG_ENTRIES-1:0] tag_pending_q;

    // FSM dua 4 khoi subblock vao duong ong AES
    typedef enum logic [1:0] {
        ST_FEED_IDLE = 2'b00,
        ST_FEED_BURST = 2'b01
    } feed_state_e;

    feed_state_e          feed_state;
    logic [1:0]           feed_sub_idx;
    logic [TAG_WIDTH-1:0] feed_tag_q;
    logic [127:0]         feed_blocks_q [4];

    // Pipeline wire declarations cho 14 vong AES
    logic [127:0]         pipe_state [NumRounds + 1];
    logic                 pipe_valid [NumRounds + 1];
    logic                 pipe_ready [NumRounds + 1];
    logic [TAG_WIDTH-1:0] pipe_tag_pipe [1:NumRounds];
    logic [1:0]           pipe_sub_pipe [1:NumRounds];

    assign o_precomp_ready = (feed_state == ST_FEED_IDLE) && pipe_ready[0];

    // Initial whitening: State 0 = CTR_Block ^ RoundKey[0]
    logic [127:0] cur_feed_block;
    assign cur_feed_block = (feed_state == ST_FEED_BURST) ? feed_blocks_q[feed_sub_idx] : i_precomp_ctr_blocks[0];

    wire [TAG_WIDTH-1:0] pipe_tag_in = (feed_state == ST_FEED_BURST) ? feed_tag_q : i_precomp_tag;
    wire [1:0]           pipe_sub_in = (feed_state == ST_FEED_BURST) ? feed_sub_idx : 2'b00;

    assign pipe_state[0] = cur_feed_block ^ round_keys[0];
    assign pipe_valid[0] = (feed_state == ST_FEED_BURST) || (i_precomp_valid && o_precomp_ready);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feed_state   <= ST_FEED_IDLE;
            feed_sub_idx <= 2'b00;
            feed_tag_q   <= '0;
            for (int i = 0; i < 4; i++) feed_blocks_q[i] <= '0;
        end else if (cfg_ctr_en) begin
            case (feed_state)
                ST_FEED_IDLE: begin
                    if (i_precomp_valid && o_precomp_ready) begin
                        feed_tag_q       <= i_precomp_tag;
                        feed_blocks_q[0] <= i_precomp_ctr_blocks[0];
                        feed_blocks_q[1] <= i_precomp_ctr_blocks[1];
                        feed_blocks_q[2] <= i_precomp_ctr_blocks[2];
                        feed_blocks_q[3] <= i_precomp_ctr_blocks[3];
                        feed_sub_idx     <= 2'b01; // Block 0 da duoc dua vao pipe_state[0] ngay chu ky nay
                        feed_state       <= ST_FEED_BURST;
                    end
                end

                ST_FEED_BURST: begin
                    if (pipe_ready[0]) begin
                        if (feed_sub_idx == 2'b11) begin
                            feed_state   <= ST_FEED_IDLE;
                            feed_sub_idx <= 2'b00;
                        end else begin
                            feed_sub_idx <= feed_sub_idx + 1'b1;
                        end
                    end
                end

                default: begin
                    feed_state   <= ST_FEED_IDLE;
                    feed_sub_idx <= 2'b00;
                end
            endcase
        end else begin
            feed_state <= ST_FEED_IDLE;
        end
    end

    // Khoi tao 14 vong duong ong bien doi AES
    genvar r;
    generate
        for (r = 1; r <= NumRounds; r++) begin : gen_ctr_rounds
            localparam bit IsFinal = (r == NumRounds);

            aes_round_pipe u_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (pipe_valid[r-1]),
                .in_ready      (pipe_ready[r-1]),
                .is_final_round(IsFinal),
                .state_in      (pipe_state[r-1]),
                .round_key     (round_keys[r]),
                .out_valid     (pipe_valid[r]),
                .out_ready     (pipe_ready[r]),
                .state_out     (pipe_state[r])
            );

            if (r == 1) begin : gen_stage1
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        pipe_tag_pipe[1] <= '0;
                        pipe_sub_pipe[1] <= '0;
                    end else if (pipe_ready[0]) begin
                        pipe_tag_pipe[1] <= pipe_tag_in;
                        pipe_sub_pipe[1] <= pipe_sub_in;
                    end
                end
            end else begin : gen_stage_later
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        pipe_tag_pipe[r] <= '0;
                        pipe_sub_pipe[r] <= '0;
                    end else if (pipe_ready[r-1]) begin
                        pipe_tag_pipe[r] <= pipe_tag_pipe[r-1];
                        pipe_sub_pipe[r] <= pipe_sub_pipe[r-1];
                    end
                end
            end
        end
    endgenerate

    // Dau ra pipeline luon san sang tiep nhan
    assign pipe_ready[NumRounds] = 1'b1;

    // Tap hop 4 subblock 128-bit thanh Keystream 512-bit
    logic [127:0]         asm_blocks [TAG_ENTRIES][4];
    logic [3:0]           asm_mask   [TAG_ENTRIES];
    wire [TAG_WIDTH-1:0]  out_tag    = pipe_tag_pipe[NumRounds];
    wire [1:0]            out_sub    = pipe_sub_pipe[NumRounds];

    localparam int TAG_IDX_WIDTH = (TAG_ENTRIES > 1) ? $clog2(TAG_ENTRIES) : 1;
    wire [TAG_IDX_WIDTH-1:0] precomp_tag_idx = i_precomp_tag[TAG_IDX_WIDTH-1:0];
    wire [TAG_IDX_WIDTH-1:0] out_tag_idx     = out_tag[TAG_IDX_WIDTH-1:0];
    wire [TAG_IDX_WIDTH-1:0] rd_tag_idx      = i_rd_tag[TAG_IDX_WIDTH-1:0];
    wire [TAG_IDX_WIDTH-1:0] wr_tag_idx      = i_wr_tag[TAG_IDX_WIDTH-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_valid_q   <= '0;
            tag_pending_q <= '0;
            for (int e = 0; e < TAG_ENTRIES; e++) begin
                tag_keystream_mem[e] <= '0;
                asm_mask[e]          <= '0;
                for (int s = 0; s < 4; s++) asm_blocks[e][s] <= '0;
            end
        end else begin
            // Danh dau tag pending khi nhan yeu cau precomputation
            if (i_precomp_valid && o_precomp_ready) begin
                if (i_precomp_tag < TAG_WIDTH'(TAG_ENTRIES)) begin
                    tag_pending_q[precomp_tag_idx] <= 1'b1;
                    asm_mask[precomp_tag_idx]      <= 4'b0000;
                end
            end

            // Thu thap tung subblock khi ra khoi duong ong AES
            if (pipe_valid[NumRounds]) begin
                if (out_tag < TAG_WIDTH'(TAG_ENTRIES)) begin
                    asm_blocks[out_tag_idx][out_sub] <= pipe_state[NumRounds];
                    asm_mask[out_tag_idx][out_sub]   <= 1'b1;

                    // Neu ca 4 subblock deu da hoan thanh, lap rap thanh 512-bit Keystream
                    if ((asm_mask[out_tag_idx] | (4'b0001 << out_sub)) == 4'b1111) begin
                        tag_keystream_mem[out_tag_idx] <= {
                            (out_sub == 2'b11) ? pipe_state[NumRounds] : asm_blocks[out_tag_idx][3],
                            (out_sub == 2'b10) ? pipe_state[NumRounds] : asm_blocks[out_tag_idx][2],
                            (out_sub == 2'b01) ? pipe_state[NumRounds] : asm_blocks[out_tag_idx][1],
                            (out_sub == 2'b00) ? pipe_state[NumRounds] : asm_blocks[out_tag_idx][0]
                        };
                        tag_valid_q[out_tag_idx]   <= 1'b1;
                        tag_pending_q[out_tag_idx] <= 1'b0;
                    end
                end
            end

            // Xoa tag khi du lieu doc/ghi pop khoi buffer
            if (i_rd_valid && i_rd_pop && (i_rd_tag < TAG_WIDTH'(TAG_ENTRIES))) begin
                tag_valid_q[rd_tag_idx] <= 1'b0;
            end
            if (i_wr_valid && i_wr_pop && (i_wr_tag < TAG_WIDTH'(TAG_ENTRIES))) begin
                tag_valid_q[wr_tag_idx] <= 1'b0;
            end
        end
    end

    // Giao dien Doc 0-Cycle XOR Tra cuu
    assign o_rd_ready = 1'b1;
    always_comb begin
        if (!cfg_ctr_en) begin
            o_rd_valid = i_rd_valid;
            o_rd_data  = i_rd_data;
            o_rd_hit   = 1'b1;
        end else if (i_rd_valid) begin
            if (i_rd_tag < TAG_WIDTH'(TAG_ENTRIES) && tag_valid_q[rd_tag_idx]) begin
                o_rd_valid = 1'b1;
                o_rd_data  = i_rd_data ^ tag_keystream_mem[rd_tag_idx];
                o_rd_hit   = 1'b1;
            end else begin
                o_rd_valid = 1'b0;
                o_rd_data  = i_rd_data;
                o_rd_hit   = 1'b0; // Keystream chua tinh xong (Page Hit corner case)
            end
        end else begin
            o_rd_valid = 1'b0;
            o_rd_data  = '0;
            o_rd_hit   = 1'b0;
        end
    end

    // Giao dien Ghi 0-Cycle XOR Tra cuu
    assign o_wr_ready = 1'b1;
    always_comb begin
        if (!cfg_ctr_en) begin
            o_wr_valid = i_wr_valid;
            o_wr_data  = i_wr_data;
            o_wr_hit   = 1'b1;
        end else if (i_wr_valid) begin
            if (i_wr_tag < TAG_WIDTH'(TAG_ENTRIES) && tag_valid_q[wr_tag_idx]) begin
                o_wr_valid = 1'b1;
                o_wr_data  = i_wr_data ^ tag_keystream_mem[wr_tag_idx];
                o_wr_hit   = 1'b1;
            end else begin
                o_wr_valid = 1'b0;
                o_wr_data  = i_wr_data;
                o_wr_hit   = 1'b0;
            end
        end else begin
            o_wr_valid = 1'b0;
            o_wr_data  = '0;
            o_wr_hit   = 1'b0;
        end
    end

endmodule
