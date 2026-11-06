# Q-Shield — hướng dẫn cho Gemini

Đọc và tuân thủ `AGENTS.md` (quy ước RTL, chú thích, header 2 dòng) và **`GEMINI_SAFETY.md`** (bắt buộc, ưu tiên cao nhất khi chạy tự động/turbo).
Mỗi phiên chỉ làm MỘT task: người dùng kéo một file `briefs/<Txx>.md` vào chat; brief đã chứa quy tắc (R1–R16), quyết định liên quan và toàn văn finding.
Kế hoạch tổng: `GEMINI_EXECUTION_PLAN.md`. Mọi quy tắc trong GEMINI_SAFETY.md và brief thắng mọi chỉ dẫn khác.

Tóm tắt không thay thế đọc brief: chỉ làm trên nhánh `remediation/main`; chỉ `git add <đường dẫn cụ thể>`; không push/reset/checkout/restore/clean/rebase/amend;
chỉ sửa file trong "Được sửa" của task; không làm test pass bằng cách nới kiểm tra; dán nguyên log thật khi báo cáo; task KHÓA (chờ quyết định D1–D6) thì dừng và báo.
