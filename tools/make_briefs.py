#!/usr/bin/env python3
"""Sinh briefs/<Txx>.md va briefs/README.md tu GEMINI_EXECUTION_PLAN.md va docs/verification_findings.md.

Moi brief tu chua du: quy tac (muc 2 cua plan), quyet dinh lien quan (muc 3), noi dung task, va toan van
dong finding. Phien Gemini chi can keo MOT file brief vao chat. Chay lai khi plan hoac findings doi.

Dung:  python tools/make_briefs.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = (ROOT / "GEMINI_EXECUTION_PLAN.md").read_text(encoding="utf-8")
FIND = (ROOT / "docs" / "verification_findings.md").read_text(encoding="utf-8")
OUT = ROOT / "briefs"

# Thu tu chay: khong trung so thu tu task vi co task phu thuoc task so lon hon.
ORDER = ["T00", "T01", "T02", "T03", "T04", "T05", "T06", "T10", "T11", "T12", "T13", "T14", "T15", "T20", "T21",
         "T40", "T30", "T31", "T32", "T33", "T34", "T41", "T50", "T52", "T60", "T61", "T62", "T51", "T70"]


def section(text, start_pat, end_pat):
    m = re.search(start_pat, text, re.M)
    if not m:
        return ""
    rest = text[m.start():]
    e = re.search(end_pat, rest[len(m.group(0)):], re.M)
    return rest[: len(m.group(0)) + e.start()] if e else rest


rules = section(PLAN, r"^## 2\. QUY TẮC BẮT BUỘC", r"^## 3\.")
decisions = section(PLAN, r"^## 3\. QUYẾT ĐỊNH", r"^## 4\.")
overview = section(PLAN, r"^## 4\. TỔNG QUAN TASK", r"^## 5\.")
note_tpl = section(PLAN, r"^### 7\.1\. Mẫu", r"^### 7\.2\.")
review_pack = section(PLAN, r"^### 7\.4\. Gói review", r"^---")

tasks = {}
for m in re.finditer(r"^#### (T\d{2})\. (.+?)\n(.*?)(?=^#### |^### |^## |\Z)", PLAN, re.M | re.S):
    tasks[m.group(1)] = (m.group(2).strip(), m.group(3).rstrip().rstrip("-").rstrip())

rows = {}
for line in overview.splitlines():
    cols = [c.strip() for c in line.split("|")[1:-1]] if line.startswith("|") else []
    if len(cols) >= 5 and re.match(r"^T\d{2}$", cols[0]):
        rows[cols[0]] = cols

dec_status = {}
dec_rows = {}
for line in decisions.splitlines():
    cols = [c.strip() for c in line.split("|")[1:-1]] if line.startswith("|") else []
    if len(cols) >= 5 and re.match(r"^D\d+$", cols[0]):
        dec_status[cols[0]] = cols[4]
        dec_rows[cols[0]] = line

# Tim dong finding va header bang gan nhat.
find_rows = {}
header = ""
for line in FIND.splitlines():
    if line.startswith("| ID |"):
        header = line
    m = re.match(r"^\| ([CHML]-\d+(?:, [CHML]-\d+)*) \|", line)
    if m:
        for fid in m.group(1).split(", "):
            find_rows.setdefault(fid, []).append((header, line))


def decisions_of(tid):
    return sorted(set(re.findall(r"D\d+", rows[tid][3]))) if tid in rows else []


def locked(tid):
    return [d for d in decisions_of(tid) if "Chưa chốt" in dec_status.get(d, "") or "Chờ duyệt" in dec_status.get(d, "")]


def build(tid):
    title, body = tasks[tid]
    fm = re.search(r"-\s+\*\*Finding:\*\*\s*(.+)", body)
    fids = re.findall(r"\b[CHML]-\d+\b", fm.group(1)) if fm else []
    deps = rows[tid][2] if tid in rows else "—"
    parts = [
        f"# Brief {tid}: {title}\n",
        "Bạn là model code thực thi một task sửa lỗi trong dự án Q-Shield (D:\\RAM, bộ điều khiển bộ nhớ DDR5 bảo mật).\n"
        "Chỉ làm task này, không tự chuyển sang task khác. Đọc hết file này; không cần đọc GEMINI_EXECUTION_PLAN.md hay\n"
        "docs/verification_findings.md (mọi thứ cần thiết đã nằm ở đây). Tìm vị trí theo tên tín hiệu, không theo số dòng.\n"
        f"Chạy mọi lệnh ở \"Xong khi\" và lưu output thật vào reports/remediation/{tid}.log. Khi xong: tạo gói review\n"
        f"build/review/{tid}/ (mục 6 bên dưới), viết remediation_notes/{tid}.md theo mẫu, cập nhật remediation_notes/INDEX.md,\n"
        f"chạy python tools/check_notes.py {tid}, commit đúng quy tắc R8 (chỉ nhánh remediation/main), tạo tag rem/{tid},\n"
        f"chạy python tools/safety_check.py --task {tid} (phải thoát 0), rồi báo cáo: file đã sửa, output từng tiêu chí,\n"
        "việc chưa làm được. Tuyệt đối không chạy: git push, git reset, git checkout, git restore, git clean, git rebase,\n"
        "git commit --amend, git add -A, git add ., rm -rf, Remove-Item -Recurse, robocopy, rmdir (xem GEMINI_SAFETY.md).\n",
        f"Phụ thuộc: {deps}. Chỉ làm khi các task này đã xong.\n",
    ]
    lk = locked(tid)
    if lk:
        parts.append("**KHÓA:** task này phụ thuộc quyết định chưa chốt: " + ", ".join(lk) +
                     ". Nếu mục 3 bên dưới vẫn ghi \"Chưa chốt\"/\"Chờ duyệt\" cho các quyết định đó thì DỪNG NGAY và báo người dùng.\n")
    parts.append("## 1. Nội dung task\n\n#### " + tid + ". " + title + "\n" + body + "\n")

    parts.append("## 2. Finding cần sửa (toàn văn từ docs/verification_findings.md)\n")
    if not fids:
        parts.append("Task này không gắn finding riêng.\n")
    for fid in fids:
        for hdr, ln in find_rows.get(fid, []):
            parts.append(f"### [{fid}]\n{hdr}\n{ln}\n")
    parts.append("Mức tin cậy: `[X]` đã xác nhận, `[A]` agent có bằng chứng chưa tái kiểm, `[R]` suy ra từ đọc mã. "
                 "Finding `[A]`/`[R]` phải được tái hiện (fail trước) trước khi sửa; không tái hiện được thì dừng và báo.\n")

    ds = decisions_of(tid)
    parts.append("## 3. Quyết định liên quan (Gemini không tự đổi, không tự chốt)\n")
    if ds:
        parts.append("| # | Câu hỏi | Đề xuất của Claude | Chặn task | Chốt |\n|---|---|---|---|---|")
        parts.extend(dec_rows[d] for d in ds if d in dec_rows)
        parts.append("")
    else:
        parts.append("Không có.\n")

    parts.append("## 4. Bốn mục tiêu của cả dự án\n\nG1 kết quả kiểm thử trung thực; G2 đường dữ liệu thật; G3 mọi Critical/High có check "
                 "tái hiện và môi trường UVM-style; G4 tuyên bố = bằng chứng. Chi tiết ở GEMINI_EXECUTION_PLAN.md.\n")
    parts.append("## 5. Quy tắc bắt buộc, môi trường và sự thật đã kiểm chứng\n\n" + rules.strip() + "\n")
    parts.append("## 6. Mẫu note và gói review\n\n" + note_tpl.strip() + "\n\n" + review_pack.strip() + "\n")
    return "\n".join(parts)


def main():
    OUT.mkdir(exist_ok=True)
    missing = [t for t in ORDER if t not in tasks]
    extra = [t for t in tasks if t not in ORDER]
    if missing or extra:
        raise SystemExit(f"ORDER lech voi plan: thieu {missing}, thua {extra}")
    for tid in ORDER:
        (OUT / f"{tid}.md").write_text(build(tid), encoding="utf-8")
    lines = [
        "# Danh sách brief theo task\n",
        "## Cách dùng (đọc trước khi giao việc)\n",
        "- Mỗi phiên chỉ kéo MỘT file brief vào chat, không kéo nhiều file, không kéo cả thư mục",
        "- Trước phiên Gemini đầu tiên: làm T00 (người dùng tự chạy) và `python tools/safety_check.py --init`",
        "- Làm tuần tự theo \"Thứ tự chạy\"; chỉ mở task kế tiếp khi task trước xong và `python tools/safety_check.py --task <Txx>` thoát 0",
        "- Task ở trạng thái KHÓA phụ thuộc quyết định chưa chốt (GEMINI_EXECUTION_PLAN.md mục 3): không giao cho tới khi người dùng chốt",
        "- Mỗi task một commit trên nhánh `remediation/main`; cuối mỗi làn dừng để Claude review",
        "- Mức suy luận gợi ý: High cho task ⚠, Medium cho phần còn lại; task ⚠ nên để Claude xem kế hoạch trước khi chạy",
        "- Sinh lại brief khi plan đổi: `python tools/make_briefs.py`\n",
        "## Thứ tự chạy\n",
        " → ".join(ORDER) + "\n",
        "## Bảng task\n",
        "| Task | Tên | Phụ thuộc | Quyết định | Mức gợi ý | Trạng thái | Cỡ brief |",
        "|---|---|---|---|---|---|---|",
    ]
    for tid in ORDER:
        r = rows.get(tid, [tid, tasks[tid][0], "—", "—"])
        size = (OUT / f"{tid}.md").stat().st_size // 1024
        lk = locked(tid)
        status = "KHÓA (" + ", ".join(lk) + ")" if lk else "Sẵn sàng"
        level = "High" if "⚠" in tasks[tid][0] else "Medium"
        lines.append(f"| [{tid}]({tid}.md) | {tasks[tid][0]} | {r[2]} | {r[3]} | {level} | {status} | {size} KB |")
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"da sinh {len(ORDER)} brief + README.md trong {OUT}")


if __name__ == "__main__":
    main()
