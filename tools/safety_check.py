#!/usr/bin/env python3
"""Kiem tra an toan sau moi phien Gemini chay tu dong (turbo).

Thoat 1 neu mot trong cac dieu kien sau vi pham:
  1. Duong dan duoc bao ve (R9) khac ban sao luu chup truoc khi sua.
  2. hwsec-repos/ bi theo doi hoac nam trong staging; file trong staging lon hon 5 MB.
  3. HEAD dang o main/master khi nhanh remediation/main da ton tai.
  4. origin/main da di chuyen so voi moc ghi bang --init (co push hoac fetch).
  5. Thieu tag pre-remediation khi nhanh remediation/main da ton tai.
  6. URL push cua origin chua bi vo hieu (DISABLED) khi nhanh remediation/main da ton tai.
  7. Voi --task Txx: moi file trong commit cua task nam trong muc "Duoc sua" cua brief.

Dung:  python tools/safety_check.py [--backup D:/RAM_backup_20261106] [--init] [--task T10]
"""
import argparse
import fnmatch
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTECTED = [
    "paper", "tailieuthamkhao", "external_refs", ".claude", ".github", "AGENTS.md", "CLAUDE.md", "GEMINI.md",
    "GEMINI_EXECUTION_PLAN.md", "GEMINI_SAFETY.md", "LICENSE",
    "docs/spec_v1.md", "docs/spec_v2.md", "docs/review_and_testplan.md", "docs/verification_plan.md",
    "docs/verification_findings.md", "docs/spec_crypto_integration.md",
]
SKIP_DIRS = {"__pycache__", "sim_build"}
SKIP_SUFFIX = {".aux", ".log", ".out", ".toc", ".blg", ".pyc"}
# Duong dan Gemini luon duoc phep ghi them ngoai muc "Duoc sua" cua task.
ALWAYS_ALLOWED = ("remediation_notes/", "reports/remediation/", "build/review/")


def git(*a):
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout.strip()


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def files(base):
    if base.is_file():
        yield base
        return
    for p in base.rglob("*"):
        if p.is_file() and not (set(p.parts) & SKIP_DIRS) and p.suffix not in SKIP_SUFFIX:
            yield p


def allowed_patterns(tid):
    brief = ROOT / "briefs" / f"{tid}.md"
    text = brief.read_text(encoding="utf-8", errors="replace") if brief.exists() else ""
    m = re.search(r"-\s+\*\*Được sửa:\*\*(.+)", text)
    if not m:
        return None
    line = m.group(1)
    return [s.strip() for s in re.findall(r"`([^`]+)`", line) if "/" in s or "." in s]


def check_task_scope(tid, bad):
    if tid == "T00":
        return
    pats = allowed_patterns(tid)
    if pats is None:
        bad.append(f"[scope] khong tim thay muc 'Duoc sua' trong briefs/{tid}.md")
        return
    log = git("log", "--format=%H %s", "remediation/main")
    commit = None
    for line in log.splitlines():
        if f"({tid})" in line.split(" ", 1)[-1]:
            commit = line.split()[0]
            break
    if not commit:
        print(f"[scope] chua co commit cho {tid}; bo qua kiem pham vi")
        return
    changed = git("show", "--name-only", "--format=", commit).splitlines()
    for f in changed:
        f = f.strip().replace("\\", "/")
        if not f or f.startswith(ALWAYS_ALLOWED):
            continue
        if not any(fnmatch.fnmatch(f, p) or f == p.rstrip("/") or f.startswith(p.rstrip("*").rstrip("/") + "/")
                   for p in pats):
            bad.append(f"[scope] {tid} sua file ngoai 'Duoc sua': {f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backup", default="D:/RAM_backup_20261106")
    ap.add_argument("--init", action="store_true", help="ghi moc ban dau (chay mot lan truoc khi sua)")
    ap.add_argument("--task", help="kiem them pham vi file cua task, vi du T10")
    args = ap.parse_args()
    backup = Path(args.backup)
    bad = []

    if backup.exists():
        for name in PROTECTED:
            src = ROOT / name
            if not src.exists():
                continue
            for p in files(src):
                rel = p.relative_to(ROOT)
                q = backup / rel
                if not q.exists():
                    bad.append(f"[R9] file moi trong vung bao ve: {rel}")
                elif sha(p) != sha(q):
                    bad.append(f"[R9] file bao ve da bi doi: {rel}")
    else:
        bad.append(f"khong thay thu muc sao luu: {backup}")

    if git("ls-files", "hwsec-repos"):
        bad.append("[git] hwsec-repos dang duoc theo doi")
    staged = git("diff", "--cached", "--name-only")
    if any(l.startswith("hwsec-repos") for l in staged.splitlines()):
        bad.append("[git] hwsec-repos nam trong staging")
    for line in staged.splitlines():
        f = ROOT / line
        if f.exists() and f.stat().st_size > 5 * 1024 * 1024:
            bad.append(f"[git] file staging lon hon 5 MB: {line}")

    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    has_rem = bool(git("branch", "--list", "remediation/main"))
    if has_rem and branch in ("main", "master"):
        bad.append(f"[git] HEAD dang o {branch}; cong viec sua phai o remediation/main")
    if has_rem and not git("tag", "--list", "pre-remediation"):
        bad.append("[git] thieu tag pre-remediation")
    if has_rem and git("remote", "get-url", "--push", "origin") != "DISABLED":
        bad.append("[git] URL push cua origin chua la DISABLED")

    base_file = backup / ".safety_baseline.json"
    now = git("rev-parse", "origin/main")
    if args.init:
        base_file.write_text(json.dumps({"origin_main": now, "head": git("rev-parse", "HEAD")}), encoding="utf-8")
        print("da ghi moc:", base_file)
    elif base_file.exists():
        if json.loads(base_file.read_text(encoding="utf-8"))["origin_main"] != now:
            bad.append("[git] origin/main da di chuyen: co push hoac fetch")
    else:
        bad.append("thieu moc: chay mot lan voi --init truoc khi bat dau sua")

    if args.task:
        check_task_scope(args.task, bad)

    if bad:
        print("SAFETY CHECK FAILED")
        for b in bad:
            print(" -", b)
        sys.exit(1)
    print("safety check passed:", len(PROTECTED), "duong dan bao ve nguyen ven, trang thai git on")


if __name__ == "__main__":
    main()
