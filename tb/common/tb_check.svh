// File:      tb_check.svh
// Chức năng: Bộ đếm kiểm tra dùng chung cho testbench; in dòng [TB_RESULT] làm căn cứ duy nhất để harness phán định PASS/FAIL.

// Harness chỉ chấp nhận PASS khi checks > 0 và fails == 0: testbench không kiểm tra gì sẽ không thể "xanh".
// XFAIL đánh dấu tính năng chưa hiện thực (gắn mã lỗ hổng R*/S* trong kế hoạch), không được tính là PASS.
int tb_checks = 0;
int tb_fails  = 0;
int tb_xfails = 0;

task automatic tb_check(input bit cond, input string msg);
    tb_checks++;
    if (cond) begin
        $display("[CHECK-OK] %s", msg);
    end else begin
        tb_fails++;
        $display("[FAIL] %s", msg);
    end
endtask

task automatic tb_xfail(input string gap_id, input string msg);
    tb_xfails++;
    $display("[XFAIL] %s: %s", gap_id, msg);
endtask

// Kiểm tra thật cho lỗ hổng đã biết: sai → XFAIL; đúng → XPASS tính là lỗi (strict) để buộc gỡ nhãn khi đã sửa.
task automatic tb_check_xfail(input bit cond, input string gap_id, input string msg);
    tb_checks++;
    if (cond) begin
        tb_fails++;
        $display("[XPASS] %s fixed, remove xfail marker: %s", gap_id, msg);
    end else begin
        tb_xfails++;
        $display("[XFAIL] %s: %s", gap_id, msg);
    end
endtask

// Gộp bộ đếm cũ (tests_run/tests_failed) của testbench có sẵn vào kết quả chuẩn.
task automatic tb_merge_legacy(input int run, input int failed);
    tb_checks += run;
    tb_fails  += failed;
endtask

task automatic tb_report();
    $display("[TB_RESULT] checks=%0d fails=%0d xfails=%0d", tb_checks, tb_fails, tb_xfails);
endtask
