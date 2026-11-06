# An toàn khi để Gemini chạy Turbo (Q-Shield)

Mục đích: cho phép Turbo (tự chạy lệnh) mà không làm mất công sức hay đẩy nhầm dữ liệu. Lý do cần: working tree có khoảng 166 file chưa commit
(gồm nhiều file xóa trong `GOLDEN_OUTPUTS/`, `sim/results/`, `sim/traces/`); một lệnh hủy diệt sẽ không khôi phục được bằng git.
Cấu trúc theo bộ khung của dự án NCKH: plan, brief từng task, note từng task, nhật ký review, và `safety_check.py`.

## 1. Đã chuẩn bị

- Bản sao lưu toàn bộ dự án (trừ `hwsec-repos/`, `build/`, `downloads/`, `*.vcd`, `*.vvp`, `__pycache__`, `sim_build/`): `D:\RAM_backup_20261106`
  (khoảng 709 MB, 23 676 file, gồm `.git/`). Chụp **trước** khi tạo các file khung này; khung được đồng bộ vào bản sao lưu sau đó (xem mục 4).
- `tools/safety_check.py`: kiểm tra sau mỗi phiên, có `--task Txx` để kiểm phạm vi file của commit (mục 4).
- `tools/check_notes.py`: kiểm note từng task. `tools/make_briefs.py`: sinh `briefs/` từ plan.
- `paper/`, `tailieuthamkhao/`, `external_refs/` bị `.gitignore`, nên chỉ bản sao lưu này bảo vệ chúng.
- **Chưa làm (cần bạn):** T00 (commit snapshot, nhánh `remediation/main`, tag `pre-remediation`, vô hiệu URL push); `python tools/safety_check.py --init`;
  bản sao lưu thứ hai ngoài ổ D (mục 8, lớp 3); dán danh sách chặn vào Gemini/Antigravity (mục 2).

## 2. Danh sách lệnh cấm (dán vào ô Deny list của Turbo)

Chưa xác nhận cú pháp ô nhập của công cụ; thêm từng dòng, nếu ô nhận mẫu thì dùng dạng tương ứng.

| Lệnh | Vì sao |
|---|---|
| `git push` | Không task nào cần đẩy lên remote |
| `git reset` | Xóa thay đổi chưa commit |
| `git checkout` / `git restore` | Ghi đè file đang sửa |
| `git clean` | Xóa file chưa theo dõi (`paper/`, `external_refs/`, `briefs/`, `docs/*.pdf`) |
| `git rebase`, `git commit --amend` | Viết lại lịch sử |
| `git stash drop` | Mất thay đổi cất tạm |
| `git add -A`, `git add .` | Kéo `hwsec-repos/` (843 MB), `external_refs/` (486 MB) vào commit |
| `rm -rf`, `Remove-Item -Recurse`, `del /s`, `rd /s`, `rmdir`, `format` | Xóa đệ quy / định dạng |

Lệnh git được phép: `git status`, `git diff`, `git log`, `git show`, `git ls-files`, `git add <đường dẫn cụ thể>`, `git commit -m ...` (chỉ trên `remediation/main`), `git tag rem/<Txx>`.

### Khối dán vào ô Deny list (mỗi dòng một mục)
```text
git push
git reset
git checkout
git restore
git clean
git rebase
git stash drop
git add -A
git add .
git commit --amend
git branch -D
git branch -d
git tag -d
git tag -f
git reflog
git gc
git prune
git update-ref
git remote
git config
git filter-branch
git worktree remove
rm -rf
rm -r
Remove-Item -Recurse
Remove-Item -Force
del /s
del /f
rmdir
rd /s
robocopy
xcopy
format
shutil.rmtree
os.remove
os.rmdir
pip install
pip uninstall
npm install
curl
wget
Invoke-WebRequest
Invoke-RestMethod
Set-ExecutionPolicy
reg add
reg delete
icacls
takeown
taskkill
```
Ghi chú cách dùng:
- `git remote`, `git config`, `git reflog` chặn cả lệnh đọc; không task nào cần. Người dùng tự chạy ở T00.
- `pip install` bị chặn; T60 cần cài `pyuvm`: bạn tạm gỡ dòng này, cài xong thêm lại và ghim phiên bản vào `requirements.txt`.
- `taskkill` bị chặn để Gemini không giết tiến trình mô phỏng/Vivado không phải do mình khởi chạy; treo thì dừng và báo.
- `shutil.rmtree`, `os.remove` chỉ bắt được khi nằm trong dòng lệnh (`python -c ...`); script `.py` Gemini tự viết không bị bắt, nên danh sách chặn chỉ là hàng rào phụ. Lớp chính là sao lưu, `safety_check.py` và nhánh riêng.

## 3. Khi nào bật hoặc tắt Turbo

- Bật Turbo cho task cơ học, chủ yếu sửa TB/công cụ/tài liệu, ít lệnh nguy hiểm: T01, T03, T05, T61, T62.
- Tắt Turbo (duyệt lệnh tay) cho: T00 (commit snapshot, tag), T02 (chạy full regression ~30 phút, ghi đè `regression_summary.json`), T04, T06, T10–T15,
  T20, T21, T30–T34, T40, T41, T50–T52, T60, T70.
- Lý do: các task còn lại sửa RTL trên đường tới hạn hoặc cơ chế bảo mật, nơi một sửa sai tốn thời gian đo lại; T40/T41 gọi Vivado (chạy lâu, ghi `syn/reports/build/`).
- Task bị KHÓA trong `briefs/README.md` (chờ quyết định D1–D6) không được giao, dù bật hay tắt Turbo.

## 4. Chạy sau mỗi phiên

```bash
python tools/safety_check.py --task <Txx>
```
Thoát 0 nghĩa là: file được bảo vệ (R9) y hệt bản sao lưu, `hwsec-repos/` không bị theo dõi hay đưa vào staging, không file staging nào lớn hơn 5 MB, HEAD không ở
`main`, URL push là `DISABLED`, `origin/main` không đổi, tag `pre-remediation` còn, và **mọi file trong commit của task nằm trong mục "Được sửa" của brief**
(cộng `remediation_notes/`, `reports/remediation/`, `build/review/`). Thoát 1 thì dừng, đừng mở phiên tiếp.
Sau đó: `python tools/check_notes.py <Txx>`; Claude đối chiếu gói `build/review/<Txx>/` (plan mục 7.4).

Khi chủ ý sửa file trong vùng bảo vệ (ví dụ Claude cập nhật `docs/verification_findings.md`), chạy lại đồng bộ bản sao lưu (additive, không `/MIR`):
```bash
robocopy D:\RAM D:\RAM_backup_20261106 /E /XD hwsec-repos build downloads __pycache__ sim_build /XF *.vcd *.vvp /NFL /NDL /NJH /NP
```

## 5. Khôi phục

- File bị ghi đè hoặc xóa trong `paper/`, `tailieuthamkhao/`, `external_refs/`, tài liệu, golden: chép lại từ `D:\RAM_backup_20261106\<đường dẫn>`.
- Thay đổi RTL/TB bị mất sau T00: `git log` và `git checkout pre-remediation -- <đường dẫn>` (tag do T00 tạo; chỉ người dùng chạy lệnh này).
- Thay đổi chưa commit **trước** T00 chỉ khôi phục được từ bản sao lưu ở mục 1. Vì vậy T00 phải là việc đầu tiên.

## 6. Giới hạn

- `safety_check.py` chỉ phát hiện, không ngăn chặn. Lệnh phá hoại đã chạy thì chỉ khôi phục từ sao lưu.
- Bản sao lưu chụp lúc 2026-11-06; sửa tài liệu bảo vệ sau thời điểm này (ví dụ cập nhật plan) sẽ bị báo là thay đổi file được bảo vệ cho tới khi đồng bộ lại (mục 4).
- `briefs/` không nằm trong danh sách bảo vệ vì được sinh lại bằng `tools/make_briefs.py`.
- `safety_check.py --task` suy ra phạm vi từ dòng `**Được sửa:**` của brief bằng các chuỗi trong dấu backtick; ghi chú dạng "(hoặc file định nghĩa ...)" không mở rộng phạm vi.

## 7. Kế hoạch theo kịch bản khi chạy Turbo hoặc chạy một mạch

Nguyên tắc: danh sách chặn chỉ là lớp ngoài cùng và có thể bị qua mặt; phải có lớp ngăn thật, lớp phát hiện và lớp khôi phục.

| # | Kịch bản | Hậu quả | Ngăn | Phát hiện | Khôi phục |
|---|---|---|---|---|---|
| S1 | Xóa hoặc ghi đè bằng đường vòng (`python -c shutil.rmtree`, `robocopy /mir`, `rmdir /s`, `del` từng file) | Mất `paper/`, `external_refs/`, tài liệu, golden | Chạy trong bản làm việc tách riêng (mục 8, lớp 1); danh sách chặn mở rộng | `safety_check.py` sau mỗi task | Chép từ sao lưu thứ hai (S3) |
| S2 | Phá hoại git ngoài danh sách: `git branch -D`, `git tag -d`, `git reflog expire`, `git gc --prune`, `git update-ref -d`, `git remote set-url`, `git config` | Mất tag `pre-remediation`, mất lịch sử, mở lại đường push | Thêm vào danh sách chặn; URL push đã vô hiệu | `safety_check.py` (tag, `origin/main`, URL push) | Dựng lại từ `git reflog` trong vài ngày, hoặc từ `git bundle` (S3) |
| S3 | Bản sao lưu cũng bị xóa hoặc hỏng | Không còn chỗ quay lại | Bản sao thứ hai ngoài vùng Gemini làm việc: `git bundle create` ra ổ khác hoặc đám mây, nén `paper/` và `tailieuthamkhao/` riêng, đặt chỉ đọc | `safety_check.py` báo thiếu thư mục sao lưu | Chép từ bản thứ hai |
| S4 | Commit nhầm `hwsec-repos/`, `external_refs/` hoặc file lớn | Kho git phình nghìn MB | Chặn `git add -A` và `git add .` | `safety_check.py` (staging, kích thước) | Người dùng gỡ commit cục bộ và commit lại |
| S5 | Đẩy lên remote (`github.com/.../DRAM`) | Mã chưa duyệt lên GitHub | URL push `DISABLED`; chặn `git push` | `origin/main` đổi so với mốc | Xóa nhánh trên remote bằng tay |
| S6 | Gemini làm yếu test cho qua (nới check, xóa assert, hardcode, chuyển FAIL thành XFAIL, tăng timeout) — chính là lỗi H-11 mà audit đã tìm ra | Số liệu sai nhưng xanh, vào bài báo | R1/R15, mục "Dừng nếu" của brief; check phải bắt được lỗi chèn vào | Claude: `git diff rem/Txx rem/Tyy` tìm check bị xóa, ngưỡng bị nới, XFAIL mới; chạy lại độc lập | Hoàn nguyên task rồi chạy lại |
| S7 | Hết quota hoặc lỗi giữa task | Cây làm việc có sửa dở | Dừng ngay khi cổng thất bại | `git status` không sạch trước task mới | Claude xem phần sửa dở rồi quyết định giữ hay bỏ |
| S8 | Treo, lặp vô hạn, đầy ổ đĩa (regression ~30 phút, Vivado, mô phỏng) | Tốn quota và thời gian | Mỗi TB có `--timeout` (T01); phiên có giới hạn thời gian | Thời gian từng task trong note | Dừng tay, xóa sản phẩm trung gian trong `build/` |
| S9 | Gemini tự cài gói hoặc tải mã từ mạng | Rủi ro chuỗi cung ứng, môi trường lệch | Chặn `pip install`, `curl`, `npm install` | `pip freeze` khác đường cơ sở | Gỡ gói, tạo lại môi trường |
| S10 | Đọc nội dung độc hại trong file (tiêm lệnh qua `hwsec-repos/`, `external_refs/`, `tailieuthamkhao/`) | Làm theo chỉ dẫn lạ | Brief chỉ trỏ tới file của dự án; không bảo Gemini đọc các thư mục tham khảo | Claude đọc lại log thấy lệnh lạ | Như S1 |
| S11 | Gemini tự chốt quyết định D1–D6 hoặc làm task KHÓA | Sửa kiến trúc sai hướng | Brief ghi KHÓA; mục "Dừng nếu" | Claude đối chiếu `INDEX.md` với bảng quyết định | Hoàn nguyên task |
| S12 | Ghi đè kết quả mô phỏng/bench làm mất bằng chứng (`regression_summary.json`, `sim/results/*`, `GOLDEN_OUTPUTS/*`) | Mất mốc so sánh | Chỉ T02/T03 được sửa các file này; sao lưu | `safety_check.py --task` (phạm vi file) | Chép từ sao lưu |

## 8. Các lớp phòng thủ, theo thứ tự nên làm

1. **Lớp 1, ngăn thật (mạnh nhất): chạy trong bản làm việc tách riêng.** `git worktree add D:\RAM_work remediation/main` chỉ chứa file đã theo dõi; `paper/`, `external_refs/`, `hwsec-repos/`
   bị `.gitignore` nên không có trong đó; Gemini không với tới thì không phá được. Cần sửa nhỏ `safety_check.py` để biết đường dẫn thư mục làm việc. **Chưa làm, cần bạn đồng ý.**
2. **Lớp 2, danh sách chặn mở rộng** (mục 2). Khớp theo chuỗi nên chỉ coi là hàng rào phụ.
3. **Lớp 3, sao lưu thứ hai ngoài vùng làm việc.** Sao lưu hiện nay ở `D:\RAM_backup_20261106`, cùng ổ D với dự án. Chép thêm sang ổ khác hoặc đám mây, đặt thuộc tính chỉ đọc.
4. **Lớp 4, cổng sau mỗi task.** Đã có: `safety_check.py --task`, `check_notes.py`, tag `rem/Txx`, gói review. Đề xuất thêm: runner từ chối bắt đầu task mới nếu `git status` có file đã theo dõi bị sửa dở (S7); chưa làm.
5. **Lớp 5, review một lần ở cuối mỗi làn.** Claude làm theo S6: so các tag, tìm check bị nới hoặc xóa, chạy lại kiểm tra độc lập, đối chiếu số liệu trong tài liệu với `regression_summary.json` và `timing_history.csv`.

## 9. Chưa kiểm chứng

- Chưa biết công cụ chạy Gemini ở chế độ không tương tác có hỏi duyệt từng lệnh hay áp dụng danh sách chặn hay không. Phải thử bằng T01 (hoặc một lệnh vô hại như `git clean -n`) trước khi giao task ⚠.
- `tools/safety_check.py`, `tools/check_notes.py` và `tools/make_briefs.py` mới viết, đã chạy thử trên repo hiện tại nhưng chưa dùng trong vòng sửa thật; lỗi cú pháp brief hoặc phạm vi sẽ lộ ở task đầu tiên.
- Chưa có `tools/run_briefs.py` (runner chạy hàng loạt); mỗi task được giao thủ công từng phiên.
