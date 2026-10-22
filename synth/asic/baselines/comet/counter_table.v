`include "parameters.vh"

module counter_table
(
    input                           clk_i,
    input                           rst_i,
    input [`ROW_ADDR_BIT - 1 : 0]   row_addr_i,
    input                           is_ACT_i,
    input                           is_RAT_valid_i,
    input                           is_RAT_hit_i,
    output [`COUNTER_BIT - 1 : 0]   min_counter_o,
    output                          update_RAT_o,
    output [`ROW_ADDR_BIT - 1 : 0]  update_RAT_row_addr_o,
    output [`ROW_ADDR_BIT - 1 : 0]  agg_row_addr_o,
    output                          issue_preventive_refresh_o

);
    //counter table
    reg [`COUNTER_BIT - 1 : 0] ct_r [`N_HASH -1 : 0][`CT_ENTRY-1:0];
    reg [`COUNTER_BIT - 1 : 0] ct_ns_r [`N_HASH -1 : 0][`CT_ENTRY-1:0];


    integer i = 0;
    integer ii = 0;
    localparam  IDLE        = 0,
                UPDATE      = 1;
    reg [1:0] state_r, state_ns_r;
    reg update_RAT_o_r, update_RAT_o_ns_r;
    reg issue_preventive_refresh_o_r, issue_preventive_refresh_o_ns_r;
    reg [`ROW_ADDR_BIT - 1 : 0] update_RAT_row_addr_o_r, update_RAT_row_addr_o_ns_r;

    wire [$clog2(`CT_ENTRY)-1:0] hash_addr [`N_HASH -1 : 0];
    wire [`COUNTER_BIT - 1 : 0] counter_value [`N_HASH -1 : 0];
    //hash function
    genvar j;
    generate
        for(j = 0; j < `N_HASH; j = j + 1) begin
            assign hash_addr[j] = row_addr_i >> j;
            assign counter_value[j] = ct_r[j][hash_addr[j]];
        end
    endgenerate
    //here is hard-coded for 4 hash functions. if you want to parameterize it, good luck.
    wire [`COUNTER_BIT - 1 : 0] min1_counter_idx = (counter_value[0] < counter_value[1]) ? 0 : 1;
    wire [`COUNTER_BIT - 1 : 0] min2_counter_idx = (counter_value[2] < counter_value[3]) ? 2 : 3;
    wire [`COUNTER_BIT - 1 : 0] min_counter_idx = (min1_counter_idx < min2_counter_idx) ? min1_counter_idx : min2_counter_idx;

    assign min_counter_o = counter_value[min_counter_idx];
    assign update_RAT_o = update_RAT_o_r;
    assign issue_preventive_refresh_o = issue_preventive_refresh_o_r;
    assign update_RAT_row_addr_o = update_RAT_row_addr_o_r;
    assign agg_row_addr_o = update_RAT_row_addr_o_r;

    always@(*) begin
        state_ns_r = state_r;
        update_RAT_o_ns_r = update_RAT_o_r;
        issue_preventive_refresh_o_ns_r = issue_preventive_refresh_o_r;
        update_RAT_row_addr_o_ns_r = update_RAT_row_addr_o_r;
        for(i = 0; i < `N_HASH; i = i + 1) begin
            for(ii = 0; ii < `CT_ENTRY; ii = ii + 1) begin
                ct_ns_r[i][ii] = ct_r[i][ii];
            end
        end
        case(state_r)
        IDLE: begin
            issue_preventive_refresh_o_ns_r = 0;
            update_RAT_row_addr_o_ns_r = 0;
            if(is_ACT_i) begin
                state_ns_r = UPDATE;
                update_RAT_row_addr_o_ns_r = row_addr_i;
            end
            else begin
                state_ns_r = IDLE;
            end
        end
        UPDATE: begin
            if(is_RAT_valid_i) begin
                if(!is_RAT_hit_i) begin
                    //meaning you could not find the row address in the RAT
                    //you should increase the counter
                    if(ct_r[min_counter_idx][hash_addr[min_counter_idx]] < `N_RH) begin
                        ct_ns_r[min_counter_idx][hash_addr[min_counter_idx]] = ct_r[min_counter_idx][hash_addr[min_counter_idx]] + 1;
                    end
                    else begin
                        update_RAT_o_ns_r = 1;
                        issue_preventive_refresh_o_ns_r = 1;
                    end
                end
                state_ns_r = IDLE;
            end
            else begin
                state_ns_r = UPDATE;
            end
        end
        default: begin
            state_ns_r = IDLE;
        end
        endcase
    end

    always@(posedge clk_i) begin
        if(rst_i) begin
            //reset the counter table
            for(i = 0; i < `N_HASH; i = i + 1) begin
                for(ii = 0; ii < `CT_ENTRY; ii = ii + 1) begin
                    ct_r[i][ii] <= 0;
                end
            end
            state_r <= IDLE;
            update_RAT_o_r <= 0;
            issue_preventive_refresh_o_r <= 0;
            update_RAT_row_addr_o_r <= 0;
        end
        else begin
            for(i = 0; i < `N_HASH; i = i + 1) begin
                for(ii = 0; ii < `CT_ENTRY; ii = ii + 1) begin
                    ct_r[i][ii] <= ct_ns_r[i][ii] ;
                end
            end
            state_r <= state_ns_r;
            update_RAT_o_r <= update_RAT_o_ns_r;
            issue_preventive_refresh_o_r <= issue_preventive_refresh_o_ns_r;
            update_RAT_row_addr_o_r <= update_RAT_row_addr_o_ns_r;
        end
    end


endmodule
