// domain_bank_coloring.sv
// Module cach ly mien bao mat theo Tenant/VM bang ky thuat Bank Coloring va anh xa ma tran GF(2)

`timescale 1ns / 1ps

module domain_bank_coloring #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int BG_WIDTH       = 3,
    parameter int BANK_WIDTH     = 2
)(
    // Tin hieu cau hinh tu CSR
    input  logic                      cfg_bank_coloring_en,
    input  logic [1:0]                cfg_mapping_mode, // 00: Standard, 01: Intel-style, 10: AMD Zen-style
    input  logic                      cfg_is_ddr5,

    // Thong tin dia chi va dinh danh luong AXI
    input  logic [AXI_ID_WIDTH-1:0]   i_req_id,
    input  logic [AXI_ADDR_WIDTH-1:0] i_req_addr,

    // Ket qua giai ma Bank Group va Bank
    output logic [BG_WIDTH-1:0]       o_bg,
    output logic [BANK_WIDTH-1:0]     o_bank
);

    // 1. Giai ma Bank tieu chuan trong Bank Group (2 bit: Addr[17:16])
    logic [BANK_WIDTH-1:0] std_bank;
    assign std_bank = i_req_addr[17:16];

    // 2. Tinh toan Bank Group theo cac phong cach kien truc vi xu ly khac nhau
    logic [2:0] bg_standard;
    logic [2:0] bg_intel;
    logic [2:0] bg_amd;

    // A. Standard XOR interleaving (Mac dinh cua Q-Shield)
    assign bg_standard = cfg_is_ddr5 ? (i_req_addr[8:6] ^ i_req_addr[20:18]) :
                                       {1'b0, (i_req_addr[7:6] ^ i_req_addr[19:18])};

    // B. Intel Core/Xeon style (Tham chieu IAIK/drama & Knock-Knock):
    // Cac bit dia chi bac cao tham gia XOR voi cac bit cot de toi uu hoa xung dot hang
    assign bg_intel = cfg_is_ddr5 ? (i_req_addr[8:6] ^ i_req_addr[15:13] ^ i_req_addr[21:19]) :
                                    {1'b0, (i_req_addr[7:6] ^ i_req_addr[14:13] ^ i_req_addr[20:19])};

    // C. AMD Zen UMC style (Tham chieu comsec-group/zenhammer & iisys-sns/AMDRE):
    // Su dung ma tran tuyen tinh tren GF(2) voi cac tap diem phan tan giua cac kenh va subchannel
    logic [2:0] amd_hash;
    always_comb begin
        amd_hash[0] = i_req_addr[6]  ^ i_req_addr[12] ^ i_req_addr[18] ^ i_req_addr[22];
        amd_hash[1] = i_req_addr[7]  ^ i_req_addr[13] ^ i_req_addr[19] ^ i_req_addr[23];
        amd_hash[2] = i_req_addr[8]  ^ i_req_addr[14] ^ i_req_addr[20] ^ i_req_addr[24];
    end
    assign bg_amd = cfg_is_ddr5 ? amd_hash : {1'b0, amd_hash[1:0]};

    // Lua chon ma tran giai ma theo cau hinh CSR
    logic [BG_WIDTH-1:0] selected_bg;
    always_comb begin
        case (cfg_mapping_mode)
            2'b01:   selected_bg = bg_intel;
            2'b10:   selected_bg = bg_amd;
            default: selected_bg = bg_standard;
        endcase
    end

    // 3. Logic Bank Coloring (Phan vung mien bao mat theo Tenant ID)
    // Tach 4 Tenant (VM0..VM3) dua tren 2 bit cao cua AXI ID:
    // - Tenant 0: BG 0, 1 (hoac Bank 0-3 tren DDR4)
    // - Tenant 1: BG 2, 3
    // - Tenant 2: BG 4, 5
    // - Tenant 3: BG 6, 7
    logic [1:0] tenant_id;
    assign tenant_id = (AXI_ID_WIDTH >= 2) ? i_req_id[AXI_ID_WIDTH-1 -: 2] : 2'b00;

    always_comb begin
        if (cfg_bank_coloring_en) begin
            if (cfg_is_ddr5) begin
                // DDR5: 8 Bank Groups -> moi Tenant so huu 2 Bank Group rieng biet
                o_bg   = {tenant_id, selected_bg[0]};
                o_bank = std_bank;
            end else begin
                // DDR4: 4 Bank Groups -> moi Tenant so huu 1 Bank Group rieng biet
                o_bg   = {1'b0, tenant_id};
                o_bank = std_bank;
            end
        end else begin
            // Khong bat Bank Coloring: Truyen truc tiep ket qua băm xen kẽ
            o_bg   = selected_bg;
            o_bank = std_bank;
        end
    end

endmodule
