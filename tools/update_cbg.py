p = r'D:\RAM\rtl\top\axi_ddr5_mc_top.sv'
s = open(p, 'r', encoding='utf-8').read()

t1 = '''    logic [BANK_WIDTH-1:0] rd_cbank [1 << ROB_PTR_WIDTH];
    logic [BANK_WIDTH-1:0] wr_cbank [1 << ROB_PTR_WIDTH];'''
r1 = '''    logic [BANK_WIDTH-1:0] rd_cbank [1 << ROB_PTR_WIDTH];
    logic [BANK_WIDTH-1:0] wr_cbank [1 << ROB_PTR_WIDTH];
    logic [BG_WIDTH-1:0]   rd_cbg   [1 << ROB_PTR_WIDTH];
    logic [BG_WIDTH-1:0]   wr_cbg   [1 << ROB_PTR_WIDTH];'''

t2 = '''    wire  [BANK_WIDTH-1:0] rel_bank = cs_is_write ? wr_cbank[cs_id[ROB_PTR_WIDTH-1:0]] : rd_cbank[cs_id[ROB_PTR_WIDTH-1:0]];'''
r2 = '''    wire  [BANK_WIDTH-1:0] rel_bank = cs_is_write ? wr_cbank[cs_id[ROB_PTR_WIDTH-1:0]] : rd_cbank[cs_id[ROB_PTR_WIDTH-1:0]];
    wire  [BG_WIDTH-1:0]   rel_bg   = cs_is_write ? wr_cbg[cs_id[ROB_PTR_WIDTH-1:0]]   : rd_cbg[cs_id[ROB_PTR_WIDTH-1:0]];'''

t3 = '''.i_rel_bg       (cs_bg),'''
r3 = '''.i_rel_bg       (rel_bg),'''

t4 = '''    always_ff @(posedge clk_axi) begin
        if (fe_rd_req_valid && fe_rd_req_ready) rd_cbank[rob_alloc_tag] <= fe_rd_req_bank;
        if (wr_fire)                            wr_cbank[wcmd_tag]      <= wcmd_bank;
    end'''
r4 = '''    always_ff @(posedge clk_axi) begin
        if (fe_rd_req_valid && fe_rd_req_ready) begin
            rd_cbank[rob_alloc_tag] <= fe_rd_req_bank;
            rd_cbg[rob_alloc_tag]   <= fe_rd_req_bg;
        end
        if (wr_fire) begin
            wr_cbank[wcmd_tag]      <= wcmd_bank;
            wr_cbg[wcmd_tag]        <= wcmd_bg;
        end
    end'''

assert t1 in s, "t1 not found"
s = s.replace(t1, r1)
assert t2 in s, "t2 not found"
s = s.replace(t2, r2)
assert t3 in s, "t3 not found"
s = s.replace(t3, r3)
assert t4 in s, "t4 not found"
s = s.replace(t4, r4)

open(p, 'w', encoding='utf-8', newline='').write(s)
print("Updated successfully!")
