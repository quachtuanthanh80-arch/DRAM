#!/usr/bin/env python3
# File: tools/check_cocotb_triage.py
# Chức năng: Phân tích log chạy cocotb (run_all_tests.py), phân loại PASS/FAIL theo stage và chặn mọi FAIL chưa giải trình.

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOG = ROOT / "reports" / "remediation" / "T45.log"

# Danh sách các stage FAIL đã biết kèm lý do môi trường/giới hạn được duyệt
KNOWN_FAILURES: dict[str, str] = {
    "PyUVM Constrained-Random & Corner Verification (MC + CSR)": (
        "MÔI TRƯỜNG: WSL Ubuntu thiếu gói pyuvm (GEMINI_SAFETY.md cấm pip install); "
        "đã kiểm chứng PASS 23/23 bins trên Windows Python 3.13 + Icarus tại T60 (rem/T60)."
    ),
}

ROW_RE = re.compile(
    r"^(?P<name>.+?)\s+\|\s+(?P<stage>[A-Za-z]+)\s+\|\s+(?P<status>PASS|FAIL|ERROR|SKIPPED)\s+\|\s+(?P<dur>\d+(?:\.\d+)?)s\s*$"
)


def parse_summary_tables(log_text: str) -> list[list[dict[str, str]]]:
    """Trích xuất tất cả bảng tổng kết COCOTB HARDWARE REGRESSION SUMMARY REPORT từ log."""
    tables: list[list[dict[str, str]]] = []
    in_table = False
    seen_header_sep = False
    current: list[dict[str, str]] = []

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        if "COCOTB HARDWARE REGRESSION SUMMARY REPORT" in line:
            in_table = True
            seen_header_sep = False
            current = []
            continue
        if not in_table:
            continue
        if line.startswith("-" * 20):
            seen_header_sep = True
            continue
        if line.startswith("=" * 20):
            if seen_header_sep and current:
                tables.append(current)
                in_table = False
                seen_header_sep = False
                current = []
            continue
        if seen_header_sep:
            m = ROW_RE.match(line)
            if m:
                current.append(
                    {
                        "name": m.group("name").strip(),
                        "stage": m.group("stage").strip(),
                        "status": m.group("status").strip(),
                        "duration": m.group("dur").strip(),
                    }
                )
    if seen_header_sep and current:
        tables.append(current)
    return tables


def triage_log_text(
    log_text: str, known_failures: dict[str, str] | None = None
) -> tuple[int, list[dict[str, str]], list[dict[str, str]], list[list[dict[str, str]]]]:
    """Phân loại bảng tổng kết cuối cùng; trả về (exit_code, rows_with_class, unexpected_fails, all_tables)."""
    known = KNOWN_FAILURES if known_failures is None else known_failures
    tables = parse_summary_tables(log_text)
    if not tables:
        return 1, [], [], []

    latest = tables[-1]
    classified: list[dict[str, str]] = []
    unexpected: list[dict[str, str]] = []

    for row in latest:
        name = row["name"]
        status = row["status"]
        if status == "PASS":
            triage = "PASS"
            reason = f"{row['duration']}s"
        elif name in known:
            triage = "KNOWN_ENV_FAIL"
            reason = known[name]
        else:
            triage = "UNEXPECTED_FAIL"
            reason = "Chưa có trong danh sách lỗi đã biết"
            unexpected.append(row)
        classified.append({**row, "triage": triage, "reason": reason})

    exit_code = 0 if not unexpected else 1
    return exit_code, classified, unexpected, tables


def run_negative_self_test() -> bool:
    """Kiểm thử âm: phải thoát 1 khi gặp FAIL lạ hoặc log không có bảng tổng kết."""
    fake_fail_log = """
================================================================================================
  COCOTB HARDWARE REGRESSION SUMMARY REPORT
================================================================================================
Test Description                                       | Stage       | Status  | Duration
------------------------------------------------------------------------------------------------
Frontend Stage (AXI4 Slave & Skid Buffer)              | Functional  | PASS    |   2.10s
Galois LFSR Bus Scrambler                              | Functional  | FAIL    |   1.50s
PyUVM Constrained-Random & Corner Verification (MC + CSR) | UVM         | FAIL    |   0.50s
================================================================================================
"""
    rc1, _, unexp1, _ = triage_log_text(fake_fail_log)
    if rc1 != 1 or len(unexp1) != 1 or unexp1[0]["name"] != "Galois LFSR Bus Scrambler":
        print("[NEGATIVE_TEST FAIL] Không bắt được stage FAIL ngoài danh sách đã biết!")
        return False

    rc2, _, _, _ = triage_log_text("log rong khong co bang tong ket")
    if rc2 != 1:
        print("[NEGATIVE_TEST FAIL] Không trả về mã lỗi 1 khi thiếu bảng tổng kết!")
        return False

    print(
        "[NEGATIVE_TEST PASS] Bắt đúng UNEXPECTED_FAIL (rc=1 cho 'Galois LFSR Bus Scrambler') "
        "và log thiếu bảng tổng kết (rc=1)."
    )
    return True


def print_triage_report(
    classified: list[dict[str, str]],
    unexpected: list[dict[str, str]],
    tables: list[list[dict[str, str]]],
) -> None:
    if len(tables) >= 2:
        first_pass = sum(1 for r in tables[0] if r["status"] == "PASS")
        last_pass = sum(1 for r in tables[-1] if r["status"] == "PASS")
        print(
            f"[TREND] So sánh log: BEFORE={first_pass}/{len(tables[0])} PASS -> "
            f"AFTER={last_pass}/{len(tables[-1])} PASS"
        )

    print("=" * 116)
    print(f"{'#':<3} | {'Stage':<12} | {'Status':<6} | {'Triage':<15} | {'Stage Name':<58} | {'Ghi chú'}")
    print("-" * 116)
    for idx, row in enumerate(classified, 1):
        print(
            f"{idx:02d}  | {row['stage']:<12} | {row['status']:<6} | {row['triage']:<15} | "
            f"{row['name'][:58]:<58} | {row['reason']}"
        )
    print("=" * 116)
    n_pass = sum(1 for r in classified if r["triage"] == "PASS")
    n_known = sum(1 for r in classified if r["triage"] == "KNOWN_ENV_FAIL")
    n_unexp = len(unexpected)
    print(
        f"[TRIAGE SUMMARY] total={len(classified)} pass={n_pass} "
        f"known_env_fail={n_known} unexpected_fail={n_unexp}"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log", type=Path, default=DEFAULT_LOG, help="Đường dẫn tới file log cocotb")
    ap.add_argument("--self-test", action="store_true", help="Chỉ chạy test âm và thoát")
    ap.add_argument("--no-self-test", action="store_true", help="Bỏ qua bước test âm")
    args = ap.parse_args()

    if args.self_test:
        return 0 if run_negative_self_test() else 1

    if not args.log.exists():
        print(f"[ERROR] Không tìm thấy file log: {args.log}")
        if not args.no_self_test:
            run_negative_self_test()
        return 1

    log_text = args.log.read_text(encoding="utf-8", errors="replace")
    rc, classified, unexpected, tables = triage_log_text(log_text)
    if not classified:
        print(f"[ERROR] Không phân tích được bảng tổng kết nào trong {args.log}")
        if not args.no_self_test:
            run_negative_self_test()
        return 1

    print_triage_report(classified, unexpected, tables)
    neg_ok = True if args.no_self_test else run_negative_self_test()
    if rc != 0:
        print("[TRIAGE FAIL] Còn stage FAIL chưa nằm trong danh sách lỗi đã biết:")
        for row in unexpected:
            print(f"  - [{row['stage']}] {row['name']} ({row['status']})")
        return 1
    if not neg_ok:
        return 1

    print("[TRIAGE PASS] Toàn bộ stage đạt hoặc thuộc danh sách lỗi môi trường đã giải trình.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
