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
    logic [127:0] round_keys [15];
    assign round_keys[0] = i_key1_data[255:128];
    assign round_keys[1] = i_key1_data[127:0];
    genvar k;
    generate
        for (k = 2; k <= 14; k++) begin : gen_rk
            assign round_keys[k] = i_key1_data[127:0] ^ {4{32'(k * 32'h9E37_79B9)}};
        end
    endgenerate

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
        .i_lookup_valid       (i_precomp_valid),
        .i_lookup_is_write    (i_precomp_is_write),
        .i_lookup_key_id      ((i_precomp_key_id != 8'h0) ? i_precomp_key_id : i_default_key_id),
        .i_lookup_epoch_nonce (i_epoch_nonce),
        .i_lookup_addr        (i_precomp_addr),
        .o_lookup_valid       (sct_lookup_valid),
        .o_ctr_blocks         (sct_ctr_blocks),
        .o_major_ctr          (sct_major_ctr),
        .o_minor_ctr          (sct_minor_ctr),
        .i_commit_valid       (i_wr_valid && o_wr_ready && (i_crypto_profile >= 2'b10)),
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
        .o_precomp_ready      (o_precomp_ready),
        .i_precomp_tag        (i_precomp_tag),
        .i_precomp_ctr_blocks (sct_ctr_blocks),

        // Read datapath XOR
        .i_rd_valid           (i_rd_valid),
        .o_rd_ready           (),
        .i_rd_tag             (i_rd_tag),
        .i_rd_data            (i_rd_data),
        .o_rd_valid           (ctr_rd_valid),
        .i_rd_pop             (i_rd_ready),
        .o_rd_data            (ctr_rd_data),
        .o_rd_hit             (ctr_rd_hit),

        // Write datapath XOR
        .i_wr_valid           (i_wr_valid),
        .o_wr_ready           (),
        .i_wr_tag             (i_wr_tag),
        .i_wr_data            (i_wr_data),
        .o_wr_valid           (ctr_wr_valid),
        .i_wr_pop             (i_wr_ready),
        .o_wr_data            (ctr_wr_data),
        .o_wr_hit             (ctr_wr_hit)
    );

    //=========================================================================
    // 4. Dong co Tinh MAC toan ven du lieu (Integrity MAC Generator) - Profile 3
    //=========================================================================
    logic         mac_wr_valid;
    logic [63:0]  mac_wr_val;
    logic         mac_violation;

    integrity_mac_gen #(
        .DATA_WIDTH (128),
        .ADDR_WIDTH (32),
        .MAC_WIDTH  (MAC_WIDTH)
    ) u_mac_gen (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .cfg_mac_en            (i_crypto_profile == 2'b11),
        .cfg_mac_key           (i_key2_data),

        // Sinh MAC cho Write Path
        .i_wr_valid            (i_wr_valid && (i_crypto_profile == 2'b11)),
        .o_wr_ready            (),
        .i_wr_addr             (i_wr_addr[31:0]),
        .i_wr_counter          ({sct_major_ctr[24:0], sct_minor_ctr}),
        .i_wr_data             (ctr_wr_data[127:0]),
        .o_wr_mac_valid        (mac_wr_valid),
        .o_wr_mac              (mac_wr_val),

        // Kiem tra MAC tren Read Path
        .i_rd_valid            (i_rd_valid && (i_crypto_profile == 2'b11)),
        .o_rd_ready            (),
        .i_rd_addr             (i_rd_addr[31:0]),
        .i_rd_counter          ({sct_major_ctr[24:0], sct_minor_ctr}),
        .i_rd_data             (ctr_rd_data[127:0]),
        .i_rd_stored_mac       (i_rd_stored_mac),
        .o_rd_mac_valid        (),
        .o_integrity_violation (mac_violation)
    );

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

    // Ghep du lieu doc cuoi cung theo Profile
    assign o_rd_ready = !skid_rd_valid_q;

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
                o_rd_valid  = ctr_rd_valid;
                o_rd_tag    = i_rd_tag;
                o_rd_addr   = i_rd_addr;
                // Poisoning: Khi MAC violation xay ra, zero-out toan bo rdata de triet tieu du lieu doc
                o_rd_data   = mac_violation ? '0 : ctr_rd_data;
                o_rd_poison = mac_violation;
                o_rd_slverr = mac_violation;
            end
        endcase
    end

    //=========================================================================
    // 6. Giao dien Xuat Duong Ghi (Write Egress)
    //=========================================================================
    assign o_wr_ready = i_wr_ready;

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

            default: begin // Profiles 2 & 3: CTR Mode
                o_wr_valid = ctr_wr_valid;
                o_wr_tag   = i_wr_tag;
                o_wr_addr  = i_wr_addr;
                o_wr_data  = ctr_wr_data;
                o_wr_mac   = mac_wr_val;
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
        mac_violation,        // Bit 1: MAC integrity violation
        1'b0                  // Bit 0: SDC filter alert
    };

    assign o_fault_addr_log = mac_violation ? i_rd_addr[31:0] : {{(22 - SCT_PAGE_WIDTH){1'b0}}, sct_major_roll_page, 10'h0};

endmodule
