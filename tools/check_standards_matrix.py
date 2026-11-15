#!/usr/bin/env python3
"""Auditor kiem tra Ma tran Tieu chuan va Bang chung (docs/standards_matrix.md)

Kiem tra:
1. Moi duong dan bang chung trong bang ton tai tren dia.
2. Trang thai thuoc tap hop hop le: {'ĐẠT', 'MỘT PHẦN', 'THAM CHIẾU', 'CHƯA LÀM'}.
3. Moi dong ĐẠT / MỘT PHẦN phai co lenh tai hien (khong duoc rong hoac '-').
4. Co du cac tieu chuan toi thieu theo brief T63:
   - IEEE Std 1619-2018 / NIST SP 800-38E
   - NIST FIPS 197
   - NIST SP 800-38D
   - JEDEC JESD79-5
   - Arm AMBA AXI4 IHI 0022
   - IEEE Std 1800 & 1800.2
   - NIST CAVP/ACVP
   - FIPS 140-3
   - Common Criteria
   - ISO/IEC 17825
5. Ho tro --self-test kiem chung test am (ma tran hong thi thoat 1).
"""

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALID_STATUSES = {"ĐẠT", "MỘT PHẦN", "THAM CHIẾU", "CHƯA LÀM"}

REQUIRED_STANDARDS = [
    ("IEEE 1619", re.compile(r"1619", re.I)),
    ("NIST FIPS 197", re.compile(r"197", re.I)),
    ("NIST SP 800-38D", re.compile(r"800-38D", re.I)),
    ("JEDEC JESD79-5", re.compile(r"JESD79-5", re.I)),
    ("Arm AMBA AXI4", re.compile(r"AXI4|IHI\s*0022", re.I)),
    ("IEEE 1800", re.compile(r"1800", re.I)),
    ("NIST CAVP/ACVP", re.compile(r"CAVP|ACVP", re.I)),
    ("FIPS 140-3", re.compile(r"140-3", re.I)),
    ("Common Criteria", re.compile(r"Common Criteria|15408", re.I)),
    ("ISO/IEC 17825", re.compile(r"17825", re.I)),
]


def clean_text(s: str) -> str:
    return re.sub(r"[*_`]", "", s).strip()


def parse_matrix(content: str, root_dir: Path = ROOT):
    errors = []
    warnings = []
    rows = []

    lines = content.splitlines()
    table_lines = [l for l in lines if l.strip().startswith("|")]

    if len(table_lines) < 3:
        errors.append("Khong tim thay bang hop le trong file ma tran")
        return errors, warnings, rows

    headers = [clean_text(c) for c in table_lines[0].split("|")[1:-1]]
    col_map = {}
    for idx, h in enumerate(headers):
        if "Tiêu chuẩn" in h:
            col_map["std"] = idx
        elif "Điều khoản" in h:
            col_map["clause"] = idx
        elif "kiểm" in h:
            col_map["item"] = idx
        elif "bằng chứng" in h:
            col_map["evidence"] = idx
        elif "Lệnh tái hiện" in h:
            col_map["cmd"] = idx
        elif "Trạng thái" in h:
            col_map["status"] = idx
        elif "Ghi chú" in h:
            col_map["notes"] = idx

    for req_col in ["std", "evidence", "status", "cmd"]:
        if req_col not in col_map:
            errors.append(f"Thieu cot bat buoc trong bang: {req_col}")
            return errors, warnings, rows

    for line_idx, line in enumerate(table_lines[2:], start=3):
        cols = [c.strip() for c in line.split("|")[1:-1]]
        if len(cols) < len(headers):
            continue

        std_name = cols[col_map["std"]]
        raw_status = cols[col_map["status"]]
        status = clean_text(raw_status).upper()
        evidence_text = cols[col_map["evidence"]]
        cmd_text = cols[col_map["cmd"]]
        clean_cmd = clean_text(cmd_text)

        row_info = {
            "line": line_idx,
            "std": std_name,
            "status": status,
            "evidence": evidence_text,
            "cmd": clean_cmd,
        }
        rows.append(row_info)

        if status not in VALID_STATUSES:
            errors.append(f"Dong {line_idx} ({std_name}): Trang thai khong hop le '{status}'. Hop le: {VALID_STATUSES}")

        if status in {"ĐẠT", "MỘT PHẦN"}:
            if not clean_cmd or clean_cmd in {"-", "N/A", "NONE"}:
                errors.append(f"Dong {line_idx} ({std_name}): Trang thai '{status}' bat buoc co lenh tai hien")

        # Parse and check file paths in evidence
        paths = re.findall(r"`([^`]+)`", evidence_text)
        if not paths:
            paths = [clean_text(p) for p in re.split(r"[,;\s]+", evidence_text) if "/" in p or "\\" in p or p.endswith((".txt", ".sv", ".py", ".md", ".sby"))]

        if status == "ĐẠT" and not paths:
            errors.append(f"Dong {line_idx} ({std_name}): Trang thai ĐẠT phai co it nhat mot file bang chung")

        for p_str in paths:
            p_clean = p_str.strip().replace("/", os.sep).replace("\\", os.sep)
            if not p_clean or p_clean in {"-", "N/A"}:
                continue
            full_path = root_dir / p_clean
            if not full_path.exists():
                errors.append(f"Dong {line_idx} ({std_name}): File bang chung khong ton tai tren dia: '{p_str}'")

    # Check minimum required standards coverage
    for std_label, std_regex in REQUIRED_STANDARDS:
        matched = any(std_regex.search(r["std"]) for r in rows)
        if not matched:
            errors.append(f"Thieu tieu chuan bat buoc trong ma tran: {std_label}")

    return errors, warnings, rows


def run_self_test():
    print("=== DANG CHAY SELF-TEST KIEM CHUNG TEST AM (NEGATIVE TESTS) ===")
    
    # Test 1: Invalid status must fail
    bad_status_md = """
| Tiêu chuẩn | Điều khoản | Điều Q-Shield kiểm | File bằng chứng | Lệnh tái hiện | Trạng thái | Ghi chú |
|---|---|---|---|---|---|---|
| IEEE Std 1619 | §5 | XTS | `LIMITATIONS.md` | `python test.py` | **HOAN_HAO** | Note |
"""
    errs, _, _ = parse_matrix(bad_status_md)
    assert any("Trang thai khong hop le" in e for e in errs), "Test 1 failed: did not catch invalid status"
    print("  [PASS] Test 1: Bat thanh cong trang thai khong hop le")

    # Test 2: Missing evidence file must fail
    bad_file_md = """
| Tiêu chuẩn | Điều khoản | Điều Q-Shield kiểm | File bằng chứng | Lệnh tái hiện | Trạng thái | Ghi chú |
|---|---|---|---|---|---|---|
| IEEE Std 1619 | §5 | XTS | `docs/non_existent_file_xyz.sv` | `python test.py` | **ĐẠT** | Note |
"""
    errs, _, _ = parse_matrix(bad_file_md)
    assert any("khong ton tai tren dia" in e for e in errs), "Test 2 failed: did not catch missing evidence file"
    print("  [PASS] Test 2: Bat thanh cong file bang chung khong ton tai")

    # Test 3: Missing reproduction command for ĐẠT must fail
    bad_cmd_md = """
| Tiêu chuẩn | Điều khoản | Điều Q-Shield kiểm | File bằng chứng | Lệnh tái hiện | Trạng thái | Ghi chú |
|---|---|---|---|---|---|---|
| IEEE Std 1619 | §5 | XTS | `LIMITATIONS.md` | - | **ĐẠT** | Note |
"""
    errs, _, _ = parse_matrix(bad_cmd_md)
    assert any("bat buoc co lenh tai hien" in e for e in errs), "Test 3 failed: did not catch missing command for ĐẠT"
    print("  [PASS] Test 3: Bat thanh cong thieu lenh tai hien cho ĐẠT")

    # Test 4: Missing required standard must fail
    bad_req_md = """
| Tiêu chuẩn | Điều khoản | Điều Q-Shield kiểm | File bằng chứng | Lệnh tái hiện | Trạng thái | Ghi chú |
|---|---|---|---|---|---|---|
| Random Std | §1 | Item | `LIMITATIONS.md` | `python test.py` | **ĐẠT** | Note |
"""
    errs, _, _ = parse_matrix(bad_req_md)
    assert any("Thieu tieu chuan bat buoc" in e for e in errs), "Test 4 failed: did not catch missing required standard"
    print("  [PASS] Test 4: Bat thanh cong thieu tieu chuan bat buoc")

    print(">>> TAT CA TEST AM CUA AUDITOR CHECK_STANDARDS_MATRIX DEU DAT (EXIT 0)")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Check Q-Shield Standards Compliance Matrix")
    parser.add_argument("file", nargs="?", default="docs/standards_matrix.md", help="Path to standards_matrix.md")
    parser.add_argument("--self-test", action="store_true", help="Chay bo kiem tra am de chung minh cong cu bat dung loi")
    args = parser.parse_args()

    if args.self_test:
        sys.exit(run_self_test())

    matrix_file = ROOT / args.file
    if not matrix_file.exists():
        print(f"[FAIL] File ma tran khong ton tai: {matrix_file}", file=sys.stderr)
        sys.exit(1)

    content = matrix_file.read_text(encoding="utf-8", errors="replace")
    errors, warnings, rows = parse_matrix(content, ROOT)

    print("=" * 88)
    print(f"  Q-SHIELD STANDARDS MATRIX AUDITOR: {matrix_file.relative_to(ROOT)}")
    print("=" * 88)
    print(f"Tong so dong tieu chuan phan tich : {len(rows)}")

    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    for st, count in sorted(counts.items()):
        print(f"  - Trạng thái {st:<12}: {count}")

    if warnings:
        print("\n[CANH BAO]:")
        for w in warnings:
            print(f"  [WARN] {w}")

    if errors:
        print(f"\n[LOI PHAT HIEN ({len(errors)})]:")
        for e in errors:
            print(f"  [FAIL] {e}")
        print("\n>>> KET QUA: MA TRAN TIEU CHUAN CO LOI (EXIT 1)")
        sys.exit(1)

    print("\n>>> KET QUA: MA TRAN TIEU CHUAN HOP LE VA DAT TAT CA RANG BUOC (EXIT 0)")
    sys.exit(0)


if __name__ == "__main__":
    main()
