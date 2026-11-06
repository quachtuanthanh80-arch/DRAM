// qshield_crypto_top.sv
// Phan he mat ma hai tang hop nhat (Two-Tier Security Subsystem) ho tro Profile 0-3, CTR Pre-computation va Multi-VM

`timescale 1ns / 1ps

module qshield_crypto_top
    import aes_pkg::*;
#(
    parameter int DATA_WIDTH    = 512,
    parameter int ADDR_WIDTH    = 34,
    parameter int TAG_WIDTH     = 5,
    parameter int TAG_ENTRIES   = 16,
    parameter int MAC_WIDTH     = 64
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // Cau hinh bao mat TMR tu APB CSR
    input  logic [1:0]                   i_crypto_profile, // 0: Bypass, 1: XTS, 2: CTR 0-cycle, 3: CTR + MAC
    input  logic [7:0]                   i_default_key_id,
    input  logic [18:0]                  i_epoch_nonce,
    input  logic [255:0]                 i_key1_data,
    input  logic [127:0]                 i_key2_data,
    input  logic                         i_keys_valid,

    // Giao dien Pre-computation Trigger tu Scheduler / Frontend
    input  logic                         i_precomp_valid,
    output logic                         o_precomp_ready,
    input  logic                         i_precomp_is_write,
    input  logic [TAG_WIDTH-1:0]         i_precomp_tag,
    input  logic [ADDR_WIDTH-1:0]        i_precomp_addr,
    input  logic [7:0]                   i_precomp_key_id,

    // Giao dien Duong Ghi (Write Datapath): wdata_buffer -> Crypto -> Memory/DFI
    input  logic                         i_wr_valid,
    output logic                         o_wr_ready,
    input  logic [TAG_WIDTH-1:0]         i_wr_tag,
    input  logic [ADDR_WIDTH-1:0]        i_wr_addr,
    input  logic [DATA_WIDTH-1:0]        i_wr_data,
    input  logic [(DATA_WIDTH/8)-1:0]    i_wr_strb,

    output logic                         o_wr_valid,
    input  logic                         i_wr_ready,
    output logic [TAG_WIDTH-1:0]         o_wr_tag,
    output logic [ADDR_WIDTH-1:0]        o_wr_addr,
    output logic [DATA_WIDTH-1:0]        o_wr_data,
    output logic [MAC_WIDTH-1:0]         o_wr_mac,

    // Giao dien Duong Doc (Read Datapath): Memory/DFI -> Crypto -> ROB
    input  logic                         i_rd_valid,
    output logic                         o_rd_ready,
    input  logic [TAG_WIDTH-1:0]         i_rd_tag,
    input  logic [ADDR_WIDTH-1:0]        i_rd_addr,
    input  logic [DATA_WIDTH-1:0]        i_rd_data,
    input  logic [MAC_WIDTH-1:0]         i_rd_stored_mac,

    output logic                         o_rd_valid,
    input  logic                         i_rd_ready,
    output logic [TAG_WIDTH-1:0]         o_rd_tag,
    output logic [ADDR_WIDTH-1:0]        o_rd_addr,
    output logic [DATA_WIDTH-1:0]        o_rd_data,
    output logic                         o_rd_poison,
    output logic                         o_rd_slverr,

    // Canh bao & Nhat ky loi an ninh phan cung
    output logic [4:0]                   o_sec_fault_set,
    output logic [31:0]                  o_fault_addr_log
);

    //=========================================================================
    // 1. Sinh khoa vong AES-256 (Round Keys Expansion)
    //=========================================================================
    // Lịch khoá FIPS-197 thật. Bản cũ đặt round_keys[k] = key ^ k*0x9E3779B9 nên vòng AES thật nhưng mật mã
    // không phải AES-256 (S27). Khi khoá đang được tính lại, precompute bị chặn (không sinh keystream dở dang).
    logic [127:0]      round_keys [15];
    logic [15*128-1:0] round_keys_flat;
    logic              kx_valid;
    aes256_key_expand u_key_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (i_key1_data),
        .o_valid      (kx_valid),
        .o_round_keys (round_keys_flat)
    );
    genvar k;
    generate
        for (k = 0; k <= 14; k++) begin : gen_rk
            assign round_keys[k] = round_keys_flat[k*128 +: 128];
        end
    endgenerate
    logic ks_precomp_ready;
    assign o_precomp_ready = ks_precomp_ready && kx_valid;

    // Profile 3 giữ beat lại tới khi có kết luận MAC (CMAC nhiều chu kỳ): các tín hiệu bắt tay khai báo trước
    wire  p3 = (i_crypto_profile == 2'b11);
    logic rd_pop, wr_pop, wr_commit, rd_accept_p3, wr_accept_p3;

    //=========================================================================
    // 2. Bang bo dem phan tach (Split-Counter Table)
    //=========================================================================
    localparam int SCT_DEPTH = 64;
    localparam int SCT_PAGE_WIDTH = $clog2(SCT_DEPTH);

    logic                      sct_lookup_valid;
    logic [127:0]              sct_ctr_blocks [4];
    logic [63:0]               sct_major_ctr;
    logic [6:0]                sct_minor_ctr;
    logic                      sct_major_roll_alert;
    logic [SCT_PAGE_WIDTH-1:0] sct_major_roll_page;

    split_counter_table #(
        .TABLE_DEPTH (SCT_DEPTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_split_counter_table (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_lookup_valid       (i_precomp_valid && o_precomp_ready),
        .i_lookup_is_write    (i_precomp_is_write),
        .i_lookup_key_id      ((i_precomp_key_id != 8'h0) ? i_precomp_key_id : i_default_key_id),
        .i_lookup_epoch_nonce (i_epoch_nonce),
        .i_lookup_addr        (i_precomp_addr),
        .o_lookup_valid       (sct_lookup_valid),
        .o_ctr_blocks         (sct_ctr_blocks),
        .o_major_ctr          (sct_major_ctr),
        .o_minor_ctr          (sct_minor_ctr),
        .i_commit_valid       (wr_commit),
        .i_commit_addr        (i_wr_addr),
        .o_major_roll_alert   (sct_major_roll_alert),
        .o_major_roll_page    (sct_major_roll_page)
    );

    //=========================================================================
    // 3. Dong co Keystream AES-CTR voi Tag Buffer 16-entry
    //=========================================================================
    wire ctr_active = (i_crypto_profile == 2'b10) || (i_crypto_profile == 2'b11);

    logic           ctr_rd_valid;
    logic [511:0]   ctr_rd_data;
    logic           ctr_rd_hit;

    logic           ctr_wr_valid;
    logic [511:0]   ctr_wr_data;
    logic           ctr_wr_hit;

    aes_ctr_keystream #(
        .TAG_WIDTH   (TAG_WIDTH),
        .TAG_ENTRIES (TAG_ENTRIES)
    ) u_aes_ctr_keystream (
        .clk                  (clk),
        .rst_n                (rst_n),
        .cfg_ctr_en           (ctr_active),
        .round_keys           (round_keys),
        .i_precomp_valid      (sct_lookup_valid),
        .o_precomp_ready      (ks_precomp_ready),
        .i_precomp_tag        (i_precomp_tag),
        .i_precomp_ctr_blocks (sct_ctr_blocks),

        // Read datapath XOR
        .i_rd_valid           (i_rd_valid),
        .o_rd_ready           (),
        .i_rd_tag             (i_rd_tag),
        .i_rd_data            (i_rd_data),
        .o_rd_valid           (ctr_rd_valid),
        .i_rd_pop             (rd_pop),
        .o_rd_data            (ctr_rd_data),
        .o_rd_hit             (ctr_rd_hit),

        // Write datapath XOR
        .i_wr_valid           (i_wr_valid),
        .o_wr_ready           (),
        .i_wr_tag             (i_wr_tag),
        .i_wr_data            (i_wr_data),
        .o_wr_valid           (ctr_wr_valid),
        .i_wr_pop             (wr_pop),
        .o_wr_data            (ctr_wr_data),
        .o_wr_hit             (ctr_wr_hit)
    );

    //=========================================================================
    // 4. Dong co Tinh MAC toan ven du lieu (Integrity MAC Generator) - Profile 3
    //=========================================================================
    logic         mac_wr_valid;
    logic [63:0]  mac_wr_val;
    logic         mac_rd_valid;
    logic         mac_violation;
    logic         mac_wr_ready, mac_rd_ready;

    // Bộ đếm ghi của từng dòng được chốt theo tag lúc precompute (tra cứu bảng bộ đếm là tổ hợp, cùng chu kỳ).
    // Bản cũ dùng bộ đếm của lần tra cứu gần nhất, có thể của một tag khác.
    logic [31:0] tag_ctr [TAG_ENTRIES];
    always_ff @(posedge clk)
        if (sct_lookup_valid && i_precomp_valid && o_precomp_ready && (i_precomp_tag < TAG_WIDTH'(TAG_ENTRIES)))
            tag_ctr[i_precomp_tag] <= {sct_major_ctr[24:0], sct_minor_ctr};

    // Encrypt-then-MAC trên cả dòng 512 bit bản mã: chiều ghi dùng bản mã vừa tạo, chiều đọc dùng bản mã từ DRAM.
    // Bản cũ chỉ phủ 128 bit thấp (S25) và chiều đọc kiểm trên bản rõ trong khi chiều ghi ký bản mã (S26).
    integrity_mac_gen #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (32),
        .MAC_WIDTH  (MAC_WIDTH)
    ) u_mac_gen (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .cfg_mac_en            (p3),
        .cfg_mac_key           (i_key2_data),

        .i_wr_valid            (wr_accept_p3),
        .o_wr_ready            (mac_wr_ready),
        .i_wr_addr             (i_wr_addr[31:0]),
        .i_wr_counter          (tag_ctr[i_wr_tag]),
        .i_wr_data             (ctr_wr_data),
        .o_wr_mac_valid        (mac_wr_valid),
        .o_wr_mac              (mac_wr_val),

        .i_rd_valid            (rd_accept_p3),
        .o_rd_ready            (mac_rd_ready),
        .i_rd_addr             (i_rd_addr[31:0]),
        .i_rd_counter          (tag_ctr[i_rd_tag]),
        .i_rd_data             (i_rd_data),
        .i_rd_stored_mac       (i_rd_stored_mac),
        .o_rd_mac_valid        (mac_rd_valid),
        .o_integrity_violation (mac_violation)
    );

    // Bộ giữ beat của profile 3: nhận khi keystream sẵn và lõi MAC rảnh, xuất khi có kết luận MAC
    logic                  rh_busy, rh_out, rh_viol;
    logic [TAG_WIDTH-1:0]  rh_tag;
    logic [ADDR_WIDTH-1:0] rh_addr;
    logic [DATA_WIDTH-1:0] rh_data;
    logic                  wh_busy, wh_out;
    logic [TAG_WIDTH-1:0]  wh_tag;
    logic [ADDR_WIDTH-1:0] wh_addr;
    logic [DATA_WIDTH-1:0] wh_data;
    logic [MAC_WIDTH-1:0]  wh_mac;
    assign rd_accept_p3 = p3 && i_rd_valid && ctr_rd_valid && !rh_busy && mac_rd_ready;
    assign wr_accept_p3 = p3 && i_wr_valid && ctr_wr_valid && !wh_busy && mac_wr_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rh_busy <= 1'b0; rh_out <= 1'b0; rh_viol <= 1'b0; rh_tag <= '0; rh_addr <= '0; rh_data <= '0;
            wh_busy <= 1'b0; wh_out <= 1'b0; wh_tag <= '0; wh_addr <= '0; wh_data <= '0; wh_mac <= '0;
        end else begin
            if (rd_accept_p3) begin
                rh_busy <= 1'b1;
                rh_tag  <= i_rd_tag;
                rh_addr <= i_rd_addr;
                rh_data <= ctr_rd_data;
            end
            if (mac_rd_valid && rh_busy) begin
                rh_out  <= 1'b1;
                rh_viol <= mac_violation;
            end
            if (rh_out && i_rd_ready) begin
                rh_out  <= 1'b0;
                rh_busy <= 1'b0;
            end
            if (wr_accept_p3) begin
                wh_busy <= 1'b1;
                wh_tag  <= i_wr_tag;
                wh_addr <= i_wr_addr;
                wh_data <= ctr_wr_data;
            end
            if (mac_wr_valid && wh_busy) begin
                wh_out <= 1'b1;
                wh_mac <= mac_wr_val;
            end
            if (wh_out && i_wr_ready) begin
                wh_out  <= 1'b0;
                wh_busy <= 1'b0;
            end
        end
    end

    assign rd_pop    = p3 ? rd_accept_p3 : i_rd_ready;
    assign wr_pop    = p3 ? wr_accept_p3 : i_wr_ready;
    assign wr_commit = p3 ? wr_accept_p3 : (i_wr_valid && o_wr_ready && (i_crypto_profile == 2'b10));

    //=========================================================================
    // 5. Page Hit Skid Buffer & Giao dien Xuat Duong Doc (Read Egress)
    //=========================================================================
    // Neu Bank Hit lam du lieu tra ve truoc khi Keystream hoan tat (!ctr_rd_hit),
    // buffer tam giu beat du lieu va lam tre 1-2 chu ky thay vi lam mat du lieu
    logic [DATA_WIDTH-1:0] skid_rd_data_q;
    logic [ADDR_WIDTH-1:0] skid_rd_addr_q;
    logic [TAG_WIDTH-1:0]  skid_rd_tag_q;
    logic                  skid_rd_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_rd_valid_q <= 1'b0;
            skid_rd_data_q  <= '0;
            skid_rd_addr_q  <= '0;
            skid_rd_tag_q   <= '0;
        end else if (i_rd_valid && !ctr_rd_hit && !skid_rd_valid_q) begin
            skid_rd_valid_q <= 1'b1;
            skid_rd_data_q  <= i_rd_data;
            skid_rd_addr_q  <= i_rd_addr;
            skid_rd_tag_q   <= i_rd_tag;
        end else if (skid_rd_valid_q && ctr_rd_hit) begin
            skid_rd_valid_q <= 1'b0;
        end
    end

    // Ghep du lieu doc cuoi cung theo Profile; profile 3 báo nhận beat khi đã chốt vào bộ giữ
    assign o_rd_ready = p3 ? rd_accept_p3 : !skid_rd_valid_q;

    always_comb begin
        case (i_crypto_profile)
            2'b00: begin // Profile 0: Bypass
                o_rd_valid  = i_rd_valid;
                o_rd_tag    = i_rd_tag;
                o_rd_addr   = i_rd_addr;
                o_rd_data   = i_rd_data;
                o_rd_poison = 1'b0;
                o_rd_slverr = 1'b0;
            end

            2'b01: begin // Profile 1: Legacy XTS Mode
                o_rd_valid  = i_rd_valid;
                o_rd_tag    = i_rd_tag;
                o_rd_addr   = i_rd_addr;
                o_rd_data   = i_rd_data; // Legacy pipe is handled via subchannel fallback
                o_rd_poison = 1'b0;
                o_rd_slverr = 1'b0;
            end

            2'b10: begin // Profile 2: High-Throughput Decoupled CTR (0-cycle)
                o_rd_valid  = ctr_rd_valid;
                o_rd_tag    = i_rd_tag;
                o_rd_addr   = i_rd_addr;
                o_rd_data   = ctr_rd_data;
                o_rd_poison = 1'b0;
                o_rd_slverr = 1'b0;
            end

            2'b11: begin // Profile 3: High-Security CTR + MAC + ASIL-D Poisoning
                // Beat chỉ ra sau khi MAC đã kiểm xong; vi phạm thì xoá dữ liệu và gắn poison/SLVERR
                o_rd_valid  = rh_out;
                o_rd_tag    = rh_tag;
                o_rd_addr   = rh_addr;
                o_rd_data   = rh_viol ? '0 : rh_data;
                o_rd_poison = rh_viol;
                o_rd_slverr = rh_viol;
            end
        endcase
    end

    //=========================================================================
    // 6. Giao dien Xuat Duong Ghi (Write Egress)
    //=========================================================================
    assign o_wr_ready = p3 ? wr_accept_p3 : i_wr_ready;

    always_comb begin
        case (i_crypto_profile)
            2'b00: begin
                o_wr_valid = i_wr_valid;
                o_wr_tag   = i_wr_tag;
                o_wr_addr  = i_wr_addr;
                o_wr_data  = i_wr_data;
                o_wr_mac   = '0;
            end

            2'b01: begin
                o_wr_valid = i_wr_valid;
                o_wr_tag   = i_wr_tag;
                o_wr_addr  = i_wr_addr;
                o_wr_data  = i_wr_data;
                o_wr_mac   = '0;
            end

            2'b10: begin // Profile 2: CTR
                o_wr_valid = ctr_wr_valid;
                o_wr_tag   = i_wr_tag;
                o_wr_addr  = i_wr_addr;
                o_wr_data  = ctr_wr_data;
                o_wr_mac   = '0;
            end

            default: begin // Profile 3: bản mã ra cùng MAC của nó
                o_wr_valid = wh_out;
                o_wr_tag   = wh_tag;
                o_wr_addr  = wh_addr;
                o_wr_data  = wh_data;
                o_wr_mac   = wh_mac;
            end
        endcase
    end

    //=========================================================================
    // 7. Tong hop canh bao loi an ninh (Unified Security Fault Aggregator)
    //=========================================================================
    assign o_sec_fault_set = {
        1'b0,                 // Bit 4: Glitch/TMR alert
        1'b0,                 // Bit 3: Multi-VM privilege alert
        sct_major_roll_alert, // Bit 2: Minor counter overflow (Major roll-over)
        mac_rd_valid && mac_violation, // Bit 1: MAC integrity violation
        1'b0                  // Bit 0: SDC filter alert
    };

    assign o_fault_addr_log = rh_viol ? rh_addr[31:0] : {{(22 - SCT_PAGE_WIDTH){1'b0}}, sct_major_roll_page, 10'h0};

endmodule
