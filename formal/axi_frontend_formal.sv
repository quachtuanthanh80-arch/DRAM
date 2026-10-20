// File: axi_frontend_formal.sv
// Chức năng: Formal wrapper kiểm chứng hình thức cho axi_slave_frontend tích hợp thuộc tính ZipCPU.
`timescale 1ns / 1ps

/* verilator lint_off SYNCASYNCNET */

module axi_frontend_formal #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_QOS_WIDTH  = 4
) (
    input  logic                      clk_axi,
    input  logic                      aresetn_axi,

    // AXI4 Slave AW
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // AXI4 Slave W
    input  logic [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                        s_axi_wlast,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,

    // AXI4 Slave B
    output logic [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // AXI4 Slave AR
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // AXI4 Slave R
    output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // Internal Core Interface
    input  logic                      i_wr_addr_ready,
    output logic                      o_wr_addr_valid,
    output logic                      o_wr_addr_cross_4kb,

    input  logic                      i_wr_data_ready,
    output logic                      o_wr_data_valid,

    input  logic                      i_bresp_valid,
    output logic                      o_bresp_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_bresp_id,
    input  logic [1:0]                i_bresp_code,

    input  logic                      i_rd_req_ready,
    output logic                      o_rd_req_valid,
    output logic                      o_rd_req_cross_4kb,

    input  logic                      i_rdata_valid,
    output logic                      o_rdata_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_rdata_id,
    input  logic [AXI_DATA_WIDTH-1:0] i_rdata,
    input  logic [1:0]                i_rdata_resp,
    input  logic                      i_rdata_last
);

    /* verilator lint_off PINCONNECTEMPTY */
    axi_slave_frontend #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH)
    ) dut (
        .clk_axi              (clk_axi),
        .aresetn_axi          (aresetn_axi),
        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awlen          (s_axi_awlen),
        .s_axi_awsize         (s_axi_awsize),
        .s_axi_awburst        (s_axi_awburst),
        .s_axi_awqos          (s_axi_awqos),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),
        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wlast          (s_axi_wlast),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),
        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        .s_axi_bready         (s_axi_bready),
        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arlen          (s_axi_arlen),
        .s_axi_arsize         (s_axi_arsize),
        .s_axi_arburst        (s_axi_arburst),
        .s_axi_arqos          (s_axi_arqos),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),
        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        .s_axi_rready         (s_axi_rready),
        .s_axi_awpoison       (1'b0),
        .s_axi_wpoison        ('0),
        .s_axi_arpoison       (1'b0),
        .s_axi_rpoison        (),
        .s_axi_awchk          (4'h0),
        .s_axi_archk          (4'h0),
        .s_axi_wchk           ('0),
        .s_axi_rchk           (),
        .cfg_parity_check_en  (1'b0),
        .o_parity_err         (),
        .o_wr_addr_valid      (o_wr_addr_valid),
        .i_wr_addr_ready      (i_wr_addr_ready),
        .o_wr_addr_id         (),
        .o_wr_addr            (),
        .o_wr_len             (),
        .o_wr_size            (),
        .o_wr_burst           (),
        .o_wr_qos             (),
        .o_wr_addr_cross_4kb  (o_wr_addr_cross_4kb),
        .o_wr_data_valid      (o_wr_data_valid),
        .i_wr_data_ready      (i_wr_data_ready),
        .o_wr_data            (),
        .o_wr_strb            (),
        .o_wr_last            (),
        .i_bresp_valid        (i_bresp_valid),
        .o_bresp_ready        (o_bresp_ready),
        .i_bresp_id           (i_bresp_id),
        .i_bresp_code         (i_bresp_code),
        .o_rd_req_valid       (o_rd_req_valid),
        .i_rd_req_ready       (i_rd_req_ready),
        .o_rd_req_id          (),
        .o_rd_req_addr        (),
        .o_rd_req_len         (),
        .o_rd_req_size        (),
        .o_rd_req_burst       (),
        .o_rd_req_qos         (),
        .o_rd_req_cross_4kb   (o_rd_req_cross_4kb),
        .i_rdata_valid        (i_rdata_valid),
        .o_rdata_ready        (o_rdata_ready),
        .i_rdata_id           (i_rdata_id),
        .i_rdata              (i_rdata),
        .i_rdata_resp         (i_rdata_resp),
        .i_rdata_last         (i_rdata_last),
        .i_rdata_poison       (1'b0)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // Bind AXI4 Formal Properties
    faxi_slave_assertions #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH)
    ) u_faxi_assert (
        .clk      (clk_axi),
        .rst_n    (aresetn_axi),
        .awid     (s_axi_awid),
        .awaddr   (s_axi_awaddr),
        .awlen    (s_axi_awlen),
        .awsize   (s_axi_awsize),
        .awburst  (s_axi_awburst),
        .awqos    (s_axi_awqos),
        .awvalid  (s_axi_awvalid),
        .awready  (s_axi_awready),
        .wdata    (s_axi_wdata),
        .wstrb    (s_axi_wstrb),
        .wlast    (s_axi_wlast),
        .wvalid   (s_axi_wvalid),
        .wready   (s_axi_wready),
        .bid      (s_axi_bid),
        .bresp    (s_axi_bresp),
        .bvalid   (s_axi_bvalid),
        .bready   (s_axi_bready),
        .arid     (s_axi_arid),
        .araddr   (s_axi_araddr),
        .arlen    (s_axi_arlen),
        .arsize   (s_axi_arsize),
        .arburst  (s_axi_arburst),
        .arqos    (s_axi_arqos),
        .arvalid  (s_axi_arvalid),
        .arready  (s_axi_arready),
        .rid      (s_axi_rid),
        .rdata    (s_axi_rdata),
        .rresp    (s_axi_rresp),
        .rlast    (s_axi_rlast),
        .rvalid   (s_axi_rvalid),
        .rready   (s_axi_rready)
    );

`ifdef FORMAL
    // Ràng buộc môi trường nội bộ: Core luôn đáp ứng hoặc phản hồi hợp lệ
    always_ff @(posedge clk_axi) begin
        if (aresetn_axi && $past(aresetn_axi)) begin
            if ($past(i_bresp_valid) && !$past(o_bresp_ready)) begin
                assume (i_bresp_valid);
                assume (i_bresp_id   == $past(i_bresp_id));
                assume (i_bresp_code == $past(i_bresp_code));
            end
            if ($past(i_rdata_valid) && !$past(o_rdata_ready)) begin
                assume (i_rdata_valid);
                assume (i_rdata_id   == $past(i_rdata_id));
                assume (i_rdata      == $past(i_rdata));
                assume (i_rdata_resp == $past(i_rdata_resp));
                assume (i_rdata_last == $past(i_rdata_last));
            end
        end
    end

    // Kiểm chứng bất biến: Khi có request ghi ra core thì valid tương ứng được chuyển giao an toàn
    always_ff @(posedge clk_axi) begin
        if (aresetn_axi && $past(aresetn_axi)) begin
            if ($past(o_wr_addr_valid) && !$past(i_wr_addr_ready)) begin
                assert (o_wr_addr_valid);
            end
            if ($past(o_rd_req_valid) && !$past(i_rd_req_ready)) begin
                assert (o_rd_req_valid);
            end
        end
    end
`endif

endmodule
