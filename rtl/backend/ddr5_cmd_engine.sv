// File:        ddr5_cmd_engine.sv
// Chức năng:   Bộ phát lệnh DDR5 song song theo bank: giữ một giao dịch mỗi bank, chọn lệnh DFI theo định thời JEDEC mỗi chu kỳ.
`timescale 1ns / 1ps

module ddr5_cmd_engine #(
    parameter int BG_COUNT        = 8,
    parameter int BG_WIDTH        = $clog2(BG_COUNT),
    parameter int BANK_COUNT      = 4,
    parameter int BANK_WIDTH      = $clog2(BANK_COUNT),
    parameter int ROW_WIDTH       = 17,
    parameter int COL_WIDTH       = 10,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int ROB_PTR_WIDTH   = 5,

    // Định thời JEDEC theo chu kỳ clock của engine. Mặc định: DDR5-3200 16 Gb với tCK điều khiển 2.5 ns (400 MHz,
    // DFI 1:4); axi_ddr5_mc_top tính lại mọi giá trị từ thông số ps và TCK_PS rồi truyền xuống.
    parameter int T_RCD           = 7,    // 17.5 ns: ACT -> RD/WR
    parameter int T_RP            = 7,    // 17.5 ns: PRE -> ACT
    parameter int T_RAS           = 13,   // 32 ns: ACT -> PRE
    parameter int T_CCD_L         = 2,    // CAS -> CAS cùng BG
    parameter int T_CCD_S         = 2,    // CAS -> CAS khác BG
    parameter int T_CCD_L_WR      = 8,    // 20 ns: WR -> WR cùng BG (tCCD_L_WR, chặt hơn tCCD_L)
    parameter int T_CL            = 8,    // RD -> beat dữ liệu đầu (cửa sổ bus DQ)
    // RD trên o_dfi_cmd -> beat 0 ở i_dfi_rddata_valid (độ trễ cố định sau training PHY, tính cả thanh ghi vào)
    parameter int T_RDV           = 9,
    parameter int T_CWL           = 9,    // WR -> beat dữ liệu ghi đầu (tphy_wrlat của khối đỉnh)
    parameter int T_RRD_S         = 2,    // ACT -> ACT khác BG
    parameter int T_RRD_L         = 2,    // ACT -> ACT cùng BG
    parameter int T_FAW           = 10,   // 25 ns: tối đa 4 ACT trong cửa sổ tFAW
    parameter int T_WR            = 12,   // 30 ns: cuối dữ liệu ghi -> PRE
    parameter int T_WTR_S         = 1,    // cuối dữ liệu ghi -> RD khác BG
    parameter int T_WTR_L         = 4,    // cuối dữ liệu ghi -> RD cùng BG
    parameter int T_RTP           = 3,    // RD -> PRE
    parameter int T_RFC           = 118,  // tRFC1 295 ns (16 Gb)
    parameter int T_RFM           = 118,  // tRFMab, lấy bằng tRFC1 (bảo thủ)
    parameter int T_REFI          = 1560, // tREFI 3.9 us (floor)
    parameter int MAX_POSTPONE    = 4,    // JEDEC: hoãn tối đa 4 REF
    // Ngân sách chu kỳ cho một lần drain trước REF/RFM; quá hạn thì ép đóng mọi bank (lỗi thiết kế hoặc tiêm lỗi)
    parameter int REF_WD          = 512,
    parameter int ROWPRESS_THRESH_DEFAULT = 5000
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    //-------------------------------------------------------------------------
    // Command Input from slack_aware_arbiter
    //-------------------------------------------------------------------------
    input  logic                                         i_cmd_valid,
    input  logic                                         i_cmd_is_write,
    input  logic [AXI_ID_WIDTH-1:0]                      i_cmd_id,
    input  logic [BG_WIDTH-1:0]                          i_cmd_bg,
    input  logic [BANK_WIDTH-1:0]                        i_cmd_bank,
    input  logic [ROW_WIDTH-1:0]                         i_cmd_row,
    input  logic [COL_WIDTH-1:0]                         i_cmd_col,
    input  logic [AXI_LEN_WIDTH-1:0]                     i_cmd_len,
    input  logic [ROB_PTR_WIDTH-1:0]                     i_cmd_tag,
    input  logic                                         i_cmd_is_mitigation,
    // Ghi từng phần (WSTRB thiếu byte) khi có ECC: engine đọc dòng trước (RMW) vì mã ECC phủ cả word
    input  logic                                         i_cmd_rmw = 1'b0,
    // Tra cờ RMW theo tag của lệnh đang ở slice (o_slice_tag -> kho ghi -> i_slice_rmw) ở chu kỳ phân loại:
    // cờ không còn nằm trên đường arbiter -> engine
    output logic [ROB_PTR_WIDTH-1:0]                     o_slice_tag,
    input  logic                                         i_slice_rmw = 1'b0,

    //-------------------------------------------------------------------------
    // RowPress Attack Monitoring & Telemetry Interface
    //-------------------------------------------------------------------------
    input  logic [15:0]                                  cfg_rowpress_thresh,
    input  logic [1:0]                                   cfg_rowpress_curve = 2'b00, // 0: Static, 1: Conservative, 2: Standard, 3: Aggressive
    // Giới hạn thời gian mở hàng (chu kỳ) chặn cửa sổ RowPress/ColumnDisturb, không vượt tRAS(max) = 9 x tREFI.
    // Khối đỉnh tính từ tREFI và TCK_PS; 8775 = 21.9 us ở 2.5 ns (chặt hơn chuẩn).
    input  logic [15:0]                                  cfg_tras_max_thresh = 16'd8775,
    output logic                                         o_rowpress_alert,
    output logic [BG_WIDTH-1:0]                          o_rowpress_bg,
    output logic [BANK_WIDTH-1:0]                        o_rowpress_bank,
    output logic [ROW_WIDTH-1:0]                         o_rowpress_row,
    output logic [15:0]                                  o_rowpress_alert_cnt,
    output logic                                         o_tras_clamped_alert,
    output logic [15:0]                                  o_tras_clamped_cnt,

    //-------------------------------------------------------------------------
    // JEDEC PRAC / QPRAC Alert-Back-Off (ABO) Physical Handshake Interface
    //-------------------------------------------------------------------------
    input  logic                                         i_dram_abo_alert = 1'b0,
    output logic                                         o_abo_active,
    output logic [15:0]                                  o_abo_alert_cnt,
    output logic [BG_WIDTH-1:0]                          o_abo_bg,
    output logic [BANK_WIDTH-1:0]                        o_abo_bank,
    output logic [ROW_WIDTH-1:0]                         o_abo_row,

    //-------------------------------------------------------------------------
    // Autonomous JEDEC DDR5 RFM Generator Interface (McSee Finding Defense)
    //-------------------------------------------------------------------------
    input  logic [7:0]                                   cfg_raammt_thresh = 8'd32,
    output logic [15:0]                                  o_rfm_auto_cnt,
    // Bộ đếm ACT cuốn chiếu bị lệch so với bản đếm ngược (dấu hiệu tiêm lỗi): bí danh của o_fault[1]
    output logic                                         o_cnt_fault,
    // Lỗi phát hiện trong silicon, đăng ký (mức ở chu kỳ phát hiện + 1): [1] RAA chéo lệch, [2] sự kiện ACT/WR kép
    // lệch, [3] cờ timer lệch timer, [4] refresh (watchdog, nợ REF tràn/âm hoặc lệch bản sao, lat_kind sai mã,
    // user_blk_q lệch), [5] beat đọc lệch lịch hoặc rd_st sai mã, [6] lệnh tới bank có slot bận (bị bỏ)
    output logic [6:1]                                   o_fault,
    // Yêu cầu RFMab từ khối ngoài phát hiện lỗi (DRM): mọi BG coi như đã tới ngưỡng RAA
    input  logic                                         i_force_rfm = 1'b0,
    output logic                                         o_rfm_active,
    // Xung mỗi REFab định kỳ: cho bộ lọc SDC đếm đủ một chu kỳ tREFW trước khi xoá bộ đếm
    output logic                                         o_ref_tick,

    //-------------------------------------------------------------------------
    // Readiness & Slack Telemetry to Arbiter
    //-------------------------------------------------------------------------
    output logic [BG_COUNT-1:0]                          o_bg_ready,
    output logic                                         o_engine_ready,
    // Slot lệnh của từng bank còn trống: arbiter chỉ cấp lệnh cho bank có slot trống
    output logic [BG_COUNT*BANK_COUNT-1:0]               o_bank_free,
    // ABO hoặc drain trước REF/RFM: chỉ nhận lệnh giảm thiểu (arbiter giữ lệnh người dùng lại)
    output logic                                         o_engine_mit_only,
    output logic                                         o_slack_cycle,

    //-------------------------------------------------------------------------
    // Decoy Dummy Access Interface (Thang Hoang & S3ORAM / SledgeHammer defense)
    //-------------------------------------------------------------------------
    input  logic                                         cfg_decoy_en = 1'b0,
    // Địa chỉ mồi {bg, bank, row} tính sẵn bên ngoài bằng PRF có khoá (không suy được từ các decoy đã thấy);
    // o_decoy_take báo địa chỉ hiện tại đã dùng, nguồn hạ i_decoy_avail tới khi nạp xong địa chỉ mới
    input  logic                                         i_decoy_avail = 1'b0,
    input  logic [BG_WIDTH+BANK_WIDTH+ROW_WIDTH-1:0]     i_decoy_addr  = '0,
    output logic                                         o_decoy_take,
    output logic                                         o_decoy_active,
    output logic [15:0]                                  o_decoy_cnt,

    //-------------------------------------------------------------------------
    // DFI / DRAM Physical Command Interface
    //-------------------------------------------------------------------------
    output logic [2:0]                                   o_dfi_cmd,     // 0=NOP, 1=ACT, 2=PRE, 3=RD, 4=WR, 5=REFab, 6=RFMab
    output logic [BG_WIDTH-1:0]                          o_dfi_bg,
    output logic [BANK_WIDTH-1:0]                        o_dfi_bank,
    output logic [ROW_WIDTH-1:0]                         o_dfi_row,
    output logic [COL_WIDTH-1:0]                         o_dfi_col,
    // Pha dữ liệu DFI: tag/độ dài đi kèm lệnh CAS; dữ liệu đọc thật trả về theo thứ tự lệnh RD
    output logic [AXI_LEN_WIDTH-1:0]                     o_dfi_len,
    output logic [ROB_PTR_WIDTH-1:0]                     o_dfi_tag,
    input  logic                                         i_dfi_rddata_valid = 1'b0,
    input  logic [AXI_DATA_WIDTH-1:0]                    i_dfi_rddata = '0,

    //-------------------------------------------------------------------------
    // DRAM Read Data Return Path (to reorder_buffer_rob)
    //-------------------------------------------------------------------------
    output logic                                         o_wb_valid,
    output logic [ROB_PTR_WIDTH-1:0]                     o_wb_tag,
    output logic [AXI_DATA_WIDTH-1:0]                    o_wb_data,
    output logic [1:0]                                   o_wb_resp,
    output logic                                         o_wb_last,
    // Beat đọc của RMW: không vào ROB mà được trộn vào slot ghi (tag = tag lệnh ghi); o_wb_last dùng chung
    output logic                                         o_rmw_valid,
    output logic [AXI_LEN_WIDTH-1:0]                     o_rmw_beat,
    // Đồng bộ beat đọc: o_wb_err = beat hiện tại là beat tổng hợp của FLUSH (không phải dữ liệu thật, resp SLVERR);
    // o_rd_take = một phần tử FIFO beat được tiêu thụ; o_rd_beat_ok = beat thật được nhận đúng chu kỳ kỳ vọng;
    // o_rd_resync = xung ở chu kỳ đầu tiên trở lại đồng bộ (mọi FIFO theo beat phía ngoài phải đặt lại con trỏ)
    output logic                                         o_wb_err,
    output logic                                         o_rd_take,
    output logic                                         o_rd_beat_ok,
    output logic                                         o_rd_flush,
    output logic                                         o_rd_resync,

    //-------------------------------------------------------------------------
    // Two-Tier Decoupled Cryptographic Pre-computation Trigger Interface
    //-------------------------------------------------------------------------
    output logic                                         o_precomp_valid,
    output logic                                         o_precomp_is_write,
    output logic [ROB_PTR_WIDTH-1:0]                     o_precomp_tag,
    output logic [33:0]                                  o_precomp_addr,
    output logic [7:0]                                   o_precomp_key_id
);

    // DFI Command Encodings
    localparam logic [2:0] CMD_NOP = 3'b000;
    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_PRE = 3'b010;
    localparam logic [2:0] CMD_RD  = 3'b011;
    localparam logic [2:0] CMD_WR  = 3'b100;
    localparam logic [2:0] CMD_REF = 3'b101;
    localparam logic [2:0] CMD_RFM = 3'b110;

    // RowPress Non-Linear Dynamic Threshold Function (ISCA'23 & Chronus HPCA'25 model)
    function automatic logic [15:0] calc_dyn_rowpress_thresh(
        input logic [15:0] base_th,
        input logic [1:0]  curve,
        input logic [15:0] duration
    );
        logic [15:0] th;
        case (curve)
            2'b00: th = base_th; // 0: Static Baseline
            2'b01: begin // 1: Conservative Decay (75% -> 50% -> 25%)
                if (duration > 16'd4000)      th = (base_th >> 2);
                else if (duration > 16'd2000) th = (base_th >> 1);
                else if (duration > 16'd1000) th = base_th - (base_th >> 2);
                else                          th = base_th;
            end
            2'b10: begin // 2: Standard Decay (Chronus HPCA'25 Industrial Model)
                if (duration > 16'd3000)      th = (base_th >> 3);
                else if (duration > 16'd1500) th = (base_th >> 2);
                else if (duration > 16'd800)  th = (base_th >> 1);
                else if (duration > 16'd400)  th = base_th - (base_th >> 2);
                else                          th = base_th;
            end
            2'b11: begin // 3: Aggressive High-Duty Cycle (Sub-10nm DRAM Model)
                if (duration > 16'd2000)      th = 16'd128;
                else if (duration > 16'd1000) th = (base_th >> 3);
                else if (duration > 16'd500)  th = (base_th >> 2);
                else if (duration > 16'd200)  th = (base_th >> 1);
                else                          th = base_th;
            end
            default: th = base_th;
        endcase
        if (base_th < 16'd64)
            calc_dyn_rowpress_thresh = th;
        else if (th < 16'd64)
            calc_dyn_rowpress_thresh = 16'd64;
        else
            calc_dyn_rowpress_thresh = th;
    endfunction

    // PRAC / QPRAC Alert-Back-Off (ABO) Edge Detector & State
    logic                 dram_abo_d;
    // JEDEC PRAC: sau ALERT_n (ABO) bộ điều khiển phải phát RFM; yêu cầu được giữ tới khi RFMab phát xong
    logic                 abo_rfm_req;

    // McSee Defense: Autonomous Rolling ACT counters and RFM requests
    logic [7:0]           rolling_act_cnt [BG_COUNT];
    logic [BG_COUNT-1:0]  rfm_req;
    // Bộ đếm chéo (kiểu prim_count của OpenTitan): bản phụ đếm ngược, tổng hai bản luôn bằng 0xFF. Glitch xoá/giảm
    // bộ đếm chính để né RFM làm lệch tổng; phản ứng an toàn là coi BG đó đã tới ngưỡng và phát RFM ngay.
    logic [7:0]           rolling_act_inv [BG_COUNT];
    logic [BG_COUNT-1:0]  cnt_err;
    always_comb
        for (int bg = 0; bg < BG_COUNT; bg++) cnt_err[bg] = (rolling_act_cnt[bg] + rolling_act_inv[bg]) != 8'hFF;

    // Bank-Group level timing
    logic [3:0]           ccd_timer  [BG_COUNT];
    logic [2:0]           ccd_s_timer;
    // tCCD_L_WR chỉ ràng buộc WR -> WR cùng BG: timer riêng nạp khi WR, chỉ đi vào điều kiện của CAS ghi
    logic [3:0]           ccdw_timer [BG_COUNT];
    logic [BG_COUNT-1:0]  ccdw_z;

    // Refresh định kỳ: mỗi tREFI nợ thêm một REF; được hoãn khi có traffic nhưng không quá MAX_POSTPONE.
    // Không có REF định kỳ thì DRAM mất dữ liệu do hết thời gian lưu giữ và mọi giả định tREFW của bộ chống RowHammer sai (R22).
    // Bảo vệ tràn khi tăng (ref_owed == 7) và chạm đáy khi giảm (ref_owed == 0 lúc phát REF) kết hợp báo o_fault[4].
    // ref_owed có bản bù ref_owed_c ghi cùng giá trị kế tiếp (đảo bit): một bit lật 1 -> 0 làm mất nợ REF âm thầm,
    // nên khi hai bản lệch, giá trị dùng tiếp là OR của hai bản (không bao giờ nhỏ hơn bản đúng) và báo fault[4].
    logic [15:0]          refi_timer;
    logic [2:0]           ref_owed;
    (* keep = "true" *) logic [2:0] ref_owed_c;
    logic [7:0]           rfc_timer;
    // Loại lệnh refresh chốt khi vào drain, one-hot (khoảng cách Hamming 2): mã lỗi phát RFMab và giữ nợ REF
    localparam logic [1:0] K_REF = 2'b01, K_RFM = 2'b10;
    logic [1:0]           lat_kind;
    logic                 ref_mode;
    logic                 refresh_needed;
    // Bản đăng ký của (ref_mode || o_abo_active), tính từ cùng giá trị kế tiếp: cổng chặn lệnh người dùng ở arbiter
    // là một FF (đường arbiter giữ 2 đầu vào như v1), đồng thời là bản đối chiếu của ref_mode khi bị glitch.
    logic                 user_blk_q;
    // Watchdog drain: đếm chu kỳ trong ref_mode; quá REF_WD thì bỏ giữ mở mọi bank (lệnh hit ACT lại sau REF)
    logic [9:0]           ref_wd_cnt;
    logic                 ref_wd_exp;

    // Ràng buộc mật độ ACT: tRRD_S toàn cục, tRRD_L theo BG, tFAW bằng 4 bộ đếm lùi (còn slot về 0 thì được ACT).
    logic [3:0]           rrd_s_timer;
    logic [3:0]           rrd_l_timer [BG_COUNT];
    // tWTR: RD phải chờ hết dữ liệu ghi trước đó (CWL + BL) cộng tWTR_S (khác BG) / tWTR_L (cùng BG).
    logic [5:0]           wtr_s_timer;
    logic [5:0]           wtr_l_timer [BG_COUNT];
    logic [4:0]           faw_slot    [4];
    logic                 faw_ok;
    // Cờ "timer bằng 0" đăng ký từ giá trị kế tiếp của timer: điều kiện sẵn sàng của bank chỉ còn AND các flop,
    // không qua bộ so sánh nhiều bit trên đường chọn lệnh (Fmax 400 MHz). Cờ được đối chiếu với timer trong silicon
    // (flag_mis, đăng ký, ngoài đường chọn lệnh). rfc_z có bản sao độc lập rfc_z2: một bản lên 1 sai lúc tRFC chưa
    // hết vẫn bị bản kia chặn ACT/REF (vi phạm tRFC ảnh hưởng toàn rank).
    logic                 rrd_s_z, wtr_s_z, ccd_s_z, rfc_z;
    (* keep = "true" *) logic rfc_z2;
    logic [BG_COUNT-1:0]  rrd_l_z, wtr_l_z, ccd_z;

    // Bank cuối cùng có hoạt động (dùng để ghi lại vị trí ABO)
    logic [BG_WIDTH-1:0]   lat_bg;
    logic [BANK_WIDTH-1:0] lat_bank;
    logic [ROW_WIDTH-1:0]  lat_row;
    // ACT đang trên DFI thuộc lệnh refresh nạn nhân (telemetry/kiểm thử: phân biệt ACT giảm thiểu với ACT người dùng)
    logic                  dfi_act_mit;

    // Mốc PRE sớm nhất sau CAS (ras_timer nạp cùng cạnh CAS lên DFI, PRE lên DFI muộn hơn 1 chu kỳ):
    // WR: tWR tính từ beat ghi cuối = CWL + (len + 1) + tWR; RD: tRTP tính từ lệnh. 6 bit: T_CWL + 7 + T_WR = 28 ở
    // mặc định, 5 bit sẽ tràn âm thầm với 32 Gb hoặc DFI_WRLAT lớn hơn (giới hạn kiểm ở elaboration).
    function automatic logic [5:0] pre_after_cas(input logic is_wr, input logic [AXI_LEN_WIDTH-1:0] len);
        pre_after_cas = is_wr ? 6'(T_CWL + int'(len) + T_WR) : 6'(T_RTP);
    endfunction

    //=========================================================================
    // Bảng giao dịch theo bank (bank-parallel): mỗi bank giữ tối đa một lệnh đang chờ. Mỗi chu kỳ engine chọn
    // một lệnh DFI trong số các bank đã sẵn sàng (CAS > ACT > PRE, round-robin giữa các bank), nên tRCD/tRP/tRAS
    // của bank này chồng lên công việc của bank khác thay vì chặn toàn bộ engine như sequencer tuần tự cũ
    // (nguồn của chặn đầu hàng R20 và kênh thời gian xuyên bank).
    //=========================================================================
    localparam int NB = BG_COUNT * BANK_COUNT;
    localparam int IW = $clog2(NB);

    logic [ROW_WIDTH-1:0]     open_row [NB];
    logic [NB-1:0]            bank_open;
    logic [4:0]               rcd_timer [NB];
    logic [4:0]               rp_timer  [NB];
    logic [5:0]               ras_timer [NB];
    logic [NB-1:0]            rcd_z, rp_z, ras_z;
    logic [15:0]              act_duration [NB];
    logic [NB-1:0]            tras_clamp_pending;
    // Chốt một lần cảnh báo RowPress cho mỗi lần mở hàng: so sánh >= thay cho == vì ngưỡng động giảm dần theo thời gian mở,
    // phép bằng có thể bị ngưỡng "nhảy qua" và không bao giờ kích hoạt (curve 2/3).
    logic [NB-1:0]            rp_alerted;
    // Kết quả so sánh ngưỡng RowPress đã đăng ký: giữ bank chưa được báo ở trạng thái chờ thay vì đánh rơi
    logic [NB-1:0]            rp_due;
    // Hàng mở do refresh nạn nhân hoặc truy cập mồi: đóng lại khi đủ tRAS nếu bank không còn lệnh chờ
    logic [NB-1:0]            close_req;
    wire  [15:0]              effective_rp_thresh = (cfg_rowpress_thresh != 16'd0) ? cfg_rowpress_thresh : 16'(ROWPRESS_THRESH_DEFAULT);

    // Slot lệnh của từng bank
    logic [NB-1:0]            s_v, s_wr, s_mit, s_rmw;
    logic [1:0]               s_ph [NB];   // RMW: 0 = cần RD, 1 = chờ dữ liệu cũ trộn vào slot ghi, 2 = cần WR
    logic [ROW_WIDTH-1:0]     s_row [NB];
    logic [COL_WIDTH-1:0]     s_col [NB];
    logic [AXI_LEN_WIDTH-1:0] s_len [NB];
    logic [ROB_PTR_WIDTH-1:0] s_tag [NB];
    // Phân loại đăng ký: hàng của slot có đang mở không (32 phép so sánh song song, không qua mux 32:1).
    // Cũ một chu kỳ: chỉ dùng khi bank không vừa nhận lệnh mới hay ACT/PRE ở cạnh trước (k_chg).
    logic [NB-1:0]            k_hit, k_open, k_chg;

    function automatic logic [IW-1:0] bidx(input logic [BG_WIDTH-1:0] bg, input logic [BANK_WIDTH-1:0] bk);
        bidx = IW'({bg, bk});
    endfunction

    wire [IW-1:0] in_b   = bidx(i_cmd_bg, i_cmd_bank);
    wire          c_load = i_cmd_valid && !s_v[in_b];
    assign o_bank_free = ~s_v;

    // Ready calculations: arbiter không còn cần chờ tCCD (engine tự kiểm ở từng bank); giữ cổng để tương thích
    assign o_bg_ready = '1;
    wire abo_ok = !o_abo_active && !i_dram_abo_alert;
    // Mọi slot rỗng: dùng cho testbench đơn vị phát lệnh tuần tự
    assign o_engine_ready    = (s_v == '0) && abo_ok;
    // Chặn lệnh người dùng cả khi drain trước REF/RFM (không chỉ khi ABO): luồng hit liên tục giữ bank mở qua
    // keep_open và hoãn REF vô hạn (RT-01). Không chặn bằng o_bank_free vì cổng đó vào tầng cuối của hàng đợi QoS
    // (đường tới hạn); lệnh đã cấp ở chu kỳ trước khi user_blk_q lên vẫn được nạp (c_load không bị chặn).
    assign o_engine_mit_only = user_blk_q || i_dram_abo_alert;
    // Hoãn REF khi còn lệnh chờ (có traffic), nhưng không quá MAX_POSTPONE
    assign refresh_needed = ((ref_owed != '0) && ((s_v == '0) || ref_owed >= 3'(MAX_POSTPONE))) || (|rfm_req) || abo_rfm_req;

    // Kích hoạt Pre-computation cho Mật mã Hai Tầng
    assign o_precomp_valid    = c_load && !i_cmd_is_mitigation && !o_rfm_active;
    assign o_precomp_is_write = i_cmd_is_write;
    assign o_precomp_tag      = i_cmd_tag;
    assign o_precomp_addr     = 34'({i_cmd_row, i_cmd_bg, i_cmd_bank, i_cmd_col, 2'b00});
    assign o_precomp_key_id   = 8'h01;

    // Tra cờ RMW (ghi thiếu byte) của slot vừa nạp ở chu kỳ sau: slot chưa được phân loại trong chu kỳ đó
    logic          ld_q;
    logic [IW-1:0] ld_b_q;
    assign o_slice_tag = s_tag[ld_b_q];

    //=========================================================================
    // Theo dõi dữ liệu đọc trả về: DRAM trả beat theo đúng thứ tự lệnh RD, không kèm địa chỉ.
    // Mỗi RD đẩy {tag, độ dài, RMW, bank} vào FIFO; beat dữ liệu thật được gán tag đầu FIFO và chuyển sang ROB
    // (hoặc trộn vào slot ghi khi là RMW).
    //=========================================================================
    localparam int RT_DEPTH = 16;
    localparam int RT_W     = $clog2(RT_DEPTH);
    logic [ROB_PTR_WIDTH-1:0] rt_tag  [RT_DEPTH];
    logic [AXI_LEN_WIDTH-1:0] rt_len  [RT_DEPTH];
    logic [IW-1:0]            rt_bank [RT_DEPTH];
    logic [RT_DEPTH-1:0]      rt_rmw;
    logic [RT_W:0]            rt_wr, rt_rd;
    logic [AXI_LEN_WIDTH-1:0] rt_beat;
    logic                     cas_rmw_q;
    logic [IW-1:0]            cas_b_q;
    wire  [RT_W-1:0]          rt_head = rt_rd[RT_W-1:0];
    wire                      rt_ne   = (rt_wr != rt_rd);
    // Ghi FIFO từ thanh ghi lệnh DFI (một chu kỳ sau RD; dữ liệu về sau T_CL >= 2): mảng không cần reset
    always_ff @(posedge clk)
        if (o_dfi_cmd == CMD_RD) begin
            rt_tag[rt_wr[RT_W-1:0]]  <= o_dfi_tag;
            rt_len[rt_wr[RT_W-1:0]]  <= o_dfi_len;
            rt_rmw[rt_wr[RT_W-1:0]]  <= cas_rmw_q;
            rt_bank[rt_wr[RT_W-1:0]] <= cas_b_q;
        end

    // Ràng buộc beat với lệnh: độ trễ RD -> beat cố định (T_RDV), nên mỗi RD trên DFI đặt len+1 bit vào thanh ghi
    // dịch exp_v (bit k = "kỳ vọng một beat ở chu kỳ hiện tại + k"). Ở RS_SYNC chỉ beat tới đúng chu kỳ kỳ vọng được
    // nhận; beat thừa hay thiếu (glitch dfi_rddata_valid, PHY lệch) chuyển sang RS_FLUSH ngay chu kỳ sau thay vì lệch
    // tag vĩnh viễn và trả dữ liệu của RD khác với OKAY (RT-03). Ở RS_FLUSH mỗi chu kỳ phát một beat tổng hợp cho tag
    // đầu FIFO với SLVERR (không treo master, không rò dữ liệu), không phát RD mới, và trở lại RS_SYNC khi FIFO, lịch
    // beat và bus đã rỗng. rd_st mã Hamming 2: 00/11 xử lý như FLUSH và báo lỗi.
    localparam int            EV_W     = T_RDV + 7;
    localparam logic [1:0]    RS_SYNC  = 2'b01, RS_FLUSH = 2'b10;
    logic [1:0]               rd_st;
    logic [EV_W-1:0]          exp_v;
    logic [EV_W-1:0]          exp_ins;
    always_comb
        exp_ins = (o_dfi_cmd == CMD_RD) ? (EV_W'((9'd2 << o_dfi_len[2:0]) - 9'd1) << (T_RDV - 1)) : '0;
    wire rd_syn     = (rd_st == RS_SYNC);
    wire rd_flush   = !rd_syn;
    wire rd_st_bad  = !rd_syn && (rd_st != RS_FLUSH);
    wire rd_take    = rd_syn ? (i_dfi_rddata_valid && exp_v[0] && rt_ne) : rt_ne;
    wire desync_c   = rd_syn && ((i_dfi_rddata_valid != exp_v[0]) || (exp_v[0] && !rt_ne));
    // RD đang trên DFI chưa có trong rt_wr/exp_v (chỉ nạp ở cạnh sau) nên phải chờ nó
    wire flush_done = (rd_st == RS_FLUSH) && !rt_ne && (exp_v == '0) && !i_dfi_rddata_valid && (o_dfi_cmd != CMD_RD);

    assign o_wb_valid   = rd_take && !rt_rmw[rt_head];
    assign o_rmw_valid  = rd_take &&  rt_rmw[rt_head];
    assign o_rmw_beat   = rt_beat;
    assign o_wb_tag     = rt_tag[rt_head];
    assign o_wb_data    = i_dfi_rddata;
    assign o_wb_err     = rd_flush;
    assign o_wb_resp    = rd_flush ? 2'b10 : 2'b00;
    assign o_wb_last    = (rt_beat == rt_len[rt_head]);
    assign o_rd_take    = rd_take;
    assign o_rd_beat_ok = rd_take && rd_syn;
    assign o_rd_flush   = rd_flush;
    // RMW gặp FLUSH vẫn chuyển sang pha WR (bank không treo); dữ liệu cũ đánh dấu lỗi nên khối đỉnh ghi kèm poison
    wire   rmw_done     = o_rmw_valid && o_wb_last;
    wire [IW-1:0] rmw_done_b = rt_bank[rt_head];

    // Chiếm dụng bus DQ có hướng: RD dùng [t+T_CL, t+T_CL+L], WR dùng [t+T_CWL, t+T_CWL+L].
    // CAS mới chỉ được phát khi cửa sổ dữ liệu của nó bắt đầu sau khi bus rảnh (chặn đè đọc-đọc và đọc-ghi).
    logic [5:0] dq_busy;
    logic       dq_wr_ok, dq_rd_ok;
    wire  [5:0] dq_dec = (dq_busy != '0) ? dq_busy - 1'b1 : '0;
    // ACT/WR phát ở cạnh trước còn trên DFI, timer của nó chỉ nạp ở cạnh này: flop riêng cho cổng chặn tức thời.
    // Sự kiện nạp tRRD/tFAW/tWTR và đếm RAA lấy OR của flop đó với giải mã thanh ghi lệnh DFI: một trong hai bản bị
    // xoá (glitch) vẫn nạp timer và đếm ACT; hai bản lệch nhau là lỗi (fault[2]) và ép RFMab.
    logic       last_act, last_wr;
    wire act_dec  = (o_dfi_cmd == CMD_ACT);
    wire wr_dec   = (o_dfi_cmd == CMD_WR);
    wire act_ev   = last_act | act_dec;
    wire wr_ev    = last_wr | wr_dec;
    wire ev_mis   = (last_act ^ act_dec) | (last_wr ^ wr_dec);
    wire act_gate = !last_act && rrd_s_z && faw_ok && rfc_z && rfc_z2;
    wire rd_gate  = !last_wr && wtr_s_z && !rd_flush;
    // Số hạng theo BG tính trước (tCCD_L, tCCD_L_WR, tWTR_L, cửa sổ DQ): điều kiện CAS theo bank không thêm đầu vào
    logic [BG_COUNT-1:0] wr_ok_g, rd_ok_g;
    always_comb
        for (int g = 0; g < BG_COUNT; g++) begin
            wr_ok_g[g] = dq_wr_ok && ccd_z[g] && ccdw_z[g];
            rd_ok_g[g] = dq_rd_ok && rd_gate && wtr_l_z[g] && ccd_z[g];
        end
    // Số hạng toàn cục của keep_open: drain khi ABO, hoặc watchdog drain hết hạn
    wire ko_glob = !(ref_mode && !abo_ok) && !ref_wd_exp;

    //=========================================================================
    // Điều kiện sẵn sàng theo bank: chỉ là AND của các flop (cờ *_z, phân loại k_*, trạng thái slot)
    //=========================================================================
    logic [NB-1:0] cas_rdy, cas_is_wr, act_rdy, pre_rdy, pre_clamp, mit_done, ras_lt;
    logic [5:0]    pac [NB];
    always_comb begin
        for (int b = 0; b < NB; b++) begin
            logic fresh, user_ok, want_cas, want_pre, keep_open;
            int   g;
            g        = b / BANK_COUNT;
            fresh    = !k_chg[b];
            // ABO: chỉ lệnh giảm thiểu được tiến; RMW đang chờ trộn dữ liệu không phát CAS
            user_ok  = abo_ok && !s_mit[b];
            want_cas = s_v[b] && fresh && user_ok && k_hit[b] && !tras_clamp_pending[b] &&
                       !(s_rmw[b] && s_ph[b] == 2'd1);
            cas_is_wr[b] = s_wr[b] && (!s_rmw[b] || s_ph[b] == 2'd2);
            cas_rdy[b] = want_cas && rcd_z[b] && ccd_s_z && (cas_is_wr[b] ? wr_ok_g[g] : rd_ok_g[g]);
            // Refresh nạn nhân: hàng nạn nhân đang mở nghĩa là đã được làm tươi lúc ACT
            mit_done[b] = s_v[b] && fresh && s_mit[b] && k_hit[b];
            act_rdy[b]  = s_v[b] && fresh && !k_open[b] && (abo_ok || s_mit[b]) && !ref_mode &&
                          rp_z[b] && rrd_l_z[g] && act_gate;
            // Bank giữ mở khi slot của nó còn CAS tới đúng hàng đang mở (kể cả RMW đang chờ trộn)
            keep_open   = s_v[b] && k_hit[b] && !s_mit[b] && !tras_clamp_pending[b] && ko_glob;
            want_pre    = k_open[b] && fresh && !keep_open &&
                          ((s_v[b] && !k_hit[b]) || close_req[b] || ref_mode || tras_clamp_pending[b]);
            pre_rdy[b]  = want_pre && ras_z[b] && rcd_z[b];
            pre_clamp[b] = tras_clamp_pending[b] && (cfg_tras_max_thresh != 16'd0);
            // Mốc PRE sau CAS của slot tính sẵn song song (không qua mux theo bank được chọn)
            pac[b]      = pre_after_cas(cas_is_wr[b], s_len[b]);
            ras_lt[b]   = ras_timer[b] < pac[b];
        end
    end

    // Round-robin find-first: ưu tiên bank ngay sau bank vừa được phục vụ. Mặt nạ "chỉ số > rr_ptr" giải mã thẳng từ
    // thanh ghi con trỏ; find-first trên phần trên mặt nạ và trên toàn bộ chạy song song rồi chọn bằng một mux.
    logic [IW-1:0] rr_ptr;
    logic [NB-1:0] rr_mask;
    always_comb
        for (int i = 0; i < NB; i++) rr_mask[i] = (i > int'(rr_ptr));
    function automatic logic [NB-1:0] ffs(input logic [NB-1:0] x);
        ffs = x & (~x + NB'(1));
    endfunction
    function automatic logic [NB-1:0] rr_pick(input logic [NB-1:0] req, input logic [NB-1:0] mask);
        rr_pick = ((req & mask) != '0) ? ffs(req & mask) : ffs(req);
    endfunction
    function automatic logic [IW-1:0] oh2idx(input logic [NB-1:0] oh);
        oh2idx = '0;
        for (int i = 0; i < NB; i++) if (oh[i]) oh2idx = oh2idx | IW'(i);
    endfunction

    wire           any_cas  = |cas_rdy;
    wire           any_act  = |act_rdy;
    wire           any_pre  = |pre_rdy;

    // Bộ lập lịch hai tầng. Tầng 1 chọn ứng viên (bank one-hot + loại lệnh, CAS > ACT > PRE, round-robin) từ điều kiện
    // sẵn sàng của chu kỳ này và đăng ký lại; tầng 2 phát ứng viên đó nếu điều kiện sẵn sàng hiện tại của chính bank
    // đó vẫn đúng. Mọi ràng buộc JEDEC vì vậy được kiểm tra đúng ở chu kỳ phát, còn chuỗi find-first 32 bit không còn
    // nằm chung đường với cập nhật timer/slot (Fmax 400 MHz). Tầng 1 bỏ qua bank đang nằm ở tầng 2 và hạ ưu tiên loại
    // lệnh tầng 2 sắp phát (CAS kế tiếp chắc chắn bị tCCD_S chặn, ACT kế tiếp bị tRRD chặn) để không phí lượt.
    localparam logic [2:0] PK_NONE = 3'd0, PK_CAS = 3'd1, PK_ACT = 3'd2, PK_PRE = 3'd3, PK_DEC = 3'd4;
    logic [NB-1:0]        pk_oh;
    logic [2:0]           pk_t;
    logic [ROW_WIDTH-1:0] pk_drow;
    wire  [NB-1:0] c1 = cas_rdy & ~pk_oh;
    wire  [NB-1:0] a1 = act_rdy & ~pk_oh;
    wire  [NB-1:0] p1 = pre_rdy & ~pk_oh;
    wire           cas_late = (pk_t == PK_CAS) && (T_CCD_S > 1);
    wire           act_late = (pk_t == PK_ACT);
    logic [NB-1:0] nxt_oh;
    logic [2:0]    nxt_t;
    // Truy cập mồi là loại ứng viên thấp nhất của tầng 1 (khi không còn việc nào): địa chỉ {bg, bank, row} từ PRF ngoài
    // được chốt ở tầng 1, tầng 2 chỉ kiểm tra lại điều kiện JEDEC của đúng bank đó
    wire [BG_WIDTH-1:0]   decoy_bg   = i_decoy_addr[BG_WIDTH+BANK_WIDTH+ROW_WIDTH-1 -: BG_WIDTH];
    wire [BANK_WIDTH-1:0] decoy_bank = i_decoy_addr[ROW_WIDTH +: BANK_WIDTH];
    wire [ROW_WIDTH-1:0]  decoy_row  = i_decoy_addr[ROW_WIDTH-1:0];
    wire [IW-1:0]         decoy_b    = bidx(decoy_bg, decoy_bank);
    wire                  decoy_c    = cfg_decoy_en && i_decoy_avail && !any_cas && !any_act && !any_pre && !ref_mode && abo_ok && (pk_t != PK_DEC);
    always_comb begin
        if ((|c1) && !cas_late)      begin nxt_oh = rr_pick(c1, rr_mask); nxt_t = PK_CAS; end
        else if ((|a1) && !act_late) begin nxt_oh = rr_pick(a1, rr_mask); nxt_t = PK_ACT; end
        else if (|p1)                begin nxt_oh = rr_pick(p1, rr_mask); nxt_t = PK_PRE; end
        else if (decoy_c)            begin nxt_oh = NB'(1) << decoy_b;    nxt_t = PK_DEC; end
        else                         begin nxt_oh = '0;                   nxt_t = PK_NONE; end
    end

    // Tầng 2: sự kiện phát one-hot theo bank; mọi cập nhật trạng thái bank dùng thẳng bit này
    wire [NB-1:0]  iss_cas  = (pk_t == PK_CAS) ? (pk_oh & cas_rdy) : '0;
    wire [NB-1:0]  iss_act  = (pk_t == PK_ACT) ? (pk_oh & act_rdy) : '0;
    wire [NB-1:0]  iss_pre  = (pk_t == PK_PRE) ? (pk_oh & pre_rdy) : '0;
    wire           is_cas   = |iss_cas;
    wire           is_act   = |iss_act;
    wire           is_pre   = |iss_pre;
    wire [NB-1:0]  pick     = iss_cas | iss_act | iss_pre;
    // Chỉ số và trường lấy từ ứng viên đã đăng ký (không phụ thuộc phép kiểm tra lại)
    wire [IW-1:0]  pick_b   = oh2idx(pk_oh);
    // REF/RFM khi mọi bank đã đóng đủ tRP và tRFC trước đó đã hết (kiểm cả hai bản sao rfc_z và rfc_z2).
    wire           all_closed  = (bank_open == '0);
    wire           any_rp_busy = (rp_z != '1);
    wire           do_ref  = ref_mode && all_closed && !any_rp_busy && rfc_z && rfc_z2 && (o_dfi_cmd != CMD_PRE);
    // Truy cập mồi: ACT một hàng ngẫu nhiên ở bank đang đóng, không có lệnh chờ, khi không còn việc nào khác
    logic [NB-1:0] dec_rdy;
    always_comb
        for (int b = 0; b < NB; b++)
            dec_rdy[b] = !bank_open[b] && !s_v[b] && rp_z[b] && rrd_l_z[b / BANK_COUNT];
    wire           do_decoy = (pk_t == PK_DEC) && cfg_decoy_en && !ref_mode && abo_ok && act_gate &&
                              ((pk_oh & dec_rdy) != '0);
    wire [NB-1:0]  iss_dec = do_decoy ? pk_oh : '0;
    assign o_decoy_take = do_decoy || ((pk_t == PK_DEC) && ((pk_oh & dec_rdy) == '0));

    // Trường của slot được chọn: AND-OR theo one-hot thay cho mux 32:1 theo chỉ số
    logic [ROW_WIDTH-1:0]     sel_row;
    logic [COL_WIDTH-1:0]     sel_col;
    logic [AXI_LEN_WIDTH-1:0] sel_len;
    logic [ROB_PTR_WIDTH-1:0] sel_tag;
    logic [5:0]               sel_dq;
    logic [BG_COUNT-1:0]      sel_bg_oh;
    logic                     sel_wr_ok, sel_rd_ok;
    logic [ROW_WIDTH-1:0]     row_cas;
    always_comb begin
        row_cas = '0; sel_col = '0; sel_len = '0; sel_tag = '0;
        sel_dq = '0; sel_bg_oh = '0; sel_wr_ok = 1'b0; sel_rd_ok = 1'b0;
        for (int b = 0; b < NB; b++) begin
            logic [5:0] dq_load;
            dq_load = (cas_is_wr[b] ? 6'(T_CWL) : 6'(T_CL)) + 6'(s_len[b]);
            if (pk_oh[b]) begin
                row_cas   = row_cas   | s_row[b];
                sel_col   = sel_col   | s_col[b];
                sel_len   = sel_len   | s_len[b];
                sel_tag   = sel_tag   | s_tag[b];
                sel_dq    = sel_dq    | dq_load;
                sel_wr_ok = sel_wr_ok | (6'(T_CWL) > dq_load);
                sel_rd_ok = sel_rd_ok | (6'(T_CL)  > dq_load);
                sel_bg_oh[b / BANK_COUNT] = 1'b1;
            end
        end
        sel_row = row_cas;
    end
    wire sel_is_wr  = |(pk_oh & cas_is_wr);
    wire sel_rmw    = |(pk_oh & s_rmw);
    wire sel_mit    = |(pk_oh & s_mit);
    // Kẹp tRAS(max) vừa được phát. Cảnh báo được đăng ký và phát ở chu kỳ sau từ bank đã lưu (open_row giữ nguyên sau
    // PRE): đường chọn lệnh không phải đi tiếp qua mux cảnh báo RowPress.
    wire           clamp_fire = |(iss_pre & pre_clamp);
    logic          clamp_q;
    logic [IW-1:0] clamp_b_q;

    // tFAW: trạng thái kế tiếp của 4 slot; faw_ok đăng ký = còn slot về 0
    logic [4:0] faw_n [4];
    always_comb begin
        logic loaded;
        loaded = 1'b0;
        for (int k = 0; k < 4; k++) begin
            faw_n[k] = (faw_slot[k] != '0) ? faw_slot[k] - 1'b1 : '0;
            // ACT vừa phát ở chu kỳ trước chiếm một slot tFAW (dùng act_ev để chống glitch xoá last_act)
            if (act_ev && !loaded && faw_slot[k] == '0) begin
                faw_n[k] = 5'((T_FAW > 2) ? T_FAW - 2 : 0);
                loaded   = 1'b1;
            end
        end
    end

    // Phát hiện lỗi phần cứng trong silicon (ngoài đường chọn lệnh tới hạn)
    logic flag_err;
    always_comb begin
        flag_err = (ccd_s_z  != (ccd_s_timer == '0)) ||
                   (rrd_s_z  != (rrd_s_timer == '0)) ||
                   (wtr_s_z  != (wtr_s_timer == '0)) ||
                   (rfc_z    != (rfc_timer   == '0)) ||
                   (rfc_z2   != (rfc_timer   == '0)) ||
                   (rfc_z    != rfc_z2)              ||
                   (dq_wr_ok != (6'(T_CWL) > dq_busy)) ||
                   (dq_rd_ok != (6'(T_CL)  > dq_busy));
        for (int bg = 0; bg < BG_COUNT; bg++) begin
            if ((ccd_z[bg]   != (ccd_timer[bg]   == '0)) ||
                (ccdw_z[bg]  != (ccdw_timer[bg]  == '0)) ||
                (rrd_l_z[bg] != (rrd_l_timer[bg] == '0)) ||
                (wtr_l_z[bg] != (wtr_l_timer[bg] == '0)))
                flag_err = 1'b1;
        end
        for (int b = 0; b < NB; b++) begin
            if ((rcd_z[b] != (rcd_timer[b] == '0)) ||
                (rp_z[b]  != (rp_timer[b]  == '0)) ||
                (ras_z[b] != (ras_timer[b] == '0)))
                flag_err = 1'b1;
        end
    end

    // Bản bù của ref_owed (Q7): khi lệch, giá trị dùng tiếp là OR của hai bản (owed_rep == ref_owed khi khớp)
    wire        refi_tick = (refi_timer <= 16'd1);
    wire        owed_mis  = (ref_owed != ~ref_owed_c);
    wire [2:0]  owed_rep  = ref_owed | ~ref_owed_c;

    wire user_blk_err = (user_blk_q != (ref_mode || o_abo_active));
    wire wd_err       = ref_wd_exp || (ref_mode && (ref_wd_cnt >= 10'(REF_WD)));
    wire lat_kind_err = (lat_kind != K_REF) && (lat_kind != K_RFM);
    wire ref_uf_err   = ref_mode && (lat_kind == K_REF) && (ref_owed == 3'd0);
    wire ref_of_err   = (refi_timer <= 16'd1) && (ref_owed == 3'd7) && !(do_ref && (lat_kind == K_REF));
    wire ref_err      = user_blk_err || wd_err || lat_kind_err || ref_uf_err || ref_of_err || owed_mis;
    wire slot_ovf_err = i_cmd_valid && s_v[in_b];

    assign o_cnt_fault   = o_fault[1];
    assign o_slack_cycle = (s_v == '0) && (o_dfi_cmd == CMD_NOP);

    //=========================================================================
    // Main Timing and Command Sequencer
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_dfi_cmd         <= CMD_NOP;
            o_dfi_bg          <= '0;
            o_dfi_bank        <= '0;
            o_dfi_row         <= '0;
            o_dfi_col         <= '0;
            o_dfi_len         <= '0;
            o_dfi_tag         <= '0;
            lat_bg            <= '0;
            lat_bank          <= '0;
            lat_row           <= '0;
            cas_rmw_q         <= 1'b0;
            cas_b_q           <= '0;
            dfi_act_mit       <= 1'b0;
            last_act          <= 1'b0;
            last_wr           <= 1'b0;
            clamp_q           <= 1'b0;
            clamp_b_q         <= '0;
            pk_oh             <= '0;
            pk_t              <= PK_NONE;
            pk_drow           <= '0;
            rr_ptr            <= '0;
            ld_q              <= 1'b0;
            ld_b_q            <= '0;

            ccd_s_timer       <= '0;
            ccd_s_z           <= 1'b1;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                ccd_timer[bg]  <= '0;
                ccdw_timer[bg] <= '0;
            end
            ccd_z              <= '1;
            ccdw_z             <= '1;
            bank_open          <= '0;
            tras_clamp_pending <= '0;
            rp_alerted         <= '0;
            rp_due             <= '0;
            close_req          <= '0;
            s_v                <= '0;
            s_rmw              <= '0;
            k_hit              <= '0;
            k_open             <= '0;
            k_chg              <= '1;
            rcd_z              <= '1;
            rp_z               <= '1;
            ras_z              <= '1;
            for (int b = 0; b < NB; b++) begin
                open_row[b]     <= '0;
                rcd_timer[b]    <= '0;
                rp_timer[b]     <= '0;
                ras_timer[b]    <= '0;
                act_duration[b] <= 16'd0;
                s_ph[b]         <= '0;
            end

            rt_wr             <= '0;
            rt_rd             <= '0;
            rt_beat           <= '0;
            rd_st             <= RS_SYNC;
            exp_v             <= '0;
            o_rd_resync       <= 1'b0;
            dq_busy           <= '0;
            dq_wr_ok          <= (T_CWL > 0);
            dq_rd_ok          <= (T_CL > 0);

            o_rowpress_alert     <= 1'b0;
            o_rowpress_bg        <= '0;
            o_rowpress_bank      <= '0;
            o_rowpress_row       <= '0;
            o_rowpress_alert_cnt <= 16'd0;
            o_tras_clamped_alert <= 1'b0;
            o_tras_clamped_cnt   <= 16'd0;
            o_rfm_auto_cnt       <= 16'd0;
            o_rfm_active         <= 1'b0;
            o_ref_tick           <= 1'b0;
            refi_timer           <= 16'(T_REFI);
            rrd_s_timer          <= '0;
            rrd_s_z              <= 1'b1;
            for (int bg = 0; bg < BG_COUNT; bg++) rrd_l_timer[bg] <= '0;
            rrd_l_z              <= '1;
            wtr_s_timer          <= '0;
            wtr_s_z              <= 1'b1;
            for (int bg = 0; bg < BG_COUNT; bg++) wtr_l_timer[bg] <= '0;
            wtr_l_z              <= '1;
            for (int k = 0; k < 4; k++) faw_slot[k] <= '0;
            faw_ok               <= 1'b1;
            ref_owed             <= '0;
            ref_owed_c           <= '1;
            rfc_timer            <= '0;
            rfc_z                <= 1'b1;
            rfc_z2               <= 1'b1;
            lat_kind             <= K_REF;
            ref_mode             <= 1'b0;
            user_blk_q           <= 1'b0;
            ref_wd_cnt           <= '0;
            ref_wd_exp           <= 1'b0;
            rfm_req              <= '0;
            for (int bg = 0; bg < BG_COUNT; bg++) rolling_act_cnt[bg] <= 8'd0;
            for (int bg = 0; bg < BG_COUNT; bg++) rolling_act_inv[bg] <= 8'hFF;
            o_fault              <= '0;

            dram_abo_d           <= 1'b0;
            abo_rfm_req          <= 1'b0;
            o_abo_active         <= 1'b0;
            o_abo_alert_cnt      <= 16'd0;
            o_abo_bg             <= '0;
            o_abo_bank           <= '0;
            o_abo_row            <= '0;
            o_decoy_active       <= 1'b0;
            o_decoy_cnt          <= 16'd0;
        end else begin
            logic ref_mode_n;
            logic abo_active_n;

            o_tras_clamped_alert <= 1'b0;
            o_rfm_active         <= 1'b0;
            o_decoy_active       <= 1'b0;
            o_ref_tick           <= 1'b0;
            o_rowpress_alert     <= 1'b0;
            o_rd_resync          <= 1'b0;
            o_dfi_cmd            <= CMD_NOP;
            dfi_act_mit          <= 1'b0;
            last_act             <= 1'b0;
            last_wr              <= 1'b0;

            // Đăng ký vector lỗi phần cứng
            o_fault[1] <= |cnt_err;
            o_fault[2] <= ev_mis;
            o_fault[3] <= flag_err;
            o_fault[4] <= ref_err;
            o_fault[5] <= desync_c || rd_st_bad;
            o_fault[6] <= slot_ovf_err;

            // 1. Timers: đếm lùi, cờ *_z nhận "giá trị kế tiếp bằng 0"; nơi nạp timer ghi đè cả cờ
            if (rfc_timer != '0)   rfc_timer   <= rfc_timer - 1'b1;
            if (rrd_s_timer != '0) rrd_s_timer <= rrd_s_timer - 1'b1;
            if (wtr_s_timer != '0) wtr_s_timer <= wtr_s_timer - 1'b1;
            if (ccd_s_timer != '0) ccd_s_timer <= ccd_s_timer - 1'b1;
            rfc_z    <= (rfc_timer   <= 8'd1);
            rfc_z2   <= (rfc_timer   <= 8'd1);
            rrd_s_z  <= (rrd_s_timer <= 4'd1);
            wtr_s_z  <= (wtr_s_timer <= 6'd1);
            ccd_s_z  <= (ccd_s_timer <= 3'd1);
            dq_busy  <= dq_dec;
            dq_wr_ok <= 6'(T_CWL) > dq_dec;
            dq_rd_ok <= 6'(T_CL)  > dq_dec;
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                if (rrd_l_timer[bg] != '0) rrd_l_timer[bg] <= rrd_l_timer[bg] - 1'b1;
                if (wtr_l_timer[bg] != '0) wtr_l_timer[bg] <= wtr_l_timer[bg] - 1'b1;
                if (ccd_timer[bg]   != '0) ccd_timer[bg]   <= ccd_timer[bg]   - 1'b1;
                if (ccdw_timer[bg]  != '0) ccdw_timer[bg]  <= ccdw_timer[bg]  - 1'b1;
                rrd_l_z[bg] <= (rrd_l_timer[bg] <= 4'd1);
                wtr_l_z[bg] <= (wtr_l_timer[bg] <= 6'd1);
                ccd_z[bg]   <= (ccd_timer[bg]   <= 4'd1);
                ccdw_z[bg]  <= (ccdw_timer[bg]  <= 4'd1);
            end
            for (int b = 0; b < NB; b++) begin
                if (rcd_timer[b] != '0) rcd_timer[b] <= rcd_timer[b] - 1'b1;
                if (rp_timer[b]  != '0) rp_timer[b]  <= rp_timer[b]  - 1'b1;
                if (ras_timer[b] != '0) ras_timer[b] <= ras_timer[b] - 1'b1;
                rcd_z[b] <= (rcd_timer[b] <= 5'd1);
                rp_z[b]  <= (rp_timer[b]  <= 5'd1);
                ras_z[b] <= (ras_timer[b] <= 6'd1);
            end
            begin
                logic ok;
                ok = 1'b0;
                for (int k = 0; k < 4; k++) begin
                    faw_slot[k] <= faw_n[k];
                    if (faw_n[k] == '0) ok = 1'b1;
                end
                faw_ok <= ok;
            end
            // Timer nạp T-2 ở chu kỳ lệnh xuất hiện trên DFI: dùng act_ev / wr_ev để chống glitch xoá last_act / last_wr
            if (act_ev) begin
                rrd_s_timer           <= 4'((T_RRD_S > 2) ? T_RRD_S - 2 : 0);
                rrd_s_z               <= !(T_RRD_S > 2);
                rrd_l_timer[o_dfi_bg] <= 4'((T_RRD_L > 2) ? T_RRD_L - 2 : 0);
                rrd_l_z[o_dfi_bg]     <= !(T_RRD_L > 2);
                // McSee: đếm ACT cuốn chiếu theo BG cho RFM tự trị
                if (rolling_act_cnt[o_dfi_bg] < 8'hFF) begin
                    rolling_act_cnt[o_dfi_bg] <= rolling_act_cnt[o_dfi_bg] + 1'b1;
                    rolling_act_inv[o_dfi_bg] <= rolling_act_inv[o_dfi_bg] - 1'b1;
                    if (rolling_act_cnt[o_dfi_bg] + 1'b1 >= (cfg_raammt_thresh != 8'd0 ? cfg_raammt_thresh : 8'd32))
                        rfm_req[o_dfi_bg] <= 1'b1;
                end
            end
            if (wr_ev) begin
                wtr_s_timer           <= 6'(T_CWL + T_WTR_S - 1) + 6'(o_dfi_len);
                wtr_s_z               <= (6'(T_CWL + T_WTR_S - 1) + 6'(o_dfi_len)) == '0;
                wtr_l_timer[o_dfi_bg] <= 6'(T_CWL + T_WTR_L - 1) + 6'(o_dfi_len);
                wtr_l_z[o_dfi_bg]     <= (6'(T_CWL + T_WTR_L - 1) + 6'(o_dfi_len)) == '0;
            end
            for (int bg = 0; bg < BG_COUNT; bg++) begin
                if (cnt_err[bg]) begin
                    rfm_req[bg]         <= 1'b1;
                    rolling_act_cnt[bg] <= 8'd0;
                    rolling_act_inv[bg] <= 8'hFF;
                end
            end
            if (i_force_rfm || ev_mis) rfm_req <= '1;
            if (lat_kind_err) lat_kind <= K_RFM;

            if (owed_mis) begin
                ref_owed   <= owed_rep;
                ref_owed_c <= ~owed_rep;
            end
            if (refi_timer <= 16'd1) begin
                refi_timer <= 16'(T_REFI);
                if (owed_rep != 3'd7) begin
                    ref_owed   <= owed_rep + 1'b1;
                    ref_owed_c <= ~(owed_rep + 1'b1);
                end
            end else begin
                refi_timer <= refi_timer - 1'b1;
            end

            ref_mode_n = ref_mode;
            if (do_ref) begin
                ref_mode_n = 1'b0;
            end else if (refresh_needed && !ref_mode) begin
                // REFab/RFMab yêu cầu mọi bank đã precharge: chặn ACT mới, CAS đang chờ được hoàn tất, rồi đóng bank
                ref_mode_n = 1'b1;
                lat_kind   <= ((ref_owed < 3'(MAX_POSTPONE)) && ((|rfm_req) || abo_rfm_req)) ? K_RFM : K_REF;
            end
            ref_mode <= ref_mode_n;

            if (!ref_mode || do_ref) begin
                ref_wd_cnt <= '0;
                ref_wd_exp <= 1'b0;
            end else begin
                if (ref_wd_cnt < 10'(REF_WD)) ref_wd_cnt <= ref_wd_cnt + 1'b1;
                if (ref_wd_cnt >= 10'(REF_WD - 1)) ref_wd_exp <= 1'b1;
            end

            // 2. PRAC / QPRAC Alert-Back-Off (ABO) Handshake Processing
            dram_abo_d   <= i_dram_abo_alert;
            abo_active_n = o_abo_active;
            if (i_dram_abo_alert && !dram_abo_d) begin
                abo_rfm_req     <= 1'b1;
                abo_active_n    = 1'b1;
                o_abo_alert_cnt <= o_abo_alert_cnt + 1'b1;
                o_abo_bg        <= lat_bg;
                o_abo_bank      <= lat_bank;
                o_abo_row       <= bank_open[bidx(lat_bg, lat_bank)] ? open_row[bidx(lat_bg, lat_bank)] : lat_row;
            end else if (!i_dram_abo_alert) begin
                abo_active_n    = 1'b0;
            end
            o_abo_active <= abo_active_n;
            user_blk_q   <= ref_mode_n || abo_active_n;

            // 3. RowPress: thời gian mở của từng bank, ngưỡng động, kẹp tRAS(max)
            for (int b = 0; b < NB; b++) begin
                if (bank_open[b]) begin
                    logic [15:0] dyn;
                    dyn = calc_dyn_rowpress_thresh(effective_rp_thresh, cfg_rowpress_curve, act_duration[b]);
                    if (act_duration[b] < 16'hFFFF) act_duration[b] <= act_duration[b] + 1'b1;
                    if (cfg_tras_max_thresh != 16'd0 && act_duration[b] >= cfg_tras_max_thresh) tras_clamp_pending[b] <= 1'b1;
                    rp_due[b] <= !rp_alerted[b] && (act_duration[b] >= dyn);
                end else begin
                    act_duration[b]       <= 16'd0;
                    tras_clamp_pending[b] <= 1'b0;
                    rp_alerted[b]         <= 1'b0;
                    rp_due[b]             <= 1'b0;
                end
            end
            // Mỗi chu kỳ báo đúng một bank đang chờ cảnh báo RowPress; bank còn lại được báo ở các chu kỳ sau
            begin
                logic [NB-1:0] rq, oh;
                rq = rp_due & bank_open & ~rp_alerted;
                oh = rq & (~rq + 1'b1);
                clamp_q   <= clamp_fire;
                clamp_b_q <= pick_b;
                if (clamp_q) begin
                    // Kẹp tRAS(max) ở chu kỳ trước: đồng thời báo cho directed_refresh_manager làm mới hàng lân cận
                    o_tras_clamped_alert <= 1'b1;
                    o_tras_clamped_cnt   <= o_tras_clamped_cnt + 1'b1;
                    o_rowpress_alert     <= 1'b1;
                    o_rowpress_bg        <= clamp_b_q[IW-1:BANK_WIDTH];
                    o_rowpress_bank      <= clamp_b_q[BANK_WIDTH-1:0];
                    o_rowpress_row       <= open_row[clamp_b_q];
                    o_rowpress_alert_cnt <= o_rowpress_alert_cnt + 1'b1;
                end else if (|rq) begin
                    logic [IW-1:0] ix;
                    ix = oh2idx(oh);
                    rp_alerted[ix]       <= 1'b1;
                    o_rowpress_alert     <= 1'b1;
                    o_rowpress_bg        <= ix[IW-1:BANK_WIDTH];
                    o_rowpress_bank      <= ix[BANK_WIDTH-1:0];
                    o_rowpress_row       <= open_row[ix];
                    o_rowpress_alert_cnt <= o_rowpress_alert_cnt + 1'b1;
                end
            end

            // 4. Đường dữ liệu đọc trả về và đồng bộ beat đọc (M-03); RMW: dữ liệu cũ trộn xong thì chuyển sang pha WR
            exp_v <= (exp_v >> 1) | exp_ins;
            if (rd_st_bad || desync_c) begin
                rd_st <= RS_FLUSH;
            end else if (flush_done) begin
                rd_st       <= RS_SYNC;
                o_rd_resync <= 1'b1;
            end
            if (o_dfi_cmd == CMD_RD) rt_wr <= rt_wr + 1'b1;
            if (rd_take) begin
                if (o_wb_last) begin
                    rt_beat <= '0;
                    rt_rd   <= rt_rd + 1'b1;
                end else begin
                    rt_beat <= rt_beat + 1'b1;
                end
            end
            if (rmw_done) s_ph[rmw_done_b] <= 2'd2;

            // 5. Phân loại đăng ký của mọi bank
            for (int b = 0; b < NB; b++) begin
                k_open[b] <= bank_open[b];
                k_hit[b]  <= bank_open[b] && (open_row[b] == s_row[b]);
                k_chg[b]  <= 1'b0;
            end
            ld_q <= c_load;
            if (ld_q) s_rmw[ld_b_q] <= s_rmw[ld_b_q] | (s_wr[ld_b_q] && !s_mit[ld_b_q] && i_slice_rmw);

            // 6. Nạp slot
            if (c_load) begin
                s_v[in_b]   <= 1'b1;
                s_wr[in_b]  <= i_cmd_is_write;
                s_mit[in_b] <= i_cmd_is_mitigation;
                s_rmw[in_b] <= i_cmd_is_write && !i_cmd_is_mitigation && i_cmd_rmw;
                s_ph[in_b]  <= '0;
                s_row[in_b] <= i_cmd_row;
                s_col[in_b] <= i_cmd_col;
                s_len[in_b] <= i_cmd_len;
                s_tag[in_b] <= i_cmd_tag;
                k_chg[in_b] <= 1'b1;
                ld_b_q      <= in_b;
            end
            for (int b = 0; b < NB; b++) if (mit_done[b]) s_v[b] <= 1'b0;

            // 7a. Cập nhật trạng thái bank theo sự kiện phát one-hot
            for (int b = 0; b < NB; b++) begin
                if (iss_cas[b]) begin
                    // ras_timer đóng vai mốc PRE sớm nhất: WR cần tWR từ dữ liệu cuối, RD cần tRTP
                    if (ras_lt[b]) begin
                        ras_timer[b] <= pac[b];
                        ras_z[b]     <= (pac[b] == '0);
                    end
                    if (s_rmw[b] && !cas_is_wr[b]) s_ph[b] <= 2'd1;   // RMW: RD xong, chờ trộn
                    else                           s_v[b]  <= 1'b0;
                end
                if (iss_act[b] || iss_dec[b]) begin
                    bank_open[b] <= 1'b1;
                    rcd_timer[b] <= 5'(T_RCD);
                    rcd_z[b]     <= (T_RCD == 0);
                    ras_timer[b] <= 6'(T_RAS);
                    ras_z[b]     <= (T_RAS == 0);
                    k_chg[b]     <= 1'b1;
                end
                if (iss_act[b]) begin
                    open_row[b] <= s_row[b];
                    // Refresh nạn nhân bằng kích hoạt (ACT -> tRAS -> PRE): hợp lệ JEDEC, xong ngay khi ACT, đóng sau tRAS.
                    // REF kèm địa chỉ hàng không tồn tại trong DDR5 và từng được phát khi bank còn mở (S12).
                    if (s_mit[b]) begin
                        s_v[b]       <= 1'b0;
                        close_req[b] <= 1'b1;
                    end
                end
                if (iss_dec[b]) begin
                    open_row[b]  <= pk_drow;
                    close_req[b] <= 1'b1;
                end
                if (iss_pre[b]) begin
                    bank_open[b] <= 1'b0;
                    rp_timer[b]  <= 5'(T_RP);
                    rp_z[b]      <= (T_RP == 0);
                    close_req[b] <= 1'b0;
                    k_chg[b]     <= 1'b1;
                    if (pre_clamp[b]) begin
                        tras_clamp_pending[b] <= 1'b0;
                        act_duration[b]       <= 16'd0;
                    end
                end
            end

            // 7b. Phát đúng một lệnh DFI mỗi chu kỳ
            pk_oh   <= nxt_oh;
            pk_t    <= nxt_t;
            pk_drow <= decoy_row;
            if (is_cas) begin
                o_dfi_cmd   <= sel_is_wr ? CMD_WR : CMD_RD;
                o_dfi_bg    <= pick_b[IW-1:BANK_WIDTH];
                o_dfi_bank  <= pick_b[BANK_WIDTH-1:0];
                o_dfi_row   <= sel_row;
                o_dfi_col   <= sel_col;
                o_dfi_len   <= sel_len;
                o_dfi_tag   <= sel_tag;
                last_wr     <= sel_is_wr;
                cas_rmw_q   <= sel_rmw && !sel_is_wr;
                cas_b_q     <= pick_b;
                dq_busy     <= sel_dq;
                dq_wr_ok    <= sel_wr_ok;
                dq_rd_ok    <= sel_rd_ok;
                for (int bg = 0; bg < BG_COUNT; bg++)
                    if (sel_bg_oh[bg]) begin
                        ccd_timer[bg] <= 4'(T_CCD_L);
                        ccd_z[bg]     <= (T_CCD_L == 0);
                        if (sel_is_wr) begin
                            ccdw_timer[bg] <= 4'(T_CCD_L_WR);
                            ccdw_z[bg]     <= (T_CCD_L_WR == 0);
                        end
                    end
                ccd_s_timer <= 3'(T_CCD_S);
                ccd_s_z     <= (T_CCD_S == 0);
                lat_bg      <= pick_b[IW-1:BANK_WIDTH];
                lat_bank    <= pick_b[BANK_WIDTH-1:0];
                lat_row     <= sel_row;
                rr_ptr      <= pick_b;
            end else if (is_act) begin
                o_dfi_cmd   <= CMD_ACT;
                o_dfi_bg    <= pick_b[IW-1:BANK_WIDTH];
                o_dfi_bank  <= pick_b[BANK_WIDTH-1:0];
                o_dfi_row   <= sel_row;
                last_act    <= 1'b1;
                dfi_act_mit <= sel_mit;
                lat_bg      <= pick_b[IW-1:BANK_WIDTH];
                lat_bank    <= pick_b[BANK_WIDTH-1:0];
                lat_row     <= sel_row;
                rr_ptr      <= pick_b;
            end else if (is_pre) begin
                o_dfi_cmd   <= CMD_PRE;
                o_dfi_bg    <= pick_b[IW-1:BANK_WIDTH];
                o_dfi_bank  <= pick_b[BANK_WIDTH-1:0];
                rr_ptr      <= pick_b;
            end else if (do_ref) begin
                o_dfi_bg   <= '0;
                o_dfi_bank <= '0;
                if (lat_kind == K_REF) begin
                    o_dfi_cmd  <= CMD_REF;
                    rfc_timer  <= 8'(T_RFC);
                    rfc_z      <= (T_RFC == 0);
                    rfc_z2     <= (T_RFC == 0);
                    if (owed_rep != 3'd0) begin
                        ref_owed   <= owed_rep - 1'b1 + ((refi_timer <= 16'd1 && owed_rep != 3'd7) ? 3'd1 : 3'd0);
                        ref_owed_c <= ~(owed_rep - 1'b1 + ((refi_timer <= 16'd1 && owed_rep != 3'd7) ? 3'd1 : 3'd0));
                    end else begin
                        ref_owed   <= (refi_timer <= 16'd1) ? 3'd1 : 3'd0;
                        ref_owed_c <= (refi_timer <= 16'd1) ? 3'd6 : 3'd7;
                    end
                    o_ref_tick <= 1'b1;
                end else begin
                    // RFMab (hoặc phục hồi khi lat_kind sai mã): làm tươi mọi bank, xoá RAA và bảo toàn nợ REF
                    o_dfi_cmd      <= CMD_RFM;
                    rfc_timer      <= 8'(T_RFM);
                    rfc_z          <= (T_RFM == 0);
                    rfc_z2         <= (T_RFM == 0);
                    lat_kind       <= K_REF;
                    rfm_req        <= '0;
                    abo_rfm_req    <= 1'b0;
                    for (int bg = 0; bg < BG_COUNT; bg++) begin
                        rolling_act_cnt[bg] <= 8'd0;
                        rolling_act_inv[bg] <= 8'hFF;
                    end
                    o_rfm_auto_cnt <= o_rfm_auto_cnt + 1'b1;
                    o_rfm_active   <= 1'b1;
                end
            end else if (do_decoy) begin
                // Truy cập mồi THẬT: ACT một hàng từ PRF có khoá ở bank đang đóng rồi PRE sau tRAS, làm nhiễu
                // mẫu ACT/row-buffer mà kẻ tấn công quan sát.
                o_decoy_active <= 1'b1;
                o_decoy_cnt    <= o_decoy_cnt + 1'b1;
                o_dfi_cmd      <= CMD_ACT;
                last_act       <= 1'b1;
                o_dfi_bg       <= pick_b[IW-1:BANK_WIDTH];
                o_dfi_bank     <= pick_b[BANK_WIDTH-1:0];
                o_dfi_row      <= pk_drow;
            end
        end
    end

`ifndef SYNTHESIS
    // Kiểm tra miền tham số định thời JEDEC khi elaboration (SA-E02..SA-E09)
    initial begin
        if (!(T_RCD >= 1 && T_RCD <= 31 && T_RP >= 1 && T_RP <= 31))
            $fatal(1, "SA-E02: T_RCD/T_RP out of 5-bit timer range [1..31]");
        if (!(T_RAS >= 1 && T_RAS <= 63 && (T_CWL + 7 + T_WR <= 63) && (T_RTP <= 63)))
            $fatal(1, "SA-E03: T_RAS / pre_after_cas out of 6-bit ras_timer range [1..63]");
        if (!((T_CWL + 7 <= 63) && (T_CL + 7 <= 63)))
            $fatal(1, "SA-E04: T_CWL/T_CL + 7 out of 6-bit dq_busy range [1..63]");
        if (!(T_CCD_L >= 1 && T_CCD_L <= 15 && T_CCD_L_WR >= 1 && T_CCD_L_WR <= 15 && T_CCD_S >= 1 && T_CCD_S <= 7))
            $fatal(1, "SA-E05: T_CCD_L/T_CCD_L_WR/T_CCD_S out of timer range");
        if (!(T_RRD_S >= 1 && T_RRD_S <= 17 && T_RRD_L >= 1 && T_RRD_L <= 17 && T_FAW >= 1 && T_FAW <= 33))
            $fatal(1, "SA-E06: T_RRD_S/T_RRD_L/T_FAW out of timer range");
        if (!((T_CWL + T_WTR_S + 6 <= 63) && (T_CWL + T_WTR_L + 6 <= 63)))
            $fatal(1, "SA-E07: T_CWL + T_WTR + 6 out of 6-bit wtr_timer range");
        if (!(T_RFC >= 1 && T_RFC <= 255 && T_RFM >= 1 && T_RFM <= 255 && T_REFI >= 16 && T_REFI <= 65535))
            $fatal(1, "SA-E08: T_RFC/T_RFM/T_REFI out of timer range");
        // T_RDV >= 2: exp_v nạp ở cạnh sau RD trên DFI tại bit T_RDV - 1 (spec_v2 M-03.1)
        if (!(T_RDV >= 2 && T_RDV <= 56 && REF_WD >= 64 && REF_WD <= 1023))
            $fatal(1, "SA-E09: T_RDV/REF_WD out of range");
    end

    // Tự kiểm mô phỏng các bất biến lịch beat đọc (TB bơm lỗi vào exp_v/rd_st đặt sim_chk_en = 0 trước khi bơm). Bất biến
    // của flop an toàn (user_blk_q, ref_owed, cờ timer) do khối kiểm trong silicon báo qua o_fault, không lặp ở đây.
    bit sim_chk_en = 1'b1;
    always_ff @(posedge clk)
        if (rst_n) begin
            if (all_closed && (any_cas || any_pre))
                $error("ddr5_cmd_engine: CAS/PRE ready while every bank is closed");
            if (sim_chk_en) begin
                if (((exp_v >> 1) & exp_ins) != '0)
                    $error("ddr5_cmd_engine: overlapping read beat schedule (A-D6)");
                if (o_rd_resync && (rt_ne || exp_v != '0))
                    $error("ddr5_cmd_engine: resync with pending read beats (A-D5)");
            end
        end
`endif

    // Unused input signals sink
    logic _unused_sink;
    assign _unused_sink = &{1'b0, i_cmd_id, 1'b0};

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
        if ($past(rst_n))  assume (rst_n);
    end

    // Hợp đồng cổng (M-12, SA-P06): lệnh CAS tối đa 8 beat; độ dài lớn hơn làm tràn các timer 6 bit theo len
    always_comb
        if (i_cmd_valid) assume (i_cmd_len < AXI_LEN_WIDTH'(8));

    // 1. Trạng thái sau reset: không có lệnh chờ, không phát lệnh DFI
    always_comb begin
        if (!rst_n) begin
            assert (s_v == '0);
            assert (o_dfi_cmd == CMD_NOP);
            assert (!o_rowpress_alert);
        end
    end

    // 2. Tính toàn vẹn lệnh DFI: Khi phát lệnh RD/WR, Bank mục tiêu bắt buộc phải đang mở và đúng hàng
    always_comb begin
        if (rst_n && (o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR)) begin
            assert (bank_open[bidx(o_dfi_bg, o_dfi_bank)]);
            assert (open_row[bidx(o_dfi_bg, o_dfi_bank)] == o_dfi_row);
        end
    end

    // 3. Tuân thủ tCCD: Khi phát lệnh RD/WR, bộ đếm tCCD_L, tCCD_L_WR (với WR) và tCCD_S được nạp đúng thông số JEDEC
    always_comb begin
        if (rst_n && (o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR)) begin
            assert (ccd_timer[o_dfi_bg] == 4'(T_CCD_L));
            assert (ccd_s_timer == 3'(T_CCD_S));
            if (o_dfi_cmd == CMD_WR) assert (ccdw_timer[o_dfi_bg] == 4'(T_CCD_L_WR));
        end
    end

    // 4. Khi ACT được nạp tRCD, khi PRE được nạp tRP
    always_comb begin
        if (rst_n) begin
            if (o_dfi_cmd == CMD_ACT) assert (rcd_timer[bidx(o_dfi_bg, o_dfi_bank)] == 5'(T_RCD));
            if (o_dfi_cmd == CMD_PRE) assert (rp_timer[bidx(o_dfi_bg, o_dfi_bank)] == 5'(T_RP));
        end
    end

    // 5. Chuyển trạng thái Bank: Sau ACT bank mở, sau PRE bank đóng
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(o_dfi_cmd == CMD_ACT)) begin
                assert (bank_open[bidx($past(o_dfi_bg), $past(o_dfi_bank))]);
            end
            if ($past(o_dfi_cmd == CMD_PRE)) begin
                assert (!bank_open[bidx($past(o_dfi_bg), $past(o_dfi_bank))]);
            end
        end
    end

    // 6. Mỗi chu kỳ chọn tối đa một bank
    always_comb begin
        if (rst_n) assert ($onehot0(pick));
    end

    // 7. PRAC / QPRAC Alert-Back-Off: Khi có tín hiệu alert, o_abo_active được kích hoạt tức thời
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(i_dram_abo_alert && !dram_abo_d)) begin
                assert (o_abo_active);
            end
        end
    end

    // 8. RowPress Dynamic LUT Bounds: dynamic threshold luôn >= 64 khi base >= 64
    always_comb begin
        if (rst_n) begin
            if (effective_rp_thresh >= 16'd64) begin
                assert (calc_dyn_rowpress_thresh(effective_rp_thresh, cfg_rowpress_curve, 16'd5000) >= 16'd64);
            end
        end
    end

    // 9. Bộ đếm chéo và các cờ timer không bao giờ lệch khi không có tiêm lỗi (SA-F01, SA-F07, SA-F09, SA-R06, SA-R07)
    always_comb begin
        if (rst_n) begin
            assert (cnt_err == '0);
            assert (!flag_err);
            assert (!ev_mis);
            assert (user_blk_q == (ref_mode || o_abo_active));
            assert (ref_wd_cnt < 10'(REF_WD) && !ref_wd_exp);
            assert (!ref_mode || (lat_kind == K_REF) || (lat_kind == K_RFM));
            assert (ref_owed == ~ref_owed_c);
            assert (rd_st == RS_SYNC || rd_st == RS_FLUSH);
            // A-D6: lịch beat đọc không chồng
            assert (((exp_v >> 1) & exp_ins) == '0);
            // A-D5: đồng bộ lại chỉ khi không còn beat chờ
            if (o_rd_resync) assert (!rt_ne && exp_v == '0);
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(rd_st_bad)) assert (o_fault[5] && (rd_st == RS_FLUSH));
            // A-D4: không RD mới từ chu kỳ thứ hai của FLUSH
            if ($past(rd_flush)) assert (o_dfi_cmd != CMD_RD);
            // SA-F09: refresh phát với lat_kind sai mã thành RFMab, nợ REF không giảm, báo fault[4]
            if ($past(do_ref && lat_kind_err)) assert (o_dfi_cmd == CMD_RFM && o_fault[4] && ref_owed >= $past(ref_owed));
            // SA-R07: REF khi nợ bằng 0 không làm nợ âm
            if ($past(do_ref && lat_kind == K_REF && ref_owed == 3'd0 && !owed_mis))
                assert (ref_owed == 3'($past(refi_tick)));
        end
    end

    // 10. Mọi bank đóng thì không có CAS/PRE sẵn sàng (cơ sở để do_ref không cần chờ bộ chọn lệnh)
    always_comb begin
        if (rst_n && all_closed) assert (!any_cas && !any_pre);
    end

    // Cover properties đo lường khả năng kích hoạt toàn bộ tập lệnh DFI
    always_ff @(posedge clk) begin
        cover (o_dfi_cmd == CMD_ACT);
        cover (o_dfi_cmd == CMD_PRE);
        cover (o_dfi_cmd == CMD_RD);
        cover (o_dfi_cmd == CMD_WR);
        cover (o_dfi_cmd == CMD_REF);
        cover (o_rowpress_alert);
        cover (o_slack_cycle);
        cover (o_abo_active);
    end
`endif

endmodule
