// File:      qs_fault_inj.svh
// Chức năng: Macro và task bơm lỗi dùng chung (deposit/flip/force có thời hạn), ghi nhật ký [FI] và đo số chu kỳ tới khi phát hiện.

// Yêu cầu TB khai báo `longint tb_cyc` (đếm cạnh lên clk sau reset) trước khi include.
// SEU một chu kỳ = deposit ở negedge chu kỳ n (flop giữ giá trị sai trong chu kỳ n, cạnh n+1 nạp lại theo logic).
// force N chu kỳ: sau release biến giữ giá trị ép tới lần gán kế tiếp nên cửa sổ lỗi thật là N+1 chu kỳ (plan §1.4).
`ifndef QS_FAULT_INJ_SVH
`define QS_FAULT_INJ_SVH
`include "qs_hier.svh"

int     fi_count          = 0;
int     fi_detect_cnt     = 0;
int     fi_detect_lat_max = 0;
longint fi_last_cyc       = -1;
bit     fi_any            = 1'b0;
string  fi_last_id        = "";

task automatic fi_log(input string id, input string path, input string how);
    fi_count++;
    fi_any      = 1'b1;
    fi_last_cyc = tb_cyc;
    fi_last_id  = id;
    $display("[FI] id=%s path=%s %s cyc=%0d", id, path, how, tb_cyc);
endtask

// Gọi tại chu kỳ quan sát thấy phát hiện; trả độ trễ so với lần bơm gần nhất
function automatic int fi_detect(input string id);
    int lat;
    lat = int'(tb_cyc - fi_last_cyc);
    fi_detect_cnt++;
    if (lat > fi_detect_lat_max) fi_detect_lat_max = lat;
    $display("[FI-DET] id=%s detected after %0d cycles (inject cyc %0d)", id, lat, fi_last_cyc);
    return lat;
endfunction

// Dòng ngoài mô hình lỗi đơn (Q8): chỉ đo, không phán định
task automatic fi_residual(input string id, input string msg);
    $display("[FI-RESIDUAL] id=%s %s", id, msg);
endtask

`define QS_DEPOSIT(id, p, v) begin p = v; fi_log(id, `QS_STR(p), $sformatf("deposit=0x%0h", v)); end
`define QS_FLIP(id, p, b) begin p[b] = ~p[b]; fi_log(id, `QS_STR(p), $sformatf("flip bit %0d", b)); end
`define QS_FORCE_N(id, p, v, n, ck) begin force p = v; fi_log(id, `QS_STR(p), $sformatf("force=0x%0h for %0d cycles", v, n)); repeat (n) @(negedge ck); release p; end

`endif
