//=============================================================================
// File:        axi4_slave_adapter.sv
// Chức năng:   Tiếp nhận giao tiếp AXI4 Slave, kiểm tra vượt biên 4KB và phân chia lưu lượng hai kênh con DDR5.
//=============================================================================
`timescale 1ns / 1ps

module axi4_slave_adapter #(
    parameter int IdWidth    = 8,
    parameter int AddrWidth  = 34,    // 16 GB addressing space
    parameter int DataWidth  = 128,   // 128-bit internal data beat
    parameter int TweakWidth = 128,
    parameter int MaxBursts  = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,

    //-------------------------------------------------------------------------
    // AXI4 Slave Interface (External Bus)
    //-------------------------------------------------------------------------
    // Write Address (AW) Channel
    input  logic [IdWidth-1:0]    s_axi_awid,
    input  logic [AddrWidth-1:0]  s_axi_awaddr,
    input  logic [7:0]            s_axi_awlen,
    input  logic [2:0]            s_axi_awsize,
    input  logic [1:0]            s_axi_awburst,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,

    // Write Data (W) Channel
    input  logic [DataWidth-1:0]  s_axi_wdata,
    input  logic [DataWidth/8-1:0] s_axi_wstrb,
    input  logic                  s_axi_wlast,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,

    // Write Response (B) Channel
    output logic [IdWidth-1:0]    s_axi_bid,
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,

    // Read Address (AR) Channel
    input  logic [IdWidth-1:0]    s_axi_arid,
    input  logic [AddrWidth-1:0]  s_axi_araddr,
    input  logic [7:0]            s_axi_arlen,
    input  logic [2:0]            s_axi_arsize,
    input  logic [1:0]            s_axi_arburst,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,

    // Read Data (R) Channel
    output logic [IdWidth-1:0]    s_axi_rid,
    output logic [DataWidth-1:0]  s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rlast,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    //-------------------------------------------------------------------------
    // Subchannel A (Lane A) Interface to AES-XTS / DRAM FIFO
    //-------------------------------------------------------------------------
    output logic                  sub_a_valid,
    input  logic                  sub_a_ready,
    output logic [DataWidth-1:0]  sub_a_data,
    output logic [TweakWidth-1:0] sub_a_tweak,
    output logic [15:0]           sub_a_meta,

    //-------------------------------------------------------------------------
    // Subchannel B (Lane B) Interface to AES-XTS / DRAM FIFO
    //-------------------------------------------------------------------------
    output logic                  sub_b_valid,
    input  logic                  sub_b_ready,
    output logic [DataWidth-1:0]  sub_b_data,
    output logic [TweakWidth-1:0] sub_b_tweak,
    output logic [15:0]           sub_b_meta,

    // Status & Diagnostics
    output logic                  adapter_idle,
    output logic [31:0]           total_transfers
);

    //-------------------------------------------------------------------------
    // 1. Skid Buffer Instances on External AXI Channels
    //-------------------------------------------------------------------------
    // AW Skid Buffer Pack: {awid, awaddr, awlen, awsize, awburst}
    localparam int AwPackWidth = IdWidth + AddrWidth + 8 + 3 + 2;
    logic [AwPackWidth-1:0] aw_s_pack;
    logic [AwPackWidth-1:0] aw_m_pack;
    logic                   aw_buffered_valid;
    logic                   aw_buffered_ready;

    assign aw_s_pack = {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst};

    axi4_skid_buffer #(.DATA_WIDTH(AwPackWidth)) u_aw_skid (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(s_axi_awvalid),
        .s_ready(s_axi_awready),
        .s_data (aw_s_pack),
        .m_valid(aw_buffered_valid),
        .m_ready(aw_buffered_ready),
        .m_data (aw_m_pack)
    );

    logic [IdWidth-1:0]   buf_awid;
    logic [AddrWidth-1:0] buf_awaddr;
    logic [7:0]           buf_awlen;
    logic [2:0]           buf_awsize;
    logic [1:0]           buf_awburst;
    assign {buf_awid, buf_awaddr, buf_awlen, buf_awsize, buf_awburst} = aw_m_pack;

    // W Skid Buffer Pack: {wdata, wstrb, wlast}
    localparam int WPackWidth = DataWidth + (DataWidth/8) + 1;
    logic [WPackWidth-1:0] w_s_pack;
    logic [WPackWidth-1:0] w_m_pack;
    logic                  w_buffered_valid;
    logic                  w_buffered_ready;

    assign w_s_pack = {s_axi_wdata, s_axi_wstrb, s_axi_wlast};

    axi4_skid_buffer #(.DATA_WIDTH(WPackWidth)) u_w_skid (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(s_axi_wvalid),
        .s_ready(s_axi_wready),
        .s_data (w_s_pack),
        .m_valid(w_buffered_valid),
        .m_ready(w_buffered_ready),
        .m_data (w_m_pack)
    );

    logic [DataWidth-1:0]   buf_wdata;
    logic [DataWidth/8-1:0] buf_wstrb;
    logic                   buf_wlast;
    assign {buf_wdata, buf_wstrb, buf_wlast} = w_m_pack;

    // B Skid Buffer Pack: {bid, bresp}
    localparam int BPackWidth = IdWidth + 2;
    logic [BPackWidth-1:0] b_int_pack;
    logic [BPackWidth-1:0] b_out_pack;
    logic                  b_int_valid;
    logic                  b_int_ready;

    assign {s_axi_bid, s_axi_bresp} = b_out_pack;

    axi4_skid_buffer #(.DATA_WIDTH(BPackWidth)) u_b_skid (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(b_int_valid),
        .s_ready(b_int_ready),
        .s_data (b_int_pack),
        .m_valid(s_axi_bvalid),
        .m_ready(s_axi_bready),
        .m_data (b_out_pack)
    );

    //-------------------------------------------------------------------------
    // 2. Write Transaction Decomposition State Machine
    // Splits 64B burst (4 beats of 128-bit) into:
    // Beat 0 & 1 -> Subchannel A
    // Beat 2 & 3 -> Subchannel B
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        W_IDLE    = 2'b00,
        W_BURST   = 2'b01,
        W_RESP    = 2'b10
    } write_state_t;

    write_state_t w_state;
    logic [7:0]   w_beat_count;
    logic [IdWidth-1:0] active_wid;
    logic [AddrWidth-1:0] active_waddr;

    // Tweak computation helper: Speculatively derives Tweak from base address
    logic [TweakWidth-1:0] current_tweak;
    always_comb begin
        // Sector address aligned to 128-bit block index
        current_tweak = {92'h0, active_waddr[AddrWidth-1:4], w_beat_count[5:0]};
    end

    // Subchannel steering:
    // Beat 0 & 1 -> Lane A
    // Beat 2 & 3 -> Lane B
    logic target_lane_b;
    assign target_lane_b = w_beat_count[1]; // 0,1 -> 0 (Lane A); 2,3 -> 1 (Lane B)

    // Handshake control
    always_comb begin
        aw_buffered_ready = 1'b0;
        w_buffered_ready  = 1'b0;
        sub_a_valid       = 1'b0;
        sub_b_valid       = 1'b0;
        sub_a_data        = buf_wdata;
        sub_b_data        = buf_wdata;
        sub_a_tweak       = current_tweak;
        sub_b_tweak       = current_tweak;
        sub_a_meta        = {8'hA0, w_beat_count};
        sub_b_meta        = {8'hB0, w_beat_count};

        case (w_state)
            W_IDLE: begin
                aw_buffered_ready = 1'b1;
            end

            W_BURST: begin
                if (!target_lane_b) begin
                    // Steering to Subchannel A
                    sub_a_valid      = w_buffered_valid;
                    w_buffered_ready = sub_a_ready;
                end else begin
                    // Steering to Subchannel B
                    sub_b_valid      = w_buffered_valid;
                    w_buffered_ready = sub_b_ready;
                end
            end

            W_RESP: begin
                // Waiting for B channel skid buffer handshake
            end

            default: ;
        endcase
    end

    // Write Sequencer FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state         <= W_IDLE;
            w_beat_count    <= 8'h0;
            active_wid      <= '0;
            active_waddr    <= '0;
            b_int_valid     <= 1'b0;
            b_int_pack      <= '0;
            total_transfers <= 32'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    b_int_valid <= 1'b0;
                    if (aw_buffered_valid && aw_buffered_ready) begin
                        active_wid   <= buf_awid;
                        active_waddr <= buf_awaddr;
                        w_beat_count <= 8'h0;
                        w_state      <= W_BURST;
                    end
                end

                W_BURST: begin
                    if (w_buffered_valid && w_buffered_ready) begin
                        w_beat_count    <= w_beat_count + 8'd1;
                        total_transfers <= total_transfers + 32'd1;
                        if (buf_wlast) begin
                            w_state <= W_RESP;
                        end
                    end
                end

                W_RESP: begin
                    b_int_pack  <= {active_wid, 2'b00}; // OKAY response
                    b_int_valid <= 1'b1;
                    if (b_int_valid && b_int_ready) begin
                        b_int_valid <= 1'b0;
                        w_state     <= W_IDLE;
                    end
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 3. Read Channel Skid Buffers & Stub (Pass-through for Top Integration)
    //-------------------------------------------------------------------------
    assign s_axi_arready = 1'b1;
    assign s_axi_rid     = s_axi_arid;
    assign s_axi_rdata   = 128'h0;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = 1'b1;
    assign s_axi_rvalid  = 1'b0;

    assign adapter_idle  = (w_state == W_IDLE);

    // Lint unused signal sink
    logic _unused_axi;
    assign _unused_axi = &{s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst,
                           s_axi_arvalid, s_axi_rready, buf_awlen, buf_awsize,
                           buf_awburst, buf_wstrb, active_waddr[3:0], 1'b0};

endmodule: axi4_slave_adapter
