#!/usr/bin/env python3
"""
sim/generate_sota_comparison.py
Exports qualitative DDR5 RowHammer architecture taxonomy (Tier 3) and clears
unverified hard-coded Tier 1/Tier 2 tables (see reports/paper/perf/ for measured data).
"""

import os
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

# -----------------------------------------------------------------------------
# 1. QUALITATIVE ARCHITECTURAL TAXONOMY (PDF-verified authors/venues/mechanisms)
# -----------------------------------------------------------------------------
QUALITATIVE_TAXONOMY = [
    {
        "scheme": "Baseline (FR-FCFS)",
        "source_paper": "JEDEC JESD79-5",
        "deployment_scope": "Memory Controller",
        "dram_die_mod": "None",
        "rate_limiting_type": "None (Unmitigated)",
        "ecc_sdc_protection": "None",
        "comparison_method": "Qualitative Taxonomy",
        "directly_comparable": True,
        "fairness_note": "Unprotected commercial DDR5 baseline (dram_support=none).",
    },
    {
        "scheme": "BlockHammer",
        "source_paper": "HPCA'21 (Yaglikci et al.)",
        "deployment_scope": "Memory Controller",
        "dram_die_mod": "None",
        "rate_limiting_type": "Counting Bloom Filter + Proactive Throttling",
        "ecc_sdc_protection": "None",
        "comparison_method": "Ramulator2 & Taxonomy",
        "directly_comparable": True,
        "fairness_note": "Evaluated in reports/paper/perf/ under dram_support=none.",
    },
    {
        "scheme": "Graphene",
        "source_paper": "MICRO'20 (Park et al.)",
        "deployment_scope": "Memory Controller (requires victim refresh)",
        "dram_die_mod": "Non-JEDEC VRR or ACT+PREpb",
        "rate_limiting_type": "Misra-Gries Frequent-Item Counter Table",
        "ecc_sdc_protection": "None",
        "comparison_method": "Ramulator2 & Taxonomy",
        "directly_comparable": False,
        "fairness_note": "Original paper evaluated on McSimA+; commercial-DRAM Graphene_ACT variant evaluated in reports/paper/perf/.",
    },
    {
        "scheme": "AQUA",
        "source_paper": "MICRO'22 (Saxena et al.)",
        "deployment_scope": "Memory Controller + DRAM Quarantine Area",
        "dram_die_mod": "None (reserves DRAM quarantine region)",
        "rate_limiting_type": "Aggressor Row Quarantine Migration",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Original paper evaluated in gem5; not directly compared in-tree.",
    },
    {
        "scheme": "Hydra",
        "source_paper": "ISCA'22 (Qureshi et al.)",
        "deployment_scope": "Memory Controller + In-Memory Counter Table",
        "dram_die_mod": "Non-JEDEC VRR or ACT+PREpb",
        "rate_limiting_type": "Group + Per-Row Counter Tracking",
        "ecc_sdc_protection": "None",
        "comparison_method": "Ramulator2 & Taxonomy",
        "directly_comparable": False,
        "fairness_note": "Commercial-DRAM Hydra_ACT variant evaluated separately from VRR Hydra in reports/paper/perf/.",
    },
    {
        "scheme": "CoMeT",
        "source_paper": "HPCA'24 (Bostanci et al.)",
        "deployment_scope": "Memory Controller (requires victim refresh)",
        "dram_die_mod": "Preventive Refresh Interface",
        "rate_limiting_type": "Count-Min Sketch + Recent Aggressor Table",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Count-Min sketch row tracker; reference model in tb/core/test_sdc_filter.py.",
    },
    {
        "scheme": "Rubix",
        "source_paper": "ASPLOS'24 (Saxena et al.)",
        "deployment_scope": "Memory Controller",
        "dram_die_mod": "None",
        "rate_limiting_type": "Randomized Line-to-Row Mapping (front-end)",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Original paper evaluated in gem5 as a front-end paired with AQUA/SRS/BlockHammer.",
    },
    {
        "scheme": "PRAC",
        "source_paper": "JEDEC DDR5 / HPCA'25 (Canpolat et al.)",
        "deployment_scope": "In-DRAM Die + Controller (ABO/RFM)",
        "dram_die_mod": "In-DRAM per-row counters + ABO",
        "rate_limiting_type": "Alert Back-Off (ABO) + RFM",
        "ecc_sdc_protection": "None",
        "comparison_method": "Ramulator2 & Taxonomy",
        "directly_comparable": False,
        "fairness_note": "Requires in-DRAM per-row counters (dram_support=in_dram); tabulated separately in reports/paper/perf/.",
    },
    {
        "scheme": "DREAM",
        "source_paper": "ISCA'25 (Taneja & Qureshi)",
        "deployment_scope": "Memory Controller (with JEDEC DRFM)",
        "dram_die_mod": "JEDEC DRFM command",
        "rate_limiting_type": "DRFM-Aware Ganged Tracking & Delayed DRFM",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Requires JEDEC DRFM command support; not simulated in-tree.",
    },
    {
        "scheme": "QPRAC",
        "source_paper": "HPCA'25 (Woo et al.)",
        "deployment_scope": "In-DRAM Die + Controller (PRAC/ABO)",
        "dram_die_mod": "In-DRAM PRAC counters + Priority Service Queue",
        "rate_limiting_type": "Priority Service Queue + Proactive RFM/REF",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Requires PRAC-capable DRAM die; not simulated in-tree.",
    },
    {
        "scheme": "PrISM",
        "source_paper": "ISCA'26 (Woo et al.)",
        "deployment_scope": "In-DRAM Die + Controller (ABO/RFM)",
        "dram_die_mod": "In-DRAM Sampled History Queue SRAM (no per-row counters)",
        "rate_limiting_type": "Intersection-Based Probabilistic Sampling + ABO",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Requires in-DRAM SHQ and ABO support; not simulated in-tree.",
    },
    {
        "scheme": "RowPress (Mitigation Methodology)",
        "source_paper": "ISCA'23 (Luo et al.)",
        "deployment_scope": "Memory Controller",
        "dram_die_mod": "None",
        "rate_limiting_type": "Bounded Maximum Row-Open Time + Adapted RH Tracker",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "Read-disturbance amplification characterization and tAggON limiting.",
    },
    {
        "scheme": "MORDOR",
        "source_paper": "arXiv'26 (Makeenkova et al.)",
        "deployment_scope": "Memory Controller",
        "dram_die_mod": "None",
        "rate_limiting_type": "Elastic Preventive Refresh Scheduling (PROQ)",
        "ecc_sdc_protection": "None",
        "comparison_method": "Literature Context",
        "directly_comparable": False,
        "fairness_note": "PRO scheduling policy operating alongside an underlying RH tracker; not simulated in-tree.",
    },
    {
        "scheme": "Q-Shield (Ours)",
        "source_paper": "This Work",
        "deployment_scope": "Pure Memory Controller (DDR5)",
        "dram_die_mod": "None (commercial DDR5)",
        "rate_limiting_type": "Dual-Hash SDC Filter + Smooth Rate Pacing + ACT+PREpb",
        "ecc_sdc_protection": "SEC-DED (72, 64) + Optional AES-256-XTS/MAC/BMT Bridge",
        "comparison_method": "RTL + Ramulator2",
        "directly_comparable": True,
        "fairness_note": "Evaluated in reports/paper/perf/ (dram_support=none) and reports/paper/security/.",
    },
]

# -----------------------------------------------------------------------------
# 2. TIER 1 & TIER 2 HARD-CODED TABLES WITHDRAWN
# -----------------------------------------------------------------------------
# APPLES_TO_APPLES_DATA (legacy hard-coded throughput rows)
# and LITERATURE_REPORTED_DATA (unverified GE/overhead/die-area numbers not matching
# source PDFs) were withdrawn. Measured DDR5 results live in reports/paper/perf/.
APPLES_TO_APPLES_DATA = []
LITERATURE_REPORTED_DATA = []


def export_json(data, filename):
    filepath = os.path.join(RESULTS_DIR, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"[+] Saved JSON : {filepath}")


def export_literature_tex(filepath):
    with open(filepath, "w", encoding="utf-8") as f:
        f.write("% Withdrawn legacy Tier 2 table: unverified GE/overhead rows were removed.\n")
        f.write("% See reports/paper/perf/ for measured DDR5 Ramulator2 results.\n")
    print(f"[+] Saved TeX  : {filepath}")


def export_taxonomy_tex(filepath):
    with open(filepath, "w", encoding="utf-8") as f:
        f.write("% Auto-generated Qualitative Taxonomy Table (PDF-verified mechanisms)\n")
        f.write("\\begin{table*}[t]\n")
        f.write("\\centering\n")
        f.write("\\caption{Qualitative Architectural Taxonomy of Memory Protection Mechanisms}\n")
        f.write("\\label{tab:qualitative_taxonomy}\n")
        f.write("\\begin{tabular}{llll}\n")
        f.write("\\hline\n")
        f.write("Scheme & Reference & Deployment Scope & Mitigation Strategy \\\\\n")
        f.write("\\hline\n")
        for r in QUALITATIVE_TAXONOMY:
            sch = f"\\textbf{{{r['scheme']}}}" if "Q-Shield" in r["scheme"] else r["scheme"]
            src = r["source_paper"].replace("&", "\\&")
            rl = r["rate_limiting_type"].replace("&", "\\&")
            f.write(f"{sch} & {src} & {r['deployment_scope']} & {rl} \\\\\n")
        f.write("\\hline\n")
        f.write("\\end{tabular}\n")
        f.write("\\end{table*}\n")
    print(f"[+] Saved TeX  : {filepath}")


def main():
    print("=" * 96)
    print("  GENERATING QUALITATIVE TAXONOMY (DDR5-ONLY; HARD-CODED TIER 1/2 WITHDRAWN)")
    print("=" * 96)

    export_json(LITERATURE_REPORTED_DATA, "literature_reported_values.json")
    export_literature_tex(os.path.join(RESULTS_DIR, "literature_reported_values.tex"))

    export_json(QUALITATIVE_TAXONOMY, "qualitative_taxonomy.json")
    export_taxonomy_tex(os.path.join(RESULTS_DIR, "qualitative_taxonomy.tex"))

    print("=" * 96)
    print("  [SUCCESS] Qualitative taxonomy exported; measured DDR5 results live in reports/paper/perf/.")
    print("=" * 96)


if __name__ == "__main__":
    main()
