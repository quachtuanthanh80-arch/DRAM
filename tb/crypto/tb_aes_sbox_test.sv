//=============================================================================
// Testbench: tb_aes_sbox_test
// Description: Automated self-checking testbench for AES S-Box.
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module tb_aes_sbox_test;

    logic [7:0] in_byte;
    logic [7:0] out_byte;

    // Instantiate S-Box DUT
    aes_sbox dut_sbox (
        .in_byte (in_byte),
        .out_byte(out_byte)
    );

    typedef logic [7:0] byte_t;
    localparam byte_t InVals[8]   = '{8'h00, 8'h01, 8'h53, 8'hd4, 8'hff, 8'h10, 8'h45, 8'h2b};
    localparam byte_t ExpVals[8]  = '{8'h63, 8'h7c, 8'hed, 8'h48, 8'h16, 8'hca, 8'h6e, 8'hf1};

    int pass_count = 0;
    int fail_count = 0;

    initial begin
        $display("==========================================================");
        $display("[TESTBENCH] Starting Automated Verification for AES S-Box...");
        $display("==========================================================");

        in_byte = 8'h00;
        #10;

        for (int i = 0; i < 8; i++) begin
            in_byte = InVals[i];
            #10;
            if (out_byte === ExpVals[i]) begin
                $display("[PASS] Iter %0d: S-Box(0x%02h) = 0x%02h (Expected: 0x%02h)",
                         i, in_byte, out_byte, ExpVals[i]);
                pass_count++;
            end else begin
                $display("[FAIL] Iter %0d: S-Box(0x%02h) = 0x%02h (Expected: 0x%02h)",
                         i, in_byte, out_byte, ExpVals[i]);
                fail_count++;
            end
        end

        $display("==========================================================");
        if (fail_count == 0) begin
            $display(">>> ALL 8 NIST S-BOX VECTORS PASSED PERFECTLY! <<<");
        end else begin
            $display(">>> TOTAL: %0d Passed, %0d Failed <<<", pass_count, fail_count);
        end
        $display("==========================================================");

        #10;
        $finish;
    end

endmodule: tb_aes_sbox_test
