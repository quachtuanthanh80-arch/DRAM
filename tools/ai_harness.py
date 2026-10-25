# File: tools/ai_harness.py
# Chức năng: Bộ điều phối tự động kết hợp Claude (Architect/Planner) và Gemini (RTL/Python Executor & Verifier).

import subprocess
import argparse
from pathlib import Path

HARNESS_DIR = Path(".harness")
PLAN_FILE = HARNESS_DIR / "1_plan.md"
REPORT_FILE = HARNESS_DIR / "2_test_report.txt"
REVIEW_FILE = HARNESS_DIR / "3_review.md"


def run_cli(cmd: list[str], input_text: str | None = None) -> str:
    res = subprocess.run(
        cmd,
        input=input_text,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        shell=True,
    )
    return (res.stdout or "") + ("\n" + res.stderr if res.stderr and res.returncode != 0 else "")


def main():
    parser = argparse.ArgumentParser(description="Claude-Plan + Gemini-Code Automated Harness")
    parser.add_argument("task", nargs="?", default="Kiểm toán và tối ưu hóa bộ kiểm thử bảo mật Q-Shield", help="Mô tả nhiệm vụ")
    parser.add_argument("--test-cmd", default="python tools/run_security_attack_suite.py", help="Lệnh kiểm chứng tự động")
    parser.add_argument("--skip-claude", action="store_true", help="Chạy kiểm chứng trực tiếp nếu đã có sẵn .harness/1_plan.md")
    args = parser.parse_args()

    HARNESS_DIR.mkdir(exist_ok=True)

    if not args.skip_claude:
        print("[PHASE 1/3] Claude Architect đang lập kế hoạch vào .harness/1_plan.md ...")
        plan_prompt = (
            f"Đọc AGENTS.md. Lập kế hoạch kỹ thuật chi tiết (Mục tiêu, Các file RTL/Python, "
            f"Ràng buộc định thời JEDEC, Tiêu chí kiểm thử) cho tác vụ: {args.task}"
        )
        plan_out = run_cli(["claude", "-p", plan_prompt])
        if plan_out.strip():
            PLAN_FILE.write_text(plan_out, encoding="utf-8")
            print(f"  [+] Đã lưu kế hoạch tại: {PLAN_FILE}")
        else:
            print("  [!] Không tìm thấy phiên bản Claude CLI hoạt động, giữ nguyên .harness/1_plan.md hiện hành.")

    print(f"[PHASE 2/3] Thực thi kiểm chứng tự động: {args.test_cmd} ...")
    test_out = run_cli(args.test_cmd.split())
    REPORT_FILE.write_text(test_out, encoding="utf-8")
    print(test_out)
    print(f"  [+] Đã lưu báo cáo kiểm thử tại: {REPORT_FILE}")

    if not args.skip_claude:
        print("[PHASE 3/3] Claude đang nghiệm thu kết quả (Cross-Review) ...")
        diff_out = run_cli(["git", "status", "-s"])
        review_prompt = (
            f"Kiểm tra báo cáo chạy test sau và đánh giá mức độ sẵn sàng báo cáo GVHD:\n\n"
            f"{test_out[-4000:]}\n\nGit status:\n{diff_out}"
        )
        review_out = run_cli(["claude", "-p", review_prompt])
        if review_out.strip():
            REVIEW_FILE.write_text(review_out, encoding="utf-8")
            print(f"  [+] Đã lưu biên bản nghiệm thu tại: {REVIEW_FILE}")


if __name__ == "__main__":
    main()
