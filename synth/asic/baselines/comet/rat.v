`include "parameters.vh"

module rat
(
    input                           clk_i,
    input                           rst_i,
    input [`ROW_ADDR_BIT - 1 : 0]   row_addr_i,
    input                           is_ACT_i,
    input                           is_CT_update_i,
    input [`COUNTER_BIT - 1 : 0]    CT_counter_i,
    input [`ROW_ADDR_BIT - 1 : 0]   CT_row_addr_i,
    output                          hit_o,
    output                          valid_o,
    output [`COUNTER_BIT - 1 : 0]   rat_counter_o,
    output [`ROW_ADDR_BIT - 1 : 0]  agg_row_addr_o,
    output                          issue_preventive_refresh_o
);

    reg [`COUNTER_BIT - 1 : 0] rat_r [`RAT_ENTRY-1:0];
    reg [`COUNTER_BIT - 1 : 0] rat_ns_r [`RAT_ENTRY-1:0];


    reg [`ROW_ADDR_BIT - 1 : 0] rat_tag_r [`RAT_ENTRY-1:0];
    reg [`ROW_ADDR_BIT - 1 : 0] rat_tag_ns_r [`RAT_ENTRY-1:0];

    reg [31:0] rng_counter_r, rng_counter_ns_r;
    reg [$clog2(`RAT_ENTRY)-1:0] current_search_addr_r, current_search_addr_ns_r;
    reg is_hit_o_r, is_hit_o_ns_r;
    reg valid_o_r, valid_o_ns_r;
    reg issue_preventive_refresh_o_r, issue_preventive_refresh_o_ns_r;
    reg [`ROW_ADDR_BIT - 1 : 0] row_addr_r, row_addr_ns_r;

    integer i = 0;
    localparam  IDLE    = 0,
                SEARCH  = 1,
                UPDATE  = 2;
    reg [1:0] state_r, state_ns_r;

    assign hit_o = is_hit_o_r;
    assign valid_o = valid_o_r;
    assign rat_counter_o = rat_r[current_search_addr_r];
    assign issue_preventive_refresh_o = issue_preventive_refresh_o_r;
    assign  agg_row_addr_o = row_addr_r;

    always@(*) begin
        rng_counter_ns_r = rng_counter_r + 1;
        state_ns_r = state_r;
        valid_o_ns_r = valid_o_r;
        is_hit_o_ns_r = is_hit_o_r;
        current_search_addr_ns_r = current_search_addr_r;
        state_ns_r = state_r;
        issue_preventive_refresh_o_ns_r = issue_preventive_refresh_o_r;
        row_addr_ns_r = row_addr_r;

        for(i = 0; i < `RAT_ENTRY; i = i + 1) begin
            rat_ns_r[i] = rat_r[i];
            rat_tag_ns_r[i] = rat_tag_r[i];
        end

        case(state_r)
        IDLE: begin
            issue_preventive_refresh_o_ns_r = 0;
            is_hit_o_ns_r = 0;
            valid_o_ns_r = 0;
            current_search_addr_ns_r = 0;
            if(is_ACT_i) begin
                state_ns_r = SEARCH;
                row_addr_ns_r = row_addr_i;
            end
            else if(is_CT_update_i) begin
                state_ns_r = IDLE;
                rat_ns_r[rng_counter_r] = CT_counter_i;
                rat_tag_ns_r[rng_counter_r] = CT_row_addr_i;
            end
            else begin
                state_ns_r = IDLE;
            end
        end
        SEARCH: begin
            if(current_search_addr_r == `RAT_ENTRY) begin
                current_search_addr_ns_r = 0;
                valid_o_ns_r = 1;
                state_ns_r = IDLE;
            end
            else begin
                current_search_addr_ns_r = current_search_addr_r + 1;
                if(rat_tag_r[current_search_addr_r] == row_addr_r) begin
                    is_hit_o_ns_r = 1;
                    valid_o_ns_r = 1;
                    state_ns_r = UPDATE;
                    current_search_addr_ns_r = current_search_addr_r;
                end
                else begin
                    state_ns_r = SEARCH;
                    is_hit_o_ns_r = 0;
                    valid_o_ns_r = 0;
                end
            end
        end
        UPDATE: begin
            if(rat_tag_r[current_search_addr_r] < `N_RH) begin
                rat_ns_r[current_search_addr_r] = rat_r[current_search_addr_r] + 1;
            end
            else begin
                //issue preventive refresh
                issue_preventive_refresh_o_ns_r = 1;
                //reset the counter
                rat_ns_r[current_search_addr_r] = 0;
            end
        end
        endcase
    end

    always@(posedge clk_i) begin
            if(rst_i) begin
                for(i = 0; i < `RAT_ENTRY; i = i + 1) begin
                    rat_r[i] <= 0;
                    rat_tag_r[i] <= 0;
                end
                rng_counter_r <= 0;
                state_r <= IDLE;
                valid_o_r <= 0;
                is_hit_o_r <= 0;
                current_search_addr_r <= 0;
                issue_preventive_refresh_o_r <= 0;
                row_addr_r <= 0;

            end
            else begin
                for(i = 0; i < `RAT_ENTRY; i = i + 1) begin
                    rat_r[i] <= rat_ns_r[i];
                    rat_tag_r[i] <= rat_tag_ns_r[i];
                end
                rng_counter_r <= rng_counter_ns_r;
                state_r <= state_ns_r;
                valid_o_r <= valid_o_ns_r;
                is_hit_o_r <= is_hit_o_ns_r;
                current_search_addr_r <= current_search_addr_ns_r;
                issue_preventive_refresh_o_r <= issue_preventive_refresh_o_ns_r;
                row_addr_r <= row_addr_ns_r;
            end
    end


endmodule