`include "parameters.vh"

module comet
(
    input                                   clk_i,
    input                                   rst_i,
    input                                   is_ACT_i,
    input [`ROW_ADDR_BIT - 1 : 0]           row_addr_i,
    output                                  issue_preventive_refresh_o,
    output [`ROW_ADDR_BIT - 1 : 0]          victim_row_addr_low_o,
    output [`ROW_ADDR_BIT - 1 : 0]          victim_row_addr_high_o
);

wire [`COUNTER_BIT - 1 : 0] ct_min_counter_o_w;
wire update_RAT_o_w;
wire [`ROW_ADDR_BIT - 1 : 0] update_RAT_row_addr_o_w;
wire issue_preventive_refresh_o_w_ct;
wire [`ROW_ADDR_BIT - 1 : 0] agg_row_addr_o_ct_w;

wire valid_o_w;
wire hit_o_w;
counter_table ct
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    .row_addr_i(row_addr_i),
    .is_ACT_i(is_ACT_i),
    .is_RAT_valid_i(valid_o_w),
    .is_RAT_hit_i(hit_o_w),
    .min_counter_o(ct_min_counter_o_w),
    .update_RAT_o(update_RAT_o_w),
    .update_RAT_row_addr_o(update_RAT_row_addr_o_w),
    .agg_row_addr_o(agg_row_addr_o_ct_w),
    .issue_preventive_refresh_o(issue_preventive_refresh_o_w_ct)
);


wire [`COUNTER_BIT - 1 : 0] rat_counter_o_w;
wire issue_preventive_refresh_o_w_rat;
wire [`ROW_ADDR_BIT - 1 : 0] agg_row_addr_o_rat_w;

rat rat_table
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    .row_addr_i(row_addr_i),
    .is_ACT_i(is_ACT_i),
    .is_CT_update_i(update_RAT_o_w),
    .CT_counter_i(ct_min_counter_o_w),
    .CT_row_addr_i(update_RAT_row_addr_o_w),
    .hit_o(hit_o_w),
    .valid_o(valid_o_w),
    .rat_counter_o(rat_counter_o_w),
    .agg_row_addr_o(agg_row_addr_o_rat_w),
    .issue_preventive_refresh_o(issue_preventive_refresh_o_w_rat)
);

issue_ref_logic irl
(
    .issue_preventive_refresh_ct_i(issue_preventive_refresh_o_w_ct),
    .issue_preventive_refresh_rat_i(issue_preventive_refresh_o_w_rat),
    .row_addr_ct_i(agg_row_addr_o_ct_w),
    .row_addr_rat_i(agg_row_addr_o_rat_w),
    .issue_preventive_refresh_o(issue_preventive_refresh_o),
    .victim_row_addr_low_o(victim_row_addr_low_o),
    .victim_row_addr_high_o(victim_row_addr_high_o)
);


endmodule