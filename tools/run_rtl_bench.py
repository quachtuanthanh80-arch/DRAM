#!/usr/bin/env python3
"""run_rtl_bench.py: replay the synthetic traces in sim/traces/rtl_bench through the real RTL (axi_ddr5_mc_top + dram_model).

Compiles tb_bench_trace once with Icarus, runs every trace under every configuration in parallel, parses the
[BENCH] line of each run and writes sim/results/rtl_bench/rtl_bench.{csv,json}. Every number comes from an RTL
simulation; nothing is estimated or calibrated.
"""
import argparse
import csv
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RTL_SOURCES = [
    "rtl/backend/secded_72_64_pkg.sv", "rtl/cdc/rst_sync.sv", "rtl/bus/axi4_skid_buffer.sv",
    "rtl/frontend/axi_slave_frontend.sv", "rtl/frontend/wdata_buffer.sv", "rtl/frontend/wr_data_store.sv",
    "rtl/frontend/axi_burst_splitter.sv", "rtl/frontend/rd_issue_queue.sv",
    "rtl/frontend/domain_bank_coloring.sv", "rtl/core/scarf_dram_randomizer.sv", "rtl/frontend/addr_mapper_ddr5.sv",
    "rtl/core/reorder_buffer_rob.sv", "rtl/core/fault_hardened_csr.sv", "rtl/crypto/multi_vm_key_table.sv",
    "rtl/core/pxor_hash_engine.sv", "rtl/core/sdc_resilient_filter.sv", "rtl/core/adaptive_threshold_engine.sv",
    "rtl/backend/directed_refresh_manager.sv", "rtl/core/qos_scheduler_queue.sv", "rtl/backend/slack_aware_arbiter.sv",
    "rtl/backend/ddr5_cmd_engine.sv", "rtl/backend/ecc_scrubber.sv", "rtl/memory/bus_scrambler.sv",
    "rtl/memory/scrambler_ks_pipe.sv", "rtl/top/bank_credit_ctrl.sv",
    "rtl/bus/perf_monitor_unit.sv", "rtl/top/axi_ddr5_mc_top.sv", "tb/common/dfi_jedec_checker.sv",
    "tb/common/dram_model.sv", "tb/top/tb_bench_trace.sv",
]
# Configurations: the RowHammer threshold 65535 effectively disables the SDC filter; other always-on defenses
# (RowPress clamp, McSee RFM, periodic REF) stay active in every configuration because they are not switchable,
# so "base" is not an undefended controller. The secure threshold (64 ACTs) is scaled to the 4000-op traces:
# with a realistic ~1000-ACT threshold the filter never fires in a trace this short.
CONFIGS = {
    "base":         dict(thresh=65535, scramble=0, scarf=0, decoy=0),
    "secure":       dict(thresh=64,    scramble=1, scarf=1, decoy=0),
    "secure_decoy": dict(thresh=64,    scramble=1, scarf=1, decoy=1),
}


def tool(name):
    for d in [r"D:\iverilog\bin", ""]:
        p = os.path.join(d, name + (".exe" if os.name == "nt" else "")) if d else name
        if not d or os.path.exists(p):
            return p
    return name


def parse(line):
    out = {}
    for tok in line.split()[1:]:
        k, _, v = tok.partition("=")
        try:
            out[k] = int(v)
        except ValueError:
            try:
                out[k] = float(v)
            except ValueError:
                out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--traces", default=os.path.join(ROOT, "sim", "traces", "rtl_bench"))
    ap.add_argument("--out", default=os.path.join(ROOT, "sim", "results", "rtl_bench"))
    ap.add_argument("--build", default=os.path.join(ROOT, ".harness", "qshield_review", "build", "rtl_bench"))
    ap.add_argument("--maxops", type=int, default=0, help="limit ops per trace (0 = whole trace)")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--configs", default=",".join(CONFIGS))
    ap.add_argument("--only", default="", help="comma-separated workload names")
    args = ap.parse_args()

    os.makedirs(args.build, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    vvp_file = os.path.join(args.build, "tb_bench_trace.vvp")
    cmd = [tool("iverilog"), "-g2012", "-I", os.path.join(ROOT, "tb", "common"), "-s", "tb_bench_trace", "-o", vvp_file]
    cmd += [os.path.join(ROOT, s) for s in RTL_SOURCES]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("compile failed:\n" + r.stdout + r.stderr)

    traces = sorted(f[:-6] for f in os.listdir(args.traces) if f.endswith(".trace"))
    if args.only:
        traces = [t for t in traces if t in args.only.split(",")]
    jobs = [(t, c) for t in traces for c in args.configs.split(",")]

    def run(job):
        wl, cfg = job
        plus = [f"+trace={os.path.join(args.traces, wl + '.trace')}", f"+wl={wl}", f"+cfg={cfg}"]
        plus += [f"+{k}={v}" for k, v in CONFIGS[cfg].items()]
        if args.maxops:
            plus.append(f"+maxops={args.maxops}")
        p = subprocess.run([tool("vvp"), "-n", vvp_file] + plus, capture_output=True, text=True, cwd=args.build)
        lines = [l for l in p.stdout.splitlines() if l.startswith("[BENCH]")]
        if not lines:
            return dict(wl=wl, cfg=cfg, error=(p.stdout + p.stderr)[-400:])
        row = parse(lines[-1])
        row.update({k: v for k, v in CONFIGS[cfg].items()})
        print(f"{wl:14s} {cfg:13s} bw={row['bw_gbps']:.3f} GB/s p50={row['rd_lat_p50_ns']:.0f} ns "
              f"row_hit={row['row_hit']:.3f} victim_act={row['act_victim']} complete={row['complete']}", flush=True)
        return row

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        rows = list(ex.map(run, jobs))

    errs = [r for r in rows if "error" in r]
    for e in errs:
        print("ERROR", e["wl"], e["cfg"], e["error"])
    rows = [r for r in rows if "error" not in r]
    with open(os.path.join(args.out, "rtl_bench.json"), "w") as f:
        json.dump(dict(source="RTL simulation (Icarus) of axi_ddr5_mc_top + behavioral dram_model",
                       clock_mhz=250, configs=CONFIGS, rows=rows), f, indent=2)
    if rows:
        keys = list(rows[0].keys())
        with open(os.path.join(args.out, "rtl_bench.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            w.writerows(rows)
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
