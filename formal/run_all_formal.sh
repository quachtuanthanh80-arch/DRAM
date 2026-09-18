#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "  Q-SHIELD MASTER HARDWARE FORMAL VERIFICATION SUITE (SYMBIYOSYS + Z3)"
echo "================================================================================"

PASSED=0
TOTAL=0

for sby_file in formal_*.sby; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "[*] Executing Formal Proof: $sby_file..."
    if sby -f "$sby_file"; then
        echo "[PASS] $sby_file verified with 0 violations."
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $sby_file failed proof!"
        exit 1
    fi
done

echo ""
echo "================================================================================"
echo "  FORMAL VERIFICATION SUMMARY: $PASSED/$TOTAL Proofs PASSED (100% Convergence)"
echo "================================================================================"
