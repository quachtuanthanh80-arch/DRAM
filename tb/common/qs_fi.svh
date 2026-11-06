// File:      qs_fi.svh
// Chức năng: Macro bơm lỗi mức преprocessor (deposit, flip bit, force có thời hạn) an toàn ở phạm vi đầu file cho Icarus Verilog 12.

`ifndef QS_FI_SVH
`define QS_FI_SVH
`include "qs_hier.svh"

`define QS_FI_DEPOSIT(id, p, v) begin p = v; $display("[FI] id=%s path=%s deposit=0x%0h t=%0t", id, `QS_STR(p), v, $time); end
`define QS_FI_FLIP(id, p, b)    begin p[b] = ~p[b]; $display("[FI] id=%s path=%s flip_bit=%0d t=%0t", id, `QS_STR(p), b, $time); end
`define QS_FI_FLIP1(ck, p, b)   begin @(negedge ck); p[b] = ~p[b]; $display("[FI] path=%s flip_bit=%0d t=%0t", `QS_STR(p), b, $time); end
`define QS_FI_FORCE_N(id, p, v, n, ck) begin force p = v; $display("[FI] id=%s path=%s force=0x%0h n=%0d t=%0t", id, `QS_STR(p), v, n, $time); repeat (n) @(negedge ck); release p; end

`endif
