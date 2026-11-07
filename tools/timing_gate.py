#!/usr/bin/env python3
# File: timing_gate.py
# Chức năng: Cổng kiểm soát định thời (Timing Gate) 400 MHz (2.5 ns) cho bộ điều khiển chuẩn axi_ddr5_mc_top qua Vivado.

import argparse
import csv
import datetime
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
HIST_CSV = ROOT / "reports" / "remediation" / "timing_history.csv"
BUILD_DIR = ROOT / "syn" / "reports" / "build"
VIVADO_DEFAULT = r"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"

HISTORICAL_BASELINES = [
    {
        "timestamp": "2026-10-31T14:10:00",
        "commit": "top14_baseline",
        "tag": "top14",
        "stage": "synth",
        "target_top": "axi_ddr5_mc_top",
        "clock_mhz": "400.0",
        "period_ns": "2.500",
        "wns_ns": "-0.611",
        "tns_ns": "-61.424",
        "lut": "64196",
        "ff": "43604",
        "bram": "0",
        "dsp": "0",
        "status": "FAIL",
        "reason": "Moc co so goc pre-remediation (top14: WNS=-0.611ns, TNS=-61.424ns)"
    },
    {
        "timestamp": "2026-10-31T21:20:00",
        "commit": "sched_v2b_baseline",
        "tag": "sched_v2b",
        "stage": "synth",
        "target_top": "axi_ddr5_mc_top",
        "clock_mhz": "400.0",
        "period_ns": "2.500",
        "wns_ns": "-0.282",
        "tns_ns": "-33.008",
        "lut": "65332",
        "ff": "44041",
        "bram": "0",
        "dsp": "0",
        "status": "FAIL",
        "reason": "Moc scheduler v2b danh dau trong finding C-5 (WNS=-0.282ns, TNS=-33.008ns)"
    }
]

CSV_FIELDS = [
    "timestamp", "commit", "tag", "stage", "target_top",
    "clock_mhz", "period_ns", "wns_ns", "tns_ns",
    "lut", "ff", "bram", "dsp", "status", "reason"
]


def git_commit_hash():
    try:
        res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception:
        return "UNKNOWN"


def ensure_history_csv():
    HIST_CSV.parent.mkdir(parents=True, exist_ok=True)
    if not HIST_CSV.exists() or HIST_CSV.stat().st_size == 0:
        with open(HIST_CSV, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
            writer.writeheader()
            for row in HISTORICAL_BASELINES:
                writer.writerow(row)


def append_history_csv(row):
    ensure_history_csv()
    with open(HIST_CSV, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writerow(row)


def parse_timing_report(rpt_path):
    wns, tns = None, None
    if not Path(rpt_path).exists():
        return wns, tns
    lines = Path(rpt_path).read_text(encoding="utf-8", errors="replace").splitlines()
    for i, line in enumerate(lines):
        if "WNS(ns)" in line and i + 2 < len(lines):
            parts = lines[i + 2].split()
            if len(parts) >= 2:
                try:
                    wns = float(parts[0])
                    tns = float(parts[1])
                except ValueError:
                    pass
            break
    return wns, tns


def parse_util_report(rpt_path):
    lut, ff, bram, dsp = 0, 0, 0, 0
    if not Path(rpt_path).exists():
        return lut, ff, bram, dsp
    lines = Path(rpt_path).read_text(encoding="utf-8", errors="replace").splitlines()
    for line in lines:
        parts = [p.strip() for p in line.split("|") if p.strip()]
        if not parts:
            continue
        name = parts[0]
        if (name.startswith("CLB LUTs") or name == "Slice LUTs" or name == "LUT as Logic") and lut == 0:
            if len(parts) >= 2 and parts[1].isdigit():
                lut = int(parts[1])
        elif (name.startswith("CLB Registers") or name == "Slice Registers" or name == "Register as Flip Flop") and ff == 0:
            if len(parts) >= 2 and parts[1].isdigit():
                ff = int(parts[1])
        elif (name.startswith("Block RAM Tile") or name.startswith("RAMB36/FIFO")) and bram == 0:
            if len(parts) >= 2 and parts[1].isdigit():
                bram = int(parts[1])
        elif (name.startswith("DSPs") or name.startswith("DSP48")) and dsp == 0:
            if len(parts) >= 2 and parts[1].isdigit():
                dsp = int(parts[1])
    return lut, ff, bram, dsp


def print_history_table():
    ensure_history_csv()
    rows = []
    with open(HIST_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print("\n" + "=" * 115)
    print("  Q-SHIELD TIMING & RESOURCE HISTORY (reports/remediation/timing_history.csv)")
    print("=" * 115)
    print(f"{'Timestamp':<20} | {'Tag':<12} | {'Stage':<6} | {'WNS(ns)':<8} | {'TNS(ns)':<8} | {'LUT':<7} | {'FF':<7} | {'DSP':<4} | {'Status':<6} | {'Commit'}")
    print("-" * 115)
    for r in rows:
        commit_short = r['commit'][:10] if len(r['commit']) > 10 else r['commit']
        print(f"{r['timestamp']:<20} | {r['tag']:<12} | {r['stage']:<6} | {r['wns_ns']:<8} | {r['tns_ns']:<8} | {r['lut']:<7} | {r['ff']:<7} | {r['dsp']:<4} | {r['status']:<6} | {commit_short}")
    print("=" * 115 + "\n")


def find_vivado(custom_path=None):
    if custom_path and Path(custom_path).exists():
        return custom_path
    if "VIVADO_BIN" in os.environ and Path(os.environ["VIVADO_BIN"]).exists():
        return os.environ["VIVADO_BIN"]
    if Path(VIVADO_DEFAULT).exists():
        return VIVADO_DEFAULT
    # Check PATH
    try:
        res = subprocess.run(["where", "vivado"], capture_output=True, text=True)
        if res.returncode == 0:
            first = res.stdout.strip().splitlines()[0]
            if Path(first).exists():
                return first
    except Exception:
        pass
    return None


def main():
    parser = argparse.ArgumentParser(description="Q-Shield Timing Gate for axi_ddr5_mc_top (400 MHz / 2.5 ns)")
    parser.add_argument("--tag", default=None, help="Tag for run and output directory")
    parser.add_argument("--impl", action="store_true", help="Run implementation (place & route) after synthesis")
    parser.add_argument("--min-wns", type=float, default=None, help="Minimum allowable WNS in ns (exits 1 if WNS < min-wns)")
    parser.add_argument("--vivado", default=None, help="Path to vivado.bat executable")
    parser.add_argument("--skip-run", action="store_true", help="Skip Vivado run and parse existing reports")
    parser.add_argument("--history", action="store_true", help="Display timing history and exit")
    args = parser.parse_args()

    ensure_history_csv()

    if args.history:
        print_history_table()
        sys.exit(0)

    tag = args.tag
    if not tag:
        tag = f"run_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"

    run_dir = BUILD_DIR / tag
    run_dir.mkdir(parents=True, exist_ok=True)

    tcl_script = ROOT / "syn" / "scripts" / "timing_gate.tcl"
    if not tcl_script.exists():
        print(f"ERROR: TCL script {tcl_script} not found!")
        sys.exit(1)

    vivado_bin = find_vivado(args.vivado)
    commit = git_commit_hash()
    start_time = time.time()

    if not args.skip_run:
        if not vivado_bin:
            print(f"ERROR: Vivado executable not found at {VIVADO_DEFAULT} or in PATH!")
            sys.exit(1)

        tcl_args = [tag]
        if args.impl:
            tcl_args.append("impl")

        cmd = [vivado_bin, "-mode", "batch", "-source", str(tcl_script), "-tclargs", *tcl_args]
        print(f"[TIMING_GATE] Launching Vivado: {' '.join(cmd)}")
        print(f"[TIMING_GATE] Output directory: {run_dir}")

        proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
        elapsed = time.time() - start_time
        print(f"[TIMING_GATE] Vivado execution completed in {elapsed:.2f}s (Exit code: {proc.returncode})")

        # Save vivado log and console
        log_file = run_dir / f"{tag}_vivado.log"
        log_file.write_text(proc.stdout + "\n" + proc.stderr, encoding="utf-8")
    else:
        print(f"[TIMING_GATE] Parsing existing reports in {run_dir} (skip-run active)")
        elapsed = 0.0

    # Parse synthesis reports
    synth_timing_rpt = run_dir / f"{tag}_timing.rpt"
    synth_util_rpt = run_dir / f"{tag}_util.rpt"

    wns, tns = parse_timing_report(synth_timing_rpt)
    lut, ff, bram, dsp = parse_util_report(synth_util_rpt)

    if wns is None:
        print(f"ERROR: Failed to parse WNS from {synth_timing_rpt}!")
        sys.exit(1)

    status = "PASS" if (args.min_wns is None or wns >= args.min_wns) else "FAIL"
    now_iso = datetime.datetime.now().isoformat()

    row = {
        "timestamp": now_iso,
        "commit": commit,
        "tag": tag,
        "stage": "synth",
        "target_top": "axi_ddr5_mc_top",
        "clock_mhz": "400.0",
        "period_ns": "2.500",
        "wns_ns": f"{wns:.3f}",
        "tns_ns": f"{tns:.3f}" if tns is not None else "0.000",
        "lut": str(lut),
        "ff": str(ff),
        "bram": str(bram),
        "dsp": str(dsp),
        "status": status,
        "reason": f"Timing gate check against threshold {args.min_wns} ns (elapsed: {elapsed:.1f}s)"
    }
    append_history_csv(row)

    print("\n" + "=" * 90)
    print(f"  TIMING GATE EVALUATION: axi_ddr5_mc_top @ 400 MHz (2.500 ns)")
    print("=" * 90)
    print(f"  Tag            : {tag}")
    print(f"  Commit         : {commit}")
    print(f"  Stage          : synth")
    print(f"  WNS            : {wns:+.3f} ns")
    print(f"  TNS            : {tns:+.3f} ns" if tns is not None else "  TNS            : N/A")
    print(f"  CLB LUTs       : {lut:,}")
    print(f"  CLB FFs        : {ff:,}")
    print(f"  Block RAM      : {bram}")
    print(f"  DSPs           : {dsp}")
    print(f"  Threshold WNS  : {args.min_wns if args.min_wns is not None else 'None'}")
    print(f"  Status         : {status}")
    print(f"  Elapsed Time   : {elapsed:.2f} s")
    print("=" * 90 + "\n")

    if args.min_wns is not None and wns < args.min_wns:
        print(f"[TIMING_GATE:FAIL] WNS {wns:+.3f} ns is below required threshold {args.min_wns:+.3f} ns!")
        sys.exit(1)
    else:
        print(f"[TIMING_GATE:PASS] Timing check passed successfully.")
        sys.exit(0)


if __name__ == "__main__":
    main()
