//=============================================================================
// Module Name: axi4_skid_buffer
// Description: Zero-Bubble Forward-Registered Skid Buffer (Register Slice).
//              Decouples AXI4 ready/valid handshakes to break long combinational
//              timing paths without introducing pipeline dead cycles (bubbles).
// Standard:    AMBA AXI4 / Synthesizable SystemVerilog (IEEE 1800-2017)
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

endmodule
