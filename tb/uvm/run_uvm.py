#!/usr/bin/env python3
"""run_uvm.py: Chạy kiểm chứng pyuvm trên Icarus Verilog cho Q-Shield (mc_env / csr_env)."""

import argparse
import datetime
import json
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

if os.name == "nt":
    os.environ["PATH"] = r"D:\iverilog\bin;" + os.environ.get("PATH", "")

from cocotb_tools.runner import get_runner
from tb.uvm.common.gate import validate_uvm_report
from tb.uvm.common.report_json import git_head_commit

MC_SOURCES = [
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
    "rtl/core/pxor_hash_engine.sv",  # sẽ loại trùng ở bước nạp bên dưới
    "rtl/core/sdc_resilient_filter.sv",
    "rtl/core/adaptive_threshold_engine.sv",
    "rtl/backend/directed_refresh_manager.sv",
    "rtl/core/qos_scheduler_queue.sv",
    "rtl/backend/slack_aware_arbiter.sv",
    "rtl/backend/ddr5_cmd_engine.sv",
    "rtl/backend/ecc_scrubber.sv",
    "rtl/memory/bus_scrambler.sv",
    "rtl/memory/scrambler_ks_pipe.sv",
    "rtl/top/bank_credit_ctrl.sv",
    "rtl/bus/perf_monitor_unit.sv",
    "rtl/top/axi_ddr5_mc_top.sv",
    "tb/common/dfi_jedec_checker.sv",
    "tb/common/dfi_jedec_checker_cyc.sv",
    "tb/common/dram_model.sv",
    "tb/uvm/hdl/mc_uvm_top.sv",
]

CSR_SOURCES = [
    "rtl/core/fault_hardened_csr.sv",
    "rtl/bus/apb_csr_regs.sv",
    "tb/uvm/hdl/csr_uvm_top.sv",
]

ENV_CONFIGS = {
    "mc": {
        "sources": list(dict.fromkeys(MC_SOURCES)),
        "includes": ["tb/common", "rtl/include"],
        "toplevel": "mc_uvm_top",
        "test_module": "tb.uvm.tests.mc_uvm_tests",
    },
    "csr": {
        "sources": CSR_SOURCES,
        "includes": ["rtl/include"],
        "toplevel": "csr_uvm_top",
        "test_module": "tb.uvm.tests.csr_uvm_tests",
    },
}


def _check_results_xml(xml_path: Path) -> bool:
    if not xml_path.exists():
        return False
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for tc in root.iter("testcase"):
            if tc.find("failure") is not None or tc.find("error") is not None:
                return False
        return len(list(root.iter("testcase"))) > 0
    except Exception:
        return False


def _run_env(env_name: str, base_seed: int, num_seeds: int) -> tuple[list[dict], dict]:
    cfg = ENV_CONFIGS[env_name]
    build_dir = ROOT / "build" / f"uvm_{env_name}"
    build_dir.mkdir(parents=True, exist_ok=True)

    runner = get_runner("icarus")
    runner.build(
        sources=[ROOT / s for s in cfg["sources"]],
        includes=[ROOT / p for p in cfg["includes"]],
        hdl_toplevel=cfg["toplevel"],
        build_dir=build_dir,
        always=False,
        build_args=["-g2012"],
    )

    seed_results: list[dict] = []
    merged_bins: dict[str, int] = {}

    for i in range(num_seeds):
        seed = base_seed + i
        seed_json = build_dir / f"seed_{seed}.json"
        if seed_json.exists():
            seed_json.unlink()
        results_xml = build_dir / "results.xml"
        if results_xml.exists():
            results_xml.unlink()

        sim_exc: str | None = None
        try:
            runner.test(
                hdl_toplevel=cfg["toplevel"],
                test_module=cfg["test_module"],
                build_dir=build_dir,
                test_dir=build_dir,
                results_xml=results_xml,
                extra_env={
                    "PYTHONPATH": str(ROOT),
                    "UVM_SEED": str(seed),
                    "UVM_SEED_JSON": str(seed_json),
                    "COCOTB_RANDOM_SEED": str(seed),
                },
            )
        except Exception as exc:
            sim_exc = str(exc)

        xml_ok = _check_results_xml(results_xml)
        if seed_json.exists():
            sdata = json.loads(seed_json.read_text(encoding="utf-8"))
        else:
            sdata = {
                "env": env_name,
                "seed": seed,
                "passed": False,
                "checks": {},
                "coverage": {"total_bins": 0, "hit_bins": 0, "pct": 0.0, "bins": {}},
                "extra": {"errors": [sim_exc or "Missing seed JSON output"]},
            }

        passed = bool(sdata.get("passed", False)) and xml_ok and (sim_exc is None)
        sdata["passed"] = passed
        if sim_exc:
            sdata.setdefault("extra", {}).setdefault("errors", []).append(sim_exc)
        seed_results.append(sdata)

        for k, v in sdata.get("coverage", {}).get("bins", {}).items():
            merged_bins[k] = merged_bins.get(k, 0) + int(v)

        tag = "PASS" if passed else "FAIL"
        cov_pct = sdata.get("coverage", {}).get("pct", 0.0)
        if passed:
            print(f"[UVM_{tag}] env={env_name} seed={seed} cov={cov_pct}%")
        else:
            errs = sdata.get("extra", {}).get("errors", [])
            print(f"[UVM_FAIL] env={env_name} seed={seed} cov={cov_pct}% errors={errs}", flush=True)

    return seed_results, merged_bins


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--env", choices=["mc", "csr", "all"], default="mc")
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--seed", type=int, default=1001)
    ap.add_argument("--out", type=Path, default=ROOT / "build" / "uvm" / "uvm_report.json")
    ap.add_argument("--min-cov", type=float, default=80.0)
    args = ap.parse_args()

    envs = ["mc", "csr"] if args.env == "all" else [args.env]
    all_results: list[dict] = []
    merged_bins: dict[str, int] = {}

    for env_name in envs:
        res_list, bins = _run_env(env_name, args.seed, args.seeds)
        all_results.extend(res_list)
        for k, v in bins.items():
            merged_bins[f"{env_name}.{k}" if len(envs) > 1 else k] = v

    total_bins = len(merged_bins)
    hit_bins = sum(1 for v in merged_bins.values() if v > 0)
    cov_pct = round((100.0 * hit_bins / total_bins), 2) if total_bins else 0.0

    failing_seeds = [f"{r['env']}:{r['seed']}" for r in all_results if not r["passed"]]
    overall_pass = len(failing_seeds) == 0

    report = {
        "env": args.env,
        "commit": git_head_commit(ROOT),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "seeds": args.seeds,
        "base_seed": args.seed,
        "status": "PASS" if overall_pass else "FAIL",
        "failing_seeds": failing_seeds,
        "coverage": {
            "total_bins": total_bins,
            "hit_bins": hit_bins,
            "pct": cov_pct,
            "bins": dict(sorted(merged_bins.items())),
        },
        "seed_results": all_results,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"[COV] AGGREGATE env={args.env} hit={hit_bins}/{total_bins} ({cov_pct}%) report={args.out}")
    for k, v in sorted(merged_bins.items()):
        print(f"[COV] bin={k} hits={v}")

    ok_gate, gate_errs = validate_uvm_report(args.out, min_cov_pct=args.min_cov)
    if not ok_gate:
        for ge in gate_errs:
            print(f"[UVM_FAIL] {ge}", flush=True)
        return 1

    print(f"[UVM_SUMMARY] env={args.env} seeds={args.seeds} status=PASS commit={report['commit'][:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
