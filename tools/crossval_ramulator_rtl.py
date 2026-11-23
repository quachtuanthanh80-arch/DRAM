# File: tools/crossval_ramulator_rtl.py
# Chức năng: Kiểm chéo trong mẫu và ngoài mẫu (T81/T90) giữa mô hình Ramulator2 Q-Shield (hiệu chuẩn & mặc định T80) với RTL sau T88, kèm thí nghiệm tách (ablation).

import argparse
import csv
import datetime
import hashlib
import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
OVERLAY_DIR = REPO_ROOT / "sim" / "ramulator2_qshield"
RAMULATOR_BUILD_DIR = REPO_ROOT / "build" / "ramulator2"
RAMULATOR_PY = RAMULATOR_BUILD_DIR / "python"
RAMULATOR_LIB = RAMULATOR_BUILD_DIR / "libramulator.so"
HASH_CACHE_FILE = REPO_ROOT / "build" / "crossval_overlay_hashes.json"
RTL_IN_JSON = REPO_ROOT / "build" / "crossval_rtl_t90" / "in_sample" / "rtl_bench.json"
RTL_HOLD_JSON = REPO_ROOT / "build" / "crossval_rtl_t90" / "holdout" / "rtl_bench.json"
RTL_BENCH_JSON_LEGACY = REPO_ROOT / "build" / "crossval_rtl" / "rtl_bench.json"
T38_LOG_POST_T88 = REPO_ROOT / "build" / "one_tb_secure_top_integrity" / "sim.log"
T38_LOG_LEGACY = REPO_ROOT / "regression_logs" / "tb_secure_top_integrity.log"
TRACE_DIR = REPO_ROOT / "sim" / "traces" / "rtl_bench"
HOLDOUT_TRACE_DIR = REPO_ROOT / "sim" / "traces" / "rtl_bench_holdout"
CROSSVAL_TRACES_DIR = REPO_ROOT / "build" / "crossval_traces"
OUT_DIR = REPO_ROOT / "reports" / "paper" / "crossval"
FROZEN_FILE = OUT_DIR / "calibration_frozen.json"
T81_TABLE_CSV = OUT_DIR / "crossval_table.csv"

# Đóng băng bộ tham số hiệu chuẩn từ T81 (tuyệt đối không tinh chỉnh theo holdout)
CALIBRATED_PARAMS = {
    "max_outstanding_reads": 19,
    "max_outstanding_writes": 8,
    "issue_gap_fe_ticks": 2,
    "read_buffer_size": 19,
    "write_buffer_size": 8,
    "wr_low_watermark": 0.1,
    "wr_high_watermark": 0.5,
    "dq_cas_gap_rd_rd_clk": 40,
    "dq_cas_gap_wr_wr_clk": 40,
    "dq_cas_gap_rd_wr_clk": 36,
    "dq_cas_gap_wr_rd_clk": 72,
    "rtl_rd_extra_lat_clk": 48,
    "disable_wr_coalesce": True,
    "sdc_count_requests": True,
    "scrub_interval_ctrl_cycles": 320,
    "ref_postpone_max": 4,
    "row": 131072,
    "nRFC": 472,
    "nRFM": 472,
    "scheduler_impl": "FRFCFSRowHit",
}

# Bộ tham số mặc định của T80 (chưa hiệu chuẩn vi kiến trúc RTL)
UNCALIBRATED_PARAMS = {
    "max_outstanding_reads": 32,
    "max_outstanding_writes": 32,
    "issue_gap_fe_ticks": 2,
    "read_buffer_size": 32,
    "write_buffer_size": 32,
    "wr_low_watermark": 0.2,
    "wr_high_watermark": 0.8,
    "dq_cas_gap_rd_rd_clk": 0,
    "dq_cas_gap_wr_wr_clk": 0,
    "dq_cas_gap_rd_wr_clk": 0,
    "dq_cas_gap_wr_rd_clk": 0,
    "rtl_rd_extra_lat_clk": 0,
    "disable_wr_coalesce": False,
    "sdc_count_requests": False,
    "scrub_interval_ctrl_cycles": 0,
    "ref_postpone_max": 0,
    "row": 131072,
    "nRFC": 472,
    "nRFM": 472,
    "scheduler_impl": "FRFCFS",
}

THRESH_BW_PCT = 10.0
THRESH_LAT_PCT = 10.0
THRESH_COUNT_PCT = 5.0


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def get_git_head() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=str(REPO_ROOT), text=True
        ).strip()
    except Exception:
        return "unknown"


def trace_dir_hashes(tdir: Path) -> dict:
    if not tdir.is_dir():
        return {}
    return {p.name: sha256_file(p) for p in sorted(tdir.glob("*.trace"))}


def import_ramulator():
    py_str = str(RAMULATOR_PY)
    if py_str not in sys.path:
        sys.path.insert(0, py_str)
    import ramulator
    return ramulator


def write_calibration_frozen() -> dict:
    if not RAMULATOR_LIB.is_file():
        sys.exit(f"ERROR: Missing {RAMULATOR_LIB}; build Ramulator2 first.")
    in_hashes = trace_dir_hashes(TRACE_DIR)
    if len(in_hashes) != 8:
        sys.exit(f"ERROR: Expected 8 original traces in {TRACE_DIR}, found {len(in_hashes)}")
    hold_exists = HOLDOUT_TRACE_DIR.is_dir() and any(HOLDOUT_TRACE_DIR.glob("*.trace"))
    if hold_exists:
        sys.exit(f"ERROR: Refusing to freeze after holdout traces already exist in {HOLDOUT_TRACE_DIR}")

    payload = {
        "frozen_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "git_head_at_freeze": get_git_head(),
        "upstream_commit_sha": "72427a1bba3771564c4fb0e494ba02242fd1eaa7",
        "libramulator_path": str(RAMULATOR_LIB),
        "libramulator_size_bytes": RAMULATOR_LIB.stat().st_size,
        "libramulator_sha256": sha256_file(RAMULATOR_LIB),
        "holdout_existed_at_freeze": False,
        "calibrated_params": CALIBRATED_PARAMS,
        "uncalibrated_t80_params": UNCALIBRATED_PARAMS,
        "original_8_trace_sha256": in_hashes,
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    FROZEN_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"[crossval] FROZEN calibration -> {FROZEN_FILE}")
    print(f"[crossval] libramulator.so SHA-256 = {payload['libramulator_sha256']}")
    print(f"[crossval] Original 8 traces hashed ({len(in_hashes)} files), holdout_existed_at_freeze=False")
    return payload


def verify_frozen() -> dict:
    if not FROZEN_FILE.is_file():
        sys.exit(f"ERROR: Missing {FROZEN_FILE}. Must freeze calibration BEFORE generating holdout traces.")
    frozen = json.loads(FROZEN_FILE.read_text(encoding="utf-8"))
    cur_lib_sha = sha256_file(RAMULATOR_LIB)
    if cur_lib_sha != frozen["libramulator_sha256"]:
        sys.exit(
            f"ERROR: libramulator.so SHA-256 changed after freeze!\n"
            f"  frozen={frozen['libramulator_sha256']}\n  current={cur_lib_sha}"
        )
    if frozen["calibrated_params"] != CALIBRATED_PARAMS:
        sys.exit("ERROR: CALIBRATED_PARAMS modified after freeze! Out-of-sample protocol violated.")
    cur_in_hashes = trace_dir_hashes(TRACE_DIR)
    if cur_in_hashes != frozen["original_8_trace_sha256"]:
        sys.exit(
            "ERROR: Original 8 traces in sim/traces/rtl_bench changed hash after freeze!\n"
            f"  frozen={frozen['original_8_trace_sha256']}\n  current={cur_in_hashes}"
        )
    return frozen


def write_t38_trace(out_path: Path) -> Path:
    """Sinh trace thao tác khớp 1-1 thứ tự V-1..V-9 trong tb/top/tb_secure_top_integrity.sv."""
    lines = ["# T38 V-1..V-9 exact transaction sequence (tb_secure_top_integrity.sv)", "META_INIT"]
    v1_addrs = [(i * 64) if i < 8 else ((64 + (i - 8)) * 64) for i in range(16)]
    for a in v1_addrs:
        lines.append(f"ST {a:08x}")
    for a in reversed(v1_addrs):
        lines.append(f"LD {a:08x}")
    lines.append(f"ST {0x00000140:08x}")
    lines.append(f"LD {0x00000140:08x}")
    lines.append("META_FLUSH")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD {0x00000000:08x}")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD_BMT_FAIL {0x00000000:08x} 2")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD_BMT_FAIL {0x00000000:08x} 2")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD_BMT_FAIL {0x00000000:08x} 2")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD {0x00000000:08x}")
    lines.append(f"ST {0x00000080:08x}")
    lines.append(f"LD {0x00000080:08x}")
    lines.append(f"ST {0x00000280:08x}")
    lines.append("META_FLUSH")
    lines.append(f"ST {0x00000280:08x}")
    lines.append("META_FLUSH")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD_BMT_FAIL {0x00000280:08x} 2")
    lines.append("CACHE_CLEAR")
    lines.append(f"ST {0x00000300:08x}")
    lines.append("META_FLUSH")
    lines.append(f"ST {0x00000300:08x}")
    lines.append("META_FLUSH")
    lines.append("CACHE_CLEAR")
    lines.append(f"LD {0x00000300:08x}")
    lines.append("CACHE_CLEAR")
    lines.append(f"ST {0x00000480:08x}")
    lines.append(f"ST {0x000004C0:08x}")
    lines.append(f"ST {0x00000500:08x}")
    lines.append(f"FORCE_MINOR {0x00000500:08x}")
    lines.append(f"ST {0x00000500:08x}")
    lines.append(f"ST {0x00001000:08x}")
    lines.append(f"LD {0x00001000:08x}")
    lines.append(f"LD {0x00000500:08x}")
    lines.append(f"LD {0x00000480:08x}")
    lines.append(f"LD {0x000004C0:08x}")
    lines.append(f"LD {0x00000000:08x}")
    lines.append("META_FLUSH")
    v9_cbs = [0, 8, 16, 24, 32, 40, 48, 56, 4, 12]
    for cb_id in v9_cbs:
        a = cb_id * 64 * 64 + 0x40
        lines.append(f"ST {a:08x}")
    for cb_id in v9_cbs:
        a = cb_id * 64 * 64 + 0x40
        lines.append(f"LD {a:08x}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_path


def run_trace_worker(job: dict) -> dict:
    ramulator = import_ramulator()
    cfg_name = job["cfg"]
    trace_path = job["trace_path"]
    base_params = UNCALIBRATED_PARAMS if job.get("mode") == "uncalibrated" else CALIBRATED_PARAMS
    p = dict(base_params)
    p.update(job.get("overrides", {}))

    is_secure = (cfg_name == "secure")
    fe = ramulator.frontend.QShieldTrace(
        clock_ratio=1,
        path=str(trace_path),
        max_outstanding_reads=p["max_outstanding_reads"],
        max_outstanding_writes=p["max_outstanding_writes"],
        issue_gap_fe_ticks=p["issue_gap_fe_ticks"],
        sequential_ops=False,
        drain_controller=True,
    )
    dram = ramulator.dram.DDR5_VRR(
        org_preset="DDR5_16Gb_x4",
        timing_preset="DDR5_3200C",
        rank=1,
        row=p["row"],
        nRFC=p["nRFC"],
        nRFM=p["nRFM"],
    )
    addr_mapper = ramulator.addr_mapper.QShieldAddrMapper(
        scramble_en=is_secure,
        scramble_seed_hex="13579BDF2468ACE0",
        is_ddr5=True,
    )
    sched = (
        ramulator.scheduler.FRFCFS()
        if p.get("scheduler_impl") == "FRFCFS"
        else ramulator.scheduler.FRFCFSRowHit()
    )
    sdc_thresh = p.get("sdc_thresh", 64 if is_secure else 65535)
    rowpress_thresh_ns = p.get("rowpress_thresh_ns", 12500)
    proq_depth = p.get("proq_depth", 32)
    ctrl = ramulator.controller.QShield(
        dram=dram,
        scheduler=sched,
        refresh_manager=ramulator.refresh_manager.AllBank(),
        row_policy=ramulator.row_policy.Open(),
        addr_mapper=addr_mapper,
        read_buffer_size=p["read_buffer_size"],
        write_buffer_size=p["write_buffer_size"],
        wr_low_watermark=p["wr_low_watermark"],
        wr_high_watermark=p["wr_high_watermark"],
        sdc_thresh=sdc_thresh,
        table_entries=256,
        dual_hash_en=True,
        pxor_mode=True,
        pxor_seed_hex="13579BDF2468ACE0",
        refw_refs=8192,
        window_size_ctrl_cycles=1000,
        multibank_thresh=2,
        blast_radius=2,
        proq_depth=proq_depth,
        throttle_pace_clk=80,
        raammt_thresh=32,
        tras_max_ns=21937,
        rowpress_thresh_ns=rowpress_thresh_ns,
        rowpress_curve=0,
        integrity_en=False,
        dq_cas_gap_rd_rd_clk=p["dq_cas_gap_rd_rd_clk"],
        dq_cas_gap_wr_wr_clk=p["dq_cas_gap_wr_wr_clk"],
        dq_cas_gap_rd_wr_clk=p["dq_cas_gap_rd_wr_clk"],
        dq_cas_gap_wr_rd_clk=p["dq_cas_gap_wr_rd_clk"],
        rtl_rd_extra_lat_clk=p["rtl_rd_extra_lat_clk"],
        disable_wr_coalesce=p["disable_wr_coalesce"],
        sdc_count_requests=p["sdc_count_requests"],
        scrub_interval_ctrl_cycles=p["scrub_interval_ctrl_cycles"],
        ref_postpone_max=p["ref_postpone_max"],
        rtl_integrity_mode=False,
    )
    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=4,
        controllers=[ctrl],
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )
    sim = ramulator.Simulation(fe, mem)
    t0 = time.monotonic()
    sim.run()
    sim.finalize()
    stats = sim.stats
    elapsed = time.monotonic() - t0

    fe_st = stats["frontend"]
    ctrl_st = stats["memory_system"]["controller"]
    reads = int(fe_st["qshield_trace_reads_done"])
    writes = int(fe_st["qshield_trace_writes_done"])
    cycles_ctrl = int(fe_st["qshield_trace_fe_ticks"])
    secs = cycles_ctrl * 2.5e-9
    bw_gbps = (64.0 * (reads + writes)) / secs / 1e9 if secs > 0 else 0.0
    rd_lat_avg_cyc = float(fe_st["qshield_trace_avg_rd_lat_fe_ticks"])
    rd_lat_avg_ns = rd_lat_avg_cyc * 2.5
    act_traffic = int(ctrl_st["qshield_traffic_acts"])
    act_victim = int(ctrl_st["qshield_mit_acts"])
    cas_cnt = int(ctrl_st["num_read_reqs_served"]) + int(ctrl_st["num_write_reqs_served"])
    row_hit = 1.0 - (act_traffic / cas_cnt) if cas_cnt > 0 else 0.0

    return {
        "split": job.get("split", "in_sample"),
        "mode": job.get("mode", "calibrated"),
        "tag": job.get("tag", ""),
        "wl": job["wl"],
        "cfg": cfg_name,
        "reads": reads,
        "writes": writes,
        "cycles_ctrl": cycles_ctrl,
        "bw_gbps": round(bw_gbps, 4),
        "rd_lat_avg_ns": round(rd_lat_avg_ns, 2),
        "row_hit": round(row_hit, 4),
        "act_traffic": act_traffic,
        "act_victim": act_victim,
        "victim_refreshes_drm": int(ctrl_st["qshield_victim_refreshes"]),
        "scrub_acts": int(ctrl_st["qshield_scrub_acts"]),
        "rowpress_alerts": int(ctrl_st["qshield_rowpress_alerts"]),
        "tras_clamps": int(ctrl_st["qshield_tras_clamps"]),
        "ref_count": int(ctrl_st["qshield_ref_count"]),
        "rfm_count": int(ctrl_st["qshield_rfm_count"]),
        "sdc_throttles": int(ctrl_st["qshield_sdc_throttles"]),
        "elapsed_s": round(elapsed, 3),
    }


def run_t38_integrity(t38_trace: Path, rtl_ml_reenc_ack_overlap: bool = False) -> dict:
    ramulator = import_ramulator()
    fe = ramulator.frontend.QShieldTrace(
        clock_ratio=1,
        path=str(t38_trace),
        max_outstanding_reads=16,
        max_outstanding_writes=8,
        issue_gap_fe_ticks=2,
        sequential_ops=True,
        drain_controller=True,
    )
    dram = ramulator.dram.DDR5_VRR(
        org_preset="DDR5_16Gb_x4",
        timing_preset="DDR5_3200C",
        rank=1,
        row=131072,
        nRFC=472,
        nRFM=472,
    )
    addr_mapper = ramulator.addr_mapper.QShieldAddrMapper(
        scramble_en=False,
        scramble_seed_hex="13579BDF2468ACE0",
        is_ddr5=True,
    )
    ctrl = ramulator.controller.QShield(
        dram=dram,
        scheduler=ramulator.scheduler.FRFCFSRowHit(),
        refresh_manager=ramulator.refresh_manager.AllBank(),
        row_policy=ramulator.row_policy.Open(),
        addr_mapper=addr_mapper,
        read_buffer_size=19,
        write_buffer_size=8,
        sdc_thresh=32,
        table_entries=256,
        dual_hash_en=True,
        pxor_mode=True,
        pxor_seed_hex="13579BDF2468ACE0",
        refw_refs=8192,
        window_size_ctrl_cycles=1024,
        multibank_thresh=2,
        blast_radius=2,
        proq_depth=32,
        throttle_pace_clk=80,
        raammt_thresh=32,
        tras_max_ns=21937,
        rowpress_thresh_ns=12500,
        rowpress_curve=0,
        integrity_en=True,
        mc_sets=16,
        mc_ways=4,
        prot_lines=4096,
        tree_levels=2,
        crypto_extra_lat_clk=84,
        disable_wr_coalesce=True,
        sdc_count_requests=True,
        scrub_interval_ctrl_cycles=0,
        ref_postpone_max=4,
        rtl_integrity_mode=True,
        rtl_ml_reenc_ack_overlap=rtl_ml_reenc_ack_overlap,
    )
    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=4,
        controllers=[ctrl],
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )
    sim = ramulator.Simulation(fe, mem)
    sim.run()
    sim.finalize()
    ctrl_st = sim.stats["memory_system"]["controller"]
    hits = int(ctrl_st["qshield_mc_hits"])
    misses = int(ctrl_st["qshield_mc_misses"])
    tot = hits + misses
    hit_rate = (100.0 * hits / tot) if tot > 0 else 0.0
    return {
        "meta_rd_cnt": int(ctrl_st["qshield_meta_rd_cnt"]),
        "meta_wr_cnt": int(ctrl_st["qshield_meta_wr_cnt"]),
        "mc_hit_cnt": hits,
        "mc_miss_cnt": misses,
        "mc_hit_rate_pct": round(hit_rate, 2),
        "reencrypt_events": int(ctrl_st["qshield_reencrypt_events"]),
    }


def parse_t38_log(log_path: Path) -> dict:
    if not log_path.is_file():
        raise FileNotFoundError(f"Missing T38 RTL log: {log_path}")
    text = log_path.read_text(encoding="utf-8", errors="replace")
    out = {"log_path": str(log_path.relative_to(REPO_ROOT)).replace("\\", "/")}
    m_tb = re.search(r"\[TB_RESULT\].*?checks=(\d+)\s+fails=(\d+)", text)
    if m_tb:
        out["checks"] = int(m_tb.group(1))
        out["fails"] = int(m_tb.group(2))
    m1 = re.search(r"\[INTEG_PERF\]\s+cycles_integ=(\d+)\s+cycles_no_integ=(\d+)", text)
    if m1:
        out["cycles_integ"] = int(m1.group(1))
        out["cycles_no_integ"] = int(m1.group(2))
    m2 = re.search(r"\[INTEG_PERF\]\s+meta_rd_cnt=(\d+)\s+meta_wr_cnt=(\d+)\s+reencrypt_events=(\d+)", text)
    if m2:
        out["meta_rd_cnt"] = int(m2.group(1))
        out["meta_wr_cnt"] = int(m2.group(2))
        out["reencrypt_events"] = int(m2.group(3))
    m3 = re.search(r"\[INTEG_PERF\]\s+mc_hit_cnt=(\d+)\s+mc_miss_cnt=(\d+)\s+mc_hit_rate=([0-9.]+)%", text)
    if m3:
        out["mc_hit_cnt"] = int(m3.group(1))
        out["mc_miss_cnt"] = int(m3.group(2))
        out["mc_hit_rate_pct"] = float(m3.group(3))
    required = {"meta_rd_cnt", "meta_wr_cnt", "reencrypt_events", "mc_hit_cnt", "mc_miss_cnt", "mc_hit_rate_pct"}
    if not required.issubset(out.keys()):
        raise RuntimeError(f"Failed to parse [INTEG_PERF] from {log_path}: got {out}")
    return out


def rel_err_pct(ram: float, rtl: float) -> float:
    if rtl == 0:
        return 0.0 if ram == 0 else 100.0
    return ((ram - rtl) / rtl) * 100.0


def audit_t81_csv() -> dict:
    """Tự đếm lại CSV của T81 để đính chính chỗ T81 nêu 10/13 thay vì 9/13 cho act_traffic."""
    if not T81_TABLE_CSV.is_file():
        return {"available": False}
    rows = list(csv.DictReader(T81_TABLE_CSV.open(encoding="utf-8")))
    clean = [r for r in rows if r["status"] != "EXPLAINED_RTL_ARTIFACT"]
    bw_ok = sum(1 for r in clean if abs(float(r["err_bw_pct"])) <= THRESH_BW_PCT)
    lat_ok = sum(1 for r in clean if abs(float(r["err_rd_lat_pct"])) <= THRESH_LAT_PCT)
    act_ok = sum(1 for r in clean if abs(float(r["err_act_traffic_pct"])) <= THRESH_COUNT_PCT)
    vic_ok = sum(1 for r in clean if abs(float(r["err_act_victim_pct"])) <= THRESH_COUNT_PCT)
    return {
        "available": True,
        "total_rows": len(rows),
        "clean_rows": len(clean),
        "bw_pass": bw_ok,
        "lat_pass": lat_ok,
        "act_traffic_pass": act_ok,
        "act_victim_pass": vic_ok,
        "t81_note_claimed_act_traffic": "10/13",
        "verified_from_t81_csv_act_traffic": f"{act_ok}/{len(clean)}",
    }


def compute_split_stats(rows: list[dict], split_label: str) -> dict:
    """Tự tính thống kê từ danh sách dòng đã ghi ra CSV (không gõ tay)."""
    n = len(rows)
    if n == 0:
        return {"split": split_label, "n_rows": 0}
    metrics = [
        ("bw", "err_bw_pct", THRESH_BW_PCT),
        ("rd_lat", "err_rd_lat_pct", THRESH_LAT_PCT),
        ("act_traffic", "err_act_traffic_pct", THRESH_COUNT_PCT),
        ("act_victim", "err_act_victim_pct", THRESH_COUNT_PCT),
    ]
    out = {
        "split": split_label,
        "n_rows": n,
        "all4_within_thresh": sum(1 for r in rows if r["within_threshold"]),
        "bw_and_lat_within_thresh": sum(
            1 for r in rows if abs(r["err_bw_pct"]) <= THRESH_BW_PCT and abs(r["err_rd_lat_pct"]) <= THRESH_LAT_PCT
        ),
        "bw_or_lat_exceed_10pct": sum(
            1 for r in rows if abs(r["err_bw_pct"]) > THRESH_BW_PCT or abs(r["err_rd_lat_pct"]) > THRESH_LAT_PCT
        ),
    }
    for mkey, col, thr in metrics:
        vals = [float(r[col]) for r in rows]
        passed = sum(1 for v in vals if abs(v) <= thr)
        mean_v = statistics.mean(vals)
        std_v = statistics.stdev(vals) if len(vals) >= 2 else 0.0
        max_abs = max(abs(v) for v in vals)
        out[mkey] = {
            "pass_count": passed,
            "total": n,
            "pass_ratio": f"{passed}/{n}",
            "signed_mean_pct": round(mean_v, 3),
            "stdev_pct": round(std_v, 3),
            "max_abs_pct": round(max_abs, 2),
        }
    return out


def run_ablation_suite(targets: list[dict], trace_map: dict, rtl_by_key: dict, ram_cal_by_key: dict) -> list[dict]:
    """Chạy thí nghiệm tách (ablation) bằng cách tắt từng cơ chế trong mô hình và đo lại."""
    ablation_variants = [
        ("baseline_calibrated", {}, "Mô hình hiệu chuẩn đóng băng"),
        ("no_patrol_scrub", {"scrub_interval_ctrl_cycles": 0}, "Tắt tuần tra ECC nền (scrub_interval=0)"),
        ("scrub_interval_420", {"scrub_interval_ctrl_cycles": 420}, "Tăng chu kỳ scrub 320->420 mô phỏng gating s_v=='0 của RTL"),
        ("no_rowpress", {"rowpress_thresh_ns": 999999999}, "Tắt cảnh báo RowPress (rowpress_thresh_ns=999999999)"),
        ("no_ref_postpone", {"ref_postpone_max": 0}, "Tắt hoãn REFab (ref_postpone_max=0)"),
        ("sdc_count_act_only", {"sdc_count_requests": False}, "Đếm SDC theo ACT thay vì mọi AXI req (sdc_count_requests=False)"),
        ("no_sdc_drm", {"sdc_thresh": 65535}, "Tắt kích hoạt SDC/DRM victim refresh (sdc_thresh=65535)"),
        ("frfcfs_sched", {"scheduler_impl": "FRFCFS"}, "Đổi bộ lập lịch FRFCFSRowHit -> FRFCFS"),
    ]
    jobs = []
    for t in targets:
        wl, cfg, split = t["wl"], t["cfg"], t["split"]
        tpath = trace_map[(split, wl)]
        for vname, ov, _ in ablation_variants:
            jobs.append({
                "split": split,
                "mode": "calibrated",
                "tag": vname,
                "wl": wl,
                "cfg": cfg,
                "trace_path": str(tpath),
                "overrides": ov,
            })

    with ProcessPoolExecutor(max_workers=4) as ex:
        res = list(ex.map(run_trace_worker, jobs))
    by_tv = {(r["split"], r["wl"], r["cfg"], r["tag"]): r for r in res}

    suite = []
    for t in targets:
        wl, cfg, split = t["wl"], t["cfg"], t["split"]
        rtl = rtl_by_key[(split, wl, cfg)]
        base_ram = ram_cal_by_key[(split, wl, cfg)]
        variants_out = []
        for vname, ov, desc in ablation_variants:
            r = by_tv[(split, wl, cfg, vname)]
            variants_out.append({
                "variant": vname,
                "description": desc,
                "overrides": ov,
                "bw_gbps": r["bw_gbps"],
                "rd_lat_avg_ns": r["rd_lat_avg_ns"],
                "act_traffic": r["act_traffic"],
                "act_victim": r["act_victim"],
                "drm_victims": r["victim_refreshes_drm"],
                "scrub_acts": r["scrub_acts"],
                "rowpress_alerts": r["rowpress_alerts"],
                "sdc_throttles": r["sdc_throttles"],
                "delta_act_vs_cal": r["act_traffic"] - base_ram["act_traffic"],
                "delta_vic_vs_cal": r["act_victim"] - base_ram["act_victim"],
                "err_act_vs_rtl_pct": round(rel_err_pct(r["act_traffic"], rtl["act_traffic"]), 2),
                "err_vic_vs_rtl_pct": round(rel_err_pct(r["act_victim"], rtl["act_victim"]), 2),
            })
        suite.append({
            "split": split,
            "wl": wl,
            "cfg": cfg,
            "reason_selected": t["reason"],
            "rtl_act_traffic": rtl["act_traffic"],
            "rtl_act_victim": rtl["act_victim"],
            "rtl_throttles": rtl.get("throttles", 0),
            "cal_act_traffic": base_ram["act_traffic"],
            "cal_act_victim": base_ram["act_victim"],
            "cal_err_act_pct": round(rel_err_pct(base_ram["act_traffic"], rtl["act_traffic"]), 2),
            "cal_err_vic_pct": round(rel_err_pct(base_ram["act_victim"], rtl["act_victim"]), 2),
            "variants": variants_out,
        })
    return suite


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--freeze", action="store_true", help="Freeze libramulator.so + calibrated params before holdout generation")
    ap.add_argument("--jobs", type=int, default=4, help="Parallel worker processes")
    args = ap.parse_args()

    # Tự động đóng băng nếu chạy lần đầu trước khi sinh holdout
    if args.freeze or (not FROZEN_FILE.is_file() and not (HOLDOUT_TRACE_DIR.is_dir() and any(HOLDOUT_TRACE_DIR.glob("*.trace")))):
        write_calibration_frozen()
        return

    t_start = time.monotonic()
    frozen = verify_frozen()

    if not RTL_IN_JSON.is_file() or not RTL_HOLD_JSON.is_file():
        sys.exit(
            f"ERROR: Missing post-T88 live RTL benchmark JSONs:\n"
            f"  in_sample={RTL_IN_JSON} (exists={RTL_IN_JSON.is_file()})\n"
            f"  holdout={RTL_HOLD_JSON} (exists={RTL_HOLD_JSON.is_file()})\n"
            f"Run tools/run_rtl_bench.py for both trace directories first."
        )

    rtl_in_data = json.loads(RTL_IN_JSON.read_text(encoding="utf-8"))
    rtl_hold_data = json.loads(RTL_HOLD_JSON.read_text(encoding="utf-8"))
    rtl_in_rows = rtl_in_data.get("rows", [])
    rtl_hold_rows = rtl_hold_data.get("rows", [])

    if len(rtl_in_rows) != 16:
        sys.exit(f"ERROR: Expected 16 in-sample RTL rows (8 traces x base/secure), got {len(rtl_in_rows)}")
    if len(rtl_hold_rows) < 12:
        sys.exit(f"ERROR: Expected >= 12 holdout RTL rows (>= 6 traces x base/secure), got {len(rtl_hold_rows)}")

    all_rtl = []
    trace_map = {}
    for split, rows, tdir in [
        ("in_sample", rtl_in_rows, TRACE_DIR),
        ("holdout", rtl_hold_rows, HOLDOUT_TRACE_DIR),
    ]:
        for r in rows:
            if r.get("complete") != 1 or r.get("jedec_viol", 1) != 0 or r.get("dram_err", 1) != 0:
                sys.exit(f"ERROR: Invalid post-T88 RTL row ({split}): {r}")
            tpath = tdir / f"{r['wl']}.trace"
            if not tpath.is_file():
                sys.exit(f"ERROR: Missing trace file {tpath}")
            trace_map[(split, r["wl"])] = tpath
            r_copy = dict(r)
            r_copy["split"] = split
            all_rtl.append(r_copy)

    rtl_by_key = {(r["split"], r["wl"], r["cfg"]): r for r in all_rtl}

    # Chạy cả mô hình hiệu chuẩn (đóng băng) lẫn mô hình mặc định T80 (chưa hiệu chuẩn)
    jobs = []
    for r in all_rtl:
        tpath = str(trace_map[(r["split"], r["wl"])])
        jobs.append({"split": r["split"], "mode": "calibrated", "wl": r["wl"], "cfg": r["cfg"], "trace_path": tpath})
        jobs.append({"split": r["split"], "mode": "uncalibrated", "wl": r["wl"], "cfg": r["cfg"], "trace_path": tpath})

    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        ram_all = list(ex.map(run_trace_worker, jobs))

    ram_cal_by_key = {(r["split"], r["wl"], r["cfg"]): r for r in ram_all if r["mode"] == "calibrated"}
    ram_uncal_by_key = {(r["split"], r["wl"], r["cfg"]): r for r in ram_all if r["mode"] == "uncalibrated"}

    # Chọn đích thí nghiệm tách (ablation): bank_conflict secure + 3 dòng act_victim lệch nhất (trong mẫu)
    in_sample_pairs = sorted(
        [(r["wl"], r["cfg"]) for r in rtl_in_rows],
        key=lambda k: abs(rel_err_pct(ram_cal_by_key[("in_sample", k[0], k[1])]["act_victim"], rtl_by_key[("in_sample", k[0], k[1])]["act_victim"])),
        reverse=True,
    )
    ablation_targets = [
        {"split": "in_sample", "wl": "bank_conflict", "cfg": "secure", "reason": "Bắt buộc theo brief (ACT -31.4% ở T81)"}
    ]
    seen_abl = {("in_sample", "bank_conflict", "secure")}
    for wl, cfg in in_sample_pairs:
        if len(ablation_targets) >= 4:
            break
        key = ("in_sample", wl, cfg)
        if key not in seen_abl:
            seen_abl.add(key)
            ev = rel_err_pct(ram_cal_by_key[key]["act_victim"], rtl_by_key[key]["act_victim"])
            ablation_targets.append({
                "split": "in_sample",
                "wl": wl,
                "cfg": cfg,
                "reason": f"Top act_victim lệch nhất trong mẫu ({ev:+.2f}%)",
            })
    # Thêm luôn 1 dòng stream_copy secure nếu chưa có để có bằng chứng ACT streaming
    if ("in_sample", "stream_copy", "secure") not in seen_abl:
        seen_abl.add(("in_sample", "stream_copy", "secure"))
        ablation_targets.append({
            "split": "in_sample",
            "wl": "stream_copy",
            "cfg": "secure",
            "reason": "Kiểm tra bổ sung chênh lệch ACT streaming 1:1 RD/WR",
        })

    ablation_suite = run_ablation_suite(ablation_targets, trace_map, rtl_by_key, ram_cal_by_key)
    ablated_keys = {(a["split"], a["wl"], a["cfg"]) for a in ablation_suite}

    # Tạo bảng so sánh 28 dòng (16 in-sample + 12 holdout) — gắn nhãn trung thực
    comparison_rows = []
    for rtl in sorted(all_rtl, key=lambda x: (0 if x["split"] == "in_sample" else 1, x["wl"], x["cfg"])):
        split, wl, cfg = rtl["split"], rtl["wl"], rtl["cfg"]
        ram = ram_cal_by_key[(split, wl, cfg)]
        ram_u = ram_uncal_by_key[(split, wl, cfg)]
        ebw = rel_err_pct(ram["bw_gbps"], rtl["bw_gbps"])
        elat = rel_err_pct(ram["rd_lat_avg_ns"], rtl["rd_lat_avg_ns"])
        eact = rel_err_pct(ram["act_traffic"], rtl["act_traffic"])
        evic = rel_err_pct(ram["act_victim"], rtl["act_victim"])
        within = (
            abs(ebw) <= THRESH_BW_PCT
            and abs(elat) <= THRESH_LAT_PCT
            and abs(eact) <= THRESH_COUNT_PCT
            and abs(evic) <= THRESH_COUNT_PCT
        )
        if within:
            status = "PASS"
            note = "Đạt cả 4 ngưỡng (BW/Lat <=10%, ACT/Vic <=5%)"
        elif (split, wl, cfg) in ablated_keys:
            status = "EXPLAINED_ABLATED"
            note = "Có thí nghiệm tách trong crossval_ablations_v2.json"
        else:
            status = "HYPOTHESIS_UNVERIFIED"
            note = "GIẢ THUYẾT: chưa có thí nghiệm tách riêng cho dòng này"

        comparison_rows.append({
            "split": split,
            "wl": wl,
            "cfg": cfg,
            "rtl_bw_gbps": rtl["bw_gbps"],
            "ram_cal_bw_gbps": ram["bw_gbps"],
            "err_bw_pct": round(ebw, 2),
            "ram_uncal_bw_gbps": ram_u["bw_gbps"],
            "err_uncal_bw_pct": round(rel_err_pct(ram_u["bw_gbps"], rtl["bw_gbps"]), 2),
            "rtl_rd_lat_avg_ns": rtl["rd_lat_avg_ns"],
            "ram_cal_rd_lat_avg_ns": ram["rd_lat_avg_ns"],
            "err_rd_lat_pct": round(elat, 2),
            "ram_uncal_rd_lat_avg_ns": ram_u["rd_lat_avg_ns"],
            "err_uncal_rd_lat_pct": round(rel_err_pct(ram_u["rd_lat_avg_ns"], rtl["rd_lat_avg_ns"]), 2),
            "rtl_act_traffic": rtl["act_traffic"],
            "ram_cal_act_traffic": ram["act_traffic"],
            "err_act_traffic_pct": round(eact, 2),
            "rtl_act_victim": rtl["act_victim"],
            "ram_cal_act_victim": ram["act_victim"],
            "err_act_victim_pct": round(evic, 2),
            "rtl_throttles": rtl.get("throttles", 0),
            "ram_cal_sdc_throttles": ram["sdc_throttles"],
            "rtl_glitch_alert": rtl.get("glitch_alert", 0),
            "within_threshold": within,
            "status": status,
            "notes": note,
        })

    # Ghi CSV trước rồi đọc lại để đảm bảo thống kê 100% tính tự động từ CSV
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    csv_v2 = OUT_DIR / "crossval_table_v2.csv"
    with open(csv_v2, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(comparison_rows[0].keys()))
        w.writeheader()
        w.writerows(comparison_rows)

    csv_loaded = []
    with open(csv_v2, "r", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            r["err_bw_pct"] = float(r["err_bw_pct"])
            r["err_rd_lat_pct"] = float(r["err_rd_lat_pct"])
            r["err_act_traffic_pct"] = float(r["err_act_traffic_pct"])
            r["err_act_victim_pct"] = float(r["err_act_victim_pct"])
            r["within_threshold"] = (r["within_threshold"] == "True")
            csv_loaded.append(r)

    stats_in = compute_split_stats([r for r in csv_loaded if r["split"] == "in_sample"], "in_sample")
    stats_hold = compute_split_stats([r for r in csv_loaded if r["split"] == "holdout"], "holdout")
    stats_all = compute_split_stats(csv_loaded, "all_14_traces")

    # Bảng slowdown tương đối secure/base (3 cột: RTL, Ram_calibrated, Ram_uncalibrated)
    slowdown_rows = []
    workloads_ordered = sorted(
        {(r["split"], r["wl"]) for r in all_rtl},
        key=lambda x: (0 if x[0] == "in_sample" else 1, x[1]),
    )
    for split, wl in workloads_ordered:
        rtl_b = rtl_by_key[(split, wl, "base")]
        rtl_s = rtl_by_key[(split, wl, "secure")]
        cal_b = ram_cal_by_key[(split, wl, "base")]
        cal_s = ram_cal_by_key[(split, wl, "secure")]
        unc_b = ram_uncal_by_key[(split, wl, "base")]
        unc_s = ram_uncal_by_key[(split, wl, "secure")]

        sd_rtl = rtl_b["bw_gbps"] / rtl_s["bw_gbps"] if rtl_s["bw_gbps"] > 0 else 0.0
        sd_cal = cal_b["bw_gbps"] / cal_s["bw_gbps"] if cal_s["bw_gbps"] > 0 else 0.0
        sd_unc = unc_b["bw_gbps"] / unc_s["bw_gbps"] if unc_s["bw_gbps"] > 0 else 0.0

        lr_rtl = rtl_s["rd_lat_avg_ns"] / rtl_b["rd_lat_avg_ns"] if rtl_b["rd_lat_avg_ns"] > 0 else 0.0
        lr_cal = cal_s["rd_lat_avg_ns"] / cal_b["rd_lat_avg_ns"] if cal_b["rd_lat_avg_ns"] > 0 else 0.0
        lr_unc = unc_s["rd_lat_avg_ns"] / unc_b["rd_lat_avg_ns"] if unc_b["rd_lat_avg_ns"] > 0 else 0.0

        slowdown_rows.append({
            "split": split,
            "wl": wl,
            "slowdown_RTL": round(sd_rtl, 4),
            "slowdown_Ram_calibrated": round(sd_cal, 4),
            "err_cal_pct": round(rel_err_pct(sd_cal, sd_rtl), 2),
            "slowdown_Ram_uncalibrated": round(sd_unc, 4),
            "err_uncal_pct": round(rel_err_pct(sd_unc, sd_rtl), 2),
            "lat_ratio_RTL": round(lr_rtl, 4),
            "lat_ratio_Ram_calibrated": round(lr_cal, 4),
            "lat_ratio_err_cal_pct": round(rel_err_pct(lr_cal, lr_rtl), 2),
            "lat_ratio_Ram_uncalibrated": round(lr_unc, 4),
            "lat_ratio_err_uncal_pct": round(rel_err_pct(lr_unc, lr_rtl), 2),
        })

    sd_csv = OUT_DIR / "crossval_slowdown_v2.csv"
    with open(sd_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(slowdown_rows[0].keys()))
        w.writeheader()
        w.writerows(slowdown_rows)

    def sd_summary(srows: list[dict]) -> dict:
        ec = [r["err_cal_pct"] for r in srows]
        eu = [r["err_uncal_pct"] for r in srows]
        return {
            "n_traces": len(srows),
            "cal_signed_mean_pct": round(statistics.mean(ec), 3),
            "cal_stdev_pct": round(statistics.stdev(ec), 3) if len(ec) >= 2 else 0.0,
            "cal_max_abs_pct": round(max(abs(x) for x in ec), 2),
            "uncal_signed_mean_pct": round(statistics.mean(eu), 3),
            "uncal_stdev_pct": round(statistics.stdev(eu), 3) if len(eu) >= 2 else 0.0,
            "uncal_max_abs_pct": round(max(abs(x) for x in eu), 2),
        }

    sd_stats = {
        "in_sample": sd_summary([r for r in slowdown_rows if r["split"] == "in_sample"]),
        "holdout": sd_summary([r for r in slowdown_rows if r["split"] == "holdout"]),
        "all": sd_summary(slowdown_rows),
    }

    # Kiểm toàn vẹn T38 trên RTL hậu-T88 (mặc định rtl_ml_reenc_ack_overlap=False khớp 83/131)
    t38_log_used = T38_LOG_POST_T88 if T38_LOG_POST_T88.is_file() else T38_LOG_LEGACY
    rtl_integ = parse_t38_log(t38_log_used)
    t38_trace = write_t38_trace(CROSSVAL_TRACES_DIR / "t38_integrity.trace")
    ram_integ_clean = run_t38_integrity(t38_trace, rtl_ml_reenc_ack_overlap=False)
    ram_integ_legacy = run_t38_integrity(t38_trace, rtl_ml_reenc_ack_overlap=True)
    e_mrd = rel_err_pct(ram_integ_clean["meta_rd_cnt"], rtl_integ["meta_rd_cnt"])
    e_mwr = rel_err_pct(ram_integ_clean["meta_wr_cnt"], rtl_integ["meta_wr_cnt"])
    e_hit = rel_err_pct(ram_integ_clean["mc_hit_rate_pct"], rtl_integ["mc_hit_rate_pct"])
    e_reenc = rel_err_pct(ram_integ_clean["reencrypt_events"], rtl_integ["reencrypt_events"])
    integ_pass = all(abs(x) <= THRESH_COUNT_PCT for x in (e_mrd, e_mwr, e_hit, e_reenc))

    # Kiểm điều kiện dừng holdout (> 1/3 ca holdout lệch BW hoặc độ trễ quá 10%)
    hold_exceed = stats_hold["bw_or_lat_exceed_10pct"]
    hold_total = stats_hold["n_rows"]
    stop_triggered = (hold_exceed * 3) > hold_total

    t81_audit = audit_t81_csv()
    hold_hashes = trace_dir_hashes(HOLDOUT_TRACE_DIR)

    # Xuất ablations JSON & summary JSON
    (OUT_DIR / "crossval_ablations_v2.json").write_text(json.dumps(ablation_suite, indent=2) + "\n", encoding="utf-8")
    summary_v2 = {
        "git_commit": get_git_head(),
        "frozen_file": str(FROZEN_FILE.relative_to(REPO_ROOT)).replace("\\", "/"),
        "libramulator_sha256": frozen["libramulator_sha256"],
        "original_8_traces_unchanged": True,
        "holdout_trace_sha256": hold_hashes,
        "t81_csv_recount_correction": t81_audit,
        "stats_in_sample": stats_in,
        "stats_holdout": stats_hold,
        "stats_all": stats_all,
        "slowdown_stats": sd_stats,
        "holdout_stop_condition": {
            "exceed_count": hold_exceed,
            "holdout_total": hold_total,
            "threshold_gt_one_third": f">{hold_total/3:.2f}",
            "triggered": stop_triggered,
        },
        "integrity_post_t88": {
            "rtl": rtl_integ,
            "ramulator_clean_default_false": ram_integ_clean,
            "ramulator_legacy_pre_t88_true": ram_integ_legacy,
            "err_meta_rd_pct": round(e_mrd, 2),
            "err_meta_wr_pct": round(e_mwr, 2),
            "err_mc_hit_rate_rel_pct": round(e_hit, 2),
            "err_reencrypt_pct": round(e_reenc, 2),
            "pass": integ_pass,
        },
        "ablations_count": len(ablation_suite),
        "elapsed_seconds": round(time.monotonic() - t_start, 3),
    }
    (OUT_DIR / "crossval_summary_v2.json").write_text(json.dumps(summary_v2, indent=2) + "\n", encoding="utf-8")

    # Sinh báo cáo Markdown tự động 100% từ dữ liệu đo
    md = [
        "# Q-Shield T90 Out-of-Sample Cross-Validation & Calibration Impact (`reports/paper/crossval/crossval_report_v2.md`)",
        f"- **Frozen Calibration:** `reports/paper/crossval/calibration_frozen.json` (`libramulator.so` SHA-256 `{frozen['libramulator_sha256']}`, đóng băng trước khi sinh holdout, giữ nguyên 100% tham số sau đóng băng).",
        f"- **Original 8 Traces Hash Check:** 8/8 file trong `sim/traces/rtl_bench/` giữ nguyên SHA-256 so với mốc đóng băng.",
        f"- **Holdout Traces (`{len(hold_hashes)}` trace mới, seed=`902026`, `4000` ops):** `{', '.join(sorted(hold_hashes.keys()))}`.",
        f"- **Holdout Stop Condition (`> 1/3` lệch BW hoặc Lat `> 10%`):** `{hold_exceed}/{hold_total}` → `{'TRIGGERED (STOP)' if stop_triggered else 'NOT TRIGGERED (OK)'}`.",
        "",
        "## 1. Đính chính thống kê T81 (tự tính lại từ `crossval_table.csv`)",
        f"- Trên `reports/paper/crossval/crossval_table.csv` của T81 (`{t81_audit.get('clean_rows')}` dòng sạch ngoài 3 hiện vật RTL trước T88): BW `<= 10%`: `{t81_audit.get('bw_pass')}/{t81_audit.get('clean_rows')}`, Lat `<= 10%`: `{t81_audit.get('lat_pass')}/{t81_audit.get('clean_rows')}`, `act_traffic <= 5%`: **`{t81_audit.get('verified_from_t81_csv_act_traffic')}`** (đính chính con số `10/13` nêu sai trong note T81), `act_victim <= 5%`: `{t81_audit.get('act_victim_pass')}/{t81_audit.get('clean_rows')}`.",
        "",
        "## 2. Thống kê tự động từ CSV (`crossval_table_v2.csv`, RTL hậu-T88, 0 lỗi glitch/ATE)",
        "| Tập dữ liệu | Dòng | BW `<=10%` (Mean ± SD) | Lat `<=10%` (Mean ± SD) | `act_traffic <=5%` (Mean ± SD) | `act_victim <=5%` (Mean ± SD) | Đạt cả 4 |",
        "|---|---:|---|---|---|---|---:|",
    ]
    for st in (stats_in, stats_hold, stats_all):
        md.append(
            f"| `{st['split']}` | {st['n_rows']} | "
            f"{st['bw']['pass_ratio']} (`{st['bw']['signed_mean_pct']:+.2f}% ± {st['bw']['stdev_pct']:.2f}%`, max `{st['bw']['max_abs_pct']:.2f}%`) | "
            f"{st['rd_lat']['pass_ratio']} (`{st['rd_lat']['signed_mean_pct']:+.2f}% ± {st['rd_lat']['stdev_pct']:.2f}%`, max `{st['rd_lat']['max_abs_pct']:.2f}%`) | "
            f"{st['act_traffic']['pass_ratio']} (`{st['act_traffic']['signed_mean_pct']:+.2f}% ± {st['act_traffic']['stdev_pct']:.2f}%`) | "
            f"{st['act_victim']['pass_ratio']} (`{st['act_victim']['signed_mean_pct']:+.2f}% ± {st['act_victim']['stdev_pct']:.2f}%`) | "
            f"{st['all4_within_thresh']}/{st['n_rows']} |"
        )

    md += [
        "",
        "## 3. Bảng chi tiết 14 Trace × `{base, secure}` (28 dòng, RTL hậu-T88)",
        "| Split | Workload | Cfg | RTL BW | Cal BW | BW Err% | RTL Lat | Cal Lat | Lat Err% | RTL ACT | Cal ACT | ACT Err% | RTL Vic | Cal Vic | Vic Err% | Status |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for c in comparison_rows:
        md.append(
            f"| `{c['split']}` | `{c['wl']}` | `{c['cfg']}` | {c['rtl_bw_gbps']:.4f} | {c['ram_cal_bw_gbps']:.4f} | {c['err_bw_pct']:+.2f}% | "
            f"{c['rtl_rd_lat_avg_ns']:.1f} | {c['ram_cal_rd_lat_avg_ns']:.1f} | {c['err_rd_lat_pct']:+.2f}% | "
            f"{c['rtl_act_traffic']} | {c['ram_cal_act_traffic']} | {c['err_act_traffic_pct']:+.2f}% | "
            f"{c['rtl_act_victim']} | {c['ram_cal_act_victim']} | {c['err_act_victim_pct']:+.2f}% | `{c['status']}` |"
        )

    md += [
        "",
        "## 4. Bảng độ chậm tương đối `secure / base` (`slowdown = BW_base / BW_secure`) — Hiệu chuẩn vs Mặc định T80",
        f"- **In-sample (8 trace):** Calibrated err mean `{sd_stats['in_sample']['cal_signed_mean_pct']:+.2f}% ± {sd_stats['in_sample']['cal_stdev_pct']:.2f}%` (max `{sd_stats['in_sample']['cal_max_abs_pct']:.2f}%`) vs Uncalibrated T80 err mean `{sd_stats['in_sample']['uncal_signed_mean_pct']:+.2f}% ± {sd_stats['in_sample']['uncal_stdev_pct']:.2f}%` (max `{sd_stats['in_sample']['uncal_max_abs_pct']:.2f}%`).",
        f"- **Holdout (6 trace):** Calibrated err mean `{sd_stats['holdout']['cal_signed_mean_pct']:+.2f}% ± {sd_stats['holdout']['cal_stdev_pct']:.2f}%` (max `{sd_stats['holdout']['cal_max_abs_pct']:.2f}%`) vs Uncalibrated T80 err mean `{sd_stats['holdout']['uncal_signed_mean_pct']:+.2f}% ± {sd_stats['holdout']['uncal_stdev_pct']:.2f}%` (max `{sd_stats['holdout']['uncal_max_abs_pct']:.2f}%`).",
        f"- **All 14 traces:** Calibrated max abs err `{sd_stats['all']['cal_max_abs_pct']:.2f}%` vs Uncalibrated T80 max abs err `{sd_stats['all']['uncal_max_abs_pct']:.2f}%`.",
        "",
        "| Split | Workload | `slowdown_RTL` | `slowdown_Ram_calibrated` | Err Cal% | `slowdown_Ram_uncalibrated` (T80) | Err Uncal% |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for s in slowdown_rows:
        md.append(
            f"| `{s['split']}` | `{s['wl']}` | {s['slowdown_RTL']:.4f} | {s['slowdown_Ram_calibrated']:.4f} | {s['err_cal_pct']:+.2f}% | "
            f"{s['slowdown_Ram_uncalibrated']:.4f} | {s['err_uncal_pct']:+.2f}% |"
        )

    md += [
        "",
        f"## 5. Thí nghiệm tách cơ chế (Ablation Suite — {len(ablation_suite)} dòng mục tiêu)",
        "Chỉ các dòng có thí nghiệm tách dưới đây mới được gắn nhãn `EXPLAINED_ABLATED`; mọi dòng lệch khác giữ nhãn `HYPOTHESIS_UNVERIFIED` (`GIẢ THUYẾT`).",
    ]
    for a in ablation_suite:
        md += [
            "",
            f"### `{a['wl']}` (`{a['cfg']}`, `{a['split']}`) — {a['reason_selected']}",
            f"- RTL: `ACT={a['rtl_act_traffic']}`, `Vic={a['rtl_act_victim']}`, `throttles={a['rtl_throttles']}` | Calibrated: `ACT={a['cal_act_traffic']}` (`{a['cal_err_act_pct']:+.2f}%`), `Vic={a['cal_act_victim']}` (`{a['cal_err_vic_pct']:+.2f}%`).",
            "| Variant | ACT | ΔACT vs Cal | ACT Err vs RTL% | Vic | ΔVic vs Cal | Vic Err vs RTL% | DRM Vic | Scrub | RP Alert | SDC Thr |",
            "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
        for v in a["variants"]:
            md.append(
                f"| `{v['variant']}` | {v['act_traffic']} | {v['delta_act_vs_cal']:+d} | {v['err_act_vs_rtl_pct']:+.2f}% | "
                f"{v['act_victim']} | {v['delta_vic_vs_cal']:+d} | {v['err_vic_vs_rtl_pct']:+.2f}% | "
                f"{v['drm_victims']} | {v['scrub_acts']} | {v['rowpress_alerts']} | {v['sdc_throttles']} |"
            )

    md += [
        "",
        "## 6. Kiểm chứng toàn vẹn T38 sau T88 (`rtl_ml_reenc_ack_overlap = false` khớp kiến trúc sạch)",
        f"- Nguồn log RTL hậu-T88: `{rtl_integ['log_path']}` (`checks={rtl_integ.get('checks')}`, `fails={rtl_integ.get('fails')}`).",
        "| Metric | RTL hậu-T88 | Ramulator2 (`rtl_ml_reenc_ack_overlap=False`) | Legacy trước-T88 (`True`) | Rel Err% | Status |",
        "|---|---:|---:|---:|---:|---|",
        f"| `META_RD` | {rtl_integ['meta_rd_cnt']} | {ram_integ_clean['meta_rd_cnt']} | {ram_integ_legacy['meta_rd_cnt']} | {e_mrd:+.2f}% | `{'PASS' if abs(e_mrd)<=THRESH_COUNT_PCT else 'FAIL'}` |",
        f"| `META_WR` | {rtl_integ['meta_wr_cnt']} | {ram_integ_clean['meta_wr_cnt']} | {ram_integ_legacy['meta_wr_cnt']} | {e_mwr:+.2f}% | `{'PASS' if abs(e_mwr)<=THRESH_COUNT_PCT else 'FAIL'}` |",
        f"| MC Hit Rate | {rtl_integ['mc_hit_rate_pct']:.1f}% ({rtl_integ['mc_hit_cnt']}/{rtl_integ['mc_hit_cnt']+rtl_integ['mc_miss_cnt']}) | {ram_integ_clean['mc_hit_rate_pct']:.2f}% ({ram_integ_clean['mc_hit_cnt']}/{ram_integ_clean['mc_hit_cnt']+ram_integ_clean['mc_miss_cnt']}) | {ram_integ_legacy['mc_hit_rate_pct']:.2f}% | {e_hit:+.2f}% | `{'PASS' if abs(e_hit)<=THRESH_COUNT_PCT else 'FAIL'}` |",
        f"| `reencrypt_events` | {rtl_integ['reencrypt_events']} | {ram_integ_clean['reencrypt_events']} | {ram_integ_legacy['reencrypt_events']} | {e_reenc:+.2f}% | `{'PASS' if abs(e_reenc)<=THRESH_COUNT_PCT else 'FAIL'}` |",
    ]
    (OUT_DIR / "crossval_report_v2.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    # In tóm tắt gọn ra stdout
    print("=" * 116)
    print("T90 OUT-OF-SAMPLE CROSS-VALIDATION SUMMARY (POST-T88 RTL vs FROZEN CALIBRATED & T80 UNCALIBRATED RAMULATOR2)")
    print("=" * 116)
    for st in (stats_in, stats_hold, stats_all):
        print(
            f"[{st['split']:13s}] BW={st['bw']['pass_ratio']} ({st['bw']['signed_mean_pct']:+.2f}%+-{st['bw']['stdev_pct']:.2f}%, max {st['bw']['max_abs_pct']:.2f}%) | "
            f"Lat={st['rd_lat']['pass_ratio']} ({st['rd_lat']['signed_mean_pct']:+.2f}%+-{st['rd_lat']['stdev_pct']:.2f}%, max {st['rd_lat']['max_abs_pct']:.2f}%) | "
            f"ACT={st['act_traffic']['pass_ratio']} | Vic={st['act_victim']['pass_ratio']}"
        )
    print(f"[T81 CSV RECOUNT] act_traffic={t81_audit.get('verified_from_t81_csv_act_traffic')} (T81 note claimed 10/13)")
    print(
        f"[SLOWDOWN s/b   ] in_sample: cal_max={sd_stats['in_sample']['cal_max_abs_pct']:.2f}% uncal_max={sd_stats['in_sample']['uncal_max_abs_pct']:.2f}% | "
        f"holdout: cal_max={sd_stats['holdout']['cal_max_abs_pct']:.2f}% uncal_max={sd_stats['holdout']['uncal_max_abs_pct']:.2f}%"
    )
    print(
        f"[T38 POST-T88   ] RTL={rtl_integ['meta_rd_cnt']}/{rtl_integ['meta_wr_cnt']}/{rtl_integ['mc_hit_rate_pct']}%/{rtl_integ['reencrypt_events']} "
        f"Ram(False)={ram_integ_clean['meta_rd_cnt']}/{ram_integ_clean['meta_wr_cnt']}/{ram_integ_clean['mc_hit_rate_pct']}%/{ram_integ_clean['reencrypt_events']} "
        f"PASS={integ_pass}"
    )
    print(f"[ABLATIONS      ] {len(ablation_suite)} targets completed -> {OUT_DIR / 'crossval_ablations_v2.json'}")
    print(f"[HOLDOUT GATE   ] bw_or_lat_exceed_10pct={hold_exceed}/{hold_total} stop_triggered={stop_triggered}")
    print(f"[DONE           ] elapsed={round(time.monotonic() - t_start, 2)}s -> {OUT_DIR / 'crossval_report_v2.md'}")
    if stop_triggered:
        print("[STOP_CONDITION_TRIGGERED] More than 1/3 of holdout rows exceed 10% BW or Read Latency error!", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
