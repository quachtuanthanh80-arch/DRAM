`include "parameters.vh"

module issue_ref_logic
(
    input                                   issue_preventive_refresh_ct_i,
    input                                   issue_preventive_refresh_rat_i,
    input   [`ROW_ADDR_BIT - 1 : 0]         row_addr_ct_i,
    input   [`ROW_ADDR_BIT - 1 : 0]         row_addr_rat_i,
    output                                  issue_preventive_refresh_o,  
    output [`ROW_ADDR_BIT - 1 : 0]          victim_row_addr_low_o,
    output [`ROW_ADDR_BIT - 1 : 0]          victim_row_addr_high_o
);

assign issue_preventive_refresh_o = issue_preventive_refresh_ct_i | issue_preventive_refresh_rat_i;

wire [`ROW_ADDR_BIT - 1 : 0] agg_row_addr;
assign agg_row_addr = issue_preventive_refresh_ct_i ? row_addr_ct_i : row_addr_rat_i;

assign victim_row_addr_low_o = agg_row_addr - 1;
assign victim_row_addr_high_o = agg_row_addr + 1;
endmodule