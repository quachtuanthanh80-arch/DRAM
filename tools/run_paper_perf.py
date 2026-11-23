# File: tools/run_paper_perf.py
# Chức năng: Khảo sát trace Chronus, đo MPKI, chạy ma trận Ramulator2 (Q-Shield và baseline) và xuất báo cáo T80.

import argparse
import concurrent.futures
import csv
import hashlib
import json
import math
import os
import random
try:
    import resource
except ImportError:
    resource = None
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RAMULATOR_PY = REPO_ROOT / "build" / "ramulator2" / "python"
CHRONUS_DIR = Path.home() / "refs" / "Chronus"
CPUTRACES_DIR = CHRONUS_DIR / "cputraces"
DISCOVERY_OUT = REPO_ROOT / "build" / "paper_perf_discovery.json"
QUICK_OUT = REPO_ROOT / "build" / "paper_perf_quick.json"
CHECKPOINT_FILE = REPO_ROOT / "build" / "paper_perf_checkpoint.jsonl"
T87_CHECKPOINT_FILE = REPO_ROOT / "build" / "paper_perf_t87_checkpoint.jsonl"
T91_CHECKPOINT_FILE = REPO_ROOT / "build" / "paper_perf_t91_checkpoint.jsonl"
T91_PILOT_OUT = REPO_ROOT / "build" / "paper_perf_t91_pilot.json"
PAPER_PERF_DIR = REPO_ROOT / "sim" / "paper_perf"
CONFIGS_DIR = PAPER_PERF_DIR / "configs"
ATTACKS_DIR = PAPER_PERF_DIR / "attacks"
REPORTS_DIR = REPO_ROOT / "reports" / "paper" / "perf"

NRH_VALUES = [1024, 512, 256, 128]
T91_NRH_VALUES = [1024, 128]
T91_NUM_MAX_CYCLES = 134_400_000        # 1.05 * tREFW (ctrl_cycles = 53,760,000 => 33.6 ms @ tCK=0.625 ns)
T91_NUM_EXPECTED_INSTS = 2_000_000_000  # < INT32_MAX; ensures every core stops at num_max_cycles
T91_REF_CYCLES = 53_760_000      # 13.44 ms reference point measured by reviewer
T91_SINGLE_WORKLOADS = [
    "429.mcf",      # High LLC MPKI (464.65), mandatory
    "tpch6",        # High LLC MPKI (17.30) / low DRAM MPKI (4.46), explicitly requested
    "tpch17",       # Medium LLC MPKI (6.76)
    "401.bzip2",    # Medium LLC MPKI (3.31), also attack co-runner
    "511.povray",   # Low LLC MPKI (0.36), long trace (3.22M lines)
    "458.sjeng",    # Low LLC MPKI (0.58), also attack co-runner
]
T91_MAX_RUN_SECONDS = 900.0             # Stop condition: any single run > 15 min
T91_MAX_WORKERS = 5                     # WSL 8 cores / 7 GB RAM cap
PARA_SEEDS = [123, 456, 789]
ALL_SCHEMES = [
    "Baseline",
    "PARA",
    "Graphene",
    "Hydra",
    "BlockHammer",
    "PRAC",
    "RFM",
    "QShield",
    "QShield_Integ",
]
T87_NEW_SCHEMES = [
    "PARA_ACT",
    "Graphene_ACT",
    "Hydra_ACT",
    "QShield_Integ",
]
ALL_SCHEMES_V2 = [
    "Baseline",
    "BlockHammer",
    "PARA_ACT",
    "Graphene_ACT",
    "Hydra_ACT",
    "QShield",
    "QShield_Integ",
    "PARA",
    "Graphene",
    "Hydra",
    "PRAC",
    "RFM",
]
DRAM_SUPPORT_MAP = {
    "Baseline": ("none", "generic_ddr_controller.cpp:8-80 (no mitigation)"),
    "BlockHammer": ("none", "blockhammer_controller.cpp:1-476 (controller-only throttling, no VRR/RFM)"),
    "PARA_ACT": ("none", "para_act.cpp:74-121 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)"),
    "Graphene_ACT": ("none", "graphene_act.cpp:100-178 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)"),
    "Hydra_ACT": ("none", "hydra_act.cpp:200-355 (commercial DRAM equivalent, ACT+PREpb radius=2, no VRR)"),
    "QShield": ("none", "qshield_controller.cpp:1255-1311 (standard ACT->tRAS->PREpb victim refresh)"),
    "QShield_Integ": ("none", "qshield_controller.cpp:1255-1311,1406-1425 (standard ACT->tRAS->PREpb + BMT/MAC)"),
    "PARA": ("vrr_non_jedec", "para.cpp:45-62 (requires non-JEDEC VRR command)"),
    "Graphene": ("vrr_non_jedec", "graphene.cpp:51-59,157-158 (requires non-JEDEC VRR command)"),
    "Hydra": ("vrr_non_jedec", "hydra.cpp:142-148,303-304,446-447 (requires non-JEDEC VRR command)"),
    "PRAC": ("in_dram", "prac_controller.cpp:36-40,160-177,225-260 (requires in-DRAM per-row counters + ABO + RFMab)"),
    "RFM": ("in_dram", "rfm_manager.cpp:69-75,131-132 (requires in-DRAM RFM target selection)"),
}
EXCLUDE_TRACES = {"mpki.csv", "atk1.trace", "atkrfm.trace"}
MIX_SEED = 20261121


def ensure_ramulator_import():
    py_str = str(RAMULATOR_PY)
    if py_str not in sys.path:
        sys.path.insert(0, py_str)
    import ramulator  # noqa: F401


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def count_lines(path: Path) -> int:
    cnt = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            cnt += chunk.count(b"\n")
    return cnt


def get_git_commit() -> str:
    try:
        r = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=True,
        )
        return r.stdout.strip()
    except Exception:
        return "unknown"


def read_meminfo():
    info = {}
    p = Path("/proc/meminfo")
    if p.is_file():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith(("MemTotal:", "MemAvailable:")):
                k, _, v = line.partition(":")
                info[k.strip()] = v.strip()
    return info


def discover():
    if not CPUTRACES_DIR.is_dir():
        print(f"ERROR: Chronus cputraces directory not found: {CPUTRACES_DIR}", file=sys.stderr)
        sys.exit(1)

    traces = []
    total_bytes = 0
    for entry in sorted(CPUTRACES_DIR.iterdir(), key=lambda p: p.name):
        if not entry.is_file():
            continue
        sz = entry.stat().st_size
        total_bytes += sz
        sample_lines = []
        with open(entry, "r", encoding="utf-8", errors="replace") as f:
            for _ in range(3):
                line = f.readline()
                if not line:
                    break
                sample_lines.append(line.rstrip("\r\n"))
        traces.append({
            "name": entry.name,
            "path": str(entry),
            "size_bytes": sz,
            "sample_lines": sample_lines,
        })

    mix_file = CHRONUS_DIR / "mixes" / "hpcasingle.mix"
    mix_lines = mix_file.read_text(encoding="utf-8", errors="replace").splitlines() if mix_file.is_file() else []
    base_cfg = CHRONUS_DIR / "base_config.yaml"
    base_cfg_text = base_cfg.read_text(encoding="utf-8", errors="replace") if base_cfg.is_file() else ""

    du_home = shutil.disk_usage(Path.home())
    du_repo = shutil.disk_usage(REPO_ROOT)

    payload = {
        "cputraces_dir": str(CPUTRACES_DIR),
        "trace_count": len(traces),
        "total_bytes": total_bytes,
        "total_gb": round(total_bytes / (1024 ** 3), 3),
        "traces": traces,
        "chronus_mix_reference_only": mix_lines,
        "chronus_base_config_reference_only": base_cfg_text,
        "host": {
            "cpu_count": os.cpu_count(),
            "meminfo": read_meminfo(),
            "disk_home_free_gb": round(du_home.free / (1024 ** 3), 2),
            "disk_repo_free_gb": round(du_repo.free / (1024 ** 3), 2),
        },
    }
    DISCOVERY_OUT.parent.mkdir(parents=True, exist_ok=True)
    DISCOVERY_OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"[discover] Found {len(traces)} trace files ({payload['total_gb']} GB) in {CPUTRACES_DIR}")
    for t in traces[:5]:
        print(f"  - {t['name']} ({t['size_bytes']} B): sample={t['sample_lines']}")
    print(f"[discover] Host CPU={payload['host']['cpu_count']}, Mem={payload['host']['meminfo']}")
    print(f"[discover] Wrote {DISCOVERY_OUT}")


def scheme_params_dict(scheme: str, n_rh: int, seed: int = 123) -> dict:
    """Return explicit, serializable parameters for a (scheme, n_rh, seed) configuration."""
    if scheme == "Baseline":
        return {"controller": "GenericDDR", "plugins": ["RowHammerObserver"]}
    if scheme in ("PARA", "PARA_ACT"):
        p = 1.0 - (1e-15 ** (1.0 / n_rh))
        d = {
            "controller": "GenericDDR",
            "plugin": "ParaAct" if scheme == "PARA_ACT" else "PARA",
            "threshold": round(p, 8),
            "seed": seed,
        }
        if scheme == "PARA_ACT":
            d["blast_radius"] = 2
        return d
    if scheme in ("Graphene", "Graphene_ACT"):
        act_th = n_rh // 2
        trefw_ns = 32_000_000
        trc_ns = 50
        n_entries = math.ceil((trefw_ns / trc_ns) / act_th) - 1
        d = {
            "controller": "GenericDDR",
            "plugin": "GrapheneAct" if scheme == "Graphene_ACT" else "Graphene",
            "activation_threshold": act_th,
            "num_table_entries": n_entries,
            "reset_period_ns": trefw_ns,
        }
        if scheme == "Graphene_ACT":
            d["blast_radius"] = 2
        return d
    if scheme in ("Hydra", "Hydra_ACT"):
        trk_th = n_rh // 2
        grp_th = max(16, int(0.8 * trk_th))
        d = {
            "controller": "GenericDDR",
            "plugin": "HydraAct" if scheme == "Hydra_ACT" else "Hydra",
            "hydra_tracking_threshold": trk_th,
            "hydra_group_threshold": grp_th,
            "hydra_row_group_size": 128,
            "hydra_reset_period_ns": 32_000_000,
            "hydra_rcc_num_per_rank": 4096,
        }
        if scheme == "Hydra_ACT":
            d["blast_radius"] = 2
        return d
    if scheme == "BlockHammer":
        return {
            "controller": "BlockHammer",
            "bf_trefw": 32_000_000,
            "bf_len_epoch": 32_000_000,
            "bf_trc": 50,
            "bf_num_rh": n_rh,
            "bf_ctr_thresh": n_rh // 2,
            "bf_ctr_count": 1024,
            "bf_num_hashes": 4,
            "bf_num_filters": 2,
        }
    if scheme == "PRAC":
        return {
            "controller": "PRAC",
            "abo_threshold": n_rh // 2,
            "abo_act_ns": 180,
            "abo_recovery_refs": 4,
            "abo_delay_acts": 4,
        }
    if scheme == "RFM":
        rfm_map = {1024: 80, 512: 40, 256: 32, 128: 16}
        return {
            "controller": "GenericDDR",
            "plugin": "RFMManager",
            "rfm_mode": "ab",
            "rfm_thresh": rfm_map[n_rh],
        }
    if scheme in ("QShield", "QShield_Integ"):
        sdc_map = {1024: 127, 512: 63, 256: 31, 128: 15}
        return {
            "controller": "QShield",
            "sdc_thresh": sdc_map[n_rh],
            "table_entries": 256,
            "dual_hash_en": True,
            "pxor_mode": True,
            "pxor_seed_hex": "A5A55A5A01234567",
            "refw_refs": 8192,
            "window_size_ctrl_cycles": 4096,
            "multibank_thresh": 2,
            "blast_radius": 2,
            "proq_depth": 32,
            "throttle_pace_clk": 80,
            "raammt_thresh": 32,
            "tras_max_ns": 21937,
            "rowpress_thresh_ns": 12500,
            "rowpress_curve": 0,
            "integrity_en": (scheme == "QShield_Integ"),
            "mc_sets": 16,
            "mc_ways": 4,
            "prot_lines": 1048576,
            "tree_levels": 4,
            "crypto_extra_lat_clk": 84,
        }
    raise ValueError(f"Unknown scheme: {scheme}")


def build_ramulator_components(scheme: str, n_rh: int, traces: list[str], num_expected_insts: int,
                               num_max_cycles: int, attacker_core_ids: list[int], seed: int,
                               meta_bypass_drm: bool = False):
    ensure_ramulator_import()
    import ramulator

    frontend = ramulator.frontend.BHO3(
        clock_ratio=5,
        ipc=4,
        inst_window_depth=128,
        llc_capacity_per_core="2MB",
        llc_num_mshr_per_core=16,
        traces=traces,
        num_expected_insts=num_expected_insts,
        num_max_cycles=num_max_cycles,
        attacker_core_ids=attacker_core_ids,
        translation=ramulator.translation.NoTranslation(max_addr=17179869184),
    )

    dram = ramulator.dram.DDR5_VRR(
        org_preset="DDR5_16Gb_x4",
        timing_preset="DDR5_3200C",
        rank=1,
    )

    observer = ramulator.controller_plugin.RowHammerObserver(n_rh=n_rh, refw_refs=8192)
    plugins = [observer]
    p = scheme_params_dict(scheme, n_rh, seed)

    if scheme == "PARA":
        plugins.append(ramulator.controller_plugin.PARA(threshold=p["threshold"], seed=seed))
    elif scheme == "PARA_ACT":
        plugins.append(ramulator.controller_plugin.ParaAct(
            threshold=p["threshold"], seed=seed, blast_radius=p["blast_radius"],
        ))
    elif scheme == "Graphene":
        plugins.append(ramulator.controller_plugin.Graphene(
            num_table_entries=p["num_table_entries"],
            activation_threshold=p["activation_threshold"],
            reset_period_ns=p["reset_period_ns"],
        ))
    elif scheme == "Graphene_ACT":
        plugins.append(ramulator.controller_plugin.GrapheneAct(
            num_table_entries=p["num_table_entries"],
            activation_threshold=p["activation_threshold"],
            reset_period_ns=p["reset_period_ns"],
            blast_radius=p["blast_radius"],
        ))
    elif scheme == "Hydra":
        plugins.append(ramulator.controller_plugin.Hydra(
            hydra_tracking_threshold=p["hydra_tracking_threshold"],
            hydra_group_threshold=p["hydra_group_threshold"],
            hydra_row_group_size=p["hydra_row_group_size"],
            hydra_reset_period_ns=p["hydra_reset_period_ns"],
            hydra_rcc_num_per_rank=p["hydra_rcc_num_per_rank"],
        ))
    elif scheme == "Hydra_ACT":
        plugins.append(ramulator.controller_plugin.HydraAct(
            hydra_tracking_threshold=p["hydra_tracking_threshold"],
            hydra_group_threshold=p["hydra_group_threshold"],
            hydra_row_group_size=p["hydra_row_group_size"],
            hydra_reset_period_ns=p["hydra_reset_period_ns"],
            hydra_rcc_num_per_rank=p["hydra_rcc_num_per_rank"],
            blast_radius=p["blast_radius"],
        ))
    elif scheme == "RFM":
        plugins.append(ramulator.controller_plugin.RFMManager(
            rfm_mode=p["rfm_mode"],
            rfm_thresh=p["rfm_thresh"],
        ))

    common_ctrl_kwargs = dict(
        dram=dram,
        scheduler=ramulator.scheduler.FRFCFS(),
        refresh_manager=ramulator.refresh_manager.AllBank(),
        row_policy=ramulator.row_policy.Open(),
        addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
        controller_plugins=plugins,
    )

    if scheme in ("Baseline", "PARA", "PARA_ACT", "Graphene", "Graphene_ACT", "Hydra", "Hydra_ACT", "RFM"):
        ctrl = ramulator.controller.GenericDDR(**common_ctrl_kwargs)
    elif scheme == "BlockHammer":
        ctrl = ramulator.controller.BlockHammer(
            **common_ctrl_kwargs,
            bf_trefw=p["bf_trefw"],
            bf_len_epoch=p["bf_len_epoch"],
            bf_trc=p["bf_trc"],
            bf_num_rh=p["bf_num_rh"],
            bf_ctr_thresh=p["bf_ctr_thresh"],
            bf_ctr_count=p["bf_ctr_count"],
            bf_num_hashes=p["bf_num_hashes"],
            bf_num_filters=p["bf_num_filters"],
        )
    elif scheme == "PRAC":
        ctrl = ramulator.controller.PRAC(
            **common_ctrl_kwargs,
            abo_threshold=p["abo_threshold"],
            abo_act_ns=p["abo_act_ns"],
            abo_recovery_refs=p["abo_recovery_refs"],
            abo_delay_acts=p["abo_delay_acts"],
        )
    elif scheme in ("QShield", "QShield_Integ"):
        ctrl = ramulator.controller.QShield(
            **common_ctrl_kwargs,
            sdc_thresh=p["sdc_thresh"],
            table_entries=p["table_entries"],
            dual_hash_en=p["dual_hash_en"],
            pxor_mode=p["pxor_mode"],
            pxor_seed_hex=p["pxor_seed_hex"],
            refw_refs=p["refw_refs"],
            window_size_ctrl_cycles=p["window_size_ctrl_cycles"],
            multibank_thresh=p["multibank_thresh"],
            blast_radius=p["blast_radius"],
            proq_depth=p["proq_depth"],
            throttle_pace_clk=p["throttle_pace_clk"],
            raammt_thresh=p["raammt_thresh"],
            tras_max_ns=p["tras_max_ns"],
            rowpress_thresh_ns=p["rowpress_thresh_ns"],
            rowpress_curve=p["rowpress_curve"],
            integrity_en=p["integrity_en"],
            mc_sets=p["mc_sets"],
            mc_ways=p["mc_ways"],
            prot_lines=p["prot_lines"],
            tree_levels=p["tree_levels"],
            crypto_extra_lat_clk=p["crypto_extra_lat_clk"],
            meta_bypass_drm=meta_bypass_drm,
        )
    else:
        raise ValueError(f"Unsupported scheme: {scheme}")

    mem = ramulator.memory_system.GenericDRAM(
        clock_ratio=2,
        controllers=[ctrl],
        channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
    )
    return frontend, mem


def extract_plugin_stats(ctrl_stats: dict, impl_name: str) -> dict:
    plug = ctrl_stats.get("controller_plugin")
    if isinstance(plug, dict):
        return plug if plug.get("impl") == impl_name else {}
    if isinstance(plug, list):
        for item in plug:
            if isinstance(item, dict) and item.get("impl") == impl_name:
                return item
    return {}


def run_single_job(job: dict) -> dict:
    """Execute one Ramulator2 simulation inside a subprocess and return flat metrics."""
    t0 = time.monotonic()
    scheme = job["scheme"]
    n_rh = job["n_rh"]
    seed = job.get("seed", 123)
    traces = job["traces"]
    num_expected_insts = job["num_expected_insts"]
    num_max_cycles = job["num_max_cycles"]
    attacker_core_ids = job.get("attacker_core_ids", [])

    result = {
        "job_id": job["job_id"],
        "category": job["category"],
        "workload": job["workload"],
        "scheme": scheme,
        "n_rh": n_rh,
        "seed": seed,
        "num_cores": len(traces),
        "num_expected_insts": num_expected_insts,
        "num_max_cycles": num_max_cycles,
        "status": "OK",
        "error": "",
    }

    try:
        ensure_ramulator_import()
        import ramulator

        meta_bypass_drm = bool(job.get("meta_bypass_drm", False))
        fe, mem = build_ramulator_components(
            scheme, n_rh, traces, num_expected_insts, num_max_cycles, attacker_core_ids, seed,
            meta_bypass_drm=meta_bypass_drm,
        )
        sim = ramulator.Simulation(fe, mem)
        sim.run()
        sim.finalize()
        stats = sim.stats

        fe_stats = stats.get("frontend", {})
        ms_stats = stats.get("memory_system", {})
        ctrl_stats = ms_stats.get("controller", {})
        obs = extract_plugin_stats(ctrl_stats, "RowHammerObserver")
        pa_stats = extract_plugin_stats(ctrl_stats, "ParaAct")
        ga_stats = extract_plugin_stats(ctrl_stats, "GrapheneAct")
        ha_stats = extract_plugin_stats(ctrl_stats, "HydraAct")

        num_cores = len(traces)
        core_ipcs = []
        core_cycles = []
        core_insts = []
        hit_max_any = False
        for c in range(num_cores):
            cyc = int(fe_stats.get(f"cycles_recorded_core_{c}", 0))
            insts = int(fe_stats.get(f"insts_recorded_core_{c}", 0))
            if cyc <= 0:
                hit_max_any = True
                cyc = num_max_cycles
            ipc = (insts / cyc) if cyc > 0 else 0.0
            core_cycles.append(cyc)
            core_insts.append(insts)
            core_ipcs.append(ipc)

        llc_misses = int(fe_stats.get("llc_read_misses", 0)) + int(fe_stats.get("llc_write_misses", 0))
        total_insts = sum(core_insts) if sum(core_insts) > 0 else num_expected_insts * num_cores
        llc_mpki = (llc_misses * 1000.0) / total_insts
        dram_reqs = int(ctrl_stats.get("num_read_reqs", 0)) + int(ctrl_stats.get("num_write_reqs", 0))
        dram_mpki = (dram_reqs * 1000.0) / total_insts

        obs_vrr = int(obs.get("obs_num_vrr", 0))
        obs_rfmab = int(obs.get("obs_num_rfmab", 0))
        qs_vic = int(ctrl_stats.get("qshield_victim_refreshes", 0))
        act_vic = (
            int(pa_stats.get("para_act_victim_refreshes", 0))
            + int(ga_stats.get("graphene_act_victim_refreshes", 0))
            + int(ha_stats.get("hydra_act_victim_refreshes", 0))
        )
        act_trig = (
            int(pa_stats.get("para_act_triggers", 0))
            + int(ga_stats.get("graphene_act_triggers", 0))
            + int(ha_stats.get("hydra_act_triggers", 0))
        )
        act_drop = (
            int(pa_stats.get("para_act_dropped", 0))
            + int(ga_stats.get("graphene_act_dropped", 0))
            + int(ha_stats.get("hydra_act_dropped", 0))
        )
        prev_refs = obs_vrr + qs_vic + act_vic + obs_rfmab
        ctrl_cycles_val = int(ctrl_stats.get("cycles", 0))
        sim_time_ms = round(ctrl_cycles_val * 0.625e-6, 6)
        peak_rss_mb = 0.0
        if resource is not None:
            peak_rss_mb = round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0, 2)

        result.update({
            "dram_support": DRAM_SUPPORT_MAP.get(scheme, ("chưa kiểm", ""))[0],
            "hit_max_cycles": hit_max_any,
            "core_ipcs": core_ipcs,
            "core_cycles": core_cycles,
            "core_insts": core_insts,
            "mean_ipc": statistics.mean(core_ipcs),
            "ctrl_cycles": ctrl_cycles_val,
            "sim_time_ms": sim_time_ms,
            "peak_rss_mb": peak_rss_mb,
            "avg_read_latency": float(ctrl_stats.get("avg_read_latency", 0.0)),
            "total_throughput_MBps": float(ctrl_stats.get("total_throughput_MBps", 0.0)),
            "llc_read_access": int(fe_stats.get("llc_read_access", 0)),
            "llc_write_access": int(fe_stats.get("llc_write_access", 0)),
            "llc_read_misses": int(fe_stats.get("llc_read_misses", 0)),
            "llc_write_misses": int(fe_stats.get("llc_write_misses", 0)),
            "llc_mshr_blacklisted": int(fe_stats.get("llc_mshr_blacklisted", 0)),
            "llc_mpki": llc_mpki,
            "dram_mpki": dram_mpki,
            "num_read_reqs": int(ctrl_stats.get("num_read_reqs", 0)),
            "num_write_reqs": int(ctrl_stats.get("num_write_reqs", 0)),
            "row_hits": int(ctrl_stats.get("row_hits", 0)),
            "row_misses": int(ctrl_stats.get("row_misses", 0)),
            "row_conflicts": int(ctrl_stats.get("row_conflicts", 0)),
            "obs_num_act": int(obs.get("obs_num_act", 0)),
            "obs_num_meta_act": int(obs.get("obs_num_meta_act", 0)),
            "obs_num_mit_act": int(obs.get("obs_num_mit_act", 0)),
            "obs_num_pre": int(obs.get("obs_num_pre", 0)),
            "obs_num_rd": int(obs.get("obs_num_rd", 0)),
            "obs_num_wr": int(obs.get("obs_num_wr", 0)),
            "obs_num_refab": int(obs.get("obs_num_refab", 0)),
            "obs_num_vrr": obs_vrr,
            "obs_num_rfmab": obs_rfmab,
            "obs_max_row_acts": int(obs.get("obs_max_row_acts", 0)),
            "obs_max_disturb_r1": int(obs.get("obs_max_disturb_r1", 0)),
            "obs_max_disturb_r2": int(obs.get("obs_max_disturb_r2", 0)),
            "obs_max_r1_bank": int(obs.get("obs_max_r1_bank", 0)),
            "obs_max_r1_row": int(obs.get("obs_max_r1_row", 0)),
            "obs_max_r1_row_is_meta": int(obs.get("obs_max_r1_row_is_meta", 0)),
            "obs_max_r1_aggr_meta_acts": int(obs.get("obs_max_r1_aggr_meta_acts", 0)),
            "obs_max_r1_aggr_mit_acts": int(obs.get("obs_max_r1_aggr_mit_acts", 0)),
            "obs_max_r1_aggr_user_acts": int(obs.get("obs_max_r1_aggr_user_acts", 0)),
            "obs_rows_exceeding_nrh_r1": int(obs.get("obs_rows_exceeding_nrh_r1", 0)),
            "obs_rows_exceeding_nrh_r2": int(obs.get("obs_rows_exceeding_nrh_r2", 0)),
            "preventive_refreshes": prev_refs,
            "act_mit_triggers": act_trig,
            "act_mit_victim_refreshes": act_vic,
            "act_mit_dropped": act_drop,
            "qshield_sdc_throttles": int(ctrl_stats.get("qshield_sdc_throttles", 0)),
            "qshield_coordinated_throttles": int(ctrl_stats.get("qshield_coordinated_throttles", 0)),
            "qshield_victim_refreshes": qs_vic,
            "qshield_mit_acts": int(ctrl_stats.get("qshield_mit_acts", 0)),
            "qshield_rfm_count": int(ctrl_stats.get("qshield_rfm_count", 0)),
            "qshield_rowpress_alerts": int(ctrl_stats.get("qshield_rowpress_alerts", 0)),
            "qshield_tras_clamps": int(ctrl_stats.get("qshield_tras_clamps", 0)),
            "qshield_proq_blocks": int(ctrl_stats.get("qshield_proq_blocks", 0)),
            "qshield_pace_defers": int(ctrl_stats.get("qshield_pace_defers", 0)),
            "qshield_mc_hits": int(ctrl_stats.get("qshield_mc_hits", 0)),
            "qshield_mc_misses": int(ctrl_stats.get("qshield_mc_misses", 0)),
            "qshield_meta_rd_cnt": int(ctrl_stats.get("qshield_meta_rd_cnt", 0)),
            "qshield_meta_wr_cnt": int(ctrl_stats.get("qshield_meta_wr_cnt", 0)),
            "qshield_reencrypt_events": int(ctrl_stats.get("qshield_reencrypt_events", 0)),
            "elapsed_s": round(time.monotonic() - t0, 3),
        })
    except Exception as exc:
        result["status"] = "UNSUPPORTED"
        result["error"] = f"{type(exc).__name__}: {exc}"
        result["elapsed_s"] = round(time.monotonic() - t0, 3)

    return result


def run_jobs_pool(jobs: list[dict], max_workers: int, label: str, checkpoint_path: Path = None,
                  fresh_workers: bool = False, log_every: int = 20) -> list[dict]:
    done_map = {}
    if checkpoint_path and checkpoint_path.is_file():
        for line in checkpoint_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip():
                continue
            rec = json.loads(line)
            done_map[rec["job_id"]] = rec

    wanted_ids = {j["job_id"] for j in jobs}
    cached_here = [done_map[jid] for jid in wanted_ids if jid in done_map]
    pending = [j for j in jobs if j["job_id"] not in done_map]
    print(f"[{label}] Total jobs={len(jobs)}, cached={len(cached_here)}, running={len(pending)} (workers={max_workers})", flush=True)

    results = list(done_map.values())
    if not pending:
        return results

    t0 = time.monotonic()
    completed = 0
    err_printed = 0
    if max_workers <= 1:
        for j in pending:
            r = run_single_job(j)
            results.append(r)
            completed += 1
            if checkpoint_path:
                with open(checkpoint_path, "a", encoding="utf-8") as cf:
                    cf.write(json.dumps(r) + "\n")
            if r["status"] != "OK" and err_printed < 3:
                err_printed += 1
                print(f"[{label}] ERROR {j['job_id']}: {r['error']}", flush=True)
            if completed % max(1, min(10, log_every)) == 0 or completed == len(pending) or r["status"] != "OK":
                print(
                    f"[{label}] {completed}/{len(pending)} ({time.monotonic()-t0:.1f}s) "
                    f"last={j['job_id']} status={r['status']} elapsed={r.get('elapsed_s')}s "
                    f"sim_ms={r.get('sim_time_ms')} rss={r.get('peak_rss_mb')}MB",
                    flush=True,
                )
    else:
        pool_kwargs = {"max_workers": max_workers}
        if fresh_workers and sys.version_info >= (3, 11):
            pool_kwargs["max_tasks_per_child"] = 1
        with concurrent.futures.ProcessPoolExecutor(**pool_kwargs) as ex:
            futs = {ex.submit(run_single_job, j): j for j in pending}
            for fut in concurrent.futures.as_completed(futs):
                j = futs[fut]
                r = fut.result()
                results.append(r)
                completed += 1
                if checkpoint_path:
                    with open(checkpoint_path, "a", encoding="utf-8") as cf:
                        cf.write(json.dumps(r) + "\n")
                if r["status"] != "OK" and err_printed < 3:
                    err_printed += 1
                    print(f"[{label}] ERROR {j['job_id']}: {r['error']}", flush=True)
                if completed % max(1, log_every) == 0 or completed == len(pending) or r["status"] != "OK":
                    print(
                        f"[{label}] {completed}/{len(pending)} ({time.monotonic()-t0:.1f}s) "
                        f"last={j['job_id']} status={r['status']} elapsed={r.get('elapsed_s')}s "
                        f"sim_ms={r.get('sim_time_ms')} rss={r.get('peak_rss_mb')}MB",
                        flush=True,
                    )

    return results


def write_scheme_configs():
    CONFIGS_DIR.mkdir(parents=True, exist_ok=True)
    common = {
        "frontend": {
            "impl": "BHO3",
            "clock_ratio": 5,
            "ipc": 4,
            "inst_window_depth": 128,
            "llc_capacity_per_core": "2MB",
            "llc_num_mshr_per_core": 16,
            "translation": {"impl": "NoTranslation", "max_addr": 17179869184},
        },
        "memory_system": {
            "impl": "GenericDRAM",
            "clock_ratio": 2,
            "channel_mapper": {"impl": "CacheLineInterleave"},
        },
        "dram": {
            "impl": "DDR5_VRR",
            "org_preset": "DDR5_16Gb_x4",
            "timing_preset": "DDR5_3200C",
            "rank": 1,
        },
        "scheduler": {"impl": "FRFCFS"},
        "refresh_manager": {"impl": "AllBank"},
        "row_policy": {"impl": "Open"},
        "addr_mapper": {"impl": "RoBaRaCoCh"},
    }
    for scheme in ALL_SCHEMES:
        cfg = {
            "scheme": scheme,
            "common": common,
            "per_nrh": {str(nrh): scheme_params_dict(scheme, nrh, 123) for nrh in NRH_VALUES},
        }
        if scheme == "PARA":
            cfg["seeds"] = PARA_SEEDS
        (CONFIGS_DIR / f"{scheme.lower()}.json").write_text(json.dumps(cfg, indent=2), encoding="utf-8")


def measure_mpki(insts: int = 5_000_000):
    t0 = time.monotonic()
    if not CPUTRACES_DIR.is_dir():
        print(f"ERROR: Missing {CPUTRACES_DIR}", file=sys.stderr)
        sys.exit(1)

    trace_files = [
        p for p in sorted(CPUTRACES_DIR.iterdir(), key=lambda x: x.name)
        if p.is_file() and p.name not in EXCLUDE_TRACES
    ]
    small_jobs = []
    large_jobs = []
    size_map = {}
    for p in trace_files:
        sz = p.stat().st_size
        size_map[p.name] = sz
        job = {
            "job_id": f"mpki__{p.name}",
            "category": "mpki_probe",
            "workload": p.name,
            "scheme": "Baseline",
            "n_rh": 1024,
            "seed": 123,
            "traces": [str(p)],
            "num_expected_insts": insts,
            "num_max_cycles": insts * 25,
            "attacker_core_ids": [],
        }
        if sz <= 250 * 1024 * 1024:
            small_jobs.append(job)
        else:
            large_jobs.append(job)

    res_small = run_jobs_pool(small_jobs, max_workers=4, label="mpki_small")
    res_large = run_jobs_pool(large_jobs, max_workers=1, label="mpki_large")
    all_res = sorted(res_small + res_large, key=lambda r: r.get("llc_mpki", -1.0), reverse=True)

    ok_res = [r for r in all_res if r["status"] == "OK"]
    if len(ok_res) < 20:
        print(f"ERROR: Only {len(ok_res)} traces succeeded MPKI probe (< 20)", file=sys.stderr)
        sys.exit(1)

    # Save full MPKI characterization
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    mpki_csv = REPORTS_DIR / "mpki_characterization.csv"
    mpki_fields = [
        "workload", "size_bytes", "status", "llc_mpki", "dram_mpki", "mean_ipc",
        "ctrl_cycles", "llc_read_misses", "llc_write_misses", "num_read_reqs",
        "num_write_reqs", "obs_num_act", "hit_max_cycles", "elapsed_s", "error",
    ]
    with open(mpki_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=mpki_fields)
        w.writeheader()
        for r in all_res:
            row = {k: r.get(k, "") for k in mpki_fields}
            row["size_bytes"] = size_map[r["workload"]]
            w.writerow(row)

    # Select 21 single-core workloads (7 Low, 7 Med, 7 High) from traces <= 300 MB (fallback <= 400 MB)
    eligible = [r for r in ok_res if size_map[r["workload"]] <= 300 * 1024 * 1024]
    if len(eligible) < 21:
        eligible = [r for r in ok_res if size_map[r["workload"]] <= 400 * 1024 * 1024]

    mpkis = sorted(r["llc_mpki"] for r in eligible)
    # Clean round thresholds if each bin gets >= 7 traces; otherwise tertiles rounded to 1 decimal
    low_th, high_th = 2.0, 10.0
    if not (sum(1 for x in mpkis if x < low_th) >= 7 and
            sum(1 for x in mpkis if low_th <= x < high_th) >= 7 and
            sum(1 for x in mpkis if x >= high_th) >= 7):
        n = len(mpkis)
        low_th = round(mpkis[n // 3], 2)
        high_th = round(mpkis[(2 * n) // 3], 2)

    low_pool = sorted([r for r in eligible if r["llc_mpki"] < low_th], key=lambda r: r["llc_mpki"])
    med_pool = sorted([r for r in eligible if low_th <= r["llc_mpki"] < high_th], key=lambda r: r["llc_mpki"])
    high_pool = sorted([r for r in eligible if r["llc_mpki"] >= high_th], key=lambda r: r["llc_mpki"], reverse=True)

    def pick_spread(pool, k):
        if len(pool) <= k:
            return pool
        idxs = [int(round(i * (len(pool) - 1) / (k - 1))) for i in range(k)]
        return [pool[idx] for idx in idxs]

    sel_high = pick_spread(high_pool, 7)
    sel_med = pick_spread(med_pool, 7)
    sel_low = pick_spread(low_pool, 7)
    for r in sel_high:
        r["mpki_group"] = "High"
    for r in sel_med:
        r["mpki_group"] = "Medium"
    for r in sel_low:
        r["mpki_group"] = "Low"
    selected_21 = sel_high + sel_med + sel_low

    # Hash & line-count only the selected workloads (plus small attack traces later)
    trace_meta = {}
    for r in selected_21:
        name = r["workload"]
        p = CPUTRACES_DIR / name
        trace_meta[name] = {
            "name": name,
            "path": str(p),
            "size_bytes": p.stat().st_size,
            "sha256": sha256_file(p),
            "lines": count_lines(p),
            "llc_mpki": round(r["llc_mpki"], 4),
            "dram_mpki": round(r["dram_mpki"], 4),
            "baseline_ipc_5m": round(r["mean_ipc"], 4),
            "group": r["mpki_group"],
        }

    # Build 20 seeded 4-core mixes
    rng = random.Random(MIX_SEED)
    high_names = [r["workload"] for r in sel_high]
    med_names = [r["workload"] for r in sel_med]
    low_names = [r["workload"] for r in sel_low]
    mixes = []
    for idx in range(5):
        mixes.append({"name": f"mix_H_{idx+1}", "type": "HHHH", "cores": [rng.choice(high_names) for _ in range(4)]})
    for idx in range(5):
        mixes.append({"name": f"mix_M_{idx+1}", "type": "MMMM", "cores": [rng.choice(med_names) for _ in range(4)]})
    for idx in range(5):
        mixes.append({"name": f"mix_L_{idx+1}", "type": "LLLL", "cores": [rng.choice(low_names) for _ in range(4)]})
    for idx in range(5):
        cores = [rng.choice(high_names), rng.choice(med_names), rng.choice(low_names), rng.choice(high_names + med_names)]
        rng.shuffle(cores)
        mixes.append({"name": f"mix_X_{idx+1}", "type": "Mixed", "cores": cores})

    # Write WORKLOADS.md
    PAPER_PERF_DIR.mkdir(parents=True, exist_ok=True)
    md_lines = [
        "# Q-Shield Performance Evaluation Workloads (`sim/paper_perf/WORKLOADS.md`)",
        "Chức năng: Danh mục trace Chronus, kết quả đo MPKI không giảm thiểu, 21 workload đơn nhân và 20 tổ hợp 4 nhân có seed.",
        "",
        "## 1. Nguồn và giấy phép",
        "- Bộ trace: **Chronus CPU Traces** (`~/refs/Chronus/cputraces/`)",
        "- Nguồn công bố: Zenodo DOI `10.5281/zenodo.14281771` (2024-12-05)",
        "- Giấy phép: **CC-BY-4.0** (chỉ ghi đường dẫn, hash SHA-256 và số dòng; không chép file trace vào repo).",
        f"- Đo MPKI bằng cấu hình `Baseline` (`DDR5_16Gb_x4`, `DDR5_3200C`, 1 kênh, 1 rank, `BHO3` 2MB LLC/core) với `num_expected_insts = {insts}`.",
        f"- Ngưỡng phân nhóm LLC MPKI (tự đo trên {len(ok_res)} trace hợp lệ, chọn từ tập `<= 300 MB`):",
        f"  - **Low**: `LLC MPKI < {low_th}` ({len(low_pool)} trace khả dụng, chọn 7)",
        f"  - **Medium**: `{low_th} <= LLC MPKI < {high_th}` ({len(med_pool)} trace khả dụng, chọn 7)",
        f"  - **High**: `LLC MPKI >= {high_th}` ({len(high_pool)} trace khả dụng, chọn 7)",
        "",
        "## 2. 21 Workload đơn nhân đã chọn",
        "| Nhóm | Tên | Đường dẫn WSL | SHA-256 | Số dòng | Kích thước (B) | LLC MPKI | DRAM MPKI | IPC Baseline |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in selected_21:
        m = trace_meta[r["workload"]]
        md_lines.append(
            f"| {m['group']} | `{m['name']}` | `{m['path']}` | `{m['sha256']}` | {m['lines']} | {m['size_bytes']} | {m['llc_mpki']:.4f} | {m['dram_mpki']:.4f} | {m['baseline_ipc_5m']:.4f} |"
        )

    md_lines += [
        "",
        f"## 3. 20 Tổ hợp 4 nhân (Random Seed = `{MIX_SEED}`)",
        "| Mix | Loại | Core 0 | Core 1 | Core 2 | Core 3 |",
        "|---|---|---|---|---|---|",
    ]
    for mx in mixes:
        c = mx["cores"]
        md_lines.append(f"| `{mx['name']}` | {mx['type']} | `{c[0]}` | `{c[1]}` | `{c[2]}` | `{c[3]}` |")

    (PAPER_PERF_DIR / "WORKLOADS.md").write_text("\n".join(md_lines) + "\n", encoding="utf-8")

    # Save matrix_spec.json and per-scheme configs
    write_scheme_configs()
    matrix_spec = {
        "git_commit": get_git_commit(),
        "mpki_probe_insts": insts,
        "mpki_thresholds": {"low_lt": low_th, "high_ge": high_th},
        "mix_seed": MIX_SEED,
        "single_core": [trace_meta[r["workload"]] for r in selected_21],
        "four_core_mixes": mixes,
        "attack_corunners": [sel_high[3]["workload"], sel_med[3]["workload"], sel_low[3]["workload"]],
        "mpki_elapsed_s": round(time.monotonic() - t0, 2),
    }
    (CONFIGS_DIR / "matrix_spec.json").write_text(json.dumps(matrix_spec, indent=2), encoding="utf-8")
    (REPORTS_DIR / "mpki_characterization.json").write_text(
        json.dumps({"thresholds": matrix_spec["mpki_thresholds"], "runs": all_res}, indent=2),
        encoding="utf-8",
    )

    print(
        f"[measure-mpki] DONE in {matrix_spec['mpki_elapsed_s']}s: "
        f"{len(ok_res)}/{len(all_res)} OK, thresholds=({low_th}, {high_th}), "
        f"selected=21 single-core + 20 4-core mixes -> {PAPER_PERF_DIR / 'WORKLOADS.md'}"
    )


def update_workloads_attack_section(atk_paths: dict[str, Path], corunners: list[str]):
    wf = PAPER_PERF_DIR / "WORKLOADS.md"
    if not wf.is_file():
        return
    base_text = wf.read_text(encoding="utf-8").split("\n## 4. ")[0].rstrip()
    pattern_desc = {
        "double_sided": "2 kẻ tấn công (row 100, 102) kẹp nạn nhân row 101 + xả LLC 8-way",
        "many_sided": "18 kẻ tấn công (row 100..134 bước 2) tự xả LLC",
        "half_double": "4 kẻ tấn công (row 100, 101, 103, 104) quanh row 102 (R=1 và R=2)",
        "rowpress_hold": "Giữ hàng 100/102 qua 16 col (bubble=400) xen kẽ 80 vòng double-sided",
    }
    sec = [
        "",
        "## 4. 4 Kịch bản tấn công (1 kẻ tấn công + 3 lành tính)",
        f"- Co-runner lành tính (Core 1–3): `{', '.join(corunners)}` (trung vị 3 nhóm High/Medium/Low).",
        "| Kịch bản | Đường dẫn | SHA-256 | Số dòng | Mẫu tấn công |",
        "|---|---|---|---|---|",
    ]
    for name in sorted(atk_paths.keys()):
        p = Path(atk_paths[name])
        sec.append(
            f"| `{name}` | `sim/paper_perf/attacks/{p.name}` | `{sha256_file(p)}` | {count_lines(p)} | {pattern_desc.get(name, '')} |"
        )
    wf.write_text(base_text + "\n" + "\n".join(sec) + "\n", encoding="utf-8")


def build_jobs_for_matrix(spec: dict, benign_insts: int, attack_insts: int, quick: bool = False) -> list[dict]:
    jobs = []
    # Attack traces
    sys.path.insert(0, str(ATTACKS_DIR))
    import gen_attack_traces
    generated = gen_attack_traces.generate_all()
    atk_paths = {p.stem: str(p) for p in generated}
    update_workloads_attack_section({p.stem: p for p in generated}, spec["attack_corunners"])

    corunners = [str(CPUTRACES_DIR / name) for name in spec["attack_corunners"]]

    if quick:
        # Median Low, Med, High + 1 Mixed 4-core + all 4 attack scenarios
        sc = spec["single_core"]
        high0 = [x for x in sc if x["group"] == "High"][3]
        med0 = [x for x in sc if x["group"] == "Medium"][3]
        low0 = [x for x in sc if x["group"] == "Low"][3]
        single_list = [high0, med0, low0]
        mix_list = [next(x for x in spec["four_core_mixes"] if x["type"] == "Mixed")]
    else:
        single_list = spec["single_core"]
        mix_list = spec["four_core_mixes"]

    def add_scheme_jobs(category, wl_name, trace_list, insts, atk_ids):
        for nrh in NRH_VALUES:
            for scheme in ALL_SCHEMES:
                seeds = PARA_SEEDS if scheme == "PARA" else [123]
                for sd in seeds:
                    jobs.append({
                        "job_id": f"{category}__{wl_name}__{scheme}__nrh{nrh}__s{sd}",
                        "category": category,
                        "workload": wl_name,
                        "scheme": scheme,
                        "n_rh": nrh,
                        "seed": sd,
                        "traces": trace_list,
                        "num_expected_insts": insts,
                        "num_max_cycles": insts * 25,
                        "attacker_core_ids": atk_ids,
                    })

    for item in single_list:
        add_scheme_jobs("single", item["name"], [item["path"]], benign_insts, [])

    for mx in mix_list:
        tpaths = [str(CPUTRACES_DIR / c) for c in mx["cores"]]
        add_scheme_jobs("mix4", mx["name"], tpaths, benign_insts, [])

    for atk_name, atk_path in sorted(atk_paths.items()):
        tpaths = [atk_path] + corunners
        add_scheme_jobs("attack", atk_name, tpaths, attack_insts, [0])

    if not quick:
        # Phase-matched single-core Baseline alone runs for attack co-runners at exact attack_insts
        for cname in spec["attack_corunners"]:
            jobs.append({
                "job_id": f"attack_alone__{cname}__Baseline__nrh1024__s123",
                "category": "attack_alone",
                "workload": cname,
                "scheme": "Baseline",
                "n_rh": 1024,
                "seed": 123,
                "traces": [str(CPUTRACES_DIR / cname)],
                "num_expected_insts": attack_insts,
                "num_max_cycles": attack_insts * 25,
                "attacker_core_ids": [],
            })

    return jobs


def check_validity_gate(results: list[dict]) -> tuple[bool, list[dict]]:
    by_key = {(r["workload"], r["scheme"], r["n_rh"]): r for r in results if r["category"] == "attack"}
    atk_names = sorted({r["workload"] for r in results if r["category"] == "attack"})
    gate_rows = []
    all_ok = True

    for atk in atk_names:
        for nrh in NRH_VALUES:
            base = by_key.get((atk, "Baseline", nrh))
            qs = by_key.get((atk, "QShield", nrh))
            qsi = by_key.get((atk, "QShield_Integ", nrh))
            if not base or not qs or not qsi or base["status"] != "OK" or qs["status"] != "OK" or qsi["status"] != "OK":
                all_ok = False
                gate_rows.append({"attack": atk, "n_rh": nrh, "pass": False, "reason": "missing_or_error"})
                continue

            base_exceed = (base["obs_rows_exceeding_nrh_r1"] > 0) or (base["obs_rows_exceeding_nrh_r2"] > 0)
            qs_vic_ok = qs["qshield_victim_refreshes"] > 0
            qsi_vic_ok = qsi["qshield_victim_refreshes"] > 0
            qs_diff = (qs["ctrl_cycles"] != base["ctrl_cycles"]) or (qs["obs_num_act"] != base["obs_num_act"])
            qsi_diff = (qsi["ctrl_cycles"] != base["ctrl_cycles"]) or (qsi["qshield_meta_rd_cnt"] > 0)
            passed = base_exceed and qs_vic_ok and qsi_vic_ok and qs_diff and qsi_diff
            if not passed:
                all_ok = False
            gate_rows.append({
                "attack": atk,
                "n_rh": nrh,
                "pass": passed,
                "base_max_r1": base["obs_max_disturb_r1"],
                "base_max_r2": base["obs_max_disturb_r2"],
                "base_exceed_r1": base["obs_rows_exceeding_nrh_r1"],
                "base_exceed_r2": base["obs_rows_exceeding_nrh_r2"],
                "qs_vic_ref": qs["qshield_victim_refreshes"],
                "qs_max_r1": qs["obs_max_disturb_r1"],
                "qs_max_r2": qs["obs_max_disturb_r2"],
                "qs_rfm": qs["qshield_rfm_count"],
                "qs_rp_alerts": qs["qshield_rowpress_alerts"],
                "qs_tras_clamps": qs["qshield_tras_clamps"],
                "qsi_meta_rd": qsi["qshield_meta_rd_cnt"],
                "qsi_meta_wr": qsi["qshield_meta_wr_cnt"],
                "qs_ipc_ratio": round(qs["mean_ipc"] / base["mean_ipc"], 4) if base["mean_ipc"] > 0 else 0.0,
            })

    return all_ok, gate_rows


def aggregate_and_report(results: list[dict], spec: dict, benign_insts: int, attack_insts: int, total_elapsed_s: float):
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    commit = get_git_commit()
    cfg_hashes = {p.name: sha256_file(p) for p in sorted(CONFIGS_DIR.glob("*.json"))}

    # Lookup Baseline alone IPC for single-core, attack_alone, and Baseline run for every (category, workload, n_rh)
    base_single = {}        # (workload, n_rh) -> ipc
    base_attack_alone = {}  # workload -> ipc
    base_run = {}           # (category, workload, n_rh) -> result dict
    for r in results:
        if r["status"] == "OK" and r["scheme"] == "Baseline":
            base_run[(r["category"], r["workload"], r["n_rh"])] = r
            if r["category"] == "single":
                base_single[(r["workload"], r["n_rh"])] = r["mean_ipc"]
            elif r["category"] == "attack_alone":
                base_attack_alone[r["workload"]] = r["mean_ipc"]

    mix_cores_map = {mx["name"]: mx["cores"] for mx in spec["four_core_mixes"]}
    corunner_names = spec["attack_corunners"]

    # Enrich every row with weighted speedup, harmonic speedup, maximum slowdown
    for r in results:
        if r["status"] != "OK":
            continue
        nrh = r["n_rh"]
        b = base_run.get((r["category"], r["workload"], nrh))
        if r["category"] == "single":
            b_ipc = base_single.get((r["workload"], nrh), r["mean_ipc"])
            r["weighted_speedup"] = (r["mean_ipc"] / b_ipc) if b_ipc > 0 else 0.0
            r["harmonic_speedup"] = r["weighted_speedup"]
            r["max_slowdown"] = (b_ipc / r["mean_ipc"]) if r["mean_ipc"] > 0 else 0.0
        elif r["category"] == "mix4":
            cnames = mix_cores_map[r["workload"]]
            ratios = []
            slows = []
            for idx, cname in enumerate(cnames):
                alone = base_single.get((cname, nrh), 0.0)
                ipc_i = r["core_ipcs"][idx]
                if alone > 0 and ipc_i > 0:
                    ratios.append(ipc_i / alone)
                    slows.append(alone / ipc_i)
            r["weighted_speedup"] = sum(ratios) if ratios else 0.0
            r["harmonic_speedup"] = (len(slows) / sum(slows)) if slows else 0.0
            r["max_slowdown"] = max(slows) if slows else 0.0
            if b and b.get("weighted_speedup", 0) > 0:
                r["norm_weighted_speedup"] = r["weighted_speedup"] / b["weighted_speedup"]
        elif r["category"] == "attack":
            # Benign co-runners are cores 1, 2, 3; compare against phase-matched attack_alone when available
            ratios = []
            slows = []
            for idx, cname in enumerate(corunner_names, start=1):
                alone = base_attack_alone.get(cname, base_single.get((cname, nrh), 0.0))
                ipc_i = r["core_ipcs"][idx]
                if alone > 0 and ipc_i > 0:
                    ratios.append(ipc_i / alone)
                    slows.append(alone / ipc_i)
            r["weighted_speedup"] = sum(ratios) if ratios else 0.0
            r["harmonic_speedup"] = (len(slows) / sum(slows)) if slows else 0.0
            r["max_slowdown"] = max(slows) if slows else 0.0

    # Write flat per-run CSV
    runs_csv = REPORTS_DIR / "perf_runs.csv"
    run_cols = [
        "job_id", "category", "workload", "scheme", "n_rh", "seed", "status", "hit_max_cycles",
        "mean_ipc", "weighted_speedup", "harmonic_speedup", "max_slowdown", "ctrl_cycles",
        "avg_read_latency", "total_throughput_MBps", "preventive_refreshes", "obs_num_act",
        "obs_num_vrr", "obs_num_rfmab", "obs_max_disturb_r1", "obs_max_disturb_r2",
        "obs_rows_exceeding_nrh_r1", "obs_rows_exceeding_nrh_r2", "qshield_sdc_throttles",
        "qshield_coordinated_throttles", "qshield_victim_refreshes", "qshield_mit_acts",
        "qshield_rfm_count", "qshield_rowpress_alerts", "qshield_tras_clamps",
        "qshield_mc_hits", "qshield_mc_misses", "qshield_meta_rd_cnt", "qshield_meta_wr_cnt",
        "qshield_reencrypt_events", "elapsed_s", "error",
    ]
    with open(runs_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=run_cols)
        w.writeheader()
        for r in sorted(results, key=lambda x: (x["category"], x["n_rh"], x["workload"], x["scheme"], x["seed"])):
            w.writerow({k: r.get(k, "") for k in run_cols})

    # Aggregate per (category, scheme, n_rh), excluding auxiliary attack_alone reference runs
    # For PARA, first average across the 3 seeds per workload (reporting seed CI95 too)
    grouped = {}
    for r in results:
        if r["category"] == "attack_alone":
            continue
        grouped.setdefault((r["category"], r["scheme"], r["n_rh"]), []).append(r)

    summary_rows = []
    for (cat, scheme, nrh), items in sorted(grouped.items(), key=lambda x: (x[0][0], x[0][2], ALL_SCHEMES.index(x[0][1]))):
        ok_items = [x for x in items if x["status"] == "OK"]
        base_items = [x for x in grouped.get((cat, "Baseline", nrh), []) if x["status"] == "OK"]
        base_by_wl = {x["workload"]: x for x in base_items}

        # Group by workload to handle PARA multi-seed properly
        by_wl = {}
        for x in ok_items:
            by_wl.setdefault(x["workload"], []).append(x)

        ws_vals = []
        hs_vals = []
        ms_vals = []
        norm_ws_vals = []
        pref_vals = []
        max_r1_vals = []
        max_r2_vals = []
        exceed_r1_sum = 0
        exceed_r2_sum = 0
        seed_ci95_ws = 0.0
        t_crit_df2 = 4.3027  # Student-t 95% CI two-sided for n=3 seeds (df=2)

        per_wl_seed_cis = []
        for wl, w_runs in by_wl.items():
            ws_w = statistics.mean(x["weighted_speedup"] for x in w_runs)
            hs_w = statistics.mean(x["harmonic_speedup"] for x in w_runs)
            ms_w = statistics.mean(x["max_slowdown"] for x in w_runs)
            pref_w = statistics.mean(x["preventive_refreshes"] for x in w_runs)
            ws_vals.append(ws_w)
            hs_vals.append(hs_w)
            ms_vals.append(ms_w)
            pref_vals.append(pref_w)
            max_r1_vals.append(max(x["obs_max_disturb_r1"] for x in w_runs))
            max_r2_vals.append(max(x["obs_max_disturb_r2"] for x in w_runs))
            exceed_r1_sum += sum(x["obs_rows_exceeding_nrh_r1"] for x in w_runs)
            exceed_r2_sum += sum(x["obs_rows_exceeding_nrh_r2"] for x in w_runs)
            if wl in base_by_wl and base_by_wl[wl]["weighted_speedup"] > 0:
                norm_ws_vals.append(ws_w / base_by_wl[wl]["weighted_speedup"])
            if len(w_runs) >= 2:
                s = statistics.stdev(x["weighted_speedup"] for x in w_runs)
                per_wl_seed_cis.append(t_crit_df2 * s / math.sqrt(len(w_runs)))

        if per_wl_seed_cis:
            seed_ci95_ws = statistics.mean(per_wl_seed_cis)

        row = {
            "category": cat,
            "scheme": scheme,
            "n_rh": nrh,
            "runs_total": len(items),
            "runs_ok": len(ok_items),
            "runs_unsupported": len(items) - len(ok_items),
            "weighted_speedup_mean": round(statistics.mean(ws_vals), 4) if ws_vals else None,
            "norm_weighted_speedup_mean": round(statistics.mean(norm_ws_vals), 4) if norm_ws_vals else None,
            "seed_ci95_ws": round(seed_ci95_ws, 5) if per_wl_seed_cis else 0.0,
            "harmonic_speedup_mean": round(statistics.mean(hs_vals), 4) if hs_vals else None,
            "max_slowdown_mean": round(statistics.mean(ms_vals), 4) if ms_vals else None,
            "preventive_refreshes_mean": round(statistics.mean(pref_vals), 1) if pref_vals else None,
            "max_disturb_r1_worst": max(max_r1_vals) if max_r1_vals else None,
            "max_disturb_r2_worst": max(max_r2_vals) if max_r2_vals else None,
            "rows_exceeding_nrh_r1_sum": exceed_r1_sum if ok_items else None,
            "rows_exceeding_nrh_r2_sum": exceed_r2_sum if ok_items else None,
        }
        summary_rows.append(row)

    summary_csv = REPORTS_DIR / "perf_summary.csv"
    sum_cols = list(summary_rows[0].keys()) if summary_rows else []
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=sum_cols)
        w.writeheader()
        for r in summary_rows:
            w.writerow(r)

    gate_ok, gate_rows = check_validity_gate(results)
    trace_hashes = {x["name"]: x["sha256"] for x in spec["single_core"]}
    for p in sorted(ATTACKS_DIR.glob("*.trace")):
        trace_hashes[p.stem] = sha256_file(p)

    est_full_min = None
    if QUICK_OUT.is_file():
        try:
            qdata = json.loads(QUICK_OUT.read_text(encoding="utf-8"))
            est_full_min = qdata.get("projection", {}).get("est_full_total_min")
        except Exception:
            est_full_min = None
    actual_min = round(total_elapsed_s / 60.0, 2)

    summary_json = {
        "git_commit": commit,
        "upstream_commit": "72427a1bba3771564c4fb0e494ba02242fd1eaa7",
        "dram_energy_model": "N/A (not provided by upstream Ramulator2 commit 72427a1)",
        "benign_expected_insts": benign_insts,
        "attack_expected_insts": attack_insts,
        "estimated_full_min": est_full_min,
        "total_elapsed_s": round(total_elapsed_s, 2),
        "actual_elapsed_min": actual_min,
        "config_hashes": cfg_hashes,
        "trace_hashes": trace_hashes,
        "validity_gate_pass": gate_ok,
        "validity_gate_rows": gate_rows,
        "summary": summary_rows,
    }
    (REPORTS_DIR / "perf_summary.json").write_text(json.dumps(summary_json, indent=2), encoding="utf-8")

    # Markdown report
    md = [
        "# Q-Shield Ramulator2 Performance Evaluation (`reports/paper/perf/perf_report.md`)",
        f"- Commit: `{commit}` | Upstream Ramulator2: `72427a1bba3771564c4fb0e494ba02242fd1eaa7`",
        "- DRAM Energy: `N/A (not provided by upstream Ramulator2 commit 72427a1)`",
        f"- `num_expected_insts`: benign=`{benign_insts}`, attack=`{attack_insts}` | Estimated: `{est_full_min} min` | Actual: `{total_elapsed_s:.2f}s` (`{actual_min} min`)",
        f"- Validity Gate: `{'PASS' if gate_ok else 'FAIL'}`",
        "",
        "## Summary by Category, N_RH, and Scheme",
        "| Category | N_RH | Scheme | OK/Total | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in summary_rows:
        md.append(
            f"| {r['category']} | {r['n_rh']} | {r['scheme']} | {r['runs_ok']}/{r['runs_total']} | "
            f"{r['norm_weighted_speedup_mean']} | {r['seed_ci95_ws']} | {r['harmonic_speedup_mean']} | "
            f"{r['max_slowdown_mean']} | {r['preventive_refreshes_mean']} | "
            f"{r['max_disturb_r1_worst']} | {r['max_disturb_r2_worst']} |"
        )
    (REPORTS_DIR / "perf_report.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return gate_ok, gate_rows, summary_rows


def run_quick(benign_insts: int = 1_000_000, attack_insts: int = 500_000):
    spec_path = CONFIGS_DIR / "matrix_spec.json"
    if not spec_path.is_file():
        print(f"ERROR: Run --measure-mpki first to generate {spec_path}", file=sys.stderr)
        sys.exit(1)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    t0 = time.monotonic()
    jobs = build_jobs_for_matrix(spec, benign_insts=benign_insts, attack_insts=attack_insts, quick=True)
    results = run_jobs_pool(jobs, max_workers=4, label="quick")
    elapsed = round(time.monotonic() - t0, 2)

    gate_ok, gate_rows = check_validity_gate(results)
    err_rows = [r for r in results if r["status"] != "OK"]

    # Estimate full matrix runtime (benign=2M, attack=500K, 5/5/3/6 memory-safe pools, 1983 total runs)
    single_runs = [r for r in results if r["category"] == "single" and r["status"] == "OK"]
    mix4_runs = [r for r in results if r["category"] == "mix4" and r["status"] == "OK"]
    atk_runs = [r for r in results if r["category"] == "attack" and r["status"] == "OK"]
    avg_single_1m = statistics.mean(r["elapsed_s"] for r in single_runs) if single_runs else 1.0
    avg_mix4_1m = statistics.mean(r["elapsed_s"] for r in mix4_runs) if mix4_runs else 5.0
    avg_atk_500k = statistics.mean(r["elapsed_s"] for r in atk_runs) if atk_runs else 10.0

    # Parse/init time stays constant while simulation cycles scale with insts; linear scaling is a safe upper bound
    full_single_2m_s = (21 * 4 * 11 + 3) * (avg_single_1m * (2_000_000 / benign_insts)) / 5.0
    full_mix4_2m_s = (20 * 4 * 11) * (avg_mix4_1m * (2_000_000 / benign_insts)) / 4.2
    full_atk_500k_s = (4 * 4 * 11) * (avg_atk_500k * (500_000 / attack_insts)) / 6.0

    payload = {
        "elapsed_s": elapsed,
        "total_jobs": len(jobs),
        "ok_jobs": len(results) - len(err_rows),
        "error_jobs": len(err_rows),
        "errors_sample": err_rows[:10],
        "validity_gate_pass": gate_ok,
        "validity_gate_rows": gate_rows,
        "projection": {
            "avg_single_s_at_1m": round(avg_single_1m, 3),
            "avg_mix4_s_at_1m": round(avg_mix4_1m, 3),
            "avg_attack_s_at_500k": round(avg_atk_500k, 3),
            "est_full_single_2m_5w_min": round(full_single_2m_s / 60.0, 2),
            "est_full_mix4_2m_pools_min": round(full_mix4_2m_s / 60.0, 2),
            "est_full_attack_500k_6w_min": round(full_atk_500k_s / 60.0, 2),
            "est_full_total_min": round((full_single_2m_s + full_mix4_2m_s + full_atk_500k_s) / 60.0, 2),
        },
        "results": results,
    }
    QUICK_OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"[quick] Completed {payload['ok_jobs']}/{payload['total_jobs']} jobs in {elapsed}s (errors={len(err_rows)})")
    print(f"[quick] VALIDITY GATE: {'PASS' if gate_ok else 'FAIL'}")
    for gr in gate_rows:
        print(f"  {gr}")
    print(f"[quick] Runtime projection (5/5/3/6 pools, 2M benign / 500K attack): {payload['projection']}")
    if err_rows:
        print("[quick] Sample errors:", err_rows[:3])
    if not gate_ok:
        sys.exit(1)


def mix_trace_bytes(traces: list[str]) -> int:
    total = 0
    for tp in traces:
        p = Path(tp)
        if p.is_file():
            total += p.stat().st_size
    return total


def run_full(benign_insts: int = 2_000_000, attack_insts: int = 500_000, resume: bool = False):
    spec_path = CONFIGS_DIR / "matrix_spec.json"
    if not spec_path.is_file():
        print(f"ERROR: Run --measure-mpki first to generate {spec_path}", file=sys.stderr)
        sys.exit(1)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    if not resume and CHECKPOINT_FILE.is_file():
        CHECKPOINT_FILE.unlink()

    t0 = time.monotonic()
    jobs = build_jobs_for_matrix(spec, benign_insts=benign_insts, attack_insts=attack_insts, quick=False)
    single_jobs = [j for j in jobs if j["category"] in ("single", "attack_alone")]
    mix4_normal_jobs = [
        j for j in jobs if j["category"] == "mix4" and mix_trace_bytes(j["traces"]) <= 350 * 1024 * 1024
    ]
    mix4_heavy_jobs = [
        j for j in jobs if j["category"] == "mix4" and mix_trace_bytes(j["traces"]) > 350 * 1024 * 1024
    ]
    attack_jobs = [j for j in jobs if j["category"] == "attack"]

    res = []
    res.extend(run_jobs_pool(single_jobs, max_workers=5, label="full_single", checkpoint_path=CHECKPOINT_FILE))
    res.extend(run_jobs_pool(mix4_normal_jobs, max_workers=5, label="full_mix4_normal", checkpoint_path=CHECKPOINT_FILE))
    res.extend(run_jobs_pool(mix4_heavy_jobs, max_workers=3, label="full_mix4_heavy", checkpoint_path=CHECKPOINT_FILE))
    res.extend(run_jobs_pool(attack_jobs, max_workers=6, label="full_attack", checkpoint_path=CHECKPOINT_FILE))

    # Deduplicate by job_id while preserving order in case resume appended any duplicate
    by_id = {r["job_id"]: r for r in res}
    results = list(by_id.values())

    elapsed = time.monotonic() - t0
    gate_ok, gate_rows, _ = aggregate_and_report(results, spec, benign_insts, attack_insts, elapsed)
    print(f"[full] Completed {len(results)} jobs in {elapsed:.2f}s ({elapsed/60.0:.2f} min) | VALIDITY GATE: {'PASS' if gate_ok else 'FAIL'}")
    if not gate_ok:
        sys.exit(1)


def inspect_vrr_spec_cost() -> dict:
    """Read exact nVRR, nRC, nRAS, nRP, tCK_ps from the generated DDR5_VRR spec."""
    ensure_ramulator_import()
    from ramulator.dram.ddr5_vrr import DDR5_VRR
    org = dict(DDR5_VRR.org_presets["DDR5_16Gb_x4"])
    tim = dict(DDR5_VRR.timing_presets["DDR5_3200C"])
    DDR5_VRR.resolve_secondary_timings(tim, org)
    tck_ps = int(tim["tCK_ps"])
    n_vrr = int(tim["nVRR"])
    n_rc = int(tim["nRC"])
    n_ras = int(tim["nRAS"])
    n_rp = int(tim["nRP"])
    act_pre_4_nck = 4 * n_rc
    return {
        "org_preset": "DDR5_16Gb_x4",
        "timing_preset": "DDR5_3200C",
        "tCK_ps": tck_ps,
        "nVRR": n_vrr,
        "tVRR_ns": round(n_vrr * tck_ps / 1000.0, 3),
        "nRC": n_rc,
        "tRC_ns": round(n_rc * tck_ps / 1000.0, 3),
        "nRAS": n_ras,
        "tRAS_ns": round(n_ras * tck_ps / 1000.0, 3),
        "nRP": n_rp,
        "tRP_ns": round(n_rp * tck_ps / 1000.0, 3),
        "act_pre_4_victims_nck": act_pre_4_nck,
        "act_pre_4_victims_ns": round(act_pre_4_nck * tck_ps / 1000.0, 3),
        "vrr_minus_4xactpre_nck": n_vrr - act_pre_4_nck,
        "vrr_minus_4xactpre_ns": round((n_vrr - act_pre_4_nck) * tck_ps / 1000.0, 3),
    }


def write_t87_scheme_configs():
    CONFIGS_DIR.mkdir(parents=True, exist_ok=True)
    common = {
        "frontend": {
            "impl": "BHO3",
            "clock_ratio": 5,
            "ipc": 4,
            "inst_window_depth": 128,
            "llc_capacity_per_core": "2MB",
            "llc_num_mshr_per_core": 16,
            "translation": {"impl": "NoTranslation", "max_addr": 17179869184},
        },
        "memory_system": {
            "impl": "GenericDRAM",
            "clock_ratio": 2,
            "channel_mapper": {"impl": "CacheLineInterleave"},
        },
        "dram": {
            "impl": "DDR5_VRR",
            "org_preset": "DDR5_16Gb_x4",
            "timing_preset": "DDR5_3200C",
            "rank": 1,
        },
        "scheduler": {"impl": "FRFCFS"},
        "refresh_manager": {"impl": "AllBank"},
        "row_policy": {"impl": "Open"},
        "addr_mapper": {"impl": "RoBaRaCoCh"},
    }
    for scheme in ALL_SCHEMES_V2:
        ds, ds_ref = DRAM_SUPPORT_MAP[scheme]
        cfg = {
            "scheme": scheme,
            "dram_support": ds,
            "dram_support_evidence": ds_ref,
            "common": common,
            "per_nrh": {str(nrh): scheme_params_dict(scheme, nrh, 123) for nrh in NRH_VALUES},
        }
        if scheme in ("PARA", "PARA_ACT"):
            cfg["seeds"] = PARA_SEEDS
        (CONFIGS_DIR / f"{scheme.lower()}.json").write_text(json.dumps(cfg, indent=2), encoding="utf-8")


def build_jobs_for_t87(spec: dict, benign_insts: int, attack_insts: int, quick: bool = False) -> list[dict]:
    jobs = []
    sys.path.insert(0, str(ATTACKS_DIR))
    import gen_attack_traces
    generated = gen_attack_traces.generate_all()
    atk_paths = {p.stem: str(p) for p in generated}
    corunners = [str(CPUTRACES_DIR / name) for name in spec["attack_corunners"]]

    if quick:
        sc = spec["single_core"]
        high0 = [x for x in sc if x["group"] == "High"][3]
        med0 = [x for x in sc if x["group"] == "Medium"][3]
        low0 = [x for x in sc if x["group"] == "Low"][3]
        single_list = [high0, med0, low0]
        mix_list = [next(x for x in spec["four_core_mixes"] if x["type"] == "Mixed")]
    else:
        single_list = spec["single_core"]
        mix_list = spec["four_core_mixes"]

    def add_t87_jobs(category, wl_name, trace_list, insts, atk_ids):
        for nrh in NRH_VALUES:
            for scheme in T87_NEW_SCHEMES:
                seeds = PARA_SEEDS if scheme == "PARA_ACT" else [123]
                for sd in seeds:
                    jobs.append({
                        "job_id": f"{category}__{wl_name}__{scheme}__nrh{nrh}__s{sd}",
                        "category": category,
                        "workload": wl_name,
                        "scheme": scheme,
                        "n_rh": nrh,
                        "seed": sd,
                        "traces": trace_list,
                        "num_expected_insts": insts,
                        "num_max_cycles": insts * 25,
                        "attacker_core_ids": atk_ids,
                        "meta_bypass_drm": False,
                    })

    for item in single_list:
        add_t87_jobs("single", item["name"], [item["path"]], benign_insts, [])
    for mx in mix_list:
        tpaths = [str(CPUTRACES_DIR / c) for c in mx["cores"]]
        add_t87_jobs("mix4", mx["name"], tpaths, benign_insts, [])
    for atk_name, atk_path in sorted(atk_paths.items()):
        tpaths = [atk_path] + corunners
        add_t87_jobs("attack", atk_name, tpaths, attack_insts, [0])
    return jobs


def estimate_t87_runtime_from_t80() -> dict:
    runs_csv = REPORTS_DIR / "perf_runs.csv"
    if not runs_csv.is_file():
        return {}
    by_scheme_cat = {}
    t80_total_cpu_s = 0.0
    t80_count = 0
    with open(runs_csv, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            es = float(row.get("elapsed_s") or 0.0)
            t80_total_cpu_s += es
            t80_count += 1
            by_scheme_cat.setdefault((row["scheme"], row["category"]), []).append(es)

    # Map T87 new schemes to their closest T80 counterparts (PARA->PARA_ACT, Graphene->Graphene_ACT, Hydra->Hydra_ACT, QShield_Integ->QShield_Integ)
    t87_cpu_s = 0.0
    breakdown = {}
    for src_scheme, dst_scheme in [
        ("PARA", "PARA_ACT"),
        ("Graphene", "Graphene_ACT"),
        ("Hydra", "Hydra_ACT"),
        ("QShield_Integ", "QShield_Integ"),
    ]:
        s_cpu = 0.0
        n_runs = 0
        for cat in ("single", "mix4", "attack"):
            vals = by_scheme_cat.get((src_scheme, cat), [])
            s_cpu += sum(vals)
            n_runs += len(vals)
        t87_cpu_s += s_cpu
        breakdown[dst_scheme] = {"runs": n_runs, "est_cpu_s": round(s_cpu, 1)}

    # T80 effective wall-clock speedup factor from parallel pools: t80_total_cpu_s / 3008.41
    eff_par = t80_total_cpu_s / 3008.41 if t80_total_cpu_s > 0 else 4.5
    est_wall_s = t87_cpu_s / eff_par
    return {
        "t80_runs": t80_count,
        "t80_total_cpu_s": round(t80_total_cpu_s, 1),
        "t80_actual_wall_s": 3008.41,
        "t80_effective_parallelism": round(eff_par, 3),
        "t87_new_runs": sum(v["runs"] for v in breakdown.values()),
        "t87_est_cpu_s": round(t87_cpu_s, 1),
        "t87_est_wall_s": round(est_wall_s, 1),
        "t87_est_wall_min": round(est_wall_s / 60.0, 2),
        "breakdown": breakdown,
    }


def run_t87_audit_meta(benign_insts: int = 2_000_000, attack_insts: int = 500_000):
    """Step 2 & Step 5: Print spec VRR cost, T87 runtime estimate, and audit every QShield_Integ Worst R1 > N_RH case."""
    spec_cost = inspect_vrr_spec_cost()
    print("=== [T87 SPEC VRR vs ACT+PRE COST] ===")
    print(json.dumps(spec_cost, indent=2))

    rt_est = estimate_t87_runtime_from_t80()
    print("=== [T87 RUNTIME ESTIMATE FROM T80 perf_runs.csv] ===")
    print(json.dumps(rt_est, indent=2))

    spec = json.loads((CONFIGS_DIR / "matrix_spec.json").read_text(encoding="utf-8"))
    runs_csv = REPORTS_DIR / "perf_runs.csv"
    viol_rows = []
    with open(runs_csv, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["scheme"] == "QShield_Integ":
                nrh = int(row["n_rh"])
                r1 = int(row["obs_max_disturb_r1"])
                if r1 > nrh:
                    viol_rows.append({
                        "job_id": row["job_id"],
                        "category": row["category"],
                        "workload": row["workload"],
                        "n_rh": nrh,
                        "t80_r1": r1,
                        "t80_r2": int(row["obs_max_disturb_r2"]),
                        "t80_exceed_r1": int(row["obs_rows_exceeding_nrh_r1"]),
                    })

    print(f"=== [T87 QShield_Integ T80 VIOLATIONS (Worst R1 > N_RH)] count={len(viol_rows)} ===")
    single_map = {x["name"]: [x["path"]] for x in spec["single_core"]}
    mix_map = {mx["name"]: [str(CPUTRACES_DIR / c) for c in mx["cores"]] for mx in spec["four_core_mixes"]}
    corunners = [str(CPUTRACES_DIR / name) for name in spec["attack_corunners"]]

    def make_audit_jobs(bypass_flag: bool, tag: str) -> list[dict]:
        jobs = []
        for vr in viol_rows:
            cat = vr["category"]
            wl = vr["workload"]
            if cat == "single":
                traces = single_map[wl]
                insts = benign_insts
                atk_ids = []
            elif cat == "mix4":
                traces = mix_map[wl]
                insts = benign_insts
                atk_ids = []
            else:
                traces = [str(ATTACKS_DIR / f"{wl}.trace")] + corunners
                insts = attack_insts
                atk_ids = [0]
            jobs.append({
                "job_id": f"{tag}__{vr['job_id']}",
                "orig_job_id": vr["job_id"],
                "category": cat,
                "workload": wl,
                "scheme": "QShield_Integ",
                "n_rh": vr["n_rh"],
                "seed": 123,
                "traces": traces,
                "num_expected_insts": insts,
                "num_max_cycles": insts * 25,
                "attacker_core_ids": atk_ids,
                "meta_bypass_drm": bypass_flag,
            })
        return jobs

    t0 = time.monotonic()
    before_jobs = make_audit_jobs(True, "before")
    after_jobs = make_audit_jobs(False, "after")
    before_res = {r["job_id"][len("before__"):]: r for r in run_jobs_pool(before_jobs, max_workers=4, label="audit_before")}
    after_res = {r["job_id"][len("after__"):]: r for r in run_jobs_pool(after_jobs, max_workers=4, label="audit_after")}

    audit_records = []
    meta_induced_cnt = 0
    mit_cascade_cnt = 0
    after_exceed_cnt = 0
    for vr in sorted(viol_rows, key=lambda x: (x["category"], x["n_rh"], -x["t80_r1"], x["workload"])):
        jid = vr["job_id"]
        rb = before_res[jid]
        ra = after_res[jid]
        is_meta_aggr = rb.get("obs_max_r1_aggr_meta_acts", 0) > 0
        is_mit_aggr = rb.get("obs_max_r1_aggr_mit_acts", 0) > 0
        if is_meta_aggr:
            meta_induced_cnt += 1
        if is_mit_aggr:
            mit_cascade_cnt += 1
        if ra.get("obs_max_disturb_r1", 0) > vr["n_rh"]:
            after_exceed_cnt += 1
        rec = {
            "category": vr["category"],
            "workload": vr["workload"],
            "n_rh": vr["n_rh"],
            "t80_r1": vr["t80_r1"],
            "before_r1": rb.get("obs_max_disturb_r1", 0),
            "before_bank": rb.get("obs_max_r1_bank", 0),
            "before_row": rb.get("obs_max_r1_row", 0),
            "before_row_is_meta": bool(rb.get("obs_max_r1_row_is_meta", 0)),
            "before_aggr_meta_acts": rb.get("obs_max_r1_aggr_meta_acts", 0),
            "before_aggr_mit_acts": rb.get("obs_max_r1_aggr_mit_acts", 0),
            "before_aggr_user_acts": rb.get("obs_max_r1_aggr_user_acts", 0),
            "after_r1": ra.get("obs_max_disturb_r1", 0),
            "after_bank": ra.get("obs_max_r1_bank", 0),
            "after_row": ra.get("obs_max_r1_row", 0),
            "after_row_is_meta": bool(ra.get("obs_max_r1_row_is_meta", 0)),
            "after_aggr_meta_acts": ra.get("obs_max_r1_aggr_meta_acts", 0),
            "after_aggr_mit_acts": ra.get("obs_max_r1_aggr_mit_acts", 0),
            "after_aggr_user_acts": ra.get("obs_max_r1_aggr_user_acts", 0),
            "after_exceed_r1": ra.get("obs_rows_exceeding_nrh_r1", 0),
            "after_ipc_ratio_vs_before": round(ra["mean_ipc"] / rb["mean_ipc"], 4) if rb["mean_ipc"] > 0 else 0.0,
        }
        audit_records.append(rec)
        print(
            f"  [{rec['category']:6s} nrh={rec['n_rh']:4d}] {rec['workload']:22s} | "
            f"BEFORE R1={rec['before_r1']:4d} (b={rec['before_bank']:2d} r={rec['before_row']:5d} "
            f"meta={int(rec['before_row_is_meta'])} a_meta={rec['before_aggr_meta_acts']} a_mit={rec['before_aggr_mit_acts']} a_usr={rec['before_aggr_user_acts']}) -> "
            f"AFTER R1={rec['after_r1']:4d} (exc={rec['after_exceed_r1']} r={rec['after_row']} a_meta={rec['after_aggr_meta_acts']} a_mit={rec['after_aggr_mit_acts']} a_usr={rec['after_aggr_user_acts']})"
        )

    payload = {
        "spec_vrr_cost": spec_cost,
        "runtime_estimate": rt_est,
        "total_t80_qshield_integ_violations": len(audit_records),
        "meta_aggressor_induced_count": meta_induced_cnt,
        "mit_cascade_induced_count": mit_cascade_cnt,
        "after_fix_remaining_violations": after_exceed_cnt,
        "audit_elapsed_s": round(time.monotonic() - t0, 2),
        "records": audit_records,
    }
    out_path = REPORTS_DIR / "qshield_integ_meta_audit.json"
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(
        f"[audit-meta] DONE in {payload['audit_elapsed_s']}s: "
        f"before_viol={len(audit_records)}, meta_aggr={meta_induced_cnt}, mit_cascade={mit_cascade_cnt}, "
        f"after_viol={after_exceed_cnt}/{len(audit_records)} -> {out_path}"
    )


def aggregate_and_report_v2(results: list[dict], spec: dict, benign_insts: int, attack_insts: int,
                            t87_elapsed_s: float, rt_est: dict):
    """Write perf_runs_v2.csv, perf_summary_v2.csv, perf_summary_v2.json, perf_report_v2.md (never touching perf_runs.csv)."""
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    commit = get_git_commit()
    spec_cost = inspect_vrr_spec_cost()
    cfg_hashes = {p.name: sha256_file(p) for p in sorted(CONFIGS_DIR.glob("*.json"))}

    base_single = {}
    base_attack_alone = {}
    base_run = {}
    for r in results:
        r["dram_support"] = DRAM_SUPPORT_MAP.get(r["scheme"], ("chưa kiểm", ""))[0]
        if r["status"] == "OK" and r["scheme"] == "Baseline":
            base_run[(r["category"], r["workload"], r["n_rh"])] = r
            if r["category"] == "single":
                base_single[(r["workload"], r["n_rh"])] = r["mean_ipc"]
            elif r["category"] == "attack_alone":
                base_attack_alone[r["workload"]] = r["mean_ipc"]

    mix_cores_map = {mx["name"]: mx["cores"] for mx in spec["four_core_mixes"]}
    corunner_names = spec["attack_corunners"]

    for r in results:
        if r["status"] != "OK":
            continue
        nrh = r["n_rh"]
        b = base_run.get((r["category"], r["workload"], nrh))
        if r["category"] == "single":
            b_ipc = base_single.get((r["workload"], nrh), r["mean_ipc"])
            r["weighted_speedup"] = (r["mean_ipc"] / b_ipc) if b_ipc > 0 else 0.0
            r["harmonic_speedup"] = r["weighted_speedup"]
            r["max_slowdown"] = (b_ipc / r["mean_ipc"]) if r["mean_ipc"] > 0 else 0.0
        elif r["category"] == "mix4":
            cnames = mix_cores_map[r["workload"]]
            ratios, slows = [], []
            for idx, cname in enumerate(cnames):
                alone = base_single.get((cname, nrh), 0.0)
                ipc_i = r["core_ipcs"][idx]
                if alone > 0 and ipc_i > 0:
                    ratios.append(ipc_i / alone)
                    slows.append(alone / ipc_i)
            r["weighted_speedup"] = sum(ratios) if ratios else 0.0
            r["harmonic_speedup"] = (len(slows) / sum(slows)) if slows else 0.0
            r["max_slowdown"] = max(slows) if slows else 0.0
            if b and b.get("weighted_speedup", 0) > 0:
                r["norm_weighted_speedup"] = r["weighted_speedup"] / b["weighted_speedup"]
        elif r["category"] == "attack":
            ratios, slows = [], []
            for idx, cname in enumerate(corunner_names, start=1):
                alone = base_attack_alone.get(cname, base_single.get((cname, nrh), 0.0))
                ipc_i = r["core_ipcs"][idx]
                if alone > 0 and ipc_i > 0:
                    ratios.append(ipc_i / alone)
                    slows.append(alone / ipc_i)
            r["weighted_speedup"] = sum(ratios) if ratios else 0.0
            r["harmonic_speedup"] = (len(slows) / sum(slows)) if slows else 0.0
            r["max_slowdown"] = max(slows) if slows else 0.0

    # Write perf_runs_v2.csv (NEVER touches perf_runs.csv!)
    runs_csv = REPORTS_DIR / "perf_runs_v2.csv"
    run_cols = [
        "job_id", "category", "workload", "scheme", "dram_support", "n_rh", "seed", "status", "hit_max_cycles",
        "mean_ipc", "weighted_speedup", "harmonic_speedup", "max_slowdown", "ctrl_cycles",
        "avg_read_latency", "total_throughput_MBps", "preventive_refreshes", "act_mit_triggers",
        "act_mit_victim_refreshes", "act_mit_dropped", "obs_num_act", "obs_num_meta_act", "obs_num_mit_act",
        "obs_num_vrr", "obs_num_rfmab", "obs_max_disturb_r1", "obs_max_disturb_r2",
        "obs_max_r1_bank", "obs_max_r1_row", "obs_max_r1_row_is_meta",
        "obs_max_r1_aggr_meta_acts", "obs_max_r1_aggr_mit_acts", "obs_max_r1_aggr_user_acts",
        "obs_rows_exceeding_nrh_r1", "obs_rows_exceeding_nrh_r2", "qshield_sdc_throttles",
        "qshield_coordinated_throttles", "qshield_victim_refreshes", "qshield_mit_acts",
        "qshield_rfm_count", "qshield_rowpress_alerts", "qshield_tras_clamps",
        "qshield_mc_hits", "qshield_mc_misses", "qshield_meta_rd_cnt", "qshield_meta_wr_cnt",
        "qshield_reencrypt_events", "elapsed_s", "error",
    ]
    with open(runs_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=run_cols)
        w.writeheader()
        for r in sorted(results, key=lambda x: (x["category"], x["n_rh"], x["workload"], x["scheme"], x["seed"])):
            w.writerow({k: r.get(k, "") for k in run_cols})

    grouped = {}
    for r in results:
        if r["category"] == "attack_alone":
            continue
        grouped.setdefault((r["category"], r["scheme"], r["n_rh"]), []).append(r)

    summary_rows = []
    for (cat, scheme, nrh), items in sorted(grouped.items(), key=lambda x: (x[0][0], x[0][2], ALL_SCHEMES_V2.index(x[0][1]))):
        ok_items = [x for x in items if x["status"] == "OK"]
        base_items = [x for x in grouped.get((cat, "Baseline", nrh), []) if x["status"] == "OK"]
        base_by_wl = {x["workload"]: x for x in base_items}

        by_wl = {}
        for x in ok_items:
            by_wl.setdefault(x["workload"], []).append(x)

        ws_vals, hs_vals, ms_vals, norm_ws_vals, pref_vals = [], [], [], [], []
        max_r1_vals, max_r2_vals = [], []
        exceed_r1_sum, exceed_r2_sum = 0, 0
        per_wl_seed_cis = []
        t_crit_df2 = 4.3027

        for wl, w_runs in by_wl.items():
            ws_w = statistics.mean(x["weighted_speedup"] for x in w_runs)
            hs_w = statistics.mean(x["harmonic_speedup"] for x in w_runs)
            ms_w = statistics.mean(x["max_slowdown"] for x in w_runs)
            pref_w = statistics.mean(x["preventive_refreshes"] for x in w_runs)
            ws_vals.append(ws_w)
            hs_vals.append(hs_w)
            ms_vals.append(ms_w)
            pref_vals.append(pref_w)
            max_r1_vals.append(max(x["obs_max_disturb_r1"] for x in w_runs))
            max_r2_vals.append(max(x["obs_max_disturb_r2"] for x in w_runs))
            exceed_r1_sum += sum(x["obs_rows_exceeding_nrh_r1"] for x in w_runs)
            exceed_r2_sum += sum(x["obs_rows_exceeding_nrh_r2"] for x in w_runs)
            if wl in base_by_wl and base_by_wl[wl]["weighted_speedup"] > 0:
                norm_ws_vals.append(ws_w / base_by_wl[wl]["weighted_speedup"])
            if len(w_runs) >= 2:
                s = statistics.stdev(x["weighted_speedup"] for x in w_runs)
                per_wl_seed_cis.append(t_crit_df2 * s / math.sqrt(len(w_runs)))

        ds, ds_ref = DRAM_SUPPORT_MAP[scheme]
        summary_rows.append({
            "category": cat,
            "scheme": scheme,
            "dram_support": ds,
            "dram_support_evidence": ds_ref,
            "n_rh": nrh,
            "runs_total": len(items),
            "runs_ok": len(ok_items),
            "runs_unsupported": len(items) - len(ok_items),
            "weighted_speedup_mean": round(statistics.mean(ws_vals), 4) if ws_vals else None,
            "norm_weighted_speedup_mean": round(statistics.mean(norm_ws_vals), 4) if norm_ws_vals else None,
            "seed_ci95_ws": round(statistics.mean(per_wl_seed_cis), 5) if per_wl_seed_cis else 0.0,
            "harmonic_speedup_mean": round(statistics.mean(hs_vals), 4) if hs_vals else None,
            "max_slowdown_mean": round(statistics.mean(ms_vals), 4) if ms_vals else None,
            "preventive_refreshes_mean": round(statistics.mean(pref_vals), 1) if pref_vals else None,
            "max_disturb_r1_worst": max(max_r1_vals) if max_r1_vals else None,
            "max_disturb_r2_worst": max(max_r2_vals) if max_r2_vals else None,
            "rows_exceeding_nrh_r1_sum": exceed_r1_sum if ok_items else None,
            "rows_exceeding_nrh_r2_sum": exceed_r2_sum if ok_items else None,
        })

    summary_csv = REPORTS_DIR / "perf_summary_v2.csv"
    sum_cols = list(summary_rows[0].keys()) if summary_rows else []
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=sum_cols)
        w.writeheader()
        for r in summary_rows:
            w.writerow(r)

    gate_ok, gate_rows = check_validity_gate(results)

    # Compute exact simulation window durations (ms) from Baseline ctrl_cycles * tCK_ps (625 ps)
    tck_ms = spec_cost["tCK_ps"] / 1e9
    single_base_ms = [r["ctrl_cycles"] * tck_ms for r in results if r["category"] == "single" and r["scheme"] == "Baseline" and r["n_rh"] == 1024]
    mix4_base_ms = [r["ctrl_cycles"] * tck_ms for r in results if r["category"] == "mix4" and r["scheme"] == "Baseline" and r["n_rh"] == 1024]
    atk_base_ms = [r["ctrl_cycles"] * tck_ms for r in results if r["category"] == "attack" and r["scheme"] == "Baseline" and r["n_rh"] == 1024]
    sim_windows = {
        "tREFW_ms": 32.0,
        "single_median_ms": round(statistics.median(single_base_ms), 4) if single_base_ms else 0.0,
        "single_range_ms": [round(min(single_base_ms), 4), round(max(single_base_ms), 4)] if single_base_ms else [0.0, 0.0],
        "mix4_median_ms": round(statistics.median(mix4_base_ms), 4) if mix4_base_ms else 0.0,
        "attack_median_ms": round(statistics.median(atk_base_ms), 4) if atk_base_ms else 0.0,
    }

    act_vrr_nonzero = sum(1 for r in results if r["scheme"].endswith("_ACT") and int(r.get("obs_num_vrr", 0)) != 0)
    act_dropped_total = sum(int(r.get("act_mit_dropped", 0)) for r in results if r["scheme"].endswith("_ACT"))
    qsi_remaining_viol = [
        {"category": r["category"], "workload": r["workload"], "n_rh": r["n_rh"], "r1": r["obs_max_disturb_r1"]}
        for r in results if r["scheme"] == "QShield_Integ" and r["obs_max_disturb_r1"] > r["n_rh"]
    ]

    summary_json = {
        "git_commit": commit,
        "upstream_commit": "72427a1bba3771564c4fb0e494ba02242fd1eaa7",
        "dram_energy_model": "N/A (not provided by upstream Ramulator2 commit 72427a1)",
        "benign_expected_insts": benign_insts,
        "attack_expected_insts": attack_insts,
        "t87_runtime_estimate": rt_est,
        "t87_actual_elapsed_s": round(t87_elapsed_s, 2),
        "t87_actual_elapsed_min": round(t87_elapsed_s / 60.0, 2),
        "spec_vrr_cost": spec_cost,
        "simulation_windows_ms": sim_windows,
        "dram_support_classification": {k: {"dram_support": v[0], "evidence": v[1]} for k, v in DRAM_SUPPORT_MAP.items()},
        "act_variants_vrr_nonzero": act_vrr_nonzero,
        "act_variants_dropped_total": act_dropped_total,
        "qshield_integ_remaining_r1_violations": qsi_remaining_viol,
        "config_hashes": cfg_hashes,
        "validity_gate_pass": gate_ok,
        "validity_gate_rows": gate_rows,
        "summary": summary_rows,
    }
    (REPORTS_DIR / "perf_summary_v2.json").write_text(json.dumps(summary_json, indent=2), encoding="utf-8")

    # Build perf_report_v2.md with TWO SEPARATE TABLES (commercial DRAM vs custom/in-DRAM)
    md = [
        "# Q-Shield Ramulator2 Performance Evaluation v2 — Commercial DRAM Separation (`reports/paper/perf/perf_report_v2.md`)",
        f"- Commit: `{commit}` | Upstream Ramulator2: `72427a1bba3771564c4fb0e494ba02242fd1eaa7`",
        "- DRAM Energy: `N/A (not provided by upstream Ramulator2 commit 72427a1)`",
        f"- `num_expected_insts`: benign=`{benign_insts}`, attack=`{attack_insts}` | T87 New Runs (`1,080`): Est=`{rt_est.get('t87_est_wall_min')} min`, Actual=`{t87_elapsed_s:.2f}s` (`{t87_elapsed_s/60.0:.2f} min`)",
        f"- Validity Gate (T80 16 checks): `{'PASS' if gate_ok else 'FAIL'}` | `*_ACT` VRR issued: `{act_vrr_nonzero}` | `*_ACT` dropped: `{act_dropped_total}` | `QShield_Integ` remaining `Worst R1 > N_RH`: `{len(qsi_remaining_viol)}`",
        "",
        "## 1. Cửa sổ mô phỏng (so với `tREFW = 32 ms`)",
        f"- Đơn nhân (Baseline, `N_RH=1024`): trung vị **`{sim_windows['single_median_ms']} ms`** (phạm vi `{sim_windows['single_range_ms'][0]}..{sim_windows['single_range_ms'][1]} ms`, tương đương `{sim_windows['single_median_ms']/32.0*100:.2f}%` của `tREFW = 32 ms`).",
        f"- Tổ hợp 4 nhân (Baseline): trung vị **`{sim_windows['mix4_median_ms']} ms`** (`{sim_windows['mix4_median_ms']/32.0*100:.2f}%` của `tREFW`).",
        f"- Kịch bản tấn công (Baseline): trung vị **`{sim_windows['attack_median_ms']} ms`** (`{sim_windows['attack_median_ms']/32.0*100:.2f}%` của `tREFW`).",
        "- Lưu ý: Cửa sổ dài `>= 1 tREFW` thuộc phạm vi T91; mọi số liệu dưới đây phản ánh cửa sổ ngắn đồng nhất với T80.",
        "",
        "## 2. Phân loại yêu cầu phần cứng DRAM (`dram_support`) và chi phí `VRR` vs `ACT + PREpb`",
        f"- Preset DRAM: `DDR5_VRR` (`{spec_cost['org_preset']}`, `{spec_cost['timing_preset']}`, `tCK = {spec_cost['tCK_ps']} ps`): **`nVRR = {spec_cost['nVRR']} nCK ({spec_cost['tVRR_ns']} ns)`**, **`nRAS = {spec_cost['nRAS']} nCK ({spec_cost['tRAS_ns']} ns)`**, **`nRP = {spec_cost['nRP']} nCK ({spec_cost['tRP_ns']} ns)`**, **`nRC = {spec_cost['nRC']} nCK ({spec_cost['tRC_ns']} ns)`**.",
        f"- Chi phí 4 nạn nhân (`R = 2`, cùng bank): `1 × VRR = {spec_cost['nVRR']} nCK ({spec_cost['tVRR_ns']} ns)` so với `4 × (ACT + PREpb) = 4 × nRC = {spec_cost['act_pre_4_victims_nck']} nCK ({spec_cost['act_pre_4_victims_ns']} ns)` (VRR đắt hơn `{spec_cost['vrr_minus_4xactpre_nck']} nCK` = `{spec_cost['vrr_minus_4xactpre_ns']} ns` mỗi lần kích hoạt, nhưng trong `rh_observer.cpp` VRR xóa nhiễu `±1, ±2` không cộng nhiễu lân cận còn `ACT + PREpb` cộng nhiễu Half-Double lên các hàng kế cận).",
        "- Quy ước đếm ACT giảm thiểu của `PARA_ACT`, `Graphene_ACT`, `Hydra_ACT`: **không đếm lại** ACT làm tươi nạn nhân (`source_id = -99`) vào bộ theo dõi của chính plugin, giống Q-Shield (`PARAMS.md` §1) để so sánh cùng điều kiện; `Hydra_ACT` vẫn đếm ACT đọc/ghi bảng RCT của mình trong `RCTCT` như upstream `Hydra`.",
        "",
        "| Scheme | `dram_support` | Căn cứ mã nguồn (`file:dòng`) |",
        "|---|---|---|",
    ]
    for sch in ALL_SCHEMES_V2:
        ds, ds_ref = DRAM_SUPPORT_MAP[sch]
        md.append(f"| `{sch}` | `{ds}` | `{ds_ref}` |")

    def append_table(title: str, rows: list[dict]):
        md.extend([
            "",
            f"## {title}",
            "| Category | N_RH | Scheme | dram_support | OK/Total | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|",
        ])
        for r in rows:
            md.append(
                f"| {r['category']} | {r['n_rh']} | {r['scheme']} | `{r['dram_support']}` | {r['runs_ok']}/{r['runs_total']} | "
                f"{r['norm_weighted_speedup_mean']} | {r['seed_ci95_ws']} | {r['harmonic_speedup_mean']} | "
                f"{r['max_slowdown_mean']} | {r['preventive_refreshes_mean']} | "
                f"{r['max_disturb_r1_worst']} | {r['max_disturb_r2_worst']} |"
            )

    none_rows = [r for r in summary_rows if r["dram_support"] == "none"]
    custom_rows = [r for r in summary_rows if r["dram_support"] != "none"]
    append_table("3. Bảng A — Cấu hình KHÔNG cần sửa chip DRAM thương mại (`dram_support = none`)", none_rows)
    append_table("4. Bảng B — Cấu hình CẦN lệnh không chuẩn hoặc hỗ trợ trong chip DRAM (`vrr_non_jedec`, `in_dram`)", custom_rows)

    md.extend([
        "",
        "## 5. Kiểm tra hàng metadata của `QShield_Integ` (`Worst R1 > N_RH`)",
        "- **Kiểm tra RTL**: Trong RTL thực tế (`rtl/top/axi_ddr5_mc_secure_top.sv:344-462` -> `rtl/frontend/axi_slave_frontend.sv:133,255` -> `rtl/frontend/addr_mapper_ddr5.sv:105` -> `rtl/top/axi_ddr5_mc_top.sv:1165-1210` -> `rtl/core/sdc_resilient_filter.sv:146`), yêu cầu metadata nội bộ (`id[3]=1`) đi qua đường nạp địa chỉ vật lý và `u_sdc_filter` hoàn toàn đồng nhất với yêu cầu người dùng — không có nhánh bỏ qua DRM.",
        "- **Sửa lệch mô hình mô phỏng (`qshield_controller.cpp`)**: Bổ sung kiểm tra `is_drm_stall()`, `is_proq_blacklisted()`, `m_row_cooldown` trong `meta_filter` (khi `meta_bypass_drm=false`, mặc định) và bổ sung kiểm tra hàng đợi metadata trong `any_user_blocked_by_proq()`. Khắc phục triệt để trường hợp vi phạm trực tiếp trên hàng metadata `row 259` (CB region, `mix4/mix_X_5 @ N_RH=1024`).",
        f"- **Phát hiện thực nghiệm trên các ca còn lại (`{len(qsi_remaining_viol)}` ca sau sửa)**: Các ca còn lại tập trung ở hàng biên `row = 295` (khoảng cách `+3` từ hàng BMT Tree Node nóng `row 292`, tức `+1` từ hàng đích làm tươi nạn nhân `row 294`), bị nhiễu thứ cấp (Half-Double cascade) bởi chính các lệnh `ACT+PREpb` làm tươi nạn nhân (`source_id = -99`) của `row 292` vì cả RTL (`rtl/core/ddr5_cmd_engine.sv:1151-1156`) và mô hình Ramulator2 đều không đếm lại ACT làm tươi nạn nhân vào `u_sdc_filter`. Chi tiết đầy đủ từng ca nằm tại `reports/paper/perf/qshield_integ_meta_audit.json`.",
    ])

    (REPORTS_DIR / "perf_report_v2.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return gate_ok, gate_rows, summary_rows


def run_t87_quick(benign_insts: int = 1_000_000, attack_insts: int = 500_000):
    spec = json.loads((CONFIGS_DIR / "matrix_spec.json").read_text(encoding="utf-8"))
    write_t87_scheme_configs()
    t0 = time.monotonic()
    jobs = build_jobs_for_t87(spec, benign_insts=benign_insts, attack_insts=attack_insts, quick=True)
    # Also include Baseline + QShield on attack scenarios so 16/16 validity gate runs self-contained
    t80_quick = json.loads(QUICK_OUT.read_text(encoding="utf-8"))["results"] if QUICK_OUT.is_file() else []
    base_qs_atk = [r for r in t80_quick if r["category"] == "attack" and r["scheme"] in ("Baseline", "QShield")]
    results = run_jobs_pool(jobs, max_workers=4, label="t87_quick")
    elapsed = round(time.monotonic() - t0, 2)
    err_rows = [r for r in results if r["status"] != "OK"]
    act_vrr = sum(int(r.get("obs_num_vrr", 0)) for r in results if r["scheme"].endswith("_ACT"))
    act_drop = sum(int(r.get("act_mit_dropped", 0)) for r in results if r["scheme"].endswith("_ACT"))
    qsi_viol = [
        (r["category"], r["workload"], r["n_rh"], r["obs_max_disturb_r1"])
        for r in results if r["scheme"] == "QShield_Integ" and r["obs_max_disturb_r1"] > r["n_rh"]
    ]
    gate_ok, gate_rows = check_validity_gate(base_qs_atk + results)
    print(
        f"[t87-quick] Completed {len(results)-len(err_rows)}/{len(results)} jobs in {elapsed}s "
        f"(errors={len(err_rows)}, act_vrr={act_vrr}, act_drop={act_drop}, qsi_r1_viol={len(qsi_viol)})"
    )
    print(f"[t87-quick] VALIDITY GATE (16 checks): {'PASS' if gate_ok else 'FAIL'}")
    if qsi_viol:
        print("[t87-quick] QShield_Integ R1>N_RH:", qsi_viol[:10])
    if err_rows or not gate_ok or act_vrr != 0 or act_drop != 0:
        sys.exit(1)


def run_t87_full(benign_insts: int = 2_000_000, attack_insts: int = 500_000, resume: bool = False):
    spec = json.loads((CONFIGS_DIR / "matrix_spec.json").read_text(encoding="utf-8"))
    write_t87_scheme_configs()
    rt_est = estimate_t87_runtime_from_t80()
    print(f"[t87-full] Estimated runtime from T80: {rt_est.get('t87_est_wall_min')} min ({rt_est.get('t87_new_runs')} new runs)")

    if not resume and T87_CHECKPOINT_FILE.is_file():
        T87_CHECKPOINT_FILE.unlink()

    t0 = time.monotonic()
    jobs = build_jobs_for_t87(spec, benign_insts=benign_insts, attack_insts=attack_insts, quick=False)
    single_jobs = [j for j in jobs if j["category"] == "single"]
    mix4_normal_jobs = [j for j in jobs if j["category"] == "mix4" and mix_trace_bytes(j["traces"]) <= 350 * 1024 * 1024]
    mix4_heavy_jobs = [j for j in jobs if j["category"] == "mix4" and mix_trace_bytes(j["traces"]) > 350 * 1024 * 1024]
    attack_jobs = [j for j in jobs if j["category"] == "attack"]

    new_res = []
    new_res.extend(run_jobs_pool(single_jobs, max_workers=5, label="t87_single", checkpoint_path=T87_CHECKPOINT_FILE))
    new_res.extend(run_jobs_pool(mix4_normal_jobs, max_workers=5, label="t87_mix4_normal", checkpoint_path=T87_CHECKPOINT_FILE))
    new_res.extend(run_jobs_pool(mix4_heavy_jobs, max_workers=3, label="t87_mix4_heavy", checkpoint_path=T87_CHECKPOINT_FILE))
    new_res.extend(run_jobs_pool(attack_jobs, max_workers=6, label="t87_attack", checkpoint_path=T87_CHECKPOINT_FILE))
    elapsed = time.monotonic() - t0

    # Merge untouched T80 runs (all schemes except old buggy QShield_Integ) with new T87 runs
    merged = {}
    if CHECKPOINT_FILE.is_file():
        for line in CHECKPOINT_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip():
                continue
            rec = json.loads(line)
            if rec.get("scheme") == "QShield_Integ":
                continue
            merged[rec["job_id"]] = rec
    for rec in new_res:
        merged[rec["job_id"]] = rec
    all_results = list(merged.values())

    gate_ok, gate_rows, _ = aggregate_and_report_v2(all_results, spec, benign_insts, attack_insts, elapsed, rt_est)
    err_cnt = sum(1 for r in all_results if r["status"] != "OK")
    print(
        f"[t87-full] Completed {len(new_res)} new + {len(all_results)-len(new_res)} T80 = {len(all_results)} total runs "
        f"in {elapsed:.2f}s ({elapsed/60.0:.2f} min) | errors={err_cnt} | VALIDITY GATE: {'PASS' if gate_ok else 'FAIL'}"
    )
    if err_cnt > 0 or not gate_ok:
        sys.exit(1)


def _t91_select_workloads(spec: dict) -> list[dict]:
    by_name = {x["name"]: x for x in spec["single_core"]}
    selected = []
    for name in T91_SINGLE_WORKLOADS:
        if name not in by_name:
            raise ValueError(f"T91 workload missing from matrix_spec.json: {name}")
        selected.append(by_name[name])
    return selected


def _t91_ensure_attack_paths() -> dict[str, Path]:
    sys.path.insert(0, str(ATTACKS_DIR))
    import gen_attack_traces
    generated = gen_attack_traces.generate_all()
    return {p.stem: p for p in generated}


def build_jobs_for_t91(spec: dict, para_seeds: int = 3) -> tuple[list[dict], dict]:
    selected_sc = _t91_select_workloads(spec)
    atk_paths = _t91_ensure_attack_paths()
    corunner_names = list(spec["attack_corunners"])
    corunner_paths = [str(CPUTRACES_DIR / name) for name in corunner_names]
    sc_names = {x["name"] for x in selected_sc}
    seeds_para = PARA_SEEDS[: max(1, min(len(PARA_SEEDS), para_seeds))]

    jobs = []

    def add_jobs(category, wl_name, trace_list, atk_ids):
        for nrh in T91_NRH_VALUES:
            for scheme in ALL_SCHEMES_V2:
                seeds = seeds_para if scheme in ("PARA", "PARA_ACT") else [123]
                for sd in seeds:
                    jobs.append({
                        "job_id": f"long__{category}__{wl_name}__{scheme}__nrh{nrh}__s{sd}",
                        "category": category,
                        "workload": wl_name,
                        "scheme": scheme,
                        "n_rh": nrh,
                        "seed": sd,
                        "traces": trace_list,
                        "num_expected_insts": T91_NUM_EXPECTED_INSTS,
                        "num_max_cycles": T91_NUM_MAX_CYCLES,
                        "attacker_core_ids": atk_ids,
                        "meta_bypass_drm": False,
                    })

    for item in selected_sc:
        add_jobs("single", item["name"], [item["path"]], [])

    for atk_name, atk_path in sorted(atk_paths.items()):
        tpaths = [str(atk_path)] + corunner_paths
        add_jobs("attack", atk_name, tpaths, [0])

    # Baseline alone runs at identical 1.05 tREFW window for any attack co-runner not in single_core subset
    extra_alone = []
    for cname in corunner_names:
        if cname not in sc_names:
            extra_alone.append(cname)
            jobs.append({
                "job_id": f"long__attack_alone__{cname}__Baseline__nrh1024__s123",
                "category": "attack_alone",
                "workload": cname,
                "scheme": "Baseline",
                "n_rh": 1024,
                "seed": 123,
                "traces": [str(CPUTRACES_DIR / cname)],
                "num_expected_insts": T91_NUM_EXPECTED_INSTS,
                "num_max_cycles": T91_NUM_MAX_CYCLES,
                "attacker_core_ids": [],
                "meta_bypass_drm": False,
            })

    subset_meta = {
        "git_commit": get_git_commit(),
        "num_max_cycles": T91_NUM_MAX_CYCLES,
        "num_expected_insts": T91_NUM_EXPECTED_INSTS,
        "expected_ctrl_cycles": int(T91_NUM_MAX_CYCLES * 2 // 5),
        "expected_sim_time_ms": round((T91_NUM_MAX_CYCLES * 2 // 5) * 0.625e-6, 4),
        "tREFW_ms": 32.0,
        "nrh_values": T91_NRH_VALUES,
        "schemes": ALL_SCHEMES_V2,
        "para_seeds": seeds_para,
        "selection_rationale": (
            "6 single-core workloads (2 per LLC MPKI group from matrix_spec.json): "
            "High=[429.mcf (highest MPKI, mandatory), tpch6 (explicitly requested, low DRAM MPKI 4.46, short trace 279,379 lines)]; "
            "Medium=[tpch17 (mid-high Medium), 401.bzip2 (median Medium, attack co-runner)]; "
            "Low=[511.povray (longest Low trace 3.22M lines), 458.sjeng (median Low, attack co-runner)]. "
            "Plus all 4 attack scenarios (1 attacker + 3 co-runners: 434.zeusmp, 401.bzip2, 458.sjeng) "
            "and Baseline alone run for 434.zeusmp at the exact same time window."
        ),
        "single_core": selected_sc,
        "attack_corunners": corunner_names,
        "extra_attack_alone_baselines": extra_alone,
        "attacks": [
            {
                "name": k,
                "path": str(v),
                "lines": count_lines(v),
                "sha256": sha256_file(v),
            }
            for k, v in sorted(atk_paths.items())
        ],
        "total_jobs": len(jobs),
    }
    return jobs, subset_meta


def run_t91_pilot(workers: int = 5):
    """Step 1 & 2 of T91: reproduce the earlier 13.44 ms reference, time each scheme family at 33.6 ms, check determinism, extrapolate total runtime."""
    workers = max(1, min(T91_MAX_WORKERS, workers))
    spec = json.loads((CONFIGS_DIR / "matrix_spec.json").read_text(encoding="utf-8"))
    selected_sc = _t91_select_workloads(spec)
    sc_map = {x["name"]: x["path"] for x in selected_sc}
    atk_paths = _t91_ensure_attack_paths()
    corunner_paths = [str(CPUTRACES_DIR / name) for name in spec["attack_corunners"]]
    ds_traces = [str(atk_paths["double_sided"])] + corunner_paths

    # 1) Reproduce the earlier 13.44 ms (53,760,000 core cycles) calibration runs
    ref_jobs = [
        {
            "job_id": "ref13ms__429.mcf__Baseline__nrh1024",
            "category": "ref_point",
            "workload": "429.mcf",
            "scheme": "Baseline",
            "n_rh": 1024,
            "seed": 123,
            "traces": [sc_map["429.mcf"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_REF_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        },
        {
            "job_id": "ref13ms__429.mcf__QShield_Integ__nrh1024",
            "category": "ref_point",
            "workload": "429.mcf",
            "scheme": "QShield_Integ",
            "n_rh": 1024,
            "seed": 123,
            "traces": [sc_map["429.mcf"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_REF_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        },
        {
            "job_id": "ref13ms__tpch6__Baseline__nrh1024",
            "category": "ref_point",
            "workload": "tpch6",
            "scheme": "Baseline",
            "n_rh": 1024,
            "seed": 123,
            "traces": [sc_map["tpch6"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_REF_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        },
    ]

    # 2) Full 1.05 tREFW (134,400,000 core cycles = 33.6 ms) pilot per configuration family
    pilot_families_sc = [
        "Baseline", "BlockHammer", "PARA_ACT", "Graphene_ACT", "Hydra_ACT",
        "PARA", "PRAC", "RFM", "QShield", "QShield_Integ",
    ]
    pilot_families_atk = [
        "Baseline", "BlockHammer", "PARA_ACT", "Graphene_ACT", "Hydra_ACT",
        "PRAC", "QShield", "QShield_Integ",
    ]
    pilot_jobs = []
    for sch in pilot_families_sc:
        pilot_jobs.append({
            "job_id": f"pilot33ms__single__429.mcf__{sch}__nrh128",
            "category": "pilot_single_heavy",
            "workload": "429.mcf",
            "scheme": sch,
            "n_rh": 128,
            "seed": 123,
            "traces": [sc_map["429.mcf"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_NUM_MAX_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        })
    for sch in ("Baseline", "QShield", "QShield_Integ", "PARA_ACT"):
        pilot_jobs.append({
            "job_id": f"pilot33ms__single__tpch6__{sch}__nrh128",
            "category": "pilot_single_light",
            "workload": "tpch6",
            "scheme": sch,
            "n_rh": 128,
            "seed": 123,
            "traces": [sc_map["tpch6"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_NUM_MAX_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        })
    for sch in pilot_families_atk:
        pilot_jobs.append({
            "job_id": f"pilot33ms__attack__double_sided__{sch}__nrh128",
            "category": "pilot_attack",
            "workload": "double_sided",
            "scheme": sch,
            "n_rh": 128,
            "seed": 123,
            "traces": ds_traces,
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_NUM_MAX_CYCLES,
            "attacker_core_ids": [0],
            "meta_bypass_drm": False,
        })

    # 3) Determinism / reproducibility check at 33.6 ms (2 identical runs each for PARA_ACT and QShield)
    det_jobs = [
        {
            "job_id": "det__tpch6__PARA_ACT__nrh128__s123__run2",
            "category": "determinism",
            "workload": "tpch6",
            "scheme": "PARA_ACT",
            "n_rh": 128,
            "seed": 123,
            "traces": [sc_map["tpch6"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_NUM_MAX_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        },
        {
            "job_id": "det__tpch6__QShield__nrh128__s123__run2",
            "category": "determinism",
            "workload": "tpch6",
            "scheme": "QShield",
            "n_rh": 128,
            "seed": 123,
            "traces": [sc_map["tpch6"]],
            "num_expected_insts": T91_NUM_EXPECTED_INSTS,
            "num_max_cycles": T91_NUM_MAX_CYCLES,
            "attacker_core_ids": [],
            "meta_bypass_drm": False,
        },
    ]

    t0 = time.monotonic()
    all_pilot = ref_jobs + pilot_jobs + det_jobs
    res = run_jobs_pool(all_pilot, max_workers=workers, label="t91_pilot", fresh_workers=True, log_every=5)
    elapsed_total = round(time.monotonic() - t0, 2)
    by_id = {r["job_id"]: r for r in res}

    # Check determinism
    det_keys = ["ctrl_cycles", "sim_time_ms", "mean_ipc", "obs_num_act", "obs_max_disturb_r1", "obs_max_disturb_r2", "preventive_refreshes"]
    det_pairs = [
        ("PARA_ACT", "pilot33ms__single__tpch6__PARA_ACT__nrh128", "det__tpch6__PARA_ACT__nrh128__s123__run2"),
        ("QShield", "pilot33ms__single__tpch6__QShield__nrh128", "det__tpch6__QShield__nrh128__s123__run2"),
    ]
    det_report = []
    det_all_ok = True
    for name, id1, id2 in det_pairs:
        r1, r2 = by_id[id1], by_id[id2]
        diffs = {k: (r1.get(k), r2.get(k)) for k in det_keys if r1.get(k) != r2.get(k)}
        ok = (r1["status"] == "OK" and r2["status"] == "OK" and not diffs)
        if not ok:
            det_all_ok = False
        det_report.append({"scheme": name, "match": ok, "diffs": diffs})

    # Check stop criteria on 33.6 ms pilot runs
    long_pilot_res = [by_id[j["job_id"]] for j in (pilot_jobs + det_jobs)]
    max_single_run_s = max((r["elapsed_s"] for r in long_pilot_res), default=0.0)
    min_sim_ms = min((r["sim_time_ms"] for r in long_pilot_res), default=0.0)
    max_rss_mb = max((r.get("peak_rss_mb", 0.0) for r in long_pilot_res), default=0.0)
    err_cnt = sum(1 for r in res if r["status"] != "OK")

    # Extrapolate full matrix wall-clock runtime at max_workers=5
    heavy_sc_s = [by_id[j["job_id"]]["elapsed_s"] for j in pilot_jobs if j["category"] == "pilot_single_heavy"]
    light_sc_s = [by_id[j["job_id"]]["elapsed_s"] for j in pilot_jobs if j["category"] == "pilot_single_light"]
    atk_s = [by_id[j["job_id"]]["elapsed_s"] for j in pilot_jobs if j["category"] == "pilot_attack"]

    avg_heavy_sc = statistics.mean(heavy_sc_s)
    avg_light_sc = statistics.mean(light_sc_s)
    # 6 single-core workloads: 1 very heavy (429.mcf), 5 medium/light (model conservatively as 50/50 heavy+light for mid, light for low)
    est_avg_sc = (avg_heavy_sc + 5 * (0.5 * avg_heavy_sc + 0.5 * avg_light_sc)) / 6.0
    avg_atk = statistics.mean(atk_s)

    eff_workers = min(workers, 4.5)  # conservative parallel efficiency for 5 workers
    extrap = {}
    for ps in (1, 3):
        n_sch = 12 if ps == 1 else 16
        n_sc = 6 * 2 * n_sch + 1
        n_atk = 4 * 2 * n_sch
        cpu_s = n_sc * est_avg_sc + n_atk * avg_atk
        wall_min = (cpu_s / eff_workers) / 60.0
        extrap[f"para_seeds_{ps}"] = {
            "total_jobs": n_sc + n_atk,
            "single_jobs": n_sc,
            "attack_jobs": n_atk,
            "est_cpu_s": round(cpu_s, 1),
            "est_wall_min_5w": round(wall_min, 2),
            "fits_4h_cap": wall_min < 240.0,
        }

    ref_repro = {j["job_id"]: by_id[j["job_id"]] for j in ref_jobs}
    b429 = ref_repro["ref13ms__429.mcf__Baseline__nrh1024"]
    q429 = ref_repro["ref13ms__429.mcf__QShield_Integ__nrh1024"]
    bt6 = ref_repro["ref13ms__tpch6__Baseline__nrh1024"]

    payload = {
        "pilot_elapsed_s": elapsed_total,
        "workers": workers,
        "errors": err_cnt,
        "max_single_run_s": max_single_run_s,
        "exceeds_15min_cap": max_single_run_s > T91_MAX_RUN_SECONDS,
        "min_sim_time_ms": min_sim_ms,
        "all_sim_ge_32ms": min_sim_ms >= 32.0,
        "max_peak_rss_mb": max_rss_mb,
        "determinism_ok": det_all_ok,
        "determinism_details": det_report,
        "ref_13_44ms_repro": {
            "baseline_429_mcf": {
                "ctrl_cycles": b429["ctrl_cycles"],
                "sim_time_ms": b429["sim_time_ms"],
                "mean_ipc": round(b429["mean_ipc"], 4),
                "obs_max_disturb_r1": b429["obs_max_disturb_r1"],
                "obs_max_r1_bank": b429["obs_max_r1_bank"],
                "obs_max_r1_row": b429["obs_max_r1_row"],
                "obs_num_act": b429["obs_num_act"],
                "elapsed_s": b429["elapsed_s"],
                "peak_rss_mb": b429["peak_rss_mb"],
            },
            "qshield_integ_429_mcf": {
                "ctrl_cycles": q429["ctrl_cycles"],
                "sim_time_ms": q429["sim_time_ms"],
                "mean_ipc": round(q429["mean_ipc"], 4),
                "slowdown_vs_baseline": round(b429["mean_ipc"] / q429["mean_ipc"], 3) if q429["mean_ipc"] > 0 else 0.0,
                "avg_read_latency": round(q429["avg_read_latency"], 2),
                "obs_num_act": q429["obs_num_act"],
                "obs_num_meta_act": q429["obs_num_meta_act"],
                "obs_num_mit_act": q429["obs_num_mit_act"],
                "qshield_mc_hits": q429["qshield_mc_hits"],
                "qshield_mc_misses": q429["qshield_mc_misses"],
                "mc_miss_rate_pct": round(
                    100.0 * q429["qshield_mc_misses"] / max(1, q429["qshield_mc_hits"] + q429["qshield_mc_misses"]), 2
                ),
                "qshield_meta_rd_cnt": q429["qshield_meta_rd_cnt"],
                "qshield_meta_wr_cnt": q429["qshield_meta_wr_cnt"],
                "qshield_rfm_count": q429["qshield_rfm_count"],
                "qshield_victim_refreshes": q429["qshield_victim_refreshes"],
                "obs_max_disturb_r1": q429["obs_max_disturb_r1"],
                "elapsed_s": q429["elapsed_s"],
                "peak_rss_mb": q429["peak_rss_mb"],
            },
            "baseline_tpch6": {
                "ctrl_cycles": bt6["ctrl_cycles"],
                "sim_time_ms": bt6["sim_time_ms"],
                "mean_ipc": round(bt6["mean_ipc"], 4),
                "obs_max_disturb_r1": bt6["obs_max_disturb_r1"],
                "elapsed_s": bt6["elapsed_s"],
                "peak_rss_mb": bt6["peak_rss_mb"],
            },
        },
        "pilot_family_timings": [
            {
                "job_id": j["job_id"],
                "category": j["category"],
                "workload": j["workload"],
                "scheme": j["scheme"],
                "elapsed_s": by_id[j["job_id"]]["elapsed_s"],
                "sim_time_ms": by_id[j["job_id"]]["sim_time_ms"],
                "peak_rss_mb": by_id[j["job_id"]]["peak_rss_mb"],
                "mean_ipc": round(by_id[j["job_id"]]["mean_ipc"], 4),
                "obs_max_disturb_r1": by_id[j["job_id"]]["obs_max_disturb_r1"],
            }
            for j in pilot_jobs
        ],
        "extrapolation": extrap,
    }
    T91_PILOT_OUT.parent.mkdir(parents=True, exist_ok=True)
    T91_PILOT_OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print("=== [T91 PILOT SUMMARY] ===", flush=True)
    print(json.dumps({
        "pilot_elapsed_s": payload["pilot_elapsed_s"],
        "errors": payload["errors"],
        "max_single_run_s": payload["max_single_run_s"],
        "min_sim_time_ms": payload["min_sim_time_ms"],
        "max_peak_rss_mb": payload["max_peak_rss_mb"],
        "determinism_ok": payload["determinism_ok"],
        "ref_13_44ms_repro": payload["ref_13_44ms_repro"],
        "extrapolation": payload["extrapolation"],
    }, indent=2), flush=True)

    if err_cnt > 0 or not det_all_ok or min_sim_ms < 32.0 or max_single_run_s > T91_MAX_RUN_SECONDS:
        print("ERROR: T91 pilot triggered a stop condition!", file=sys.stderr, flush=True)
        sys.exit(1)


def _count_r1_violations_from_csv(csv_path: Path, subset_sc: set[str], subset_atk: set[str]) -> dict:
    """Count Worst R1 > N_RH cases from an existing T80/T87 perf_runs CSV, both on T91 subset and full matrix."""
    out = {}
    if not csv_path.is_file():
        return out
    with open(csv_path, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            cat = row.get("category", "")
            if cat not in ("single", "attack"):
                continue
            nrh = int(row["n_rh"])
            if nrh not in T91_NRH_VALUES:
                continue
            sch = row["scheme"]
            wl = row["workload"]
            r1 = int(row["obs_max_disturb_r1"])
            viol = (r1 > nrh)

            for scope, in_scope in [
                ("subset", (cat == "single" and wl in subset_sc) or (cat == "attack" and wl in subset_atk)),
                ("full", True),
            ]:
                if not in_scope:
                    continue
                key = (scope, cat, nrh, sch)
                entry = out.setdefault(key, {"runs": 0, "viol_runs": 0, "workloads": set(), "viol_workloads": set(), "worst_r1": 0})
                entry["runs"] += 1
                entry["workloads"].add(wl)
                if viol:
                    entry["viol_runs"] += 1
                    entry["viol_workloads"].add(wl)
                if r1 > entry["worst_r1"]:
                    entry["worst_r1"] = r1

    # Convert sets to counts for JSON serialization
    final = {}
    for k, v in out.items():
        final[k] = {
            "runs": v["runs"],
            "viol_runs": v["viol_runs"],
            "workloads": len(v["workloads"]),
            "viol_workloads": len(v["viol_workloads"]),
            "worst_r1": v["worst_r1"],
        }
    return final


def aggregate_and_report_long(results: list[dict], spec: dict, subset_meta: dict, elapsed_s: float, pilot_data: dict):
    """Emit perf_runs_long.csv, perf_summary_long.csv, perf_summary_long.json, perf_report_long.md (never touching T80/T87 files)."""
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    commit = get_git_commit()
    spec_cost = inspect_vrr_spec_cost()
    cfg_hashes = {p.name: sha256_file(p) for p in sorted(CONFIGS_DIR.glob("*.json"))}

    # Lookup trace line counts for wrap estimation
    sc_lines_map = {x["name"]: x["lines"] for x in subset_meta["single_core"]}
    sc_group_map = {x["name"]: x["group"] for x in subset_meta["single_core"]}
    atk_lines_map = {x["name"]: x["lines"] for x in subset_meta["attacks"]}
    corunner_names = subset_meta["attack_corunners"]

    base_single = {}        # (workload, n_rh) -> ipc
    base_attack_alone = {}  # workload -> ipc
    base_run = {}           # (category, workload, n_rh) -> result dict
    for r in results:
        r["dram_support"] = DRAM_SUPPORT_MAP.get(r["scheme"], ("chưa kiểm", ""))[0]
        if "sim_time_ms" not in r:
            r["sim_time_ms"] = round(int(r.get("ctrl_cycles", 0)) * 0.625e-6, 6)
        llc_tot = int(r.get("llc_read_access", 0)) + int(r.get("llc_write_access", 0))
        t_lines = sc_lines_map.get(r["workload"], atk_lines_map.get(r["workload"], 0))
        r["trace_lines"] = t_lines
        r["est_trace_wraps"] = round(llc_tot / t_lines, 2) if t_lines > 0 else 0.0
        if r["status"] == "OK" and r["scheme"] == "Baseline":
            base_run[(r["category"], r["workload"], r["n_rh"])] = r
            if r["category"] == "single":
                base_single[(r["workload"], r["n_rh"])] = r["mean_ipc"]
            elif r["category"] == "attack_alone":
                base_attack_alone[r["workload"]] = r["mean_ipc"]

    for r in results:
        if r["status"] != "OK":
            continue
        nrh = r["n_rh"]
        if r["category"] == "single":
            b_ipc = base_single.get((r["workload"], nrh), r["mean_ipc"])
            r["weighted_speedup"] = (r["mean_ipc"] / b_ipc) if b_ipc > 0 else 0.0
            r["harmonic_speedup"] = r["weighted_speedup"]
            r["max_slowdown"] = (b_ipc / r["mean_ipc"]) if r["mean_ipc"] > 0 else 0.0
        elif r["category"] == "attack":
            ratios, slows = [], []
            for idx, cname in enumerate(corunner_names, start=1):
                alone = base_single.get((cname, nrh), base_attack_alone.get(cname, 0.0))
                ipc_i = r["core_ipcs"][idx]
                if alone > 0 and ipc_i > 0:
                    ratios.append(ipc_i / alone)
                    slows.append(alone / ipc_i)
            r["weighted_speedup"] = sum(ratios) if ratios else 0.0
            r["harmonic_speedup"] = (len(slows) / sum(slows)) if slows else 0.0
            r["max_slowdown"] = max(slows) if slows else 0.0

    # Write perf_runs_long.csv
    runs_csv = REPORTS_DIR / "perf_runs_long.csv"
    run_cols = [
        "job_id", "category", "workload", "scheme", "dram_support", "n_rh", "seed", "status", "hit_max_cycles",
        "ctrl_cycles", "sim_time_ms", "trace_lines", "est_trace_wraps",
        "mean_ipc", "weighted_speedup", "harmonic_speedup", "max_slowdown",
        "avg_read_latency", "total_throughput_MBps", "preventive_refreshes", "act_mit_triggers",
        "act_mit_victim_refreshes", "act_mit_dropped", "obs_num_act", "obs_num_meta_act", "obs_num_mit_act",
        "obs_num_refab", "obs_num_vrr", "obs_num_rfmab", "obs_max_row_acts",
        "obs_max_disturb_r1", "obs_max_disturb_r2",
        "obs_max_r1_bank", "obs_max_r1_row", "obs_max_r1_row_is_meta",
        "obs_max_r1_aggr_meta_acts", "obs_max_r1_aggr_mit_acts", "obs_max_r1_aggr_user_acts",
        "obs_rows_exceeding_nrh_r1", "obs_rows_exceeding_nrh_r2", "qshield_sdc_throttles",
        "qshield_coordinated_throttles", "qshield_victim_refreshes", "qshield_mit_acts",
        "qshield_rfm_count", "qshield_rowpress_alerts", "qshield_tras_clamps",
        "qshield_proq_blocks", "qshield_pace_defers",
        "qshield_mc_hits", "qshield_mc_misses", "qshield_meta_rd_cnt", "qshield_meta_wr_cnt",
        "qshield_reencrypt_events", "peak_rss_mb", "elapsed_s", "error",
    ]
    with open(runs_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=run_cols)
        w.writeheader()
        for r in sorted(results, key=lambda x: (x["category"], x["n_rh"], x["workload"], x["scheme"], x["seed"])):
            w.writerow({k: r.get(k, "") for k in run_cols})

    # Aggregate per (category, scheme, n_rh), excluding auxiliary attack_alone
    grouped = {}
    for r in results:
        if r["category"] == "attack_alone":
            continue
        grouped.setdefault((r["category"], r["scheme"], r["n_rh"]), []).append(r)

    summary_rows = []
    for (cat, scheme, nrh), items in sorted(grouped.items(), key=lambda x: (x[0][0], x[0][2], ALL_SCHEMES_V2.index(x[0][1]))):
        ok_items = [x for x in items if x["status"] == "OK"]
        base_items = [x for x in grouped.get((cat, "Baseline", nrh), []) if x["status"] == "OK"]
        base_by_wl = {x["workload"]: x for x in base_items}

        by_wl = {}
        for x in ok_items:
            by_wl.setdefault(x["workload"], []).append(x)

        ws_vals, hs_vals, ms_vals, norm_ws_vals, pref_vals, ipc_vals = [], [], [], [], [], []
        max_r1_vals, max_r2_vals, sim_ms_vals = [], [], []
        exceed_r1_runs = 0
        exceed_r1_wls = 0
        exceed_r1_rows_sum = 0
        exceed_r2_rows_sum = 0
        per_wl_seed_cis = []
        t_crit_df2 = 4.3027

        for wl, w_runs in by_wl.items():
            ws_w = statistics.mean(x["weighted_speedup"] for x in w_runs)
            hs_w = statistics.mean(x["harmonic_speedup"] for x in w_runs)
            ms_w = statistics.mean(x["max_slowdown"] for x in w_runs)
            pref_w = statistics.mean(x["preventive_refreshes"] for x in w_runs)
            ipc_w = statistics.mean(x["mean_ipc"] for x in w_runs)
            ws_vals.append(ws_w)
            hs_vals.append(hs_w)
            ms_vals.append(ms_w)
            pref_vals.append(pref_w)
            ipc_vals.append(ipc_w)
            w_r1 = max(x["obs_max_disturb_r1"] for x in w_runs)
            w_r2 = max(x["obs_max_disturb_r2"] for x in w_runs)
            max_r1_vals.append(w_r1)
            max_r2_vals.append(w_r2)
            sim_ms_vals.extend(x["sim_time_ms"] for x in w_runs)
            exceed_r1_runs += sum(1 for x in w_runs if x["obs_max_disturb_r1"] > nrh)
            if w_r1 > nrh:
                exceed_r1_wls += 1
            exceed_r1_rows_sum += sum(x["obs_rows_exceeding_nrh_r1"] for x in w_runs)
            exceed_r2_rows_sum += sum(x["obs_rows_exceeding_nrh_r2"] for x in w_runs)
            if wl in base_by_wl and base_by_wl[wl]["weighted_speedup"] > 0:
                norm_ws_vals.append(ws_w / base_by_wl[wl]["weighted_speedup"])
            if len(w_runs) >= 2:
                s = statistics.stdev(x["weighted_speedup"] for x in w_runs)
                per_wl_seed_cis.append(t_crit_df2 * s / math.sqrt(len(w_runs)))

        ds, ds_ref = DRAM_SUPPORT_MAP[scheme]
        summary_rows.append({
            "category": cat,
            "scheme": scheme,
            "dram_support": ds,
            "dram_support_evidence": ds_ref,
            "n_rh": nrh,
            "runs_total": len(items),
            "runs_ok": len(ok_items),
            "workloads_total": len(by_wl),
            "sim_time_ms_min": round(min(sim_ms_vals), 4) if sim_ms_vals else 0.0,
            "sim_time_ms_max": round(max(sim_ms_vals), 4) if sim_ms_vals else 0.0,
            "mean_ipc_avg": round(statistics.mean(ipc_vals), 4) if ipc_vals else None,
            "weighted_speedup_mean": round(statistics.mean(ws_vals), 4) if ws_vals else None,
            "norm_weighted_speedup_mean": round(statistics.mean(norm_ws_vals), 4) if norm_ws_vals else None,
            "seed_ci95_ws": round(statistics.mean(per_wl_seed_cis), 5) if per_wl_seed_cis else 0.0,
            "harmonic_speedup_mean": round(statistics.mean(hs_vals), 4) if hs_vals else None,
            "max_slowdown_mean": round(statistics.mean(ms_vals), 4) if ms_vals else None,
            "preventive_refreshes_mean": round(statistics.mean(pref_vals), 1) if pref_vals else None,
            "max_disturb_r1_worst": max(max_r1_vals) if max_r1_vals else None,
            "max_disturb_r2_worst": max(max_r2_vals) if max_r2_vals else None,
            "r1_exceed_runs": exceed_r1_runs,
            "r1_exceed_workloads": exceed_r1_wls,
            "rows_exceeding_nrh_r1_sum": exceed_r1_rows_sum if ok_items else None,
            "rows_exceeding_nrh_r2_sum": exceed_r2_rows_sum if ok_items else None,
        })

    summary_csv = REPORTS_DIR / "perf_summary_long.csv"
    sum_cols = list(summary_rows[0].keys()) if summary_rows else []
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=sum_cols)
        w.writeheader()
        for r in summary_rows:
            w.writerow(r)

    # Compare Worst R1 > N_RH across T80, T87, and T91
    subset_sc = {x["name"] for x in subset_meta["single_core"]}
    subset_atk = {x["name"] for x in subset_meta["attacks"]}
    t80_viol = _count_r1_violations_from_csv(REPORTS_DIR / "perf_runs.csv", subset_sc, subset_atk)
    t87_viol = _count_r1_violations_from_csv(REPORTS_DIR / "perf_runs_v2.csv", subset_sc, subset_atk)
    t91_viol = _count_r1_violations_from_csv(runs_csv, subset_sc, subset_atk)

    r1_comparison = []
    for sch in ALL_SCHEMES_V2:
        ds, _ = DRAM_SUPPORT_MAP[sch]
        row_cmp = {"scheme": sch, "dram_support": ds}
        for label, vmap in [("t80_sub", t80_viol), ("t87_sub", t87_viol), ("t91_long", t91_viol)]:
            tot_runs = 0
            tot_vruns = 0
            tot_wls = 0
            tot_vwls = 0
            sc1024 = vmap.get(("subset", "single", 1024, sch))
            sc128 = vmap.get(("subset", "single", 128, sch))
            atk1024 = vmap.get(("subset", "attack", 1024, sch))
            atk128 = vmap.get(("subset", "attack", 128, sch))
            for d in (sc1024, sc128, atk1024, atk128):
                if d:
                    tot_runs += d["runs"]
                    tot_vruns += d["viol_runs"]
                    tot_wls += d["workloads"]
                    tot_vwls += d["viol_workloads"]
            row_cmp[label] = {
                "viol_runs": tot_vruns,
                "total_runs": tot_runs,
                "viol_wls": tot_vwls,
                "total_wls": tot_wls,
                "single_1024": f"{sc1024['viol_runs']}/{sc1024['runs']}" if sc1024 else "N/A",
                "single_128": f"{sc128['viol_runs']}/{sc128['runs']}" if sc128 else "N/A",
                "attack_1024": f"{atk1024['viol_runs']}/{atk1024['runs']}" if atk1024 else "N/A",
                "attack_128": f"{atk128['viol_runs']}/{atk128['runs']}" if atk128 else "N/A",
            }
        # Also record full T87 matrix (single+attack @ 1024/128) for context
        full_v, full_t = 0, 0
        for cat in ("single", "attack"):
            for nrh in T91_NRH_VALUES:
                d = t87_viol.get(("full", cat, nrh, sch))
                if d:
                    full_v += d["viol_runs"]
                    full_t += d["runs"]
        row_cmp["t87_full_sc_atk_1024_128"] = f"{full_v}/{full_t}" if full_t else "N/A"
        r1_comparison.append(row_cmp)

    # Extract 429.mcf long-window details for explaining the 2 warning numbers
    by_wl_sch = {(r["category"], r["workload"], r["scheme"], r["n_rh"]): r for r in results if r["seed"] == 123}
    mcf_b_1024 = by_wl_sch.get(("single", "429.mcf", "Baseline", 1024), {})
    mcf_qs_1024 = by_wl_sch.get(("single", "429.mcf", "QShield", 1024), {})
    mcf_qsi_1024 = by_wl_sch.get(("single", "429.mcf", "QShield_Integ", 1024), {})
    mcf_b_128 = by_wl_sch.get(("single", "429.mcf", "Baseline", 128), {})
    mcf_qsi_128 = by_wl_sch.get(("single", "429.mcf", "QShield_Integ", 128), {})

    all_sim_ms = [r["sim_time_ms"] for r in results if r["status"] == "OK"]
    min_sim_ms = min(all_sim_ms) if all_sim_ms else 0.0
    max_sim_ms = max(all_sim_ms) if all_sim_ms else 0.0
    max_run_s = max((r["elapsed_s"] for r in results), default=0.0)
    max_rss_mb = max((r.get("peak_rss_mb", 0.0) for r in results), default=0.0)
    act_vrr_nonzero = sum(1 for r in results if r["scheme"].endswith("_ACT") and int(r.get("obs_num_vrr", 0)) != 0)
    act_dropped_total = sum(int(r.get("act_mit_dropped", 0)) for r in results if r["scheme"].endswith("_ACT"))

    # Per-workload wrap statistics on Baseline N_RH=1024
    wrap_rows = []
    for item in subset_meta["single_core"]:
        r = by_wl_sch.get(("single", item["name"], "Baseline", 1024))
        if r:
            wrap_rows.append({
                "category": "single",
                "workload": item["name"],
                "group": item["group"],
                "trace_lines": item["lines"],
                "size_mb": round(item["size_bytes"] / (1024 * 1024), 2),
                "core_insts": r["core_insts"][0] if r.get("core_insts") else 0,
                "llc_accesses": r["llc_read_access"] + r["llc_write_access"],
                "est_trace_wraps": r["est_trace_wraps"],
                "baseline_ipc": round(r["mean_ipc"], 4),
                "baseline_r1_1024": r["obs_max_disturb_r1"],
            })
    for atk in subset_meta["attacks"]:
        r = by_wl_sch.get(("attack", atk["name"], "Baseline", 1024))
        if r:
            wrap_rows.append({
                "category": "attack",
                "workload": atk["name"],
                "group": "Attack(1+3)",
                "trace_lines": atk["lines"],
                "size_mb": round(Path(atk["path"]).stat().st_size / (1024 * 1024), 4),
                "core_insts": r["core_insts"][0] if r.get("core_insts") else 0,
                "llc_accesses": r["llc_read_access"] + r["llc_write_access"],
                "est_trace_wraps": r["est_trace_wraps"],
                "baseline_ipc": round(r["mean_ipc"], 4),
                "baseline_r1_1024": r["obs_max_disturb_r1"],
            })

    summary_json = {
        "git_commit": commit,
        "upstream_commit": "72427a1bba3771564c4fb0e494ba02242fd1eaa7",
        "dram_energy_model": "N/A (not provided by upstream Ramulator2 commit 72427a1)",
        "subset_spec": subset_meta,
        "total_runs": len(results),
        "ok_runs": sum(1 for r in results if r["status"] == "OK"),
        "sim_time_ms_min": min_sim_ms,
        "sim_time_ms_max": max_sim_ms,
        "all_sim_ge_32ms": (min_sim_ms >= 32.0 and len(all_sim_ms) == len(results)),
        "max_single_run_s": max_run_s,
        "max_peak_rss_mb": max_rss_mb,
        "actual_elapsed_s": round(elapsed_s, 2),
        "actual_elapsed_min": round(elapsed_s / 60.0, 2),
        "act_variants_vrr_nonzero": act_vrr_nonzero,
        "act_variants_dropped_total": act_dropped_total,
        "spec_vrr_cost": spec_cost,
        "pilot_summary": pilot_data,
        "trace_wrap_analysis": wrap_rows,
        "r1_violation_comparison": r1_comparison,
        "config_hashes": cfg_hashes,
        "summary": summary_rows,
    }
    (REPORTS_DIR / "perf_summary_long.json").write_text(json.dumps(summary_json, indent=2), encoding="utf-8")

    # Build perf_report_long.md
    c_repro = (pilot_data or {}).get("ref_13_44ms_repro", {})
    cb429 = c_repro.get("baseline_429_mcf", {})
    cq429 = c_repro.get("qshield_integ_429_mcf", {})
    cbt6 = c_repro.get("baseline_tpch6", {})

    qsi_1024_mc_tot = mcf_qsi_1024.get("qshield_mc_hits", 0) + mcf_qsi_1024.get("qshield_mc_misses", 0)
    qsi_1024_mc_miss_pct = (100.0 * mcf_qsi_1024.get("qshield_mc_misses", 0) / qsi_1024_mc_tot) if qsi_1024_mc_tot else 0.0
    qsi_1024_slowdown = (
        mcf_b_1024.get("mean_ipc", 0.0) / mcf_qsi_1024.get("mean_ipc", 1.0)
        if mcf_qsi_1024.get("mean_ipc", 0.0) > 0 else 0.0
    )

    md = [
        "# Q-Shield Ramulator2 Long-Window Evaluation (`>= 1 tREFW = 32 ms`, `reports/paper/perf/perf_report_long.md`)",
        f"- Commit: `{commit}` | Upstream Ramulator2: `72427a1bba3771564c4fb0e494ba02242fd1eaa7`",
        "- DRAM Energy: `N/A (not provided by upstream Ramulator2 commit 72427a1)`",
        f"- Cửa sổ theo thời gian: `num_max_cycles = {T91_NUM_MAX_CYCLES}` (chu kỳ lõi BHO3), `num_expected_insts = {T91_NUM_EXPECTED_INSTS}`, `ctrl_cycles = {subset_meta['expected_ctrl_cycles']}`, **`sim_time_ms` thực đo: `[{min_sim_ms:.4f}, {max_sim_ms:.4f}] ms`** (`>= 32.0 ms = 1 tREFW` trên **`{summary_json['ok_runs']}/{summary_json['total_runs']}`** lượt chạy).",
        f"- Thời gian thực tế: `{elapsed_s:.2f}s` (`{elapsed_s/60.0:.2f} phút`) | Lượt chạy lâu nhất: `{max_run_s:.2f}s` (`<= 900s`) | Đỉnh RSS/worker: `{max_rss_mb:.1f} MB` | `*_ACT` VRR=`{act_vrr_nonzero}`, dropped=`{act_dropped_total}`.",
        f"- Kiểm tra tái lập cùng seed (`PARA_ACT` & `QShield` @ `tpch6`, `N_RH=128`, `seed=123`, `33.6 ms`): **`{'PASS (khớp tuyệt đối)' if (pilot_data or {}).get('determinism_ok') else 'FAIL'}`**.",
        "- Lưu ý về hiệu chuẩn: Giữ cùng tham số mô hình mặc định như T80/T87 (chưa bật bộ tham số hiệu chuẩn trong mẫu của T81/T90, có độ lạc quan hệ thống ~4–5% theo R-86/R-89).",
        "",
        "## 1. Cách chọn tập con workload và phân tích lặp trace (`BHO3`)",
        f"- {subset_meta['selection_rationale']}",
        "- **Cảnh báo lặp trace:** `BHO3`/`SimpleO3` tự quay vòng về đầu trace khi đọc hết file. Ở cửa sổ dài `33.6 ms`, các trace ngắn (`tpch6` 279.379 dòng, `458.sjeng` 71.977 dòng, 4 attack trace 1.800–14.720 dòng) bị lặp nhiều lần; các số liệu dưới đây phải đọc kèm số lần lặp ước lượng (`llc_accesses / trace_lines`, với kịch bản tấn công là tổng truy cập LLC của cả 4 nhân chia cho số dòng trace tấn công).",
        "",
        "| Category | Workload | Nhóm MPKI | Số dòng trace | Kích thước (MB) | Lệnh core 0 (Baseline 33.6 ms) | Tổng truy cập LLC | Ước lượng vòng lặp (`LLC/dòng`) | IPC Baseline | Worst R1 Baseline (`N_RH=1024`) |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for wr in wrap_rows:
        md.append(
            f"| {wr['category']} | `{wr['workload']}` | {wr['group']} | {wr['trace_lines']} | {wr['size_mb']} | "
            f"{wr['core_insts']} | {wr['llc_accesses']} | {wr['est_trace_wraps']} | {wr['baseline_ipc']} | {wr['baseline_r1_1024']} |"
        )

    md.extend([
        "",
        "## 2. Tái lập và giải thích hai hiện tượng cảnh giác trên `429.mcf`",
        "### 2.1. Đối chiếu trực tiếp điểm đo 13,44 ms (`num_max_cycles = 53,760,000`, `N_RH = 1024`) và cửa sổ dài 33,6 ms",
        "| Cấu hình | Cửa sổ | `ctrl_cycles` | `sim_time_ms` | IPC | Tỉ lệ chậm vs Baseline | `avg_read_lat` (nCK) | Tổng ACT | Meta ACT | Mit ACT | MC Miss Rate | `RFMab` | `Worst R1` |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        f"| `Baseline` (`429.mcf`) | 13.44 ms | {cb429.get('ctrl_cycles')} | {cb429.get('sim_time_ms')} | {cb429.get('mean_ipc')} | 1.000× | — | {cb429.get('obs_num_act')} | 0 | 0 | — | 0 | **{cb429.get('obs_max_disturb_r1')}** (b={cb429.get('obs_max_r1_bank')}, r={cb429.get('obs_max_r1_row')}) |",
        f"| `QShield_Integ` (`429.mcf`) | 13.44 ms | {cq429.get('ctrl_cycles')} | {cq429.get('sim_time_ms')} | **{cq429.get('mean_ipc')}** | **{cq429.get('slowdown_vs_baseline')}×** | {cq429.get('avg_read_latency')} | {cq429.get('obs_num_act')} | {cq429.get('obs_num_meta_act')} | {cq429.get('obs_num_mit_act')} | {cq429.get('mc_miss_rate_pct')}% | {cq429.get('qshield_rfm_count')} | {cq429.get('obs_max_disturb_r1')} |",
        f"| `Baseline` (`tpch6`) | 13.44 ms | {cbt6.get('ctrl_cycles')} | {cbt6.get('sim_time_ms')} | {cbt6.get('mean_ipc')} | 1.000× | — | — | 0 | 0 | — | 0 | {cbt6.get('obs_max_disturb_r1')} |",
        f"| `Baseline` (`429.mcf`) | **33.6 ms** | {mcf_b_1024.get('ctrl_cycles')} | {mcf_b_1024.get('sim_time_ms')} | {round(mcf_b_1024.get('mean_ipc', 0.0), 4)} | 1.000× | {round(mcf_b_1024.get('avg_read_latency', 0.0), 2)} | {mcf_b_1024.get('obs_num_act')} | 0 | 0 | — | 0 | **{mcf_b_1024.get('obs_max_disturb_r1')}** (b={mcf_b_1024.get('obs_max_r1_bank')}, r={mcf_b_1024.get('obs_max_r1_row')}) |",
        f"| `QShield` (`429.mcf`) | **33.6 ms** | {mcf_qs_1024.get('ctrl_cycles')} | {mcf_qs_1024.get('sim_time_ms')} | {round(mcf_qs_1024.get('mean_ipc', 0.0), 4)} | {round(mcf_b_1024.get('mean_ipc', 0.0) / max(1e-9, mcf_qs_1024.get('mean_ipc', 1e-9)), 3)}× | {round(mcf_qs_1024.get('avg_read_latency', 0.0), 2)} | {mcf_qs_1024.get('obs_num_act')} | 0 | {mcf_qs_1024.get('obs_num_mit_act')} | — | {mcf_qs_1024.get('qshield_rfm_count')} | {mcf_qs_1024.get('obs_max_disturb_r1')} |",
        f"| `QShield_Integ` (`429.mcf`) | **33.6 ms** | {mcf_qsi_1024.get('ctrl_cycles')} | {mcf_qsi_1024.get('sim_time_ms')} | **{round(mcf_qsi_1024.get('mean_ipc', 0.0), 4)}** | **{qsi_1024_slowdown:.3f}×** | {round(mcf_qsi_1024.get('avg_read_latency', 0.0), 2)} | {mcf_qsi_1024.get('obs_num_act')} | {mcf_qsi_1024.get('obs_num_meta_act')} | {mcf_qsi_1024.get('obs_num_mit_act')} | {qsi_1024_mc_miss_pct:.2f}% | {mcf_qsi_1024.get('qshield_rfm_count')} | {mcf_qsi_1024.get('obs_max_disturb_r1')} |",
        "",
        "### 2.2. Giải thích cơ chế định lượng",
        f"1. **Tại sao `Baseline` `429.mcf` đạt `Worst R1 = {cb429.get('obs_max_disturb_r1')}` (13.44 ms) và `{mcf_b_1024.get('obs_max_disturb_r1')}` (33.6 ms) không có tấn công:** `429.mcf` (tối ưu mạng đơn hình SPEC CPU2006) có mật độ truy cập DRAM cực lớn (`LLC MPKI = 464.65`, `DRAM MPKI = 72.20`, xung đột hàng cao khi duyệt danh sách cung/nút liên tục qua `15.28M` dòng trace, gần như không lặp lại nhiều trong 13.44 ms). Các cấu trúc nút gốc/cung nóng nằm gần nhau về địa chỉ vật lý dưới ánh xạ `RoBaRaCoCh` nên tạo ra xung đột đóng/mở hàng liên tục trên cùng bank (tại `b={cb429.get('obs_max_r1_bank')}, r={cb429.get('obs_max_r1_row')}` sau 13.44 ms và `b={mcf_b_1024.get('obs_max_r1_bank')}, r={mcf_b_1024.get('obs_max_r1_row')}` sau 33.6 ms), tích lũy nhiễu vượt `N_RH = 1024` ngay cả trên tải lành tính khi chưa hết 1 `tREFW`. Đây là hiện tượng **benign RowHammer-like hot-row thrashing** có thật trong ứng dụng bộ nhớ dày đặc, khẳng định vì sao cửa sổ ngắn 0.24 ms ở T80 (`Worst R1 = 133`) che khuất rủi ro này.",
        f"2. **Tại sao `QShield_Integ` chậm ~`{cq429.get('slowdown_vs_baseline')}×` (13.44 ms) / `{qsi_1024_slowdown:.2f}×` (33.6 ms) trên `429.mcf` trong khi `QShield` không toàn vẹn chỉ chậm ~`{round(mcf_b_1024.get('mean_ipc', 0.0) / max(1e-9, mcf_qs_1024.get('mean_ipc', 1e-9)), 2)}×`:** Nguyên nhân không phải lỗi mô phỏng mà là **nút cổ chai dung lượng bộ đệm metadata (Metadata Cache thrashing)** khớp đúng RTL (`qshield_meta_cache.sv`: chỉ `16 sets × 4 ways = 64 entries = 4 KB` dùng chung cho Counter Block, 4 tầng Bonsai Merkle Tree và MAC Line): trên `429.mcf`, tỉ lệ trượt metadata cache lên tới **`{qsi_1024_mc_miss_pct:.2f}%`** (`hits={mcf_qsi_1024.get('qshield_mc_hits')}`, `misses={mcf_qsi_1024.get('qshield_mc_misses')}`), phát sinh `{mcf_qsi_1024.get('obs_num_meta_act')}` lệnh ACT metadata (`{100.0 * mcf_qsi_1024.get('obs_num_meta_act', 0) / max(1, mcf_qsi_1024.get('obs_num_act', 1)):.1f}%` tổng ACT), kéo theo `{mcf_qsi_1024.get('qshield_rfm_count')}` lệnh `RFMab` (so với `{mcf_qs_1024.get('qshield_rfm_count')}` của `QShield`) và `{mcf_qsi_1024.get('obs_num_mit_act')}` ACT giảm thiểu, đẩy độ trễ đọc trung bình từ `{round(mcf_b_1024.get('avg_read_latency', 0.0), 1)}` nCK lên `{round(mcf_qsi_1024.get('avg_read_latency', 0.0), 1)}` nCK (cộng thêm `crypto_extra_lat_clk = 84` nCK). Khi báo cáo trong paper, con số chậm ~4–5× trên `429.mcf` phải nêu rõ là **chi phí của cấu hình FPGA-scale 4 KB metadata cache trên tải random-pointer-chasing cực hạn**, không được che giấu cũng không được quy nạp thành chi phí trung bình của mọi workload.",
    ])

    def append_long_table(title: str, rows: list[dict]):
        md.extend([
            "",
            f"## {title}",
            "| Category | N_RH | Scheme | dram_support | OK/Total | `sim_ms` min..max | Mean IPC | Norm WS | Seed 95% CI | Harmonic Speedup | Max Slowdown | Prev Ref | Worst R1 | Worst R2 | Ca `R1 > N_RH` (runs / wl) |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        ])
        for r in rows:
            md.append(
                f"| {r['category']} | {r['n_rh']} | {r['scheme']} | `{r['dram_support']}` | {r['runs_ok']}/{r['runs_total']} | "
                f"{r['sim_time_ms_min']:.2f}..{r['sim_time_ms_max']:.2f} | {r['mean_ipc_avg']} | "
                f"{r['norm_weighted_speedup_mean']} | {r['seed_ci95_ws']} | {r['harmonic_speedup_mean']} | "
                f"{r['max_slowdown_mean']} | {r['preventive_refreshes_mean']} | "
                f"{r['max_disturb_r1_worst']} | {r['max_disturb_r2_worst']} | "
                f"{r['r1_exceed_runs']}/{r['runs_ok']} ({r['r1_exceed_workloads']}/{r['workloads_total']}) |"
            )

    none_rows = [r for r in summary_rows if r["dram_support"] == "none"]
    custom_rows = [r for r in summary_rows if r["dram_support"] != "none"]
    append_long_table("3. Bảng A — Cửa sổ dài (`>= 1 tREFW`), cấu hình KHÔNG cần sửa chip DRAM thương mại (`dram_support = none`)", none_rows)
    append_long_table("4. Bảng B — Cửa sổ dài (`>= 1 tREFW`), cấu hình CẦN lệnh không chuẩn hoặc hỗ trợ trong chip DRAM (`vrr_non_jedec`, `in_dram`)", custom_rows)

    md.extend([
        "",
        "## 5. So sánh số ca `Worst R1 > N_RH` giữa cửa sổ ngắn (T80, T87) và cửa sổ dài (T91, `>= 1 tREFW`)",
        "Bảng so sánh trực tiếp trên **cùng tập con 6 đơn nhân + 4 tấn công tại `N_RH ∈ {1024, 128}`** (và cột tham chiếu ma trận đầy đủ `single+attack @ 1024/128` của T87). Các nhóm `dram_support` vẫn tách rõ, không xếp hạng chung.",
        "",
        "| Nhóm DRAM | Scheme | T80 ngắn (cùng tập con: `viol/runs`) | T87 ngắn (cùng tập con: `viol/runs`) | **T91 dài ≥ 1 tREFW (`viol/runs`)** | T91 `single@1024` | T91 `single@128` | T91 `attack@1024` | T91 `attack@128` | T87 full (`single+atk@1024,128`) |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ])
    for rc in r1_comparison:
        t80s = rc["t80_sub"]
        t87s = rc["t87_sub"]
        t91s = rc["t91_long"]
        t80_str = f"{t80s['viol_runs']}/{t80s['total_runs']}" if t80s["total_runs"] else "N/A (T87)"
        t87_str = f"{t87s['viol_runs']}/{t87s['total_runs']}" if t87s["total_runs"] else "N/A"
        t91_str = f"**{t91s['viol_runs']}/{t91s['total_runs']}**"
        md.append(
            f"| `{rc['dram_support']}` | `{rc['scheme']}` | {t80_str} | {t87_str} | {t91_str} | "
            f"{t91s['single_1024']} | {t91s['single_128']} | {t91s['attack_1024']} | {t91s['attack_128']} | "
            f"{rc['t87_full_sc_atk_1024_128']} |"
        )

    # Detailed list of all QShield / QShield_Integ violations in long window (if any)
    qs_viols = [
        r for r in results
        if r["category"] in ("single", "attack")
        and r["scheme"] in ("QShield", "QShield_Integ")
        and r["obs_max_disturb_r1"] > r["n_rh"]
    ]
    md.extend([
        "",
        f"## 6. Chi tiết các ca `Worst R1 > N_RH` của `QShield` và `QShield_Integ` ở cửa sổ dài (`count = {len(qs_viols)}`)",
    ])
    if qs_viols:
        md.extend([
            "| Category | Workload | Scheme | N_RH | Worst R1 | Bank | Row | `row_is_meta` | `a_meta` | `a_mit` | `a_usr` | `rows_exceed_r1` |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|",
        ])
        for r in sorted(qs_viols, key=lambda x: (x["scheme"], x["category"], x["n_rh"], -x["obs_max_disturb_r1"])):
            md.append(
                f"| {r['category']} | `{r['workload']}` | `{r['scheme']}` | {r['n_rh']} | {r['obs_max_disturb_r1']} | "
                f"{r['obs_max_r1_bank']} | {r['obs_max_r1_row']} | {r['obs_max_r1_row_is_meta']} | "
                f"{r['obs_max_r1_aggr_meta_acts']} | {r['obs_max_r1_aggr_mit_acts']} | {r['obs_max_r1_aggr_user_acts']} | "
                f"{r['obs_rows_exceeding_nrh_r1']} |"
            )
    else:
        md.append("- Không có ca nào vượt `N_RH`.")

    (REPORTS_DIR / "perf_report_long.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return summary_json


def run_t91_full(workers: int = 5, para_seeds: int = 3, resume: bool = False):
    """Run full T91 long-window (>= 1 tREFW = 32 ms) subset matrix and emit perf_runs_long.csv + perf_report_long.md."""
    workers = max(1, min(T91_MAX_WORKERS, workers))
    spec = json.loads((CONFIGS_DIR / "matrix_spec.json").read_text(encoding="utf-8"))
    write_t87_scheme_configs()

    pilot_data = {}
    if T91_PILOT_OUT.is_file():
        pilot_data = json.loads(T91_PILOT_OUT.read_text(encoding="utf-8"))

    jobs, subset_meta = build_jobs_for_t91(spec, para_seeds=para_seeds)
    (CONFIGS_DIR / "long_subset_spec.json").write_text(json.dumps(subset_meta, indent=2), encoding="utf-8")

    if not resume and T91_CHECKPOINT_FILE.is_file():
        T91_CHECKPOINT_FILE.unlink()

    t0 = time.monotonic()
    single_jobs = [j for j in jobs if j["category"] in ("single", "attack_alone")]
    attack_jobs = [j for j in jobs if j["category"] == "attack"]

    raw_res = []
    raw_res.extend(run_jobs_pool(single_jobs, max_workers=workers, label="t91_single", checkpoint_path=T91_CHECKPOINT_FILE, fresh_workers=True, log_every=5))
    raw_res.extend(run_jobs_pool(attack_jobs, max_workers=workers, label="t91_attack", checkpoint_path=T91_CHECKPOINT_FILE, fresh_workers=True, log_every=5))
    elapsed = time.monotonic() - t0

    # Keep only jobs belonging to this T91 matrix (deduplicated)
    wanted_ids = {j["job_id"] for j in jobs}
    by_id = {r["job_id"]: r for r in raw_res if r["job_id"] in wanted_ids}
    results = list(by_id.values())

    # Enforce strict T91 stop criteria
    err_rows = [r for r in results if r["status"] != "OK"]
    short_rows = [r for r in results if r.get("sim_time_ms", 0.0) < 32.0]
    slow_rows = [r for r in results if r.get("elapsed_s", 0.0) > T91_MAX_RUN_SECONDS]

    summary_json = aggregate_and_report_long(results, spec, subset_meta, elapsed, pilot_data)
    print(
        f"[t91-full] Completed {summary_json['ok_runs']}/{summary_json['total_runs']} runs in "
        f"{elapsed:.2f}s ({elapsed/60.0:.2f} min) | sim_time_ms=[{summary_json['sim_time_ms_min']:.4f}, "
        f"{summary_json['sim_time_ms_max']:.4f}] | max_run_s={summary_json['max_single_run_s']:.2f}s | "
        f"max_rss={summary_json['max_peak_rss_mb']:.1f}MB | errors={len(err_rows)} | "
        f"lt32ms={len(short_rows)} | gt15min={len(slow_rows)}",
        flush=True,
    )
    if err_rows or short_rows or slow_rows or len(results) != len(jobs):
        if err_rows:
            print(f"[t91-full] STOP: {len(err_rows)} failed runs (sample: {err_rows[0]['job_id']}: {err_rows[0]['error']})", file=sys.stderr)
        if short_rows:
            print(f"[t91-full] STOP: {len(short_rows)} runs with sim_time_ms < 32 (sample: {short_rows[0]['job_id']}: {short_rows[0]['sim_time_ms']})", file=sys.stderr)
        if slow_rows:
            print(f"[t91-full] STOP: {len(slow_rows)} runs exceeded 15 min (sample: {slow_rows[0]['job_id']}: {slow_rows[0]['elapsed_s']}s)", file=sys.stderr)
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--discover", action="store_true", help="Discover Chronus traces and host specs")
    ap.add_argument("--measure-mpki", action="store_true", help="Measure Baseline MPKI across all Chronus traces and build workload matrix")
    ap.add_argument("--quick", action="store_true", help="Run fast smoke matrix + validity gate across all 9 schemes and 4 N_RH")
    ap.add_argument("--t87-audit-meta", action="store_true", help="Audit T80 QShield_Integ Worst R1>N_RH cases before/after DRM metadata protection")
    ap.add_argument("--t87-quick", action="store_true", help="Run T87 quick smoke matrix for *_ACT and fixed QShield_Integ")
    ap.add_argument("--t87-full", action="store_true", help="Run full T87 matrix (1080 new runs) and emit perf_runs_v2/perf_report_v2")
    ap.add_argument("--t91-pilot", action="store_true", help="Run T91 pilot: 13.44 ms reference, per-family 33.6 ms timings, determinism check, runtime extrapolation")
    ap.add_argument("--t91-full", action="store_true", help="Run full T91 long-window (>= 1 tREFW) matrix and emit perf_runs_long.csv + perf_report_long.md")
    ap.add_argument("--workers", type=int, default=5, help="Max parallel workers for T91 (clamped <= 5)")
    ap.add_argument("--para-seeds", type=int, default=3, help="Number of seeds for PARA/PARA_ACT in T91 (1 or 3)")
    ap.add_argument("--benign-insts", type=int, default=2_000_000)
    ap.add_argument("--attack-insts", type=int, default=500_000)
    ap.add_argument("--resume", action="store_true", help="Resume full matrix from checkpoint")
    args = ap.parse_args()

    if args.discover:
        discover()
    elif args.measure_mpki:
        measure_mpki(insts=args.benign_insts)
    elif args.quick:
        run_quick()
    elif args.t87_audit_meta:
        run_t87_audit_meta(benign_insts=args.benign_insts, attack_insts=args.attack_insts)
    elif args.t87_quick:
        run_t87_quick()
    elif args.t87_full:
        run_t87_full(benign_insts=args.benign_insts, attack_insts=args.attack_insts, resume=args.resume)
    elif args.t91_pilot:
        run_t91_pilot(workers=args.workers)
    elif args.t91_full:
        run_t91_full(workers=args.workers, para_seeds=args.para_seeds, resume=args.resume)
    else:
        run_full(benign_insts=args.benign_insts, attack_insts=args.attack_insts, resume=args.resume)


if __name__ == "__main__":
    main()
