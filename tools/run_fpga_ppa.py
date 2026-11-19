#!/usr/bin/env python3
# tools/run_fpga_ppa.py
# Chức năng: Tự động chạy P&R Vivado và tổng hợp báo cáo PPA FPGA sau route trên xczu7ev cho paper (T83).

import argparse
import datetime
import glob
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
DEFAULT_OUT_DIR = ROOT / "reports" / "paper" / "fpga"
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


def run_vivado(vivado_bin, out_dir: Path, top, tag, period, presynth_dcp=None, max_threads=None):
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
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    elapsed = time.time() - t0
    print(f">>> VIVADO KET THUC: exit={p.returncode}, thoi gian={elapsed:.1f}s, log={log_path.name}", flush=True)
    if p.returncode != 0:
        print("[STDOUT/STDERR VIVADO TAIL]:\n" + (p.stdout + "\n" + p.stderr)[-3000:], flush=True)
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


def execute_point(vivado_bin, out_dir: Path, target, tag, period_ns, skip_rerun, presynth_dcp, max_threads, run_records):
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


def main():
    parser = argparse.ArgumentParser(description="Q-Shield Reproducible Post-Route FPGA PPA Runner")
    parser.add_argument("--top", default="all", choices=["axi_ddr5_mc_top", "axi_ddr5_mc_secure_top", "all"], help="Target top module")
    parser.add_argument("--period", type=float, default=2.500, help="Initial clock period in ns (default: 2.500)")
    parser.add_argument("--mode", default="auto", choices=["auto", "exact-paper"], help="auto: step period until WNS>=0; exact-paper: run fixed paper points (2.5/3.8/4.1/4.15 ns)")
    parser.add_argument("--max-attempts", type=int, default=5, help="Max confirmed-period retries in auto mode (default: 5)")
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
            attempt_idx = 0

            while cur_wns < 0.0 and attempt_idx < args.max_attempts:
                attempt_idx += 1
                raw_period = cur_period - cur_wns
                conf_period = round(math.ceil(raw_period / 0.05) * 0.05, 3)
                if conf_period <= cur_period:
                    conf_period = round(cur_period + 0.05, 3)
                conf_tag = f"{prefix}_confirmed" if attempt_idx == 1 else f"{prefix}_confirmed_r{attempt_idx}"

                if args.skip_rerun and not (out_dir / f"{conf_tag}_route_timing.rpt").exists():
                    # Khi chỉ tổng hợp lại báo cáo sẵn có, dừng tại điểm chưa chạy trên đĩa
                    break

                print(f"\n[CANH BAO] {target} WNS={cur_wns:.3f}ns < 0 o chu ky {cur_period:.3f}ns.", flush=True)
                print(f"           Tinh chu ky xac nhan (luot {attempt_idx}): {conf_period:.3f}ns ({1000.0/conf_period:.2f} MHz).", flush=True)

                use_dcp = None if args.no_reuse_dcp else session_presynth_dcp
                c_t_res, c_u_res, c_p_res, c_h_entries, c_run_meta = execute_point(
                    vivado_bin, out_dir, target, conf_tag, conf_period, args.skip_rerun, use_dcp, args.threads, run_records
                )
                stage_dict = build_stage_dict(conf_tag, conf_period, c_t_res, c_u_res, c_p_res, c_run_meta)
                all_attempts.append(stage_dict)
                conf_dict = stage_dict
                conf_h_entries = c_h_entries
                conf_power_hier = c_p_res["by_hierarchy"] if c_p_res else {}
                cur_period = conf_period
                cur_wns = c_t_res["wns"]

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
