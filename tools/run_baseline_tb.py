#!/usr/bin/env python3
# File:      run_baseline_tb.py
# Chức năng: Biên dịch và chạy testbench trên ảnh chụp RTL v1 (build/sched_bench/rtl_v1/rtl, bản đóng băng Q5) với -DQS_BASELINE_V1 để lấy bằng chứng FAIL.

import os
import re
import subprocess
import sys

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    if len(sys.argv) < 2:
        sys.exit("Usage: python tools/run_baseline_tb.py <top> [timeout_s]")
    top = sys.argv[1]
    tmo = int(sys.argv[2]) if len(sys.argv) > 2 else 900

    src = open(os.path.join(root, "run_iverilog_regression.py"), encoding="utf-8").read()
    i = src.index(f'"top": "{top}"')
    s_idx = src.index('"sources"', i)
    j = src.index("]", s_idx)
    raw_paths = []
    if "top_common_sources" in src[s_idx:j]:
        tc_start = src.index("top_common_sources = [")
        tc_end = src.index("]", tc_start)
        raw_paths.extend(
            os.path.join(root, *[eval(p) for p in m.split(", ")])
            for m in re.findall(r"os\.path\.join\(root, ([^)]*)\)", src[tc_start:tc_end])
        )
    raw_paths.extend(
        os.path.join(root, *[eval(p) for p in m.split(", ")])
        for m in re.findall(r"os\.path\.join\(root, ([^)]*)\)", src[s_idx:j])
    )
    raw_paths = [
        os.path.join(root, "rtl", "backend", "secded_72_64_pkg.sv"),
        os.path.join(root, "tb", "common", "ddr5_jedec_bin_pkg.sv"),
    ] + [p for p in raw_paths if not p.endswith(("secded_72_64_pkg.sv", "ddr5_jedec_bin_pkg.sv"))]

    rtl_root = os.path.join(root, "rtl") + os.sep
    snap_root = os.path.join(root, "build", "sched_bench", "rtl_v1", "rtl") + os.sep
    paths = [p.replace(rtl_root, snap_root) if p.startswith(rtl_root) else p for p in raw_paths]
    # Tệp RTL mới của v2 (ví dụ bank_credit_ctrl.sv) không có trong ảnh chụp v1: bỏ qua
    paths = [p for p in paths if os.path.isfile(p)]

    bdir = os.path.join(root, "build", "v1_" + top)
    os.makedirs(bdir, exist_ok=True)
    log_dir = os.path.join(root, "regression_logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"baseline_v1_{top}.log")

    cmd = [
        r"D:\iverilog\bin\iverilog.exe",
        "-g2012",
        "-DQS_BASELINE_V1",
        "-I", os.path.join(root, "tb", "common"),
        "-s", top,
        "-o", "t.vvp",
    ] + paths

    r_cmp = subprocess.run(cmd, capture_output=True, text=True, cwd=bdir)
    if r_cmp.returncode != 0:
        msg = "=== COMPILE FAILED ===\n" + r_cmp.stdout + "\n" + r_cmp.stderr
        with open(log_file, "w", encoding="utf-8") as f:
            f.write(msg)
        sys.exit(msg)

    r_sim = subprocess.run(
        [r"D:\iverilog\bin\vvp.exe", os.path.join(bdir, "t.vvp")],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=root,
        timeout=tmo,
    )
    full_out = f"=== COMPILE ===\n{' '.join(cmd)}\n\n=== STDOUT ===\n{r_sim.stdout}\n=== STDERR ===\n{r_sim.stderr}\n"
    with open(log_file, "w", encoding="utf-8") as f:
        f.write(full_out)

    out_lines = r_sim.stdout.splitlines()
    print(f"[BASELINE_V1] top={top} rc={r_sim.returncode} log={log_file}")
    summary = [l for l in out_lines if any(k in l for k in ("TB_RESULT", "FAIL", "PASS", "ERROR", "err "))]
    print("\n".join(summary[-40:] if summary else out_lines[-20:]))

if __name__ == "__main__":
    main()

