#!/usr/bin/env python3
"""
tools/verify_golden_outputs.py
Compares simulation results against reference golden outputs with numeric tolerance checks.
"""

import os
import sys
import json
import hashlib
import argparse

REGRESSION_KEY_FIELDS = [
    "total_tests",
    "clean_passed",
    "xfail_passed",
    "failed",
    "total_xfails",
    "commit_sha",
]

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

    try:
        with open(cur_path, 'r', encoding='utf-8') as f1, open(gold_path, 'r', encoding='utf-8') as f2:
            d1 = json.load(f1)
            d2 = json.load(f2)
    except Exception as e:
        return False, f"JSON parse error: {e}"

    if not key_numeric_fields:
        return False, "No key fields specified for verification (dummy JSON check rejected)"

    if isinstance(d1, dict) and isinstance(d2, dict):
        for k in key_numeric_fields:
            if k not in d1:
                return False, f"Field '{k}' missing in current results ({cur_path})"
            if k not in d2:
                return False, f"Field '{k}' missing in golden reference ({gold_path})"

            val1 = d1[k]
            val2 = d2[k]

            if isinstance(val1, str) or isinstance(val2, str):
                if str(val1).strip() != str(val2).strip():
                    return False, f"Field '{k}' mismatch: current='{val1}' vs golden='{val2}'"
            else:
                try:
                    v1, v2 = float(val1), float(val2)
                except (ValueError, TypeError):
                    return False, f"Field '{k}' cannot be parsed as numeric: {val1} vs {val2}"

                if v2 == 0:
                    diff = abs(v1 - v2)
                    if diff > tolerance:
                        return False, f"Field '{k}' deviates: current={val1} vs golden={val2} (abs diff {diff} > tol {tolerance})"
                else:
                    diff = abs(v1 - v2) / abs(v2)
                    if diff > tolerance:
                        return False, f"Field '{k}' deviates by {diff*100:.2f}% (tol: {tolerance*100}%): current={val1} vs golden={val2}"

        return True, "Key fields verified within tolerance"

    return False, f"Unsupported data structure: {type(d1)} vs {type(d2)}"

def verify_attack_emulation(cur_path, gold_path, tolerance=0.01):
    if not os.path.exists(cur_path):
        return False, f"Missing result file: {cur_path}"
    if not os.path.exists(gold_path):
        return False, f"Missing golden file: {gold_path}"
    try:
        with open(cur_path, 'r', encoding='utf-8') as f1, open(gold_path, 'r', encoding='utf-8') as f2:
            d1 = json.load(f1)
            d2 = json.load(f2)
    except Exception as e:
        return False, f"JSON load error: {e}"

    if "attacks" not in d1 or "attacks" not in d2:
        return False, "Missing 'attacks' list in emulation summary"
    if len(d1["attacks"]) != len(d2["attacks"]):
        return False, f"Attacks count mismatch: {len(d1['attacks'])} vs {len(d2['attacks'])}"

    for i, (a1, a2) in enumerate(zip(d1["attacks"], d2["attacks"])):
        for k in ["total_accesses", "mitigations_issued", "escaped_bitflips"]:
            if a1.get(k) != a2.get(k):
                return False, f"Attack {a1.get('attack_tag', i)} field '{k}' mismatch: {a1.get(k)} vs {a2.get(k)}"

    if "fuzzer" in d1 and "fuzzer" in d2:
        for k in ["total_accesses", "mitigations", "escaped_bitflips"]:
            if d1["fuzzer"].get(k) != d2["fuzzer"].get(k):
                return False, f"Fuzzer field '{k}' mismatch: {d1['fuzzer'].get(k)} vs {d2['fuzzer'].get(k)}"

    return True, f"All {len(d1['attacks'])} attack vectors and fuzzer metrics match golden"

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    golden_dir = os.path.join(root, "GOLDEN_OUTPUTS")
    sim_res_dir = os.path.join(root, "sim", "results")

    parser = argparse.ArgumentParser(description="Q-Shield Golden Output Verification Utility")
    parser.add_argument("--golden-dir", default=golden_dir, help="Directory containing golden reference artifacts")
    parser.add_argument("--cur-regression", default=os.path.join(root, "regression_summary.json"), help="Path to current regression summary")
    parser.add_argument("--cur-attack", default=os.path.join(sim_res_dir, "attack_emulation_summary.json"), help="Path to current attack emulation summary")
    parser.add_argument("--tolerance", type=float, default=0.01, help="Allowed numeric deviation tolerance (default 0.01 = 1%)")
    args = parser.parse_args()

    print("=" * 80)
    print("       Q-SHIELD GOLDEN OUTPUT VERIFICATION UTILITY")
    print("=" * 80)

    checks = [
        ("attack_emulation_summary.json", lambda: verify_attack_emulation(
            args.cur_attack, os.path.join(args.golden_dir, "attack_emulation_summary.json"), tolerance=args.tolerance
        )),
        ("regression_summary.json", lambda: verify_json_match(
            args.cur_regression, os.path.join(args.golden_dir, "regression_summary.json"),
            key_numeric_fields=REGRESSION_KEY_FIELDS, tolerance=args.tolerance
        )),
    ]

    all_passed = True
    for name, check_fn in checks:
        ok, msg = check_fn()
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
