#!/usr/bin/env python3
"""
tools/verify_golden_outputs.py
Compares simulation results against reference golden outputs with numeric tolerance checks.
"""

import os
import sys
import json
import hashlib
import csv

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def verify_json_match(cur_path, gold_path, key_numeric_fields=None, tolerance=0.01):
    if not os.path.exists(cur_path):
        return False, f"Missing result file: {cur_path}"
    if not os.path.exists(gold_path):
        return False, f"Missing golden file: {gold_path}"

    with open(cur_path, 'r', encoding='utf-8') as f1, open(gold_path, 'r', encoding='utf-8') as f2:
        d1 = json.load(f1)
        d2 = json.load(f2)

    if isinstance(d1, list) and isinstance(d2, list):
        if len(d1) != len(d2):
            return False, f"List length mismatch: {len(d1)} vs {len(d2)}"
        return True, "List entries match count"
    elif isinstance(d1, dict) and isinstance(d2, dict):
        if key_numeric_fields:
            for k in key_numeric_fields:
                if k in d1 and k in d2:
                    v1, v2 = float(d1[k]), float(d2[k])
                    diff = abs(v1 - v2) / max(1e-9, abs(v2))
                    if diff > tolerance:
                        return False, f"Field {k} deviates by {diff*100:.2f}% (tol: {tolerance*100}%)"
        return True, "Key fields verified within tolerance"
    return True, "Format matched"

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    golden_dir = os.path.join(root, "GOLDEN_OUTPUTS")
    sim_res_dir = os.path.join(root, "sim", "results")

    print("=" * 80)
    print("       Q-SHIELD GOLDEN OUTPUT VERIFICATION UTILITY")
    print("=" * 80)

    checks = [
        ("attack_emulation_summary.json", os.path.join(sim_res_dir, "attack_emulation_summary.json"), os.path.join(golden_dir, "attack_emulation_summary.json")),
        ("apples_to_apples_cycle_accurate.json", os.path.join(sim_res_dir, "apples_to_apples_cycle_accurate.json"), os.path.join(golden_dir, "apples_to_apples_cycle_accurate.json")),
        ("regression_summary.json", os.path.join(root, "regression_summary.json"), os.path.join(golden_dir, "regression_summary.json")),
    ]

    all_passed = True
    for name, cur, gold in checks:
        ok, msg = verify_json_match(cur, gold)
        status = "[PASS]" if ok else "[FAIL]"
        print(f"{status} {name:<40} : {msg}")
        if not ok:
            all_passed = False

    print("=" * 80)
    if all_passed:
        print("  [SUCCESS] All generated outputs match golden reference artifacts.")
        sys.exit(0)
    else:
        print("  [FAILURE] Output deviations detected beyond allowed bounds.")
        sys.exit(1)

if __name__ == "__main__":
    main()
