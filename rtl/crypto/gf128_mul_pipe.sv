// File: gf128_mul_pipe.sv
// Chức năng: Bộ nhân trường hữu hạn GF(2^128) pipeline đa thức GHASH theo NIST SP 800-38D.

`timescale 1ns / 1ps

module gf128_mul_pipe #(
    parameter int GF_STAGES = 4 // Số tầng pipeline (mặc định 4 tầng, mỗi tầng 32 bit-step)
)(
    input  logic         clk,
    input  logic         rst_n,

    // Giao diện bắt tay đầu vào
    input  logic         i_valid,
    output logic         o_ready,
    input  logic [127:0] i_x,
    input  logic [127:0] i_y,

    // Giao diện bắt tay đầu ra
    output logic         o_valid,
    input  logic         i_ready,
    output logic [127:0] o_z
);
    // Đa thức rút gọn NIST SP 800-38D: R = 11100001 || 0^120
    localparam logic [127:0] GHASH_R = 128'he100_0000_0000_0000_0000_0000_0000_0000;
    localparam int STEPS_PER_STAGE   = 128 / GF_STAGES;

    logic pipe_stall;

    // Tín hiệu pipeline giữa các tầng: X, V, Z và cờ valid
    logic [127:0] stage_x_q     [1:GF_STAGES];
    logic [127:0] stage_v_q     [1:GF_STAGES];
    logic [127:0] stage_z_q     [1:GF_STAGES];
    logic         stage_valid_q [1:GF_STAGES];

    // Đầu vào tầng 0
    wire         stage_0_valid = i_valid && o_ready;
    wire [127:0] stage_0_x     = i_x;
    wire [127:0] stage_0_v     = i_y;
    wire [127:0] stage_0_z     = 128'd0;

    // Cơ chế pipeline: mỗi tầng thực thi STEPS_PER_STAGE bước dịch và cộng trường GF(2^128)
    generate
        for (genvar s = 0; s < GF_STAGES; s++) begin : gen_stages
            logic [127:0] comb_v [0:STEPS_PER_STAGE];
            logic [127:0] comb_z [0:STEPS_PER_STAGE];

            wire [127:0] in_x;
            wire [127:0] in_v;
            wire [127:0] in_z;
            wire         in_val;

            if (s == 0) begin : gen_s0
                assign in_x   = stage_0_x;
                assign in_v   = stage_0_v;
                assign in_z   = stage_0_z;
                assign in_val = stage_0_valid;
            end else begin : gen_sx
                assign in_x   = stage_x_q[s];
                assign in_v   = stage_v_q[s];
                assign in_z   = stage_z_q[s];
                assign in_val = stage_valid_q[s];
            end

            assign comb_v[0] = in_v;
            assign comb_z[0] = in_z;

            for (genvar step = 0; step < STEPS_PER_STAGE; step++) begin : gen_steps
                localparam int BIT_IDX = 127 - (s * STEPS_PER_STAGE + step);

                // Nếu bit thứ i của X là 1: cộng dồn V vào tích Z
                assign comb_z[step+1] = in_x[BIT_IDX] ? 
                                        (comb_z[step] ^ comb_v[step]) : 
                                        comb_z[step];

                // Dịch phải V: nếu bit thấp nhất là 1 thì XOR với đa thức rút gọn R
                assign comb_v[step+1] = comb_v[step][0] ? 
                                        ({1'b0, comb_v[step][127:1]} ^ GHASH_R) : 
                                        {1'b0, comb_v[step][127:1]};
            end

            // Thanh ghi chốt trạng thái cuối mỗi tầng pipeline
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    stage_valid_q[s+1] <= 1'b0;
                    stage_x_q[s+1]     <= 128'd0;
                    stage_v_q[s+1]     <= 128'd0;
                    stage_z_q[s+1]     <= 128'd0;
                end else if (!pipe_stall) begin
                    stage_valid_q[s+1] <= in_val;
                    stage_x_q[s+1]     <= in_x;
                    stage_v_q[s+1]     <= comb_v[STEPS_PER_STAGE];
                    stage_z_q[s+1]     <= comb_z[STEPS_PER_STAGE];
                end
            end
        end
    endgenerate

    // Đầu ra sau GF_STAGES tầng pipeline
    assign o_valid    = stage_valid_q[GF_STAGES];
    assign o_z        = stage_z_q[GF_STAGES];

    // Điều khiển dừng pipeline khi phía sau chưa sẵn sàng nhận
    assign pipe_stall = o_valid && !i_ready;
    assign o_ready    = !pipe_stall;

endmodule
