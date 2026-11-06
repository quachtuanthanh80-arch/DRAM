// File:      cmd_engine_v2_formal.sv
// Chức năng: Wrapper formal theo cổng cho ddr5_cmd_engine v2 (FV-1a/FV-1b): mô hình beat đọc tự dựng, giả định nguồn lệnh, thuộc tính SA-P/R/D/F.
`default_nettype none

module cmd_engine_v2_formal (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_cmd_valid,
    input  wire        i_cmd_is_write,
    input  wire        i_cmd_bg,
    input  wire        i_cmd_bank,
    input  wire [7:0]  i_cmd_row,
    input  wire [5:0]  i_cmd_col,
    input  wire [7:0]  i_cmd_len,
    input  wire [4:0]  i_cmd_tag,
    input  wire        i_cmd_is_mitigation,
    input  wire        i_cmd_rmw,
    input  wire        i_rd_valid_free,
    input  wire [63:0] i_rd_data
);
    localparam [2:0] CMD_RD = 3'd3, CMD_WR = 3'd4;
    localparam integer T_RDV  = 3;
    localparam integer REF_WD = 32;
    // Cận FLUSH của cấu hình nhỏ: 4 slot x 2 beat + T_RDV + 8 + 2 cộng biên
    localparam integer FLUSH_MAX_F = 40;

    wire        rd_valid;
    wire [3:0]  o_bank_free;
    wire        o_engine_mit_only, o_abo_active;
    wire [2:0]  o_dfi_cmd;
    wire        o_dfi_bg, o_dfi_bank;
    wire [7:0]  o_dfi_row;
    wire [5:0]  o_dfi_col;
    wire [7:0]  o_dfi_len;
    wire [4:0]  o_dfi_tag;
    wire        o_wb_valid, o_wb_last, o_wb_err, o_rmw_valid;
    wire [4:0]  o_wb_tag;
    wire [63:0] o_wb_data;
    wire [1:0]  o_wb_resp;
    wire        o_rd_take, o_rd_beat_ok, o_rd_flush, o_rd_resync;
    wire [6:1]  o_fault;

    ddr5_cmd_engine #(
        .BG_COUNT(2), .BANK_COUNT(2), .ROW_WIDTH(8), .COL_WIDTH(6), .ROB_PTR_WIDTH(5),
        .T_RCD(2), .T_RP(2), .T_RAS(3), .T_CCD_L(1), .T_CCD_S(1), .T_CCD_L_WR(2), .T_CL(3), .T_RDV(T_RDV),
        .T_CWL(2), .T_RRD_S(1), .T_RRD_L(1), .T_FAW(4), .T_WR(2), .T_WTR_S(1), .T_WTR_L(1), .T_RTP(1),
        .T_RFC(4), .T_RFM(4), .T_REFI(20), .REF_WD(REF_WD), .ROWPRESS_THRESH_DEFAULT(10)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .i_cmd_valid(i_cmd_valid), .i_cmd_is_write(i_cmd_is_write), .i_cmd_id(4'd0), .i_cmd_bg(i_cmd_bg),
        .i_cmd_bank(i_cmd_bank), .i_cmd_row(i_cmd_row), .i_cmd_col(i_cmd_col), .i_cmd_len(i_cmd_len),
        .i_cmd_tag(i_cmd_tag), .i_cmd_is_mitigation(i_cmd_is_mitigation), .i_cmd_rmw(i_cmd_rmw),
        .o_slice_tag(), .i_slice_rmw(i_cmd_rmw),
        .cfg_rowpress_thresh(16'd5000), .cfg_rowpress_curve(2'b00), .cfg_tras_max_thresh(16'd8000),
        .o_rowpress_alert(), .o_rowpress_bg(), .o_rowpress_bank(), .o_rowpress_row(), .o_rowpress_alert_cnt(),
        .o_tras_clamped_alert(), .o_tras_clamped_cnt(),
        .i_dram_abo_alert(1'b0), .o_abo_active(o_abo_active), .o_abo_alert_cnt(), .o_abo_bg(), .o_abo_bank(),
        .o_abo_row(),
        .cfg_raammt_thresh(8'd32), .o_rfm_auto_cnt(), .o_cnt_fault(), .o_rfm_active(), .o_ref_tick(),
        .o_bg_ready(), .o_engine_ready(), .o_bank_free(o_bank_free), .o_engine_mit_only(o_engine_mit_only),
        .o_slack_cycle(),
        .cfg_decoy_en(1'b0), .i_decoy_avail(1'b0), .i_decoy_addr(10'd0), .o_decoy_take(), .o_decoy_active(),
        .o_decoy_cnt(),
        .o_dfi_cmd(o_dfi_cmd), .o_dfi_bg(o_dfi_bg), .o_dfi_bank(o_dfi_bank), .o_dfi_row(o_dfi_row),
        .o_dfi_col(o_dfi_col), .o_dfi_len(o_dfi_len), .o_dfi_tag(o_dfi_tag),
        .i_dfi_rddata_valid(rd_valid), .i_dfi_rddata(i_rd_data),
        .o_wb_valid(o_wb_valid), .o_wb_tag(o_wb_tag), .o_wb_data(o_wb_data), .o_wb_resp(o_wb_resp),
        .o_wb_last(o_wb_last), .o_wb_err(o_wb_err), .o_rmw_valid(o_rmw_valid), .o_rmw_beat(),
        .o_rd_take(o_rd_take), .o_rd_beat_ok(o_rd_beat_ok), .o_rd_flush(o_rd_flush), .o_rd_resync(o_rd_resync),
        .o_fault(o_fault), .i_force_rfm(1'b0),
        .o_precomp_valid(), .o_precomp_is_write(), .o_precomp_tag(), .o_precomp_addr(), .o_precomp_key_id()
    );

    // Mô hình beat của wrapper (không lấy từ DUT): RD ở chu kỳ E đặt kỳ vọng ở E + T_RDV + b, b = 0..len
    reg [15:0] mexp;
    wire [15:0] ins = (o_dfi_cmd == CMD_RD) ? (((16'd1 << (o_dfi_len[2:0] + 1)) - 16'd1) << (T_RDV - 1)) : 16'd0;
    always @(posedge clk) begin
        if (!rst_n) mexp <= 16'd0;
        else        mexp <= (mexp >> 1) | ins;
    end

`ifdef FV_FAULT
    // FV-1b: beat đọc tự do (thiếu, thừa, trễ, sớm tuỳ ý)
    assign rd_valid = i_rd_valid_free;
`else
    // FV-1a: beat tới đúng lịch
    assign rd_valid = mexp[0];
`endif

    reg        f_past_valid = 1'b0;
    reg [7:0]  mit_run, flush_run;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!rst_n) begin
            mit_run   <= 8'd0;
            flush_run <= 8'd0;
        end else begin
            mit_run   <= o_engine_mit_only ? ((mit_run == 8'hFF) ? mit_run : mit_run + 8'd1) : 8'd0;
            flush_run <= o_rd_flush ? ((flush_run == 8'hFF) ? flush_run : flush_run + 8'd1) : 8'd0;
        end
    end

`ifdef FORMAL
    // Nguồn lệnh hợp lệ: I-T1 (bank trống), độ dài < 2, arbiter đăng ký tôn trọng mit_only của chu kỳ trước
    always @(*) begin
        if (i_cmd_valid) assume (o_bank_free[{i_cmd_bg, i_cmd_bank}]);
        assume (i_cmd_len < 8'd2);
        assume (!i_cmd_rmw);
    end
    always @(posedge clk) begin
        if (f_past_valid && $past(o_engine_mit_only)) assume (!(i_cmd_valid && !i_cmd_is_mitigation));
    end

    always @(posedge clk) begin
        if (f_past_valid && rst_n && $past(rst_n)) begin
            // SA-P07: mã DFI hợp lệ
            assert (o_dfi_cmd != 3'b111);
            if (o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR) assert (o_dfi_len < 8'd8);
            // SA-R01 (REF_WD nhỏ), SA-F13: không bỏ lệnh khi nguồn tôn trọng I-T1
            assert (mit_run <= REF_WD);
            assert (!o_fault[6]);
            // SA-D03: không RD mới khi FLUSH đã bật từ chu kỳ trước
            if ($past(o_rd_flush)) assert (o_dfi_cmd != CMD_RD);
            // SA-D04: đánh dấu beat lỗi nhất quán
            if (o_wb_err) assert (o_wb_resp == 2'b10);
            if ((o_wb_valid || o_rmw_valid) && o_rd_flush) assert (o_wb_err);
            if ((o_wb_valid || o_rmw_valid) && !o_rd_flush) assert (!o_wb_err && o_wb_resp == 2'b00);
            // SA-D07: đồng bộ lại chỉ ở cạnh FLUSH -> SYNC, xung một chu kỳ
            if (o_rd_resync) assert ($past(o_rd_flush) && !o_rd_flush);
            if ($past(o_rd_resync)) assert (!o_rd_resync);
            // SA-D10
            assert (flush_run <= FLUSH_MAX_F);
            // SA-D08: cửa sổ beat của RD mới không chồng lên beat đang chờ
            if (o_dfi_cmd == CMD_RD) assert ((((mexp >> 1) & ins) == 16'd0));
`ifdef FV_FAULT
            // SA-D02: lệch beat ở SYNC -> FLUSH và fault[5] ở chu kỳ sau
            if ($past(!o_rd_flush && (rd_valid != mexp[0]))) assert (o_rd_flush && o_fault[5]);
`else
            // SA-D01: ở SYNC chỉ nhận beat đúng chu kỳ; beat đúng lịch không bao giờ gây FLUSH
            if (!o_rd_flush) assert (o_rd_beat_ok == (rd_valid && mexp[0]));
            assert (!o_rd_flush);
            assert (!o_fault[5]);
`endif
        end
    end
`endif
endmodule
`default_nettype wire
