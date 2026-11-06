// File:      bank_credit_ctrl.sv
// Chức năng: Tín dụng hàng đợi QoS theo bank (chỗ riêng + quỹ chung mỗi BG) cho lệnh đọc/ghi trước bộ ánh xạ, kèm giám sát tràn/âm trong silicon.
`timescale 1ns / 1ps

module bank_credit_ctrl #(
    parameter int BG_COUNT   = 8,
    parameter int BANK_COUNT = 4,
    parameter int BG_WIDTH   = $clog2(BG_COUNT),
    parameter int BANK_WIDTH = $clog2(BANK_COUNT),
    parameter int BG_QDEPTH  = 8
) (
    input  logic                                 clk,
    input  logic                                 rst_n,

    // Sự kiện chiếm: lệnh đọc được chọn khỏi hàng đợi phát lệnh / lệnh ghi bắt tay vào bộ ánh xạ
    input  logic                                 i_rd_fire,
    input  logic [BG_WIDTH-1:0]                  i_rd_bg,
    input  logic [BANK_WIDTH-1:0]                i_rd_bank,
    input  logic                                 i_wr_fire,
    input  logic [BG_WIDTH-1:0]                  i_wr_bg,
    input  logic [BANK_WIDTH-1:0]                i_wr_bank,
    // Sự kiện trả: lệnh người dùng rời arbiter, bank là bank logic đã bị trừ lúc chiếm
    input  logic                                 i_rel_valid,
    input  logic [BG_WIDTH-1:0]                  i_rel_bg,
    input  logic [BANK_WIDTH-1:0]                i_rel_bank,

    // bank_credit: còn chỗ cho thêm một lệnh tới bank; wbank_credit: còn chỗ cho một lệnh ghi và đồng thời một lệnh
    // đọc bất kỳ của cùng BG (dùng khi hàng đợi phát lệnh còn giữ lệnh đọc tới BG đó)
    output logic [BG_COUNT*BANK_COUNT-1:0]       o_bank_credit,
    output logic [BG_COUNT*BANK_COUNT-1:0]       o_wbank_credit,
    // Sự kiện đọc của chu kỳ trước (đã đăng ký, chưa vào bộ đếm): BG của nó bị che một chu kỳ cho cả đọc lẫn ghi
    output logic                                 o_chg_rd_q,
    output logic [BG_WIDTH-1:0]                  o_chg_rd_bg_q,
    // Giám sát tổ hợp (vào bộ gom lỗi): trả vào bank có bộ đếm bằng 0 / bộ đếm vượt độ sâu hàng đợi BG
    output logic                                 o_cnt_err
);

    // Mỗi bank có một chỗ riêng trong hàng đợi của BG, các chỗ còn lại (BG_QDEPTH - BANK_COUNT) dùng chung (như credit
    // theo VC của NoC). Lệnh bị PROQ chặn ở một bank chỉ chiếm được chỗ riêng của bank đó và quỹ chung, nên không bao
    // giờ lấy hết chỗ của bank khác cùng BG: đóng kênh thời gian LeakyHammer xuyên bank qua dung lượng hàng đợi (V19).
    // Sự kiện chiếm được đăng ký trước khi cộng vào bộ đếm; bank_credit là thanh ghi tính cho chu kỳ kế tiếp từ trạng
    // thái đăng ký và lệnh ghi của chu kỳ này; lệnh đọc vừa chọn chưa có trong đó (bộ chọn của hàng đợi phát lệnh nằm
    // ngoài vòng tín dụng), nên BG của nó bị che một chu kỳ (o_chg_rd_*).
    localparam int NBK          = BG_COUNT * BANK_COUNT;
    localparam int BKW          = BG_WIDTH + BANK_WIDTH;
    localparam int Q_SHARED     = BG_QDEPTH - BANK_COUNT;
    localparam int Q_SHARED_WR  = (Q_SHARED > 0) ? (Q_SHARED - 1) : 0;

    logic [3:0]          bk_cnt [NBK];
    logic [NBK-1:0]      bank_credit, wbank_credit;
    logic                chg_rd_q, chg_wr_q;
    logic [BKW-1:0]      chg_rd_b_q, chg_wr_b_q;
    logic [3:0]          bk_base [NBK];
    logic [NBK-1:0]      base_nz, wr_hit, bk_uf, bk_of;
    logic [4:0]          sh_base [BG_COUNT];

    always_comb begin
        for (int b = 0; b < NBK; b++) begin
            logic [3:0] add_v;
            logic       sub_v;
            add_v     = ((chg_rd_q && chg_rd_b_q == BKW'(b)) ? 4'd1 : 4'd0)
                      + ((chg_wr_q && chg_wr_b_q == BKW'(b)) ? 4'd1 : 4'd0);
            sub_v     = (i_rel_valid && {i_rel_bg, i_rel_bank} == BKW'(b));
            bk_uf[b]  = sub_v && (bk_cnt[b] == 4'd0) && (add_v == 4'd0);
            bk_of[b]  = (bk_cnt[b] > 4'(BG_QDEPTH)) || ((bk_cnt[b] + add_v - (sub_v ? 4'd1 : 4'd0)) > 4'(BG_QDEPTH));
            if (bk_uf[b])
                bk_base[b] = 4'd0;
            else if (bk_of[b])
                bk_base[b] = 4'(BG_QDEPTH);
            else
                bk_base[b] = bk_cnt[b] + add_v - (sub_v ? 4'd1 : 4'd0);
            base_nz[b] = bk_base[b] != 4'd0;
            wr_hit[b]  = i_wr_fire && {i_wr_bg, i_wr_bank} == BKW'(b);
        end
        // Số chỗ chung đang dùng của BG = tổng (n - 1) trên các bank có n > 0
        for (int g = 0; g < BG_COUNT; g++) begin
            sh_base[g] = '0;
            for (int k = 0; k < BANK_COUNT; k++)
                if (base_nz[g*BANK_COUNT + k]) sh_base[g] = sh_base[g] + 5'(bk_base[g*BANK_COUNT + k]) - 5'd1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int b = 0; b < NBK; b++) bk_cnt[b] <= '0;
            chg_rd_q     <= 1'b0;
            chg_wr_q     <= 1'b0;
            bank_credit  <= '1;
            wbank_credit <= '1;
        end else begin
            chg_rd_q <= i_rd_fire;
            chg_wr_q <= i_wr_fire;
            for (int b = 0; b < NBK; b++) for (int b = 0; b < NBK; b++) bk_cnt[b] <= bk_base[b];
            for (int g = 0; g < BG_COUNT; g++) begin
                logic wr_sh;
                // Sự kiện mới trong BG này dùng chỗ chung khi bank đích đã có lệnh (hoặc hai sự kiện cùng bank)
                wr_sh = |(wr_hit[g*BANK_COUNT +: BANK_COUNT] & base_nz[g*BANK_COUNT +: BANK_COUNT]);
                for (int k = 0; k < BANK_COUNT; k++) begin
                    int  b;
                    logic res_ok, sh_ok, wsh_ok;
                    b        = g*BANK_COUNT + k;
                    res_ok   = !base_nz[b] && !wr_hit[b];
                    sh_ok    = wr_sh ? (sh_base[g] + 5'd1 < 5'(Q_SHARED))    : (sh_base[g] < 5'(Q_SHARED));
                    wsh_ok   = wr_sh ? (sh_base[g] + 5'd1 < 5'(Q_SHARED_WR)) : (sh_base[g] < 5'(Q_SHARED_WR));
                    bank_credit[b]  <= res_ok || sh_ok;
                    // Ghi vào bank trống dùng chỗ riêng nhưng lệnh đọc đồng thời có thể tới chính bank đó và cần một
                    // chỗ chung, nên nhánh chỗ riêng vẫn đòi quỹ chung còn chỗ; ngược lại cần hai chỗ chung (spec_v2 M-02.2)
                    wbank_credit[b] <= (res_ok && sh_ok) || wsh_ok;
                end
            end
        end
    end
    always_ff @(posedge clk) begin
        chg_rd_b_q <= {i_rd_bg, i_rd_bank};
        chg_wr_b_q <= {i_wr_bg, i_wr_bank};
    end

    assign o_bank_credit  = bank_credit;
    assign o_wbank_credit = wbank_credit;
    assign o_chg_rd_q     = chg_rd_q;
    assign o_chg_rd_bg_q  = chg_rd_b_q[BKW-1 -: BG_WIDTH];
    assign o_cnt_err      = (|bk_uf) || (|bk_of);

`ifdef FORMAL
    // SA-C05: tín dụng ghi luôn chặt hơn tín dụng đọc (suy từ công thức, đúng với mọi đầu vào)
    always_comb
        if (rst_n) assert ((wbank_credit & ~bank_credit) == '0);
`endif

endmodule
