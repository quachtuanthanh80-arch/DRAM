#!/usr/bin/env python3
"""
Script: tools/run_security_eval.py
Description: Danh gia bao mat RowHammer/RowPress tren RTL axi_ddr5_mc_top (T82).
             Moi so lieu deu doc tu mo phong Icarus Verilog that cua RTL + dram_model.sv
             va doi chieu voi gioi han ly thuyet trong docs/security_bound.md.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import datetime
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = ROOT / "build" / "security_eval"
REPORT_DIR = ROOT / "reports" / "paper" / "security"

RH_EVAL_RE = re.compile(r"^\[RH_EVAL_RESULT\]\s+(.*)$", re.MULTILINE)
R82_RE = re.compile(r"^\[R82_RESULT\]\s+(.*)$", re.MULTILINE)
DIAG_ROW_RE = re.compile(r"^\[RH_DIAG_ROW\]\s+(.*)$", re.MULTILINE)
TB_RESULT_RE = re.compile(r"\[TB_RESULT\]\s+checks=(\d+)\s+fails=(\d+)\s+xfails=(\d+)")

# Danh sach nguon RTL dung chuan cho axi_ddr5_mc_top (tu run_iverilog_regression.py)
RTL_SOURCES = [
    "rtl/backend/secded_72_64_pkg.sv",
    "tb/common/ddr5_jedec_bin_pkg.sv",
    "rtl/cdc/rst_sync.sv",
    "rtl/bus/axi4_skid_buffer.sv",
    "rtl/frontend/axi_slave_frontend.sv",
    "rtl/frontend/wdata_buffer.sv",
    "rtl/frontend/wr_data_store.sv",
    "rtl/frontend/axi_burst_splitter.sv",
    "rtl/frontend/rd_issue_queue.sv",
    "rtl/frontend/domain_bank_coloring.sv",
    "rtl/core/scarf_dram_randomizer.sv",
    "rtl/frontend/addr_mapper_ddr5.sv",
    "rtl/core/reorder_buffer_rob.sv",
    "rtl/core/fault_hardened_csr.sv",
    "rtl/crypto/multi_vm_key_table.sv",
    "rtl/core/pxor_hash_engine.sv",
    "rtl/core/sdc_resilient_filter.sv",
    "rtl/core/adaptive_threshold_engine.sv",
    "rtl/backend/directed_refresh_manager.sv",
    "rtl/core/qos_scheduler_queue.sv",
    "rtl/backend/slack_aware_arbiter.sv",
    "rtl/backend/ddr5_cmd_engine.sv",
    "rtl/backend/ecc_scrubber.sv",
    "rtl/memory/bus_scrambler.sv",
    "rtl/memory/scrambler_ks_pipe.sv",
    "rtl/bus/perf_monitor_unit.sv",
    "rtl/top/bank_credit_ctrl.sv",
    "rtl/top/axi_ddr5_mc_top.sv",
    "tb/common/dfi_jedec_checker.sv",
    "tb/common/dram_model.sv",
    "tb/security/tb_rh_eval.sv",
]


def find_tool(name: str, default_dir: str = r"D:\iverilog\bin") -> str:
    found = shutil.which(name)
    if found:
        return found
    fallback = Path(default_dir) / f"{name}.exe"
    if fallback.is_file():
        return str(fallback)
    return name


def get_git_commit() -> str:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout.strip()
    except Exception:
        return "unknown"


def pxor_hash(tag_22: int, seed_64: int) -> int:
    eff_seed = 0xA5A55A5A01234567 if seed_64 == 0 else (seed_64 & 0xFFFFFFFFFFFFFFFF)
    out = 0
    for h in range(8):
        bit = 0
        for t in range(22):
            idx1 = (t * 3 + h * 7) % 64
            idx2 = (t * 5 + h + 13) % 64
            coeff = ((eff_seed >> idx1) & 1) ^ ((eff_seed >> idx2) & 1) ^ (1 if t == h else 0)
            if coeff and ((tag_22 >> t) & 1):
                bit ^= 1
        out |= bit << h
    return out


def sdc_hashes(bg: int, bank: int, row: int, seed_64: int) -> tuple[int, int]:
    tag = ((bg & 0x7) << 19) | ((bank & 0x3) << 17) | (row & 0x1FFFF)
    seed_b = ((~seed_64) & 0xFFFFFFFFFFFFFFFF) ^ 0xF0F00F0FAAAA5555
    return pxor_hash(tag, seed_64), pxor_hash(tag, seed_b)


def find_pxor_collision(target_bg: int, target_bk: int, target_row: int, seed_64: int) -> tuple[int, int, int]:
    tgt_a, tgt_b = sdc_hashes(target_bg, target_bk, target_row, seed_64)
    # Uu tien bank 1..2 trong bg 1..5 de khong cham ngong da bank SledgeHammer (<= 2 bank)
    for bank_list in ((1, 2), (0, 3)):
        for bg in range(1, 6):
            for bk in bank_list:
                for row in range(0x0400, 0x4000):
                    ha, hb = sdc_hashes(bg, bk, row, seed_64)
                    if ha == tgt_a and hb == tgt_b:
                        return bg, bk, row
    raise RuntimeError(f"Khong tim thay va cham PXOR 2 bang cho ({target_bg},{target_bk},0x{target_row:x})")


def find_non_colliding_far_row(seed_64: int) -> int:
    tgt_ha = set()
    tgt_hb = set()
    for row in (0x00FD, 0x00FE, 0x00FF, 0x0101, 0x0102, 0x0103):
        ha, hb = sdc_hashes(0, 0, row, seed_64)
        tgt_ha.add(ha)
        tgt_hb.add(hb)
    for r in range(0x0300, 0x4000):
        ha, hb = sdc_hashes(0, 0, r, seed_64)
        if (ha not in tgt_ha) and (hb not in tgt_hb):
            return r
    raise RuntimeError("Khong tim thay far_row khong trung bin PXOR")


def parse_kv_line(line: str) -> dict[str, int]:
    out: dict[str, int] = {}
    for tok in line.strip().split():
        if "=" not in tok:
            continue
        k, v = tok.split("=", 1)
        if v.startswith("0x") or v.startswith("0X"):
            out[k] = int(v, 16)
        else:
            try:
                out[k] = int(v)
            except ValueError:
                pass
    return out


def compile_tb(iverilog_bin: str, radius: int) -> Path:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    vvp_path = BUILD_DIR / f"tb_rh_eval_r{radius}.vvp"
    sources = [str(ROOT / rel) for rel in RTL_SOURCES]
    cmd = [
        iverilog_bin,
        "-g2012",
        "-Wall",
        "-I",
        str(ROOT / "tb" / "common"),
        f"-Ptb_rh_eval.RH_RADIUS={radius}",
        "-s",
        "tb_rh_eval",
        "-o",
        str(vvp_path),
    ] + sources
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if res.returncode != 0:
        raise RuntimeError(f"Bien dich that bai (R={radius}):\n{res.stdout}\n{res.stderr}")
    return vvp_path


def run_sim_worker(job: dict) -> dict:
    vvp_bin = job["vvp_bin"]
    vvp_path = job["vvp_path"]
    plusargs = job["plusargs"]
    timeout_s = job.get("timeout_s", 1800)
    cmd = [vvp_bin, str(vvp_path)] + plusargs
    log_file = BUILD_DIR / f"{job['run_id']}.log"
    t0 = time.time()
    try:
        res = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
        )
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        rc = res.returncode
    except subprocess.TimeoutExpired as e:
        out_s = e.stdout.decode("utf-8", errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err_s = e.stderr.decode("utf-8", errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        out = out_s + "\n" + err_s
        elapsed = round(time.time() - t0, 3)
        log_file.write_text(f"CMD: {' '.join(cmd)}\nRC: -1 (TIMEOUT after {timeout_s}s)\n\n{out}", encoding="utf-8")
        return {
            **job,
            "status": "TIMEOUT",
            "rc": -1,
            "runtime_s": elapsed,
            "checks": 0,
            "fails": 1,
            "xfails": 0,
            "parsed": {},
            "r82_lines": [],
            "has_tb_result": False,
            "log_path": str(log_file.relative_to(ROOT)).replace("\\", "/"),
        }

    elapsed = round(time.time() - t0, 3)
    log_file.write_text(f"CMD: {' '.join(cmd)}\nRC: {rc}\n\n{out}", encoding="utf-8")

    tb_m = TB_RESULT_RE.findall(out)
    checks = fails = xfails = 0
    if tb_m:
        checks, fails, xfails = (int(x) for x in tb_m[-1])

    rh_m = RH_EVAL_RE.findall(out)
    parsed = parse_kv_line(rh_m[-1]) if rh_m else {}
    r82_rows = []
    for line in R82_RE.findall(out):
        r82_rows.append(line.strip())
    diag_rows = []
    for line in DIAG_ROW_RE.findall(out):
        diag_rows.append(parse_kv_line(line))

    return {
        **job,
        "rc": rc,
        "runtime_s": elapsed,
        "checks": checks,
        "fails": fails,
        "xfails": xfails,
        "parsed": parsed,
        "r82_lines": r82_rows,
        "diag_rows": diag_rows,
        "has_tb_result": bool(tb_m),
        "log_path": str(log_file.relative_to(ROOT)).replace("\\", "/"),
    }


def t_max_formula(n_rh: int, radius: int, lam: int) -> int:
    # Theo docs/security_bound.md muc 3 (da sua R-83): T_max(N_RH, R, Lambda) = floor((N_RH - 2 - Lambda) / (4R))
    return (n_rh - 2 - lam) // (4 * radius)


def evaluate_row(raw: dict, lam_cal: int, bw_base_gbps: float) -> dict:
    p = raw["parsed"]
    radius = raw["radius"]
    n_rh = raw["nrh"]
    thresh = raw["thresh"]
    group = raw["bound_group"]

    d_tgt = p.get("d_max_target", -1)
    d_glb = p.get("d_max_global", -1)
    d_max = max(d_tgt, d_glb)
    lam_all = p.get("lambda_all", 0)
    lam_usr = p.get("lambda_user", 0)
    l_mit = p.get("l_mit_cyc", 0)
    lam_eff = max(lam_cal, lam_all)

    b1_no_epoch = 2 * radius * thresh + 1 + lam_eff
    b1_with_epoch = 4 * radius * thresh + 1 + lam_eff
    b1_no_epoch_local = 2 * radius * thresh + 1 + lam_all

    dummy_resets = p.get("dummy_resets", 0)
    bin_wipes = p.get("bin_wipes", 0)
    b2_exp_single = round(thresh * (1.0 + 2.0 * dummy_resets / 256.0), 2)
    b2_exp_double = round(2.0 * b2_exp_single, 2)
    phys_ceil = (8192 * 1560) // 20  # 638976 ACTs/bank trong mot tREFW

    meas_cyc = max(1, p.get("meas_cyc", 1))
    ben_beats = p.get("ben_beats", 0)
    bw_gbps = round((ben_beats * 8.0) / (meas_cyc * 2.5), 4)
    bw_ratio_pct = round((bw_gbps / bw_base_gbps) * 100.0, 2) if bw_base_gbps > 0 else 0.0
    d_over_nrh = round(d_max / float(n_rh), 4)

    jedec_viol = p.get("jedec_viol", -1)
    dram_err = p.get("dram_err", -1)

    if raw["rc"] != 0 or not raw["has_tb_result"] or raw["fails"] > 0 or jedec_viol != 0 or dram_err != 0 or not p:
        verdict = "SIM_ERROR"
    elif group == "B1":
        if d_max > b1_no_epoch or d_max > b1_with_epoch or d_over_nrh >= 1.0:
            verdict = "B1_VIOLATION_STOP"
        else:
            verdict = "PASS_B1"
    elif group == "B2":
        if d_max > b1_no_epoch or d_over_nrh >= 1.0:
            verdict = "FINDING_EXCEEDS_B1"
        else:
            verdict = "PASS_UNDER_B1"
    elif group == "PHYS":
        if d_max > phys_ceil:
            verdict = "PHYS_VIOLATION_STOP"
        elif d_over_nrh >= 1.0 or d_max > b1_no_epoch:
            verdict = "FINDING_KNOWN_SEED_BYPASS"
        else:
            verdict = "PASS_UNDER_PHYS"
    else:
        verdict = "UNKNOWN"

    return {
        "run_id": raw["run_id"],
        "case_name": raw["case_name"],
        "case_id": raw["case_id"],
        "bound_group": group,
        "radius": radius,
        "n_rh": n_rh,
        "n_agg": raw.get("n_agg", 1),
        "thresh_t": thresh,
        "d_max_target": d_tgt,
        "d_max_global": d_glb,
        "d_max": d_max,
        "d_over_nrh": d_over_nrh,
        "lambda_cal": lam_cal,
        "lambda_meas_all": lam_all,
        "lambda_meas_user": lam_usr,
        "l_mit_cyc": l_mit,
        "b1_no_epoch": b1_no_epoch,
        "b1_no_epoch_local": b1_no_epoch_local,
        "b1_with_epoch": b1_with_epoch,
        "b2_exp_single": b2_exp_single,
        "b2_exp_double": b2_exp_double,
        "phys_ceil": phys_ceil,
        "rp_open_max": p.get("rp_open_max", 0),
        "rp_single_max": p.get("rp_single_max", 0),
        "rp_alerts": p.get("rp_alerts", 0),
        "tras_clamps": p.get("tras_clamps", 0),
        "total_acts": p.get("total_acts", 0),
        "refs": p.get("refs", 0),
        "rfms": p.get("rfms", 0),
        "mit_done": p.get("mit_done", 0),
        "max_key": f"0x{p.get('max_key', 0):08x}",
        "dummy_resets": dummy_resets,
        "bin_wipes": bin_wipes,
        "meas_cyc": meas_cyc,
        "ben_beats": ben_beats,
        "ben_bw_gbps": bw_gbps,
        "ben_bw_pct_base": bw_ratio_pct,
        "jedec_viol": jedec_viol,
        "dram_err": dram_err,
        "checks": raw["checks"],
        "fails": raw["fails"],
        "runtime_s": raw["runtime_s"],
        "verdict": verdict,
        "log_path": raw.get("log_path", ""),
    }


def build_jobs_for_radius(
    vvp_path: Path,
    vvp_bin: str,
    radius: int,
    nrh_list: list[int],
    lam_cal: int,
    seed_64: int,
    coll_a: tuple[int, int, int],
    coll_b: tuple[int, int, int],
    far_row: int,
    quick: bool,
    full_matrix: bool,
) -> list[dict]:
    seed_hi = (seed_64 >> 32) & 0xFFFFFFFF
    seed_lo = seed_64 & 0xFFFFFFFF
    jobs: list[dict] = []

    if full_matrix:
        attack_specs = [
            ("single_sided", 2, "B1", 1),
            ("double_sided", 3, "B1", 2),
            ("many_sided_4", 4, "B1", 4),
            ("many_sided_8", 4, "B1", 8),
            ("many_sided_16", 4, "B1", 16),
            ("many_sided_32", 4, "B1", 32),
            ("half_double", 5, "B1", 4),
            ("decoy_feinting", 6, "B1", 2),
            ("rowpress_long_hold", 9, "B1", 1),
            ("rowpress_subthresh", 10, "B1", 1),
            ("hash_coll_unknown_seed", 7, "B2", 2),
            ("hash_coll_unknown_seed_2bank", 7, "B2", 2),
            ("hash_coll_known_seed", 8, "PHYS", 2),
        ]
        if quick:
            keep = {
                "single_sided",
                "double_sided",
                "many_sided_8",
                "half_double",
                "decoy_feinting",
                "rowpress_long_hold",
                "rowpress_subthresh",
                "hash_coll_unknown_seed",
                "hash_coll_unknown_seed_2bank",
                "hash_coll_known_seed",
            }
            attack_specs = [s for s in attack_specs if s[0] in keep]
    else:
        # Lat cat kiem chung R = 3 (cfg_victim3_en = 1)
        attack_specs = [
            ("double_sided", 3, "B1", 2),
            ("half_double", 5, "B1", 4),
            ("many_sided_8", 4, "B1", 8),
        ]

    for nrh in nrh_list:
        t_val = t_max_formula(nrh, radius, lam_cal)
        if t_val < 2:
            raise RuntimeError(f"T_max={t_val} < 2 tai N_RH={nrh}, R={radius}, lam={lam_cal}")
        if t_val >= 2048:
            raise RuntimeError(f"T_max={t_val} >= 2048 cho N_RH={nrh} < 4096 (vi pham quy tac BATCH_T82)")

        for cname, cid, bgroup, n_agg in attack_specs:
            if cname == "hash_coll_unknown_seed_2bank" and nrh not in (256, 128):
                continue
            run_id = f"r{radius}_{cname}_nrh{nrh}"
            waves = 2 if quick else (4 if nrh <= 256 else 3)
            dummy_m = 64 if quick else 128
            max_cyc = 400000
            dummy_banks = 1
            if cid == 7:
                if cname == "hash_coll_unknown_seed_2bank":
                    dummy_banks = 2
                    if nrh <= 128:
                        waves = 3
                        dummy_m = 80
                    else:
                        waves = 2
                        dummy_m = 65
                elif nrh <= 128:
                    waves = 3 if quick else 4
                    dummy_m = 80
                elif nrh <= 256:
                    waves = 2 if quick else 3
                    dummy_m = 65
                elif nrh <= 512:
                    waves = 2
                    dummy_m = 50
                else:
                    waves = 2
                    dummy_m = 25
            elif cid == 8:
                margin = 4 if t_val >= 32 else (2 if t_val >= 8 else 1)
                step = max(1, t_val - margin)
                waves = max(waves, ((nrh * 2) // (2 * step)) + 3)
            benign_flag = 0 if cid == 9 else 1
            args = [
                f"+CASE_ID={cid}",
                f"+NRH={nrh}",
                f"+THRESH={t_val}",
                f"+N_AGG={n_agg}",
                f"+BENIGN={benign_flag}",
                "+RP_CURVE=3",
                "+RP_HOLD=850",
                f"+WAVES={waves}",
                f"+DUMMY_M={dummy_m}",
                f"+MAX_CYC={max_cyc}",
                f"+DUMMY_BANKS={dummy_banks}",
                f"+SEED_HI={seed_hi:08X}",
                f"+SEED_LO={seed_lo:08X}",
                f"+DA_BG={coll_a[0]}",
                f"+DA_BK={coll_a[1]}",
                f"+DA_ROW={coll_a[2]}",
                f"+DB_BG={coll_b[0]}",
                f"+DB_BK={coll_b[1]}",
                f"+DB_ROW={coll_b[2]}",
                f"+FAR_ROW={far_row}",
            ]
            jobs.append(
                {
                    "run_id": run_id,
                    "case_name": cname,
                    "case_id": cid,
                    "bound_group": bgroup,
                    "radius": radius,
                    "nrh": nrh,
                    "n_agg": n_agg,
                    "thresh": t_val,
                    "vvp_bin": vvp_bin,
                    "vvp_path": str(vvp_path),
                    "plusargs": args,
                    "timeout_s": 4800,
                }
            )
    return jobs


def build_diag_jobs(
    vvp_r3: Path,
    vvp_bin: str,
    seed_64: int,
    coll_a: tuple[int, int, int],
    coll_b: tuple[int, int, int],
    far_row: int,
) -> list[dict]:
    seed_hi = (seed_64 >> 32) & 0xFFFFFFFF
    seed_lo = seed_64 & 0xFFFFFFFF
    specs = [
        ("r3_hd_diag_base_t10", "half_double_diag_base", 1, 0),
        ("r3_hd_diag_novic3_t10", "half_double_diag_novic3", 0, 0),
        ("r3_hd_diag_nomit_t10", "half_double_diag_nomit", 1, 1),
    ]
    out: list[dict] = []
    for run_id, cname, vic3, ign_mit in specs:
        out.append(
            {
                "run_id": run_id,
                "case_name": cname,
                "case_id": 5,
                "bound_group": "B1",
                "radius": 3,
                "nrh": 128,
                "n_agg": 4,
                "thresh": 10,
                "vvp_bin": vvp_bin,
                "vvp_path": str(vvp_r3),
                "plusargs": [
                    "+CASE_ID=5",
                    "+NRH=128",
                    "+THRESH=10",
                    "+N_AGG=4",
                    "+BENIGN=1",
                    "+RP_CURVE=3",
                    "+RP_HOLD=850",
                    "+WAVES=4",
                    "+DUMMY_M=128",
                    "+MAX_CYC=400000",
                    f"+FORCE_VIC3_EN={vic3}",
                    f"+IGNORE_MIT_ACT={ign_mit}",
                    "+DIAG_DUMP=1",
                    f"+SEED_HI={seed_hi:08X}",
                    f"+SEED_LO={seed_lo:08X}",
                    f"+DA_BG={coll_a[0]}",
                    f"+DA_BK={coll_a[1]}",
                    f"+DA_ROW={coll_a[2]}",
                    f"+DB_BG={coll_b[0]}",
                    f"+DB_BK={coll_b[1]}",
                    f"+DB_ROW={coll_b[2]}",
                    f"+FAR_ROW={far_row}",
                ],
                "timeout_s": 2400,
            }
        )
    return out


def parse_r82_lines(lines: list[str]) -> list[dict]:
    parsed = []
    for line in lines:
        kv = {}
        for tok in line.replace("[R82_RESULT]", "").strip().split():
            if "=" not in tok:
                continue
            k, v = tok.split("=", 1)
            kv[k] = v
        parsed.append(kv)
    return parsed


def write_reports(
    rows: list[dict],
    cal_info: dict,
    diag_controls: list[dict],
    r82_rows: list[dict],
    coll_info: dict,
    seed_64: int,
    quick: bool,
) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    csv_path = REPORT_DIR / "security_eval_table.csv"
    json_path = REPORT_DIR / "security_eval_summary.json"
    md_path = REPORT_DIR / "security_eval_report.md"

    fieldnames = [
        "run_id",
        "case_name",
        "bound_group",
        "radius",
        "n_rh",
        "n_agg",
        "thresh_t",
        "d_max_target",
        "d_max_global",
        "d_max",
        "d_over_nrh",
        "lambda_cal",
        "lambda_meas_all",
        "lambda_meas_user",
        "l_mit_cyc",
        "b1_no_epoch",
        "b1_with_epoch",
        "b2_exp_single",
        "b2_exp_double",
        "phys_ceil",
        "rp_open_max",
        "rp_single_max",
        "rp_alerts",
        "tras_clamps",
        "total_acts",
        "refs",
        "rfms",
        "dummy_resets",
        "bin_wipes",
        "ben_bw_gbps",
        "ben_bw_pct_base",
        "jedec_viol",
        "dram_err",
        "verdict",
    ]
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fieldnames})

    b1_violations = [r for r in rows if r["verdict"] == "B1_VIOLATION_STOP"]
    sim_errors = [r for r in rows if r["verdict"] == "SIM_ERROR"]
    phys_violations = [r for r in rows if r["verdict"] == "PHYS_VIOLATION_STOP"]
    findings_over_1 = [r for r in rows if r["d_over_nrh"] >= 1.0 or r["verdict"] in ("FINDING_EXCEEDS_B1", "FINDING_KNOWN_SEED_BYPASS")]

    summary = {
        "timestamp_iso": datetime.datetime.now().isoformat(),
        "git_commit": get_git_commit(),
        "quick_mode": quick,
        "seed_hex": f"0x{seed_64:016X}",
        "calibration": cal_info,
        "diag_controls": diag_controls,
        "pxor_collisions": coll_info,
        "r82_many_sided_6r": r82_rows,
        "counts": {
            "total_runs": len(rows),
            "b1_violations": len(b1_violations),
            "sim_errors": len(sim_errors),
            "phys_violations": len(phys_violations),
            "cases_d_over_nrh_ge_1_or_exceeds_b1": len(findings_over_1),
        },
        "results": rows,
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    lines = [
        "# Q-Shield RTL RowHammer / RowPress Security Evaluation Report (T82)",
        "",
        f"- Ngày đo: `{summary['timestamp_iso']}`",
        f"- Git commit: `{summary['git_commit']}`",
        f"- Chế độ chạy: `{'quick' if quick else 'full'}` | Seed PXOR: `0x{seed_64:016X}`",
        f"- Băng thông luồng lành tính cơ sở (`benign_only`): **`{cal_info['bw_base_gbps']:.4f} GB/s`** "
        f"(`{cal_info['benign_only']['ben_beats']}` beats trong `{cal_info['benign_only']['meas_cyc']}` chu kỳ @ 400 MHz)",
        "",
        "## 1. Hiệu chuẩn độ trễ giảm thiểu Λ và cấu hình ngưỡng T_max(N_RH, R, Λ)",
        "",
        "| R | Λ hiệu chuẩn (`lambda_cal`) | L_mit đo (chu kỳ) | Cận cấu trúc `ceil(L_mit/20)+1` | D_max đo / B1 (1 epoch) | Nguồn kiểm |",
        "| :---: | :---: | :---: | :---: | :---: | :--- |",
    ]
    for rk, c in sorted(cal_info["per_radius"].items()):
        bound_str = math.ceil(c["l_mit_cyc"] / 20.0) + 1 if c["l_mit_cyc"] > 0 else 1
        lines.append(
            f"| `R={rk}` | `{c['lambda_cal']}` | `{c['l_mit_cyc']}` | `{bound_str}` | "
            f"`{c.get('d_max_target', -1)} / {c.get('b1_no_epoch', -1)}` (bin_wipes={c.get('bin_wipes', 0)}) | "
            f"`{c['run_id']}` (`jedec_viol={c['jedec_viol']}`) |"
        )

    if diag_controls:
        lines += [
            "",
            "## 1b. Đối chứng nguyên nhân `r3_half_double_nrh128` (`R=3, N_RH=128, T=10`)",
            "",
            "| Run ID | `cfg_victim3_en` | `ignore_mit_act` | `d_max_target` | `max_key` | `mit_done` | `dummy_resets` | `lam_all/usr` | `bw` (%) |",
            "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
        ]
        for dc in diag_controls:
            lines.append(
                f"| `{dc['run_id']}` | {dc['force_vic3_en']} | {dc['ignore_mit_act']} | "
                f"**{dc['d_max']}** | `{dc['max_key']}` | {dc['mit_done']} | {dc['dummy_resets']} | "
                f"`{dc['lambda_meas_all']}/{dc['lambda_meas_user']}` | {dc['ben_bw_pct_base']:.1f}% |"
            )

    lines += [
        "",
        "## 2. Bảng kết quả đầy đủ (Mẫu tấn công × Ngưỡng `N_RH`)",
        "",
        "- Ghi chú: `rowpress_long_hold` tắt luồng nền (`BENIGN=0`) để `RFMab` nền không che khuất kích hoạt `o_rowpress_alert`; `rowpress_subthresh` chạy kèm luồng nền (`BENIGN=1`).",
        "",
        "| Mẫu tấn công | Nhóm | R | N_RH | T cấu hình | D_max (ACT) | D / N_RH | Λ đo (all/usr) | Giới hạn B1 (1 epoch) | B2 kỳ vọng (1×) | RowPress open max (tích luỹ / 1 lần) | RP alert / clamp | Băng thông nền (GB/s, %) | Kết luận |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |",
    ]
    for r in rows:
        b2_str = f"{r['b2_exp_single']:.1f}" if r["bound_group"] == "B2" else "—"
        lines.append(
            f"| `{r['case_name']}` | `{r['bound_group']}` | {r['radius']} | {r['n_rh']} | {r['thresh_t']} | "
            f"**{r['d_max']}** | `{r['d_over_nrh']:.4f}` | `{r['lambda_meas_all']}/{r['lambda_meas_user']}` | "
            f"{r['b1_no_epoch']} | {b2_str} | `{r['rp_open_max']} / {r['rp_single_max']}` | "
            f"`{r['rp_alerts']} / {r['tras_clamps']}` | `{r['ben_bw_gbps']:.3f}` ({r['ben_bw_pct_base']:.1f}%) | `{r['verdict']}` |"
        )

    lines += [
        "",
        "## 3. Các ca `D / N_RH >= 1.0` hoặc vượt B1 (báo nguyên văn theo quy tắc T82, không ẩn/lọc)",
        "",
    ]
    if not findings_over_1:
        lines.append("Không có ca nào có `D / N_RH >= 1.0` hoặc vượt B1.")
    else:
        lines += [
            "| Run ID | Nhóm | N_RH | T | D_max | D / N_RH | B1 (1 epoch) | K (`dummy_resets`) | `bin_wipes` | Trạng thái |",
            "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |",
        ]
        for r in findings_over_1:
            lines.append(
                f"| `{r['run_id']}` | `{r['bound_group']}` | {r['n_rh']} | {r['thresh_t']} | "
                f"{r['d_max']} | `{r['d_over_nrh']:.4f}` | {r['b1_no_epoch']} | {r['dummy_resets']} | {r['bin_wipes']} | `{r['verdict']}` |"
            )

    lines += [
        "",
        "## 4. Phép đo riêng R-82: `test_many_sided_hammering_distribution` (8 hàng, `cfg_sdc_thresh = 4`)",
        "",
        "| Biến thể | PXOR | Số vòng | Hàng throttle (ngõ ra) | Hàng throttle (kiểu đếm cũ) | Lần đặt lại bin A bởi hàng khác | Lần đặt lại bin B bởi hàng khác | Mặt nạ hàng bị mất đếm | Số lần throttle từng hàng (`counts_out`) |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |",
    ]
    for r82 in r82_rows:
        lines.append(
            f"| sub={r82.get('sub')} | {r82.get('pxor')} | {r82.get('rounds')} | "
            f"**{r82.get('out_throttled_rows')}** | {r82.get('old_in_rows')} | "
            f"{r82.get('bin_a_resets_by_other')} | {r82.get('bin_b_resets_by_other')} | "
            f"`{r82.get('victim_rows_reset_mask')}` | `{r82.get('counts_out')}` |"
        )
    if r82_rows:
        lines += [
            "",
            f"- Hash A của 8 hàng (`pxor=0`): `{r82_rows[0].get('ha')}`",
            f"- Hash B của 8 hàng (`pxor=0`): `{r82_rows[0].get('hb')}`",
        ]
        px_r = [x for x in r82_rows if x.get("pxor") == "1"]
        if px_r:
            lines += [
                f"- Hash A của 8 hàng (`pxor=1`): `{px_r[0].get('ha')}`",
                f"- Hash B của 8 hàng (`pxor=1`): `{px_r[0].get('hb')}`",
            ]

    lines += [
        "",
        "## 5. Va chạm PXOR biết seed đã kiểm chứng trên RTL",
        "",
        f"- Mục tiêu `v-1` `(0,0,0x0FF)` trùng hoàn toàn cả 2 bảng với `d_a={coll_info['v_minus_1']['dummy']}` (`ha=0x{coll_info['v_minus_1']['ha']:02x}, hb=0x{coll_info['v_minus_1']['hb']:02x}`).",
        f"- Mục tiêu `v+1` `(0,0,0x101)` trùng hoàn toàn cả 2 bảng với `d_b={coll_info['v_plus_1']['dummy']}` (`ha=0x{coll_info['v_plus_1']['ha']:02x}, hb=0x{coll_info['v_plus_1']['hb']:02x}`).",
    ]
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="Chay nhanh tap dai dien (N_RH 256, 128)")
    ap.add_argument("--workers", type=int, default=min(4, os.cpu_count() or 1))
    ap.add_argument("--radius", type=int, default=2)
    ap.add_argument("--seed", default="0xA5A55A5A01234567")
    args = ap.parse_args()

    seed_64 = int(args.seed, 16)
    seed_hi = (seed_64 >> 32) & 0xFFFFFFFF
    seed_lo = seed_64 & 0xFFFFFFFF
    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    print("=" * 96, flush=True)
    print(f"  Q-SHIELD T82 SECURITY EVALUATION ({'QUICK' if args.quick else 'FULL'}) | R={args.radius} | workers={args.workers}", flush=True)
    print("=" * 96, flush=True)

    vvp_r2 = compile_tb(iverilog_bin, args.radius)
    radii_to_compile = [args.radius]
    vvp_by_r = {args.radius: vvp_r2}
    if args.radius == 2:
        vvp_r3 = compile_tb(iverilog_bin, 3)
        vvp_by_r[3] = vvp_r3
        radii_to_compile.append(3)

    # 1. Tim cap va cham PXOR chinh xac cho v-1 (0x0FF) va v+1 (0x101) va far_row khong trung bin
    coll_a = find_pxor_collision(0, 0, 0x00FF, seed_64)
    coll_b = find_pxor_collision(0, 0, 0x0101, seed_64)
    far_row = find_non_colliding_far_row(seed_64)
    ha_a, hb_a = sdc_hashes(0, 0, 0x00FF, seed_64)
    ha_b, hb_b = sdc_hashes(0, 0, 0x0101, seed_64)
    ha_f, hb_f = sdc_hashes(0, 0, far_row, seed_64)
    coll_info = {
        "v_minus_1": {"target": "(0,0,0x00ff)", "dummy": f"({coll_a[0]},{coll_a[1]},0x{coll_a[2]:04x})", "ha": ha_a, "hb": hb_a},
        "v_plus_1": {"target": "(0,0,0x0101)", "dummy": f"({coll_b[0]},{coll_b[1]},0x{coll_b[2]:04x})", "ha": ha_b, "hb": hb_b},
        "far_row": {"target": f"(0,0,0x{far_row:04x})", "ha": ha_f, "hb": hb_f},
    }
    print(f"  [PXOR] v-1 collision: {coll_info['v_minus_1']['dummy']} (ha=0x{ha_a:02x}, hb=0x{hb_a:02x})", flush=True)
    print(f"  [PXOR] v+1 collision: {coll_info['v_plus_1']['dummy']} (ha=0x{ha_b:02x}, hb=0x{hb_b:02x})", flush=True)
    print(f"  [PXOR] far_row (non-colliding): 0x{far_row:04x} ({far_row}) (ha=0x{ha_f:02x}, hb=0x{hb_f:02x})", flush=True)

    # 2. Chay hieu chuan benign_only + lambda_cal cho moi ban kinh R
    base_jobs = [
        {
            "run_id": f"r{args.radius}_benign_only",
            "case_name": "benign_only",
            "case_id": 0,
            "bound_group": "BASE",
            "radius": args.radius,
            "nrh": 0,
            "thresh": 128,
            "vvp_bin": vvp_bin,
            "vvp_path": str(vvp_r2),
            "plusargs": [
                "+CASE_ID=0",
                "+NRH=128",
                "+THRESH=128",
                "+BENIGN=1",
                "+MAX_CYC=20000",
                f"+SEED_HI={seed_hi:08X}",
                f"+SEED_LO={seed_lo:08X}",
            ],
            "timeout_s": 1200,
        },
        {
            "run_id": "r82_many_sided_6r",
            "case_name": "r82_many_sided_6r",
            "case_id": 11,
            "bound_group": "R82",
            "radius": args.radius,
            "nrh": 0,
            "thresh": 4,
            "vvp_bin": vvp_bin,
            "vvp_path": str(vvp_r2),
            "plusargs": ["+CASE_ID=11", "+THRESH=4"],
            "timeout_s": 120,
        },
    ]
    for r_val in radii_to_compile:
        base_jobs.append(
            {
                "run_id": f"r{r_val}_lambda_cal",
                "case_name": "lambda_cal",
                "case_id": 1,
                "bound_group": "CAL",
                "radius": r_val,
                "nrh": 128,
                "thresh": 16,
                "vvp_bin": vvp_bin,
                "vvp_path": str(vvp_by_r[r_val]),
                "plusargs": [
                    "+CASE_ID=1",
                    "+NRH=128",
                    "+THRESH=16",
                    "+BENIGN=1",
                    "+MAX_CYC=60000",
                    f"+SEED_HI={seed_hi:08X}",
                    f"+SEED_LO={seed_lo:08X}",
                ],
                "timeout_s": 1200,
            }
        )

    diag_jobs = build_diag_jobs(vvp_by_r[3], vvp_bin, seed_64, coll_a, coll_b, far_row) if 3 in vvp_by_r else []

    base_res = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as ex:
        for res in ex.map(run_sim_worker, base_jobs + diag_jobs):
            base_res[res["run_id"]] = res

    ben_raw = base_res[f"r{args.radius}_benign_only"]
    bp = ben_raw["parsed"]
    if not bp or ben_raw["fails"] > 0 or bp.get("jedec_viol", -1) != 0 or bp.get("dram_err", -1) != 0:
        print("[ERROR] benign_only that bai:", ben_raw, flush=True)
        return 1
    bw_base_gbps = round((bp["ben_beats"] * 8.0) / (max(1, bp["meas_cyc"]) * 2.5), 4)
    print(f"  [BASE] Benign-only BW = {bw_base_gbps:.4f} GB/s ({bp['ben_beats']} beats / {bp['meas_cyc']} cyc)", flush=True)

    r82_raw = base_res["r82_many_sided_6r"]
    r82_rows = parse_r82_lines(r82_raw.get("r82_lines", []))
    for line in r82_raw.get("r82_lines", []):
        print(" ", line, flush=True)
    if r82_raw["fails"] > 0 or not r82_rows:
        print("[ERROR] r82_many_sided_6r that bai", flush=True)
        return 1

    per_radius_cal = {}
    for r_val in radii_to_compile:
        cal_raw = base_res[f"r{r_val}_lambda_cal"]
        cp = cal_raw["parsed"]
        if not cp or cal_raw["fails"] > 0 or cp.get("jedec_viol", -1) != 0:
            print(f"[ERROR] lambda_cal R={r_val} that bai:", cal_raw, flush=True)
            return 1
        lam_cal = max(cp.get("lambda_all", 0), cp.get("lam_pend", 0))
        l_mit = cp.get("l_mit_cyc", 0)
        d_cal_tgt = cp.get("d_max_target", -1)
        b1_cal = 2 * r_val * 16 + 1 + lam_cal
        bin_wipes_cal = cp.get("bin_wipes", 0)
        struct_bound = math.ceil(l_mit / 20.0) + 1 if l_mit > 0 else 1
        print(
            f"  [CAL R={r_val}] lambda_all={cp.get('lambda_all')} lambda_user={cp.get('lambda_user')} "
            f"lam_pend={cp.get('lam_pend')} l_mit_cyc={l_mit} (bound <= {struct_bound}) "
            f"d_max_target={d_cal_tgt} b1_no_epoch={b1_cal} bin_wipes={bin_wipes_cal}",
            flush=True,
        )
        if lam_cal > struct_bound:
            print(f"[WARN] R={r_val}: lambda_cal={lam_cal} > struct_bound={struct_bound}!", flush=True)
        per_radius_cal[str(r_val)] = {
            "run_id": cal_raw["run_id"],
            "lambda_cal": lam_cal,
            "lambda_user": cp.get("lambda_user", 0),
            "l_mit_cyc": l_mit,
            "struct_bound": struct_bound,
            "d_max_target": d_cal_tgt,
            "b1_no_epoch": b1_cal,
            "bin_wipes": bin_wipes_cal,
            "jedec_viol": cp.get("jedec_viol", -1),
        }

    cal_info = {
        "bw_base_gbps": bw_base_gbps,
        "benign_only": {"ben_beats": bp["ben_beats"], "meas_cyc": bp["meas_cyc"], "jedec_viol": bp["jedec_viol"]},
        "per_radius": per_radius_cal,
    }

    diag_controls: list[dict] = []
    if diag_jobs and "3" in per_radius_cal:
        lam_c3 = per_radius_cal["3"]["lambda_cal"]
        for dj in diag_jobs:
            dres = base_res[dj["run_id"]]
            drow = evaluate_row(dres, lam_c3, bw_base_gbps)
            f_vic3 = 1 if "+FORCE_VIC3_EN=1" in dj["plusargs"] else 0
            ign_m = 1 if "+IGNORE_MIT_ACT=1" in dj["plusargs"] else 0
            drow["force_vic3_en"] = f_vic3
            drow["ignore_mit_act"] = ign_m
            drow["diag_rows"] = dres.get("diag_rows", [])
            diag_controls.append(drow)
            print(
                f"  [DIAG_CTL] {drow['run_id']:<24} vic3={f_vic3} ign_mit={ign_m} "
                f"D={drow['d_max']} max_key={drow['max_key']} mit_done={drow['mit_done']} "
                f"dummy_resets={drow['dummy_resets']} lam={drow['lambda_meas_all']}/{drow['lambda_meas_user']} "
                f"bw={drow['ben_bw_pct_base']:.1f}%",
                flush=True,
            )
            for dr in drow["diag_rows"]:
                print(
                    f"    [RH_DIAG_ROW] row=0x{dr.get('row', 0):04x} user_acts={dr.get('user_acts', 0)} "
                    f"mit_acts={dr.get('mit_acts', 0)} disturb_max={dr.get('disturb_max', 0)}",
                    flush=True,
                )

    # 3. Sinh va chay toan bo ma tran mau x nguong
    nrh_main = [256, 128] if args.quick else [1024, 512, 256, 128]
    jobs = build_jobs_for_radius(
        vvp_r2, vvp_bin, args.radius, nrh_main, per_radius_cal[str(args.radius)]["lambda_cal"],
        seed_64, coll_a, coll_b, far_row, args.quick, full_matrix=True
    )
    if not args.quick and 3 in vvp_by_r:
        jobs += build_jobs_for_radius(
            vvp_by_r[3], vvp_bin, 3, [256, 128], per_radius_cal["3"]["lambda_cal"],
            seed_64, coll_a, coll_b, far_row, False, full_matrix=False
        )

    print(f"  [RUN] Executing {len(jobs)} RTL evaluation runs with {args.workers} workers...", flush=True)
    eval_rows: list[dict] = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as ex:
        for res in ex.map(run_sim_worker, jobs):
            lam_c = per_radius_cal[str(res["radius"])]["lambda_cal"]
            row = evaluate_row(res, lam_c, bw_base_gbps)
            eval_rows.append(row)
            print(
                f"  [{row['verdict']:<25}] {row['run_id']:<34} T={row['thresh_t']:<3} "
                f"D={row['d_max']:<5} D/N_RH={row['d_over_nrh']:.4f} B1={row['b1_no_epoch']:<4} "
                f"lam={row['lambda_meas_all']}/{row['lambda_meas_user']} bw={row['ben_bw_pct_base']:5.1f}% "
                f"({row['runtime_s']:.1f}s)",
                flush=True,
            )

    write_reports(eval_rows, cal_info, diag_controls, r82_rows, coll_info, seed_64, args.quick)

    sim_errs = [r for r in eval_rows if r["verdict"] == "SIM_ERROR"]
    b1_viols = [r for r in eval_rows if r["verdict"] in ("B1_VIOLATION_STOP", "PHYS_VIOLATION_STOP")]
    print("=" * 96, flush=True)
    print(f"  DONE: total={len(eval_rows)} | sim_errors={len(sim_errs)} | b1_or_phys_violations={len(b1_viols)}", flush=True)
    print(f"  Reports: {REPORT_DIR / 'security_eval_report.md'}", flush=True)
    print("=" * 96, flush=True)

    if sim_errs:
        return 1
    if b1_viols:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
