#!/usr/bin/env python3
"""Kiem tra file note cua task sua loi: remediation_notes/<Txx>.md theo mau o GEMINI_EXECUTION_PLAN.md muc 7.1.

Thoat 1 neu:
  - note thieu hoac thieu muc bat buoc;
  - note ghi 'trang thai: DUNG' (task dung giua chung khong duoc qua cong);
  - finding trong brief khong co trong bang '## Finding';
  - file doi tu base_commit khong duoc nhac trong note;
  - duong dan/so dong trong '## Cho da sua' khong ton tai.

Dung:  python tools/check_notes.py <Txx> | --all
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_HEADERS = [
    "## Finding",
    "## Chỗ đã sửa",
    "## Test đã đổi hoặc xóa",
    "## Kết quả kiểm chứng",
    "## Timing",
    "## Bất biến tính mới",
    "## Corner case",
    "## Ngoài phạm vi \"Được sửa\"",
    "## Reviewer nên soi kỹ",
    "## Chưa làm / nợ lại",
]
WATCHED_PREFIX = ("rtl/", "tb/", "formal/", "syn/", "tools/", "sim/", "docs/")
IGNORED_PREFIX = ("remediation_notes/", "reports/remediation/", "build/", "hwsec-repos/")


def run_git(cmd):
    r = subprocess.run(["git"] + cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip()


def check_task(tid):
    print(f"Kiem note cho {tid}...")
    errors = []
    note_path = ROOT / "remediation_notes" / f"{tid}.md"
    if not note_path.exists():
        return [f"khong thay note: {note_path}"]
    content = note_path.read_text(encoding="utf-8", errors="replace")

    if not re.search(rf"^#\s+{tid}[:\s]", content, re.MULTILINE):
        errors.append(f"thieu tieu de '# {tid}: ...'")
    for key in ("- base_commit:", "- trạng thái:", "- quyết định đã dùng:"):
        if key not in content:
            errors.append(f"thieu dong '{key}'")
    if re.search(r"-\s+trạng thái:\s*DỪNG", content):
        errors.append("note ghi 'trạng thái: DỪNG': task chua xong, khong duoc qua cong (xem REVIEW_LOG R-03)")

    for h in REQUIRED_HEADERS:
        name = h.split("(")[0].strip()
        if not re.search(rf"^{re.escape(name)}.*$", content, re.MULTILINE):
            errors.append(f"thieu muc bat buoc '{h}'")

    brief_path = ROOT / "briefs" / f"{tid}.md"
    if brief_path.exists():
        brief = brief_path.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"-\s+\*\*Finding:\*\*\s*(.+)", brief)
        if m:
            sec = re.search(r"## Finding(.*?)(\n## |\Z)", content, re.DOTALL)
            sec_text = sec.group(1) if sec else ""
            for fid in re.findall(r"\b[CHML]-\d+\b", m.group(1)):
                if fid not in sec_text:
                    errors.append(f"finding '{fid}' cua brief {tid} khong co trong bang '## Finding'")

    bc = re.search(r"-\s+base_commit:\s*([0-9a-fA-F]{7,40})", content)
    base = bc.group(1) if bc else None
    if bc is None and "- base_commit:" in content:
        errors.append("base_commit khong phai hash git")
    if base and tid != "T00":
        log_out = run_git(["log", f"{base}..HEAD", "--format=%H %s"])
        task_commit = next((l.split()[0] for l in log_out.splitlines() if f"({tid})" in l), None)
        if task_commit:
            changed = run_git(["show", "--name-only", "--format=", task_commit]).splitlines()
        else:
            status = run_git(["status", "--porcelain"]).splitlines()
            untracked = [l[3:].strip() for l in status if l.startswith("?? ") and l[3:].strip().startswith(WATCHED_PREFIX)]
            changed = list(set(run_git(["diff", "--name-only", base]).splitlines()
                               + run_git(["diff", "--cached", "--name-only", base]).splitlines() + untracked))
        for f in changed:
            f = f.strip()
            if not f or f.startswith(IGNORED_PREFIX) or f.endswith(".log"):
                continue
            if f not in content and Path(f).name not in content:
                errors.append(f"file doi tu {base[:8]} khong duoc nhac trong note: {f}")

    cs = re.search(r"## Chỗ đã sửa(.*?)(\n## |\Z)", content, re.DOTALL)
    if cs:
        for line in cs.group(1).splitlines():
            line = line.strip()
            if not line.startswith("|") or "File" in line or "---" in line:
                continue
            cols = [c.strip() for c in line.split("|")[1:-1]]
            if not cols or not cols[0] or cols[0].startswith("(") or "không có" in cols[0].lower():
                continue
            parts = cols[0].split(":")
            p = ROOT / parts[0].strip()
            if not p.exists():
                errors.append(f"duong dan trong 'Chỗ đã sửa' khong ton tai: {parts[0]}")
            elif len(parts) > 1 and parts[1].strip().isdigit():
                n = len(p.read_text(encoding="utf-8", errors="replace").splitlines())
                if not 1 <= int(parts[1]) <= n + 5:
                    errors.append(f"so dong {parts[1]} ngoai pham vi {parts[0]} ({n} dong)")
    return errors


def main():
    if len(sys.argv) < 2:
        print("Dung: python tools/check_notes.py <Txx> | --all")
        sys.exit(1)
    if sys.argv[1] == "--all":
        idx = ROOT / "remediation_notes" / "INDEX.md"
        if not idx.exists():
            print("khong thay remediation_notes/INDEX.md")
            sys.exit(1)
        failed = {}
        for line in idx.read_text(encoding="utf-8").splitlines():
            cols = [c.strip() for c in line.split("|")[1:-1]] if line.startswith("|") else []
            if cols and re.match(r"^T\d{2}$", cols[0]):
                errs = check_task(cols[0])
                if errs:
                    failed[cols[0]] = errs
        if failed:
            print("\n[FAIL] check_notes --all:")
            for t, errs in failed.items():
                print(f"Task {t}:")
                for e in errs:
                    print("  -", e)
            sys.exit(1)
        print("\n[PASS] moi task trong INDEX.md qua check_notes")
        return
    errs = check_task(sys.argv[1])
    if errs:
        print(f"\n[FAIL] check_notes {sys.argv[1]}:")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    print(f"\n[PASS] check_notes {sys.argv[1]}")


if __name__ == "__main__":
    main()
