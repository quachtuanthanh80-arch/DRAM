# Nhật ký review và quyết định của reviewer

File này do reviewer (Claude) ghi, không phải do Gemini. Mỗi dòng là một quyết định có hiệu lực cho các task sau.

## 2026-11-06: thiết lập khung

| # | Quyết định | Lý do |
|---|---|---|
| R-01 | Baseline gồm 4 báo cáo verification độc lập (VA, VB, VC, VD) hợp nhất trong `docs/verification_findings.md`. Mục `[A]`/`[R]` chưa được Claude tái kiểm; task đầu tiên chạm mục đó phải tái hiện (fail trước) | Tránh sửa theo phỏng đoán |
| R-02 | Số "38/40", "30/30", "19", "14", "20 suites" trong mọi tài liệu đều không dùng được cho tới khi T02 sinh lại `regression_summary.json` | Ba nguồn kết quả mâu thuẫn và đều cũ (H-9) |
| R-03 | Task có dòng `- trạng thái: DỪNG` trong note không được đánh dấu xong; `check_notes.py` thoát 1 | Tránh lặp lỗi task dừng nhưng vẫn bị commit và chuyển tiếp |
| R-04 | Không nới check, không thêm XFAIL, không tăng timeout để task qua cổng (R1, R15). Nếu T41 không đóng được timing thì dừng và báo; không đổi chu kỳ 2.5 ns, không đổi part | Tránh lặp lỗi claim 424,1 MHz không có nguồn (C-5) |
| R-05 | Khi báo mutation, ghi rõ phạm vi (số mutant, cách chọn); không viết "mutation score 100%" trần | Tránh nói quá |
| R-06 | `check_corner_matrix.py` "covered" mới nghĩa là có test trỏ tới. Trước T70 Claude kiểm chọn mẫu 10 ca xem test có thật sự kiểm đúng corner case | Tránh coi file tồn tại là đã kiểm |
| R-07 | D1 và D6 đã chốt (2026-11-06); D2, D3, D4, D5 còn "Chưa chốt"; task KHÓA chưa được giao | Gemini không tự chốt kiến trúc |
| R-08 | D1: `axi_ddr5_mc_top` là top chuẩn. C-3, C-4, H-1 (lỗi của `sec_ddr5_controller_top`) đóng theo phạm vi ở T10 (nhãn demo + `LIMITATIONS.md`); T11 kiểm đường chính cho cùng lớp lỗi. Nếu T10 phát hiện số liệu/claim lấy từ synth của top demo, chuyển sang T51 | Top demo có synth script riêng (`syn/run_synth.tcl`), có nguy cơ gán nhầm số liệu |
| R-09 | D6: Gemini commit chỉ trên `remediation/main`; `CLAUDE.md` giữ nguyên cho Claude | Giữ ranh giới vai trò |
