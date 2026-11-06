// File: multi_vm_key_table.sv
// Chức năng: Bảng lưu trữ và tra cứu khóa mã hóa AES-256 theo ASID cho môi trường ảo hóa bảo mật (AMD SEV-style).
`timescale 1ns / 1ps

module multi_vm_key_table #(
    parameter int ASID_WIDTH  = 4,
    parameter int NUM_VMS     = 1 << ASID_WIDTH, // 16 máy ảo độc lập
    parameter int KEY_WIDTH   = 256,
    parameter int TWEAK_WIDTH = 128
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // APB4 Configuration Interface (Khóa chỉ được lập trình từ mức đặc quyền giám sát)
    input  logic                   s_apb_psel,
    input  logic                   s_apb_penable,
    input  logic                   s_apb_pwrite,
    input  logic [7:0]             s_apb_paddr,
    input  logic [31:0]            s_apb_pwdata,
    input  logic [2:0]             s_apb_pprot,    // AMBA APB4: [0]=1 privileged, [1]=1 non-secure, [2]=1 instruction
    output logic [31:0]            s_apb_prdata,
    output logic                   s_apb_pready,
    output logic                   s_apb_pslverr,

    // Tra cứu đường ghi (Write Datapath Port)
    input  logic [ASID_WIDTH-1:0]  i_wr_asid,
    input  logic                   i_wr_c_bit,     // C-bit: 1 = Encrypted, 0 = Shared plaintext
    output logic [KEY_WIDTH-1:0]   o_wr_key,
    output logic [TWEAK_WIDTH-1:0] o_wr_tweak_key,
    output logic                   o_wr_bypass,
    output logic                   o_wr_valid,

    // Tra cứu đường đọc (Read Datapath Port)
    input  logic [ASID_WIDTH-1:0]  i_rd_asid,
    input  logic                   i_rd_c_bit,
    output logic [KEY_WIDTH-1:0]   o_rd_key,
    output logic [TWEAK_WIDTH-1:0] o_rd_tweak_key,
    output logic                   o_rd_bypass,
    output logic                   o_rd_valid
);

    // Mảng thanh ghi phân rã theo từ 32-bit nhằm tương thích tối đa với công cụ tổng hợp và bộ mô phỏng
    logic [31:0] vm_key_words   [0:NUM_VMS-1][0:7];
    logic [31:0] vm_tweak_words [0:NUM_VMS-1][0:3];
    logic        vm_valid_reg   [0:NUM_VMS-1];

    // Phân giải địa chỉ APB4:
    // Addr[7:4] = ASID (0..15)
    // Addr[3:0] = Offset thanh ghi con (Word 0..7 của Key, Word 8..11 của Tweak Key, Word 12 = Control)
    wire [ASID_WIDTH-1:0] apb_asid   = s_apb_paddr[7:4];
    wire [3:0]            apb_offset = s_apb_paddr[3:0];
    // Chỉ chấp nhận truy cập secure + privileged (hypervisor/firmware tin cậy). Bản cũ lấy PPROT[1] (bit non-secure)
    // làm bit đặc quyền, nên truy cập non-secure lại được coi là có quyền (S7).
    wire                  apb_priv   = s_apb_pprot[0] && !s_apb_pprot[1];

    assign s_apb_pready  = 1'b1;
    assign s_apb_pslverr = s_apb_psel && s_apb_penable && !apb_priv;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int v = 0; v < NUM_VMS; v++) begin
                // Không có khoá mặc định đoán được: khoá bằng 0 và valid = 0 cho tới khi hypervisor nạp khoá
                vm_valid_reg[v] <= 1'b0;
                for (int w = 0; w < 8; w++) vm_key_words[v][w] <= '0;
                for (int t = 0; t < 4; t++) vm_tweak_words[v][t] <= '0;
            end
        end else if (s_apb_psel && s_apb_penable && s_apb_pwrite && apb_priv) begin
            if (apb_offset < 4'd8) begin
                vm_key_words[apb_asid][apb_offset[2:0]] <= s_apb_pwdata;
            end else if (apb_offset < 4'd12) begin
                vm_tweak_words[apb_asid][apb_offset[1:0]] <= s_apb_pwdata;
            end else if (apb_offset == 4'd12) begin
                vm_valid_reg[apb_asid] <= s_apb_pwdata[0];
            end
        end
    end

    // Khoá và tweak chỉ ghi: không bao giờ đọc ngược qua APB, kể cả từ mức có quyền. Chỉ đọc được bit valid.
    always_comb begin
        s_apb_prdata = 32'h0;
        if (s_apb_psel && apb_priv && apb_offset == 4'd12)
            s_apb_prdata = {31'h0, vm_valid_reg[apb_asid]};
    end

    // Ghép các từ 32-bit thành khóa 256-bit và 128-bit không chu kỳ rỗng cho luồng ghi
    assign o_wr_key = {
        vm_key_words[i_wr_asid][7], vm_key_words[i_wr_asid][6],
        vm_key_words[i_wr_asid][5], vm_key_words[i_wr_asid][4],
        vm_key_words[i_wr_asid][3], vm_key_words[i_wr_asid][2],
        vm_key_words[i_wr_asid][1], vm_key_words[i_wr_asid][0]
    };
    assign o_wr_tweak_key = {
        vm_tweak_words[i_wr_asid][3], vm_tweak_words[i_wr_asid][2],
        vm_tweak_words[i_wr_asid][1], vm_tweak_words[i_wr_asid][0]
    };
    assign o_wr_bypass = !i_wr_c_bit; // Bỏ qua mã hóa khi C-bit = 0 (bộ nhớ chia sẻ DMA)
    // Khối mã hoá phải từ chối (fail-closed) truy cập C-bit = 1 của ASID chưa được nạp khoá
    assign o_wr_valid  = vm_valid_reg[i_wr_asid];
    assign o_rd_valid  = vm_valid_reg[i_rd_asid];

    // Ghép các từ 32-bit cho luồng đọc
    assign o_rd_key = {
        vm_key_words[i_rd_asid][7], vm_key_words[i_rd_asid][6],
        vm_key_words[i_rd_asid][5], vm_key_words[i_rd_asid][4],
        vm_key_words[i_rd_asid][3], vm_key_words[i_rd_asid][2],
        vm_key_words[i_rd_asid][1], vm_key_words[i_rd_asid][0]
    };
    assign o_rd_tweak_key = {
        vm_tweak_words[i_rd_asid][3], vm_tweak_words[i_rd_asid][2],
        vm_tweak_words[i_rd_asid][1], vm_tweak_words[i_rd_asid][0]
    };
    assign o_rd_bypass = !i_rd_c_bit;

endmodule
