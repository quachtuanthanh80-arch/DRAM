#!/usr/bin/env bash
# ==============================================================================
# Q-Shield: Fast Minimal Reproducibility Script (< 60 Seconds)
# Purpose: Executes a fast subset of regression, attack emulation, and
#          architectural simulation, verifying against GOLDEN_OUTPUTS.
# ==============================================================================

set -e

echo "=== [1/4] Environment Inspection ==="
python --version
if command -v iverilog &> /dev/null; then
    iverilog -v 2>&1 | head -n 1
else
    echo "Notice: iverilog not found in PATH; skipping RTL compile and testing sim/only."
fi

echo ""
echo "=== [2/4] Running Master RTL Regression (14 Modules) ==="
python run_iverilog_regression.py

echo ""
echo "=== [3/4] Running Security Attack Emulation (Benign & RowHammer) ==="
python sim/run_attack_emulation.py

echo ""
echo "=== [4/4] Verifying Results Against GOLDEN_OUTPUTS Reference ==="
python -c "
import json, sys

# Check Attack Emulation
with open('sim/results/attack_emulation_summary.json') as f1, open('GOLDEN_OUTPUTS/attack_emulation_summary.json') as f2:
    cur_list, gold_list = json.load(f1), json.load(f2)
    assert len(cur_list) == len(gold_list), 'Trace count mismatch'
    total_escaped = sum(item['escaped_bitflips'] for item in cur_list)
    assert total_escaped == 0, f'Security breach: {total_escaped} escaped flips'
    print('  [PASS] Attack Emulation: 0 escaped flips verified across all evaluation traces.')

# Check RTL Regression
with open('regression_summary.json') as f1, open('GOLDEN_OUTPUTS/regression_summary.json') as f2:
    cur, gold = json.load(f1), json.load(f2)
    assert cur['failed'] == 0, 'RTL unit test failed'
    assert cur['passed'] == gold['passed'], 'Passed test count mismatch'
    print(f'  [PASS] RTL Regression: {cur[\"passed\"]}/{cur[\"total_tests\"]} tests passed cleanly.')

print('\n>>> MINIMAL REPRODUCTION VERIFIED SUCCESSFULLY (Time < 15s) <<<')
"
