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

    logic [7:0] InVals[8];
    logic [7:0] ExpVals[8];

    int pass_count = 0;
    int fail_count = 0;

    initial begin
        InVals[0] = 8'h00; ExpVals[0] = 8'h63;
        InVals[1] = 8'h01; ExpVals[1] = 8'h7c;
        InVals[2] = 8'h53; ExpVals[2] = 8'hed;
        InVals[3] = 8'hd4; ExpVals[3] = 8'h48;
        InVals[4] = 8'hff; ExpVals[4] = 8'h16;
        InVals[5] = 8'h10; ExpVals[5] = 8'hca;
        InVals[6] = 8'h45; ExpVals[6] = 8'h6e;
        InVals[7] = 8'h2b; ExpVals[7] = 8'hf1;

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
