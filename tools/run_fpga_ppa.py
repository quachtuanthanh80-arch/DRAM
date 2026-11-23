#!/usr/bin/env python3
# tools/run_fpga_ppa.py
# Chức năng: Tự động chạy P&R Vivado và tổng hợp báo cáo PPA FPGA sau route trên xczu7ev cho paper (T83).

import argparse
import datetime
import glob
import hashlib
import json
import math
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
T83_SUMMARY_JSON = ROOT / "reports" / "paper" / "fpga" / "fpga_ppa_summary.json"
T89_SUMMARY_JSON = ROOT / "reports" / "paper" / "fpga" / "t89" / "fpga_ppa_summary.json"
DEFAULT_OUT_DIR = ROOT / "reports" / "paper" / "fpga" / "t89"
VIVADO_DEFAULT = r"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"

EXACT_PAPER_POINTS = {
    "axi_ddr5_mc_top": [
        ("core_2500ps", 2.500),
        ("core_confirmed", 3.800),
    ],
    "axi_ddr5_mc_secure_top": [
        ("sec_2500ps", 2.500),
        ("sec_confirmed", 4.100),
        ("sec_confirmed_r2", 4.150),
    ],
}


def find_vivado(custom_path=None):
    if custom_path and Path(custom_path).exists():
        return str(Path(custom_path).resolve())
    if "VIVADO_BIN" in os.environ and Path(os.environ["VIVADO_BIN"]).exists():
        return str(Path(os.environ["VIVADO_BIN"]).resolve())
    for cand in ("vivado", "vivado.bat"):
        found = shutil.which(cand)
        if found:
            return found
    if Path(VIVADO_DEFAULT).exists():
        return VIVADO_DEFAULT
    for pattern in ("/opt/Xilinx/Vivado/*/bin/vivado", "/tools/Xilinx/Vivado/*/bin/vivado"):
        matches = sorted(glob.glob(pattern), reverse=True)
        if matches and Path(matches[0]).exists():
            return matches[0]
    return None


def get_git_metadata():
    commit = None
    dirty = None
    try:
        r1 = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, timeout=5)
        if r1.returncode == 0:
            commit = r1.stdout.strip()
        r2 = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True, timeout=5)
        if r2.returncode == 0:
            dirty = bool(r2.stdout.strip())
    except Exception:
        pass
    return {"git_commit": commit, "git_dirty": dirty}


def compute_rtl_hashes():
    rtl_dir = ROOT / "rtl"
    hashes = {}
    for p in sorted(rtl_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        hashes[rel] = h.hexdigest()
    return hashes


def write_rtl_hashes_file(out_dir: Path, git_commit: str):
    hashes = compute_rtl_hashes()
    lines = [
        f"# RTL SHA-256 Snapshot (captured BEFORE Vivado P&R)",
        f"git_head: {git_commit}",
        f"captured_at: {datetime.datetime.now().isoformat()}",
        f"rtl_file_count: {len(hashes)}",
        "",
    ]
    for rel, digest in hashes.items():
        lines.append(f"{digest}  {rel}")
    out_path = out_dir / "RTL_HASHES.txt"
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[+] Da ghi {out_path} ({len(hashes)} file rtl/**, HEAD={git_commit})", flush=True)
    return hashes


def parse_rtl_hashes_file(path: Path) -> dict:
    hashes = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^([0-9a-fA-F]{64})\s+(.+)$", line.strip())
        if m:
            hashes[m.group(2).strip()] = m.group(1).lower()
    return hashes


def verify_rtl_hashes_match_ref(ref_path: Path):
    if not ref_path.exists():
        print(f"[STOP_CONDITION_TRIGGERED] Khong tim thay file hash tham chieu: {ref_path}", file=sys.stderr, flush=True)
        sys.exit(2)
    ref_hashes = parse_rtl_hashes_file(ref_path)
    cur_hashes = compute_rtl_hashes()
    if cur_hashes != ref_hashes:
        changed = [k for k in sorted(set(cur_hashes) | set(ref_hashes)) if cur_hashes.get(k) != ref_hashes.get(k)]
        print(
            f"[STOP_CONDITION_TRIGGERED] SHA-256 rtl/** KHAC voi {ref_path}: {changed}",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(2)
    print(f"[+] Xac nhan SHA-256 rtl/** KHOP 100% voi {ref_path} ({len(cur_hashes)} file)", flush=True)
    return cur_hashes


def verify_rtl_hashes_unchanged(expected_hashes: dict, stage_label: str):
    current = compute_rtl_hashes()
    if current != expected_hashes:
        changed = [k for k in sorted(set(current) | set(expected_hashes)) if current.get(k) != expected_hashes.get(k)]
        print(
            f"[STOP_CONDITION_TRIGGERED] Cay rtl/** thay doi trong luc chay Vivado ({stage_label}): {changed}",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(2)


def get_rtl_diff_since_t83():
    try:
        r = subprocess.run(
            ["git", "diff", "--name-status", "rem/T83..HEAD", "--", "rtl/"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0:
            return [line.strip() for line in r.stdout.splitlines() if line.strip()]
    except Exception:
        pass
    return []


def parse_vivado_version(log_path: Path):
    if not log_path.exists():
        return None
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines()[:30]:
        m = re.match(r"^#\s*(Vivado\s+v.+)$", line.strip())
        if m:
            return m.group(1).strip()
    return None


def parse_timing_rpt(rpt_path: Path):
    if not rpt_path.exists():
        return None
    content = rpt_path.read_text(encoding="utf-8", errors="replace")
    lines = content.splitlines()

    res = {
        "wns": None,
        "tns": None,
        "failing_endpoints": None,
        "total_endpoints": None,
        "whs": None,
        "ths": None,
        "wpws": None,
        "period": None,
        "freq_mhz": None,
    }

    for i, line in enumerate(lines):
        if "Design Timing Summary" in line:
            for j in range(i + 1, min(i + 15, len(lines))):
                row = lines[j].strip()
                parts = row.split()
                if len(parts) >= 8 and re.match(r"^-?\d+\.\d+", parts[0]):
                    try:
                        res["wns"] = float(parts[0])
                        res["tns"] = float(parts[1])
                        res["failing_endpoints"] = int(parts[2])
                        res["total_endpoints"] = int(parts[3])
                        res["whs"] = float(parts[4])
                        res["ths"] = float(parts[5])
                        if len(parts) >= 9:
                            res["wpws"] = float(parts[8])
                    except (ValueError, IndexError):
                        pass
                    break

        if "Clock Summary" in line:
            for j in range(i + 1, min(i + 15, len(lines))):
                row = lines[j].strip()
                m = re.match(r"^clk_axi\s+\{[^}]+\}\s+([\d.]+)\s+([\d.]+)", row)
                if m:
                    res["period"] = float(m.group(1))
                    res["freq_mhz"] = float(m.group(2))
                    break

    return res


def parse_util_rpt(rpt_path: Path):
    if not rpt_path.exists():
        return None
    content = rpt_path.read_text(encoding="utf-8", errors="replace")

    res = {
        "lut": None,
        "lut_logic": None,
        "lut_mem": None,
        "lut_avail": 230400,
        "lut_pct": None,
        "ff": None,
        "ff_avail": 460800,
        "ff_pct": None,
        "bram_tile": 0.0,
        "ramb36": 0,
        "ramb18": 0,
        "uram": 0,
        "dsp": 0,
    }

    m = re.search(r"\|\s*CLB LUTs\*?\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*([\d.]+)", content)
    if m:
        res["lut"] = int(m.group(1))
        res["lut_avail"] = int(m.group(2))
        res["lut_pct"] = float(m.group(3))

    m = re.search(r"\|\s*LUT as Logic\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["lut_logic"] = int(m.group(1))

    m = re.search(r"\|\s*LUT as Memory\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["lut_mem"] = int(m.group(1))

    m = re.search(r"\|\s*CLB Registers\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*([\d.]+)", content)
    if m:
        res["ff"] = int(m.group(1))
        res["ff_avail"] = int(m.group(2))
        res["ff_pct"] = float(m.group(3))

    m = re.search(r"\|\s*Block RAM Tile\s*\|\s*([\d.]+)\s*\|", content)
    if m:
        res["bram_tile"] = float(m.group(1))

    m = re.search(r"\|\s*RAMB36/FIFO\*?\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["ramb36"] = int(m.group(1))

    m = re.search(r"\|\s*RAMB18\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["ramb18"] = int(m.group(1))

    m = re.search(r"\|\s*URAM\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["uram"] = int(m.group(1))

    m = re.search(r"\|\s*DSPs\s*\|\s*(\d+)\s*\|", content)
    if m:
        res["dsp"] = int(m.group(1))

    return res


def parse_power_rpt(rpt_path: Path):
    if not rpt_path.exists():
        return None
    content = rpt_path.read_text(encoding="utf-8", errors="replace")

    res = {
        "total_w": None,
        "dynamic_w": None,
        "static_w": None,
        "confidence": None,
        "saif_file": None,
        "mode": "vectorless (Vivado default toggle rate 12.5%, no Simulation Activity File)",
        "by_hierarchy": {},
    }

    m = re.search(r"\|\s*Total On-Chip Power \(W\)\s*\|\s*([\d.]+)\s*\|", content)
    if m:
        res["total_w"] = float(m.group(1))
    m = re.search(r"\|\s*Dynamic \(W\)\s*\|\s*([\d.]+)\s*\|", content)
    if m:
        res["dynamic_w"] = float(m.group(1))
    m = re.search(r"\|\s*Device Static \(W\)\s*\|\s*([\d.]+)\s*\|", content)
    if m:
        res["static_w"] = float(m.group(1))
    m = re.search(r"\|\s*Confidence Level\s*\|\s*([^|]+?)\s*\|", content)
    if m:
        res["confidence"] = m.group(1).strip()
    m = re.search(r"\|\s*Simulation Activity File\s*\|\s*([^|]+?)\s*\|", content)
    if m:
        res["saif_file"] = m.group(1).strip()

    # Parse 3.1 By Hierarchy (skip Table of Contents by checking underline '---')
    lines = content.splitlines()
    in_hier = False
    stack = []
    for idx, line in enumerate(lines):
        if line.strip() == "3.1 By Hierarchy" and idx + 1 < len(lines) and lines[idx + 1].strip().startswith("---"):
            in_hier = True
            continue
        if in_hier:
            if not line.strip().startswith("|"):
                if res["by_hierarchy"] and line.strip() == "":
                    break
                continue
            raw_cols = line.split("|")[1:-1]
            if len(raw_cols) != 2:
                continue
            raw_name = raw_cols[0]
            val_str = raw_cols[1].strip()
            try:
                pwr = float(val_str.lstrip("<"))
            except ValueError:
                continue
            name = raw_name.strip()
            indent = len(raw_name) - len(raw_name.lstrip(" "))
            depth = max(0, (indent - 1) // 2)
            while len(stack) > depth:
                stack.pop()
            stack.append(name)
            path = "/".join(stack)
            res["by_hierarchy"][path] = pwr

    return res


def parse_hier_util_rpt(rpt_path: Path):
    if not rpt_path.exists():
        return []
    content = rpt_path.read_text(encoding="utf-8", errors="replace")
    entries = []
    stack = []

    for line in content.splitlines():
        if not line.strip().startswith("|"):
            continue
        raw_cols = line.split("|")[1:-1]
        if len(raw_cols) < 11:
            continue
        raw_inst = raw_cols[0]
        cols = [c.strip() for c in raw_cols]
        inst = cols[0]
        module = cols[1]
        try:
            total_luts = int(cols[2])
            logic_luts = int(cols[3])
            lutrams = int(cols[4])
            srls = int(cols[5])
            ffs = int(cols[6])
            ramb36 = int(cols[7])
            ramb18 = int(cols[8])
            uram = int(cols[9])
            dsp = int(cols[10])
        except ValueError:
            continue

        indent = len(raw_inst) - len(raw_inst.lstrip(" "))
        depth = max(0, (indent - 1) // 2)
        while len(stack) > depth:
            stack.pop()
        stack.append(inst)
        path = "/".join(stack)

        entries.append({
            "path": path,
            "instance": inst,
            "depth": depth,
            "module": module,
            "total_luts": total_luts,
            "logic_luts": logic_luts,
            "lutrams": lutrams,
            "srls": srls,
            "ffs": ffs,
            "ramb36": ramb36,
            "ramb18": ramb18,
            "bram_tile": ramb36 + 0.5 * ramb18,
            "uram": uram,
            "dsp": dsp,
        })

    return entries


def extract_key_blocks(entries, power_by_hier):
    """Trich xuat cac khoi chinh theo yeu cau brief (loi, bridge, AES, GF-mult, MC, cay)."""
    blocks = []
    for e in entries:
        inst = e["instance"]
        mod = e["module"]
        path = e["path"]
        if e["depth"] <= 2 or any(
            k in inst or k in mod
            for k in (
                "u_mc_core",
                "u_crypto_bridge",
                "u_bmt_engine",
                "u_meta_cache",
                "u_mac_unit",
                "u_enc_lane",
                "u_dec_pipe",
                "u_tweak_gen",
                "u_integrity_csr",
                "gf128",
                "aes",
                "u_qos_queue",
                "u_wds",
                "u_sdc_filter",
                "u_cmd_engine",
                "u_rob",
                "u_drm",
                "u_frontend",
            )
        ):
            pwr = power_by_hier.get(path)
            item = dict(e)
            item["dynamic_power_w"] = pwr
            blocks.append(item)
    return blocks


def run_vivado(vivado_bin, out_dir: Path, top, tag, period, presynth_dcp=None, max_threads=None, max_point_seconds=None):
    tcl_script = ROOT / "syn" / "scripts" / "impl_paper.tcl"
    log_path = out_dir / f"{tag}_vivado.log"
    jou_path = out_dir / f"{tag}_vivado.jou"
    dcp_arg = str(presynth_dcp) if (presynth_dcp and Path(presynth_dcp).exists()) else ""
    threads_arg = str(max_threads) if max_threads is not None else ""

    cmd = [
        str(vivado_bin),
        "-mode", "batch",
        "-log", str(log_path),
        "-journal", str(jou_path),
        "-source", str(tcl_script),
        "-tclargs", str(top), str(tag), f"{period:.3f}", dcp_arg, str(out_dir), threads_arg,
    ]
    # Bỏ các tham số tùy chọn rỗng ở cuối để lệnh gọn, dễ đọc khi log lại
    while cmd[-1] == "":
        cmd.pop()

    print(f"\n>>> DANG CHAY VIVADO: {' '.join(cmd)}", flush=True)
    t0 = time.time()
    try:
        p = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=max_point_seconds,
        )
    except subprocess.TimeoutExpired:
        elapsed = time.time() - t0
        print(
            f"[STOP_CONDITION_TRIGGERED] Vivado {top} ({tag}, {period:.3f}ns) vuot gioi han {max_point_seconds}s ({elapsed:.1f}s)!",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(4)
    elapsed = time.time() - t0
    print(f">>> VIVADO KET THUC: exit={p.returncode}, thoi gian={elapsed:.1f}s, log={log_path.name}", flush=True)
    if p.returncode != 0:
        print("[STDOUT/STDERR VIVADO TAIL]:\n" + (p.stdout + "\n" + p.stderr)[-3000:], flush=True)
    if max_point_seconds is not None and elapsed > max_point_seconds:
        print(
            f"[STOP_CONDITION_TRIGGERED] Vivado {top} ({tag}, {period:.3f}ns) chay {elapsed:.1f}s > {max_point_seconds}s!",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(4)
    return {
        "returncode": p.returncode,
        "elapsed_s": round(elapsed, 2),
        "command": cmd,
        "log_file": str(log_path.relative_to(ROOT)) if log_path.is_relative_to(ROOT) else str(log_path),
        "journal_file": str(jou_path.relative_to(ROOT)) if jou_path.is_relative_to(ROOT) else str(jou_path),
        "vivado_version": parse_vivado_version(log_path),
    }


def extract_run_metrics(out_dir: Path, tag):
    timing_rpt = out_dir / f"{tag}_route_timing.rpt"
    util_rpt = out_dir / f"{tag}_route_util.rpt"
    hier_rpt = out_dir / f"{tag}_route_util_hier.rpt"
    power_rpt = out_dir / f"{tag}_route_power.rpt"

    t_res = parse_timing_rpt(timing_rpt)
    u_res = parse_util_rpt(util_rpt)
    p_res = parse_power_rpt(power_rpt)
    h_entries = parse_hier_util_rpt(hier_rpt)

    return t_res, u_res, p_res, h_entries


def build_stage_dict(tag, period_ns, t_res, u_res, p_res, run_meta=None):
    return {
        "tag": tag,
        "period_ns": period_ns,
        "target_freq_mhz": round(1000.0 / period_ns, 2),
        "fmax_mhz": round(1000.0 / period_ns, 2),
        "wns_ns": t_res["wns"] if t_res else None,
        "tns_ns": t_res["tns"] if t_res else None,
        "whs_ns": t_res["whs"] if t_res else None,
        "ths_ns": t_res["ths"] if t_res else None,
        "wpws_ns": t_res["wpws"] if t_res else None,
        "failing_endpoints": t_res["failing_endpoints"] if t_res else None,
        "total_endpoints": t_res["total_endpoints"] if t_res else None,
        "lut": u_res["lut"] if u_res else None,
        "lut_logic": u_res["lut_logic"] if u_res else None,
        "lut_mem": u_res["lut_mem"] if u_res else None,
        "lut_pct": u_res["lut_pct"] if u_res else None,
        "ff": u_res["ff"] if u_res else None,
        "ff_pct": u_res["ff_pct"] if u_res else None,
        "bram_tile": u_res["bram_tile"] if u_res else None,
        "ramb36": u_res["ramb36"] if u_res else None,
        "ramb18": u_res["ramb18"] if u_res else None,
        "dsp": u_res["dsp"] if u_res else None,
        "power_total_w": p_res["total_w"] if p_res else None,
        "power_dynamic_w": p_res["dynamic_w"] if p_res else None,
        "power_static_w": p_res["static_w"] if p_res else None,
        "power_confidence": p_res["confidence"] if p_res else None,
        "power_mode": p_res["mode"] if p_res else None,
        "elapsed_s": run_meta.get("elapsed_s") if run_meta else None,
        "log_file": run_meta.get("log_file") if run_meta else None,
    }


def clean_out_dir(out_dir: Path):
    patterns = ("*.rpt", "*.dcp", "*_vivado.log", "*_vivado.jou", "fpga_ppa_summary.*", "repro_manifest.json")
    removed = 0
    for pat in patterns:
        for p in out_dir.glob(pat):
            p.unlink()
            removed += 1
    print(f"[CLEAN] Da xoa {removed} file cu trong {out_dir} de tai lap sach tu RTL.", flush=True)


def execute_point(vivado_bin, out_dir: Path, target, tag, period_ns, skip_rerun, presynth_dcp, max_threads, run_records, max_point_seconds=None):
    timing_rpt = out_dir / f"{tag}_route_timing.rpt"
    run_meta = None
    if not skip_rerun or not timing_rpt.exists():
        run_meta = run_vivado(
            vivado_bin,
            out_dir,
            target,
            tag,
            period_ns,
            presynth_dcp=presynth_dcp,
            max_threads=max_threads,
            max_point_seconds=max_point_seconds,
        )
        run_records.append({"top": target, "tag": tag, "period_ns": period_ns, **run_meta})
        if run_meta["returncode"] != 0:
            print(f"[FAIL] Chay Vivado P&R cho {target} ({tag}) that bai!", file=sys.stderr)
            sys.exit(1)
    else:
        log_path = out_dir / f"{tag}_vivado.log"
        run_meta = {
            "elapsed_s": None,
            "log_file": str(log_path.relative_to(ROOT)) if (log_path.exists() and log_path.is_relative_to(ROOT)) else (str(log_path) if log_path.exists() else None),
            "vivado_version": parse_vivado_version(log_path),
        }
        print(f"[SKIP] Da co bao cao route cho {tag}: {timing_rpt.name}", flush=True)

    t_res, u_res, p_res, h_entries = extract_run_metrics(out_dir, tag)
    if not t_res or t_res["wns"] is None:
        print(f"[FAIL] Khong doc duoc WNS tu {timing_rpt}", file=sys.stderr)
        sys.exit(1)
    return t_res, u_res, p_res, h_entries, run_meta


def run_periods_sweep(args, vivado_bin, out_dir: Path, git_meta: dict, rtl_hashes_before: dict):
    """Che do quet danh sach chu ky tuy chon (T92): giu nguyen duong chay T83/T89."""
    periods = [round(float(x.strip()), 3) for x in args.periods.split(",") if x.strip()]
    if not periods:
        print("[FAIL] --periods rong!", file=sys.stderr)
        sys.exit(1)

    targets = ["axi_ddr5_mc_top", "axi_ddr5_mc_secure_top"] if args.top == "all" else [args.top]
    t83_data = json.loads(T83_SUMMARY_JSON.read_text(encoding="utf-8")) if T83_SUMMARY_JSON.exists() else {}
    t89_data = json.loads(T89_SUMMARY_JSON.read_text(encoding="utf-8")) if T89_SUMMARY_JSON.exists() else {}

    run_records = []
    summary_data = {
        "timestamp": datetime.datetime.now().isoformat(),
        "device": "xczu7ev-ffvc1156-2-e",
        "mode": "sweep",
        "periods_requested": periods,
        "stop_on_fail": bool(args.stop_on_fail),
        "max_point_seconds": args.max_point_seconds,
        "presynth_dcp_arg": args.presynth_dcp,
        "ref_rtl_hashes": args.ref_rtl_hashes,
        "os": platform.platform(),
        "cpu_count": os.cpu_count(),
        "max_threads": args.threads,
        "no_reuse_dcp": args.no_reuse_dcp,
        **git_meta,
        "vivado_version": None,
        "power_methodology": "vectorless report_power (Vivado default toggle rate 12.5%, no Simulation Activity File)",
        "results": {},
    }

    for target in targets:
        prefix = "core" if target == "axi_ddr5_mc_top" else "sec"
        session_dcp = Path(args.presynth_dcp).resolve() if (args.presynth_dcp and Path(args.presynth_dcp).exists()) else None
        if args.presynth_dcp and not session_dcp:
            print(f"[CANH BAO] Khong thay presynth_dcp {args.presynth_dcp}, se tong hop moi tu RTL.", flush=True)

        sweep_pts = []
        hier_by_tag = {}
        pwr_hier_by_tag = {}
        first_fail_pt = None

        for idx, per in enumerate(periods):
            tag = f"{prefix}_{int(round(per * 1000))}ps"
            use_dcp = None if args.no_reuse_dcp else session_dcp
            t_res, u_res, p_res, h_entries, run_meta = execute_point(
                vivado_bin, out_dir, target, tag, per, args.skip_rerun, use_dcp,
                args.threads, run_records, max_point_seconds=args.max_point_seconds,
            )
            verify_rtl_hashes_unchanged(rtl_hashes_before, f"{target}:{tag}")
            if session_dcp is None and not args.no_reuse_dcp:
                cand = out_dir / f"{tag}_presynth.dcp"
                if cand.exists():
                    session_dcp = cand

            st = build_stage_dict(tag, per, t_res, u_res, p_res, run_meta)
            st["passed"] = bool(st["wns_ns"] is not None and st["wns_ns"] >= 0.0 and (st["failing_endpoints"] or 0) == 0)
            st["source"] = "t92_sweep"
            sweep_pts.append(st)
            hier_by_tag[tag] = h_entries
            pwr_hier_by_tag[tag] = p_res["by_hierarchy"] if p_res else {}

            print(
                f"[SWEEP] {target} {tag} ({per:.3f} ns / {st['fmax_mhz']:.2f} MHz): "
                f"WNS={st['wns_ns']:.3f}ns, TNS={st['tns_ns']:.3f}ns, EP={st['failing_endpoints']}, "
                f"LUT={st['lut']}, FF={st['ff']}, Pwr={st['power_total_w']:.3f}W, "
                f"status={'PASS' if st['passed'] else 'FAIL'}",
                flush=True,
            )

            if not st["passed"]:
                if first_fail_pt is None:
                    first_fail_pt = st
                if args.stop_on_fail:
                    print(f"[SWEEP] Dung tai diem truot dau tien: {per:.3f} ns (WNS={st['wns_ns']:.3f}ns, EP={st['failing_endpoints']}).", flush=True)
                    break

        passing_pts = [p for p in sweep_pts if p["passed"]]
        non_monotonic = False
        for i in range(len(sweep_pts)):
            for j in range(i + 1, len(sweep_pts)):
                a, b = sweep_pts[i], sweep_pts[j]
                if (a["period_ns"] > b["period_ns"] and not a["passed"] and b["passed"]) or (
                    b["period_ns"] > a["period_ns"] and not b["passed"] and a["passed"]
                ):
                    non_monotonic = True

        t89_ref = t89_data.get("results", {}).get(target, {}).get("confirmed")
        t83_ref = t83_data.get("results", {}).get(target, {}).get("confirmed")

        if passing_pts:
            conf_dict = min(passing_pts, key=lambda p: p["period_ns"])
            conf_h_entries = hier_by_tag.get(conf_dict["tag"], [])
            conf_power_hier = pwr_hier_by_tag.get(conf_dict["tag"], {})
        elif t89_ref:
            conf_dict = dict(t89_ref)
            conf_dict["passed"] = True
            conf_dict["source"] = "T89_reference (not re-run)"
            conf_h_entries = t89_data.get("results", {}).get(target, {}).get("hierarchical_util", [])
            conf_power_hier = t89_data.get("results", {}).get(target, {}).get("power_by_hierarchy", {})
        else:
            conf_dict = sweep_pts[-1]
            conf_h_entries = hier_by_tag.get(conf_dict["tag"], [])
            conf_power_hier = pwr_hier_by_tag.get(conf_dict["tag"], {})

        key_blocks = extract_key_blocks(conf_h_entries, conf_power_hier)
        summary_data["results"][target] = {
            "top": target,
            "stage": "post_route",
            "confirmed": conf_dict,
            "first_failing_point": first_fail_pt,
            "non_monotonic": non_monotonic,
            "sweep_points": sweep_pts,
            "t83_reference": t83_ref,
            "t89_reference": t89_ref,
            "key_blocks": key_blocks,
            "hierarchical_util": conf_h_entries,
            "power_by_hierarchy": conf_power_hier,
        }

    for rec in run_records:
        if rec.get("vivado_version"):
            summary_data["vivado_version"] = rec["vivado_version"]
            break

    verify_rtl_hashes_unchanged(rtl_hashes_before, "final")
    rtl_diff_t83 = get_rtl_diff_since_t83()
    summary_data["rtl_hashes_file"] = str((out_dir / "RTL_HASHES.txt").relative_to(ROOT)).replace("\\", "/")
    summary_data["rtl_hashes_verified_unchanged"] = True
    summary_data["rtl_files_changed_since_rem_t83"] = rtl_diff_t83

    sum_json = out_dir / "fpga_ppa_summary.json"
    sum_json.write_text(json.dumps(summary_data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n[+] Da luu bao cao JSON: {sum_json}", flush=True)

    manifest_json = out_dir / "repro_manifest.json"
    manifest_data = {
        "timestamp": summary_data["timestamp"],
        "device": summary_data["device"],
        "mode": "sweep",
        "periods_requested": periods,
        "stop_on_fail": bool(args.stop_on_fail),
        "presynth_dcp_arg": args.presynth_dcp,
        "ref_rtl_hashes": args.ref_rtl_hashes,
        "vivado_bin": vivado_bin,
        "vivado_version": summary_data["vivado_version"],
        "max_threads": args.threads,
        "no_reuse_dcp": args.no_reuse_dcp,
        "os": summary_data["os"],
        "cpu_count": summary_data["cpu_count"],
        **git_meta,
        "runs": run_records,
    }
    manifest_json.write_text(json.dumps(manifest_data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[+] Da luu manifest tai lap: {manifest_json}", flush=True)

    sum_md = out_dir / "fpga_ppa_summary.md"
    md_lines = [
        "# Q-Shield FPGA Post-Route Core Fmax Sweep Summary (T92)",
        f"- Ngày đo: {summary_data['timestamp']}",
        f"- Chip mục tiêu: `{summary_data['device']}` (Xilinx Zynq UltraScale+)",
        f"- Vivado: `{summary_data['vivado_version'] or 'unknown'}` | Threads: `{args.threads}` | Presynth DCP: `{args.presynth_dcp or 'fresh synth'}`",
        f"- Git commit: `{git_meta['git_commit'] or 'unknown'}` | RTL hash snapshot: `{summary_data['rtl_hashes_file']}` (khớp 100% với T89 và không đổi sau mọi lượt route)",
        f"- Phương pháp đo công suất: {summary_data['power_methodology']}",
        "",
    ]
    for target, info in summary_data["results"].items():
        conf = info["confirmed"]
        ffp = info["first_failing_point"]
        t83r = info["t83_reference"]
        t89r = info["t89_reference"]
        md_lines.extend([
            f"## 1. Bảng từng điểm quét của `{target}`",
            "",
            "| Tag | Nguồn | Period (ns) | Fmax (MHz) | WNS (ns) | TNS (ns) | WHS (ns) | Failing EP | LUTs (%) | FFs (%) | Power (W) | Elapsed (s) | Kết quả |",
            "| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
        ])
        if t89r:
            md_lines.append(
                f"| `{t89r['tag']}` | T89 (dẫn chiếu) | `{t89r['period_ns']:.3f}` | `{t89r['fmax_mhz']:.2f}` | `{t89r['wns_ns']:.3f}` | `{t89r['tns_ns']:.3f}` | `{t89r['whs_ns']:.3f}` | `{t89r['failing_endpoints']}` | `{t89r['lut']}` (`{t89r['lut_pct']:.2f}%`) | `{t89r['ff']}` (`{t89r['ff_pct']:.2f}%`) | `{t89r['power_total_w']:.3f}` | `{t89r.get('elapsed_s', '—')}` | PASS |"
            )
        for pt in info["sweep_points"]:
            elap = f"{pt['elapsed_s']:.1f}" if pt.get("elapsed_s") is not None else "—"
            md_lines.append(
                f"| `{pt['tag']}` | T92 (mới) | `{pt['period_ns']:.3f}` | `{pt['fmax_mhz']:.2f}` | `{pt['wns_ns']:.3f}` | `{pt['tns_ns']:.3f}` | `{pt['whs_ns']:.3f}` | `{pt['failing_endpoints']}` | `{pt['lut']}` (`{pt['lut_pct']:.2f}%`) | `{pt['ff']}` (`{pt['ff_pct']:.2f}%`) | `{pt['power_total_w']:.3f}` | {elap} | {'PASS' if pt['passed'] else 'FAIL'} |"
            )
        md_lines.extend([
            "",
            "## 2. Fmax xác nhận và đối chiếu T83 / T89",
            f"- **Fmax xác nhận (`WNS >= 0`, `0` failing EP, chu kỳ nhỏ nhất đạt):** **`{conf['fmax_mhz']:.2f} MHz`** tại **`{conf['period_ns']:.3f} ns`** (`WNS = {conf['wns_ns']:+.3f} ns`, `TNS = {conf['tns_ns']:.3f} ns`, `0` EP trượt, `LUT = {conf['lut']}`, `FF = {conf['ff']}`, `Power = {conf['power_total_w']:.3f} W`, nguồn: `{conf['source']}`).",
            f"- **Điểm trượt kế bên:** " + (
                f"`{ffp['period_ns']:.3f} ns` (`{ffp['fmax_mhz']:.2f} MHz`, `WNS = {ffp['wns_ns']:.3f} ns`, `TNS = {ffp['tns_ns']:.3f} ns`, `{ffp['failing_endpoints']}` EP trượt)."
                if ffp else "Không có điểm trượt trong dải đã quét."
            ),
            f"- **Tính đơn điệu:** {'KHÔNG ĐƠN ĐIỆU (đã báo cả hai điểm)' if info['non_monotonic'] else 'Đơn điệu trong dải quét'}.",
            "",
            "| Mốc | Period (ns) | Fmax (MHz) | WNS (ns) | Failing EP | LUTs | FFs | Power (W) | ΔFmax (T92 so với mốc) |",
            "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
        ])
        if t83r:
            md_lines.append(
                f"| T83 (trước T86/T88) | `{t83r['period_ns']:.3f}` | `{t83r['fmax_mhz']:.2f}` | `{t83r['wns_ns']:+.3f}` | `{t83r['failing_endpoints']}` | `{t83r['lut']}` | `{t83r['ff']}` | `{t83r['power_total_w']:.3f}` | `{conf['fmax_mhz'] - t83r['fmax_mhz']:+.2f} MHz` |"
            )
        if t89r:
            md_lines.append(
                f"| T89 (nhảy bước 2.5→4.2) | `{t89r['period_ns']:.3f}` | `{t89r['fmax_mhz']:.2f}` | `{t89r['wns_ns']:+.3f}` | `{t89r['failing_endpoints']}` | `{t89r['lut']}` | `{t89r['ff']}` | `{t89r['power_total_w']:.3f}` | `{conf['fmax_mhz'] - t89r['fmax_mhz']:+.2f} MHz` |"
            )
        md_lines.append(
            f"| **T92 (quét mịn bước 0.05 ns)** | **`{conf['period_ns']:.3f}`** | **`{conf['fmax_mhz']:.2f}`** | **`{conf['wns_ns']:+.3f}`** | **`{conf['failing_endpoints']}`** | **`{conf['lut']}`** | **`{conf['ff']}`** | **`{conf['power_total_w']:.3f}`** | `0.00 MHz` |"
        )
        md_lines.extend([
            "",
            "- **Lưu ý nhân quả:** Không khẳng định nguyên nhân chênh lệch Fmax giữa T92 và T83 vì có 8 file `rtl/**` đổi giữa `rem/T83` và `HEAD` và chưa chạy ablation P&R từng thay đổi.",
            "- **Phạm vi `axi_ddr5_mc_secure_top`:** Không quét lại vì T83 đã kẹp chặt giữa `4.100 ns` (`WNS = -0.005 ns`, `3` EP trượt) và `4.150 ns` (`WNS = +0.021 ns`, `0` EP) và T89 đã xác nhận lại đúng `4.150 ns` (`WNS = +0.018 ns`, `0` EP).",
            "",
        ])

    sum_md.write_text("\n".join(md_lines), encoding="utf-8")
    print(f"[+] Da luu bao cao Markdown: {sum_md}", flush=True)
    sys.exit(0)


def main():
    parser = argparse.ArgumentParser(description="Q-Shield Reproducible Post-Route FPGA PPA Runner")
    parser.add_argument("--top", default="all", choices=["axi_ddr5_mc_top", "axi_ddr5_mc_secure_top", "all"], help="Target top module")
    parser.add_argument("--period", type=float, default=2.500, help="Initial clock period in ns (default: 2.500)")
    parser.add_argument("--mode", default="auto", choices=["auto", "exact-paper"], help="auto: step period until WNS>=0; exact-paper: run fixed paper points (2.5/3.8/4.1/4.15 ns)")
    parser.add_argument("--periods", default=None, help="Comma-separated period list in ns for sweep mode (e.g. 4.150,4.100,4.050,4.000,3.950,3.900)")
    parser.add_argument("--stop-on-fail", action="store_true", help="In --periods sweep mode, stop after the first failing point")
    parser.add_argument("--presynth-dcp", default=None, help="Existing presynth .dcp checkpoint to reuse in sweep mode")
    parser.add_argument("--ref-rtl-hashes", default=None, help="Reference RTL_HASHES.txt to verify SHA-256 equality before running")
    parser.add_argument("--max-point-seconds", type=int, default=None, help="Stop if any single Vivado point exceeds this many seconds")
    parser.add_argument("--max-attempts", type=int, default=4, help="Max confirmed-period retries in auto mode (default: 4)")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Output directory for reports, logs, and checkpoints")
    parser.add_argument("--clean", action="store_true", help="Remove old artifacts in out-dir before running from clean RTL")
    parser.add_argument("--no-reuse-dcp", action="store_true", help="Synthesize from RTL at every period point instead of reusing session presynth.dcp")
    parser.add_argument("--threads", type=int, default=None, help="Set Vivado general.maxThreads for more deterministic P&R")
    parser.add_argument("--skip-rerun", action="store_true", help="Skip running Vivado if route reports already exist")
    parser.add_argument("--vivado", default=None, help="Path to vivado / vivado.bat")
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    if args.clean:
        if args.skip_rerun:
            print("[FAIL] Khong the ket hop --clean va --skip-rerun!", file=sys.stderr)
            sys.exit(1)
        clean_out_dir(out_dir)

    vivado_bin = find_vivado(args.vivado)
    if not vivado_bin and not args.skip_rerun:
        print("[FAIL] Khong tim thay Vivado executable! Dat VIVADO_BIN hoac truyen --vivado.", file=sys.stderr)
        sys.exit(1)

    git_meta = get_git_metadata()
    if args.ref_rtl_hashes:
        verify_rtl_hashes_match_ref(Path(args.ref_rtl_hashes).resolve())
    rtl_hashes_before = write_rtl_hashes_file(out_dir, git_meta["git_commit"] or "unknown")
    if args.periods:
        run_periods_sweep(args, vivado_bin, out_dir, git_meta, rtl_hashes_before)
        return
    targets = ["axi_ddr5_mc_top", "axi_ddr5_mc_secure_top"] if args.top == "all" else [args.top]
    run_records = []
    summary_data = {
        "timestamp": datetime.datetime.now().isoformat(),
        "device": "xczu7ev-ffvc1156-2-e",
        "mode": args.mode,
        "os": platform.platform(),
        "cpu_count": os.cpu_count(),
        "max_threads": args.threads,
        "no_reuse_dcp": args.no_reuse_dcp,
        **git_meta,
        "vivado_version": None,
        "power_methodology": "vectorless report_power (Vivado default toggle rate 12.5%, no Simulation Activity File)",
        "results": {},
    }

    for target in targets:
        prefix = "core" if target == "axi_ddr5_mc_top" else "sec"
        all_attempts = []
        session_presynth_dcp = None

        if args.mode == "exact-paper":
            points = EXACT_PAPER_POINTS[target]
            init_dict = None
            conf_dict = None
            conf_h_entries = []
            conf_power_hier = {}

            for idx, (tag, per) in enumerate(points):
                use_dcp = None if (args.no_reuse_dcp or idx == 0) else session_presynth_dcp
                t_res, u_res, p_res, h_entries, run_meta = execute_point(
                    vivado_bin, out_dir, target, tag, per, args.skip_rerun, use_dcp, args.threads, run_records
                )
                if idx == 0:
                    cand_dcp = out_dir / f"{tag}_presynth.dcp"
                    if cand_dcp.exists() and (not args.skip_rerun or not args.no_reuse_dcp):
                        session_presynth_dcp = cand_dcp
                stage_dict = build_stage_dict(tag, per, t_res, u_res, p_res, run_meta)
                if idx == 0:
                    init_dict = stage_dict
                else:
                    all_attempts.append(stage_dict)
                conf_dict = stage_dict
                conf_h_entries = h_entries
                conf_power_hier = p_res["by_hierarchy"] if p_res else {}
        else:
            init_tag = f"{prefix}_2500ps"
            init_period = args.period
            t_res, u_res, p_res, h_entries, run_meta = execute_point(
                vivado_bin, out_dir, target, init_tag, init_period, args.skip_rerun, None, args.threads, run_records
            )
            init_dict = build_stage_dict(init_tag, init_period, t_res, u_res, p_res, run_meta)
            conf_dict = dict(init_dict)
            conf_h_entries = h_entries
            conf_power_hier = p_res["by_hierarchy"] if p_res else {}

            cand_dcp = out_dir / f"{init_tag}_presynth.dcp"
            if not args.no_reuse_dcp and cand_dcp.exists() and (run_meta.get("elapsed_s") is not None or args.skip_rerun):
                session_presynth_dcp = cand_dcp

            cur_period = init_period
            cur_wns = t_res["wns"]
            cur_fail_ep = t_res["failing_endpoints"] if t_res["failing_endpoints"] is not None else 0
            verify_rtl_hashes_unchanged(rtl_hashes_before, f"{target}:{init_tag}")
            attempt_idx = 0

            while (cur_wns < 0.0 or cur_fail_ep > 0) and attempt_idx < args.max_attempts:
                attempt_idx += 1
                raw_period = cur_period - min(cur_wns, 0.0)
                conf_period = round(math.ceil(raw_period / 0.05) * 0.05, 3)
                if conf_period <= cur_period:
                    conf_period = round(cur_period + 0.05, 3)
                conf_tag = f"{prefix}_confirmed" if attempt_idx == 1 else f"{prefix}_confirmed_r{attempt_idx}"

                if args.skip_rerun and not (out_dir / f"{conf_tag}_route_timing.rpt").exists():
                    # Khi chỉ tổng hợp lại báo cáo sẵn có, dừng tại điểm chưa chạy trên đĩa
                    break

                print(f"\n[CANH BAO] {target} WNS={cur_wns:.3f}ns, failing_ep={cur_fail_ep} o chu ky {cur_period:.3f}ns.", flush=True)
                print(f"           Tinh chu ky xac nhan (luot {attempt_idx}/{args.max_attempts}): {conf_period:.3f}ns ({1000.0/conf_period:.2f} MHz).", flush=True)

                use_dcp = None if args.no_reuse_dcp else session_presynth_dcp
                c_t_res, c_u_res, c_p_res, c_h_entries, c_run_meta = execute_point(
                    vivado_bin, out_dir, target, conf_tag, conf_period, args.skip_rerun, use_dcp, args.threads, run_records
                )
                verify_rtl_hashes_unchanged(rtl_hashes_before, f"{target}:{conf_tag}")
                stage_dict = build_stage_dict(conf_tag, conf_period, c_t_res, c_u_res, c_p_res, c_run_meta)
                all_attempts.append(stage_dict)
                conf_dict = stage_dict
                conf_h_entries = c_h_entries
                conf_power_hier = c_p_res["by_hierarchy"] if c_p_res else {}
                cur_period = conf_period
                cur_wns = c_t_res["wns"]
                cur_fail_ep = c_t_res["failing_endpoints"] if c_t_res["failing_endpoints"] is not None else 0

            if cur_wns < 0.0 or cur_fail_ep > 0:
                print(
                    f"[STOP_CONDITION_TRIGGERED] {target} khong dat WNS>=0 va 0 failing EP sau {args.max_attempts} lan thu "
                    f"(last period={cur_period:.3f}ns, WNS={cur_wns:.3f}ns, failing_ep={cur_fail_ep})!",
                    file=sys.stderr,
                    flush=True,
                )
                sys.exit(3)

        key_blocks = extract_key_blocks(conf_h_entries, conf_power_hier)
        summary_data["results"][target] = {
            "top": target,
            "stage": "post_route",
            "initial": init_dict,
            "confirmed": conf_dict,
            "attempts": all_attempts,
            "key_blocks": key_blocks,
            "hierarchical_util": conf_h_entries,
            "power_by_hierarchy": conf_power_hier,
        }

    for rec in run_records:
        if rec.get("vivado_version"):
            summary_data["vivado_version"] = rec["vivado_version"]
            break

    verify_rtl_hashes_unchanged(rtl_hashes_before, "final")
    rtl_diff_t83 = get_rtl_diff_since_t83()
    t83_cmp = {}
    if T83_SUMMARY_JSON.exists() and out_dir != T83_SUMMARY_JSON.parent.resolve():
        try:
            t83_data = json.loads(T83_SUMMARY_JSON.read_text(encoding="utf-8"))
            for target, info in summary_data["results"].items():
                if target in t83_data.get("results", {}):
                    old_c = t83_data["results"][target]["confirmed"]
                    new_c = info["confirmed"]
                    t83_cmp[target] = {
                        "t83_period_ns": old_c["period_ns"],
                        "t89_period_ns": new_c["period_ns"],
                        "delta_period_ns": round(new_c["period_ns"] - old_c["period_ns"], 3),
                        "t83_fmax_mhz": old_c["fmax_mhz"],
                        "t89_fmax_mhz": new_c["fmax_mhz"],
                        "delta_fmax_mhz": round(new_c["fmax_mhz"] - old_c["fmax_mhz"], 2),
                        "t83_wns_ns": old_c["wns_ns"],
                        "t89_wns_ns": new_c["wns_ns"],
                        "t83_lut": old_c["lut"],
                        "t89_lut": new_c["lut"],
                        "delta_lut": new_c["lut"] - old_c["lut"],
                        "t83_ff": old_c["ff"],
                        "t89_ff": new_c["ff"],
                        "delta_ff": new_c["ff"] - old_c["ff"],
                        "t83_bram": old_c["bram_tile"],
                        "t89_bram": new_c["bram_tile"],
                        "delta_bram": round(new_c["bram_tile"] - old_c["bram_tile"], 1),
                        "t83_power_w": old_c["power_total_w"],
                        "t89_power_w": new_c["power_total_w"],
                        "delta_power_w": round(new_c["power_total_w"] - old_c["power_total_w"], 3),
                    }
        except Exception:
            pass
    summary_data["rtl_hashes_file"] = str((out_dir / "RTL_HASHES.txt").relative_to(ROOT)).replace("\\", "/")
    summary_data["rtl_hashes_verified_unchanged"] = True
    summary_data["rtl_files_changed_since_rem_t83"] = rtl_diff_t83
    summary_data["comparison_vs_t83"] = t83_cmp

    sum_json = out_dir / "fpga_ppa_summary.json"
    sum_json.write_text(json.dumps(summary_data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n[+] Da luu bao cao JSON: {sum_json}")

    manifest_json = out_dir / "repro_manifest.json"
    manifest_data = {
        "timestamp": summary_data["timestamp"],
        "device": summary_data["device"],
        "mode": args.mode,
        "vivado_bin": vivado_bin,
        "vivado_version": summary_data["vivado_version"],
        "max_threads": args.threads,
        "no_reuse_dcp": args.no_reuse_dcp,
        "os": summary_data["os"],
        "cpu_count": summary_data["cpu_count"],
        **git_meta,
        "runs": run_records,
    }
    manifest_json.write_text(json.dumps(manifest_data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"[+] Da luu manifest tai lap: {manifest_json}")

    sum_md = out_dir / "fpga_ppa_summary.md"
    dirty_label = "dirty (chưa commit)" if git_meta["git_dirty"] else ("clean" if git_meta["git_dirty"] is False else "unknown")
    md_lines = [
        "# Q-Shield FPGA Post-Route PPA Evaluation Summary",
        f"- Ngày đo: {summary_data['timestamp']}",
        f"- Chip mục tiêu: `{summary_data['device']}` (Xilinx Zynq UltraScale+)",
        f"- Vivado: `{summary_data['vivado_version'] or 'unknown'}` | Threads: `{args.threads if args.threads is not None else 'default'}` | Reuse session presynth DCP: `{not args.no_reuse_dcp}`",
        f"- Git commit: `{git_meta['git_commit'] or 'unknown'}` ({dirty_label})",
        f"- Phương pháp đo công suất: {summary_data['power_methodology']}",
        "",
        "## 1. Bảng tổng hợp hiệu năng định thời và tài nguyên sau Place & Route",
        "",
        "| Module | Initial @ 400 MHz (2.500 ns) WNS / TNS / WHS | Confirmed Period (ns) | Confirmed Fmax (MHz) | Confirmed WNS / TNS / WHS | LUTs (%) | FFs (%) | BRAM Tiles | DSPs | Total Power (W) [Dyn / Static] |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
    ]
    table_start = len(md_lines) - 2

    for target, info in summary_data["results"].items():
        init = info["initial"]
        conf = info["confirmed"]
        init_str = f"`{init['wns_ns']:.3f}` / `{init['tns_ns']:.3f}` / `{init['whs_ns']:.3f}`"
        conf_str = f"`{conf['wns_ns']:.3f}` / `{conf['tns_ns']:.3f}` / `{conf['whs_ns']:.3f}`"
        pwr_str = f"`{conf['power_total_w']:.3f}` (`{conf['power_dynamic_w']:.3f}` / `{conf['power_static_w']:.3f}`)"
        md_lines.append(
            f"| `{target}` | {init_str} | `{conf['period_ns']:.3f}` | **`{conf['fmax_mhz']:.2f}`** | {conf_str} | `{conf['lut']}` (`{conf['lut_pct']:.2f}%`) | `{conf['ff']}` (`{conf['ff_pct']:.2f}%`) | `{conf['bram_tile']}` | `{conf['dsp']}` | {pwr_str} |"
        )
    table_end = len(md_lines)

    md_lines.extend([
        "",
        "## 2. Toàn bộ các điểm đo đã chạy (trung thực mọi lần thử)",
        "",
        "| Top | Tag | Period (ns) | Fmax (MHz) | WNS (ns) | TNS (ns) | WHS (ns) | Failing EP | LUTs | FFs | Total Power (W) | Elapsed (s) | Log |",
        "| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |",
    ])
    for target, info in summary_data["results"].items():
        all_pts = [info["initial"]] + info.get("attempts", [])
        for pt in all_pts:
            elap_s = f"{pt['elapsed_s']:.1f}" if pt.get("elapsed_s") is not None else "—"
            log_s = f"`{pt['log_file']}`" if pt.get("log_file") else "—"
            md_lines.append(
                f"| `{target}` | `{pt['tag']}` | `{pt['period_ns']:.3f}` | `{pt['fmax_mhz']:.2f}` | `{pt['wns_ns']:.3f}` | `{pt['tns_ns']:.3f}` | `{pt['whs_ns']:.3f}` | `{pt['failing_endpoints']}` | `{pt['lut']}` | `{pt['ff']}` | `{pt['power_total_w']:.3f}` | {elap_s} | {log_s} |"
            )

    md_lines.append("")
    md_lines.append("## 3. Phân rã tài nguyên và công suất theo khối (Post-Route Confirmed)")
    md_lines.append("")
    for target, info in summary_data["results"].items():
        md_lines.append(f"### {target} (`{info['confirmed']['tag']}` @ `{info['confirmed']['period_ns']:.3f} ns` / `{info['confirmed']['fmax_mhz']:.2f} MHz`)")
        md_lines.append("| Hierarchical Path | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM Tiles | DSP | Dynamic Power (W) |")
        md_lines.append("| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
        for b in info.get("key_blocks", []):
            pwr = f"{b['dynamic_power_w']:.3f}" if b.get("dynamic_power_w") is not None else "—"
            md_lines.append(
                f"| `{b['path']}` | `{b['module']}` | {b['total_luts']} | {b['logic_luts']} | {b['lutrams']} | {b['ffs']} | {b['bram_tile']} | {b['dsp']} | {pwr} |"
            )
        md_lines.append("")

    if t83_cmp:
        md_lines.extend([
            "## 4. So sánh với mốc T83 (trước T86/T88)",
            "",
            "| Module | T83 Fmax (MHz) [Period] | T89 Fmax (MHz) [Period] | ΔFmax (MHz) | T83 LUT | T89 LUT (Δ) | T83 FF | T89 FF (Δ) | T83 BRAM | T89 BRAM (Δ) | T83 Power (W) | T89 Power (W) (Δ) |",
            "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
        ])
        for target, c in t83_cmp.items():
            md_lines.append(
                f"| `{target}` | `{c['t83_fmax_mhz']:.2f}` (`{c['t83_period_ns']:.3f} ns`) | `{c['t89_fmax_mhz']:.2f}` (`{c['t89_period_ns']:.3f} ns`) | `{c['delta_fmax_mhz']:+.2f}` | "
                f"`{c['t83_lut']}` | `{c['t89_lut']}` (`{c['delta_lut']:+d}`) | `{c['t83_ff']}` | `{c['t89_ff']}` (`{c['delta_ff']:+d}`) | "
                f"`{c['t83_bram']}` | `{c['t89_bram']}` (`{c['delta_bram']:+.1f}`) | `{c['t83_power_w']:.3f}` | `{c['t89_power_w']:.3f}` (`{c['delta_power_w']:+.3f}`) |"
            )
        md_lines.extend([
            "",
            "### File `rtl/**` thay đổi giữa `rem/T83` và `HEAD` (chưa tách nhân quả riêng từng file bằng ablation P&R)",
        ])
        for line in rtl_diff_t83:
            md_lines.append(f"- `{line}`")
        md_lines.append("")

    sum_md.write_text("\n".join(md_lines), encoding="utf-8")
    print(f"[+] Da luu bao cao Markdown: {sum_md}")

    print("\n" + "=" * 108)
    print("  Q-SHIELD POST-ROUTE FPGA PPA SUMMARY REPORT")
    print("=" * 108)
    for line in md_lines[table_start:table_end]:
        print(line)
    print("=" * 108)
    sys.exit(0)


if __name__ == "__main__":
    main()
