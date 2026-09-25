//=============================================================================
// File:        axi4_skid_buffer.sv
// Chức năng:   Đệm trượt Forward/Reverse 2 tầng hấp thụ áp lực bắt tay AXI4 đạt thông lượng Zero-Bubble.
//=============================================================================
`timescale 1ns / 1ps

module axi4_skid_buffer #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Upstream (Slave) Interface
    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [DATA_WIDTH-1:0] s_data,

    // Downstream (Master) Interface
    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [DATA_WIDTH-1:0] m_data
);

    // Internal Skid Storage
    logic [DATA_WIDTH-1:0] skid_data_reg;
    logic                  skid_valid_reg;

    // Upstream is ready whenever the auxiliary skid buffer is empty
    assign s_ready = ~skid_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid        <= 1'b0;
            m_data         <= '0;
            skid_valid_reg <= 1'b0;
            skid_data_reg  <= '0;
        end else begin
            // Downstream transaction completed or output currently vacant
            if (m_ready || !m_valid) begin
                if (skid_valid_reg) begin
                    // Drain the skid buffer into main output
                    m_valid        <= 1'b1;
                    m_data         <= skid_data_reg;
                    skid_valid_reg <= 1'b0;
                end else begin
                    // Forward incoming data straight to output
                    m_valid        <= s_valid;
                    m_data         <= s_data;
                end
            end else if (s_valid && s_ready) begin
                // Downstream is stalled; absorb the incoming beat into skid buffer
                skid_valid_reg <= 1'b1;
                skid_data_reg  <= s_data;
            end
        end
    end

    //=========================================================================
    // SystemVerilog Assertions (SVA) - Protocol Verification
    //=========================================================================
`ifdef SVA_CHECKERS
    // 1. Data must remain stable when s_valid is high and s_ready is low
    property p_upstream_stable;
        @(posedge clk) disable iff (!rst_n)
        (s_valid && !s_ready) |=> (s_valid && $stable(s_data));
    endproperty
    assert_upstream_stable: assert property (p_upstream_stable)
        else $error("[SVA ERROR] Upstream data altered during stall!");

    // 2. Output data must remain stable when m_valid is high and m_ready is low
    property p_downstream_stable;
        @(posedge clk) disable iff (!rst_n)
        (m_valid && !m_ready) |=> (m_valid && $stable(m_data));
    endproperty
    assert_downstream_stable: assert property (p_downstream_stable)
        else $error("[SVA ERROR] Downstream data altered during stall!");
`endif

    //=========================================================================
    // Hardware Formal Verification (SymbiYosys / SVA)
    //=========================================================================
`ifdef FORMAL
    initial begin
        assume (!rst_n);
    end

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    // Protocol Assumption: Upstream input stability when backpressured
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_valid) && !$past(s_ready)) begin
                assume (s_valid);
                assume (s_data == $past(s_data));
            end
        end
    end

    // Property 1: Reset Behavior - all valids must drop to 0
    always_comb begin
        if (!rst_n) begin
            assert (!m_valid);
            assert (!skid_valid_reg);
            assert (s_ready);
        end
    end

    // Property 2: Downstream Output Stability when stalled
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(m_valid) && !$past(m_ready)) begin
                assert (m_valid);
                assert (m_data == $past(m_data));
            end
        end
    end

    // Property 3: Maximum Occupancy Invariant (skid buffer holds at most 2 items)
    wire [1:0] occupancy = {1'b0, m_valid} + {1'b0, skid_valid_reg};
    always_comb begin
        if (rst_n) begin
            assert (occupancy <= 2'd2);
        end
    end

    // Property 4: Zero-Bubble Invariant
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(!m_valid && !skid_valid_reg && s_valid)) begin
                assert (m_valid);
                assert (m_data == $past(s_data));
            end
        end
    end

    // Property 5: Full Backpressure Assertion
    always_comb begin
        if (rst_n) begin
            if (skid_valid_reg) begin
                assert (!s_ready);
            end else begin
                assert (s_ready);
            end
        end
    end
`endif

endmodule
