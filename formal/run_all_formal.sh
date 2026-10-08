#!/usr/bin/env bash
# ==============================================================================
# Script: run_all_formal.sh
# Description: Master Hardware Formal Verification Suite Runner for Q-Shield
#              Executes all SymbiYosys (.sby) specifications using Z3 SMT solver.
# Output Artifacts:
#   - logs/<spec>.log        : Detailed solver execution and proof traces
#   - reports/summary.json   : Machine-readable JSON summary of proof results
#
# Note: This script assumes .sby files are valid; if not, refer to logs.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOGS_DIR="$SCRIPT_DIR/logs"
REPORTS_DIR="$SCRIPT_DIR/reports"
mkdir -p "$LOGS_DIR" "$REPORTS_DIR"

echo "================================================================================"
echo "  Q-SHIELD MASTER HARDWARE FORMAL VERIFICATION SUITE (SYMBIYOSYS + Z3)"
echo "================================================================================"

# Check toolchain availability
if ! command -v sby &> /dev/null; then
    echo "[-] Error: 'sby' (SymbiYosys) not found in PATH."
    echo "    Please install SymbiYosys from YosysHQ: https://github.com/YosysHQ/sby"
    exit 1
fi

if ! command -v z3 &> /dev/null; then
    echo "[-] Warning: 'z3' SMT solver not found in PATH. SBY may fail if configured for Z3."
fi

SBY_VERSION=$(sby --version 2>&1 | head -n 1 || echo "Unknown SBY Version")
Z3_VERSION=$(z3 --version 2>&1 | head -n 1 || echo "Unknown Z3 Version")

echo "  SBY Engine : $SBY_VERSION"
echo "  SMT Solver : $Z3_VERSION"
echo "  Output Logs: $LOGS_DIR"
echo "================================================================================"

TOTAL=0
PASSED=0
FAILED=0
START_ALL=$(date +%s)

SUMMARY_JSON="$REPORTS_DIR/summary.json"
echo "{" > "$SUMMARY_JSON"
echo "  \"tool_versions\": { \"sby\": \"$SBY_VERSION\", \"z3\": \"$Z3_VERSION\" }," >> "$SUMMARY_JSON"
echo "  \"results\": [" >> "$SUMMARY_JSON"

FIRST_ENTRY=true

for sby_file in formal_*.sby; do
    if [ ! -f "$sby_file" ]; then
        continue
    fi
    TOTAL=$((TOTAL + 1))
    SPEC_NAME="${sby_file%.sby}"
    LOG_FILE="$LOGS_DIR/${SPEC_NAME}.log"

    # Extract mode and depth from .sby file
    MODE=$(grep -E '^\s*mode\s+' "$sby_file" | awk '{print $2}' || echo "bmc")
    DEPTH=$(grep -E '^\s*depth\s+' "$sby_file" | awk '{print $2}' || echo "20")

    printf "[%02d] Checking: %-26s (Mode: %-5s Depth: %-3s) ... " "$TOTAL" "$sby_file" "$MODE" "$DEPTH"

    T_START=$(date +%s)
    
    # Execute SBY with timeout of 300 seconds
    if timeout 300 sby -f "$sby_file" > "$LOG_FILE" 2>&1; then
        T_END=$(date +%s)
        DURATION=$((T_END - T_START))
        STATUS="PROVED"
        PASSED=$((PASSED + 1))
        echo "PROVED (${DURATION}s)"
    else
        EXIT_CODE=$?
        T_END=$(date +%s)
        DURATION=$((T_END - T_START))
        if [ $EXIT_CODE -eq 124 ]; then
            STATUS="TIMEOUT"
            echo "TIMEOUT (>300s)"
        else
            STATUS="FAILED"
            echo "FAILED (code $EXIT_CODE)"
        fi
        FAILED=$((FAILED + 1))
    fi

    # Append to JSON
    if [ "$FIRST_ENTRY" = true ]; then
        FIRST_ENTRY=false
    else
        echo "," >> "$SUMMARY_JSON"
    fi

    cat <<EOF >> "$SUMMARY_JSON"
    {
      "property": "$SPEC_NAME",
      "file": "$sby_file",
      "mode": "$MODE",
      "depth": "$DEPTH",
      "status": "$STATUS",
      "duration_seconds": $DURATION,
      "log_path": "$LOG_FILE"
    }
EOF
done

END_ALL=$(date +%s)
TOTAL_DURATION=$((END_ALL - START_ALL))

echo "  ]," >> "$SUMMARY_JSON"
echo "  \"total_properties\": $TOTAL," >> "$SUMMARY_JSON"
echo "  \"passed\": $PASSED," >> "$SUMMARY_JSON"
echo "  \"failed\": $FAILED," >> "$SUMMARY_JSON"
echo "  \"total_duration_seconds\": $TOTAL_DURATION" >> "$SUMMARY_JSON"
echo "}" >> "$SUMMARY_JSON"

echo ""
echo "================================================================================"
echo "  FORMAL VERIFICATION SUMMARY REPORT"
echo "================================================================================"
echo "  Total Properties Verified : $TOTAL"
echo "  Passed                    : $PASSED"
echo "  Failed                    : $FAILED"
echo "  Total Execution Time      : ${TOTAL_DURATION}s"
echo "  JSON Summary File         : $SUMMARY_JSON"
echo "================================================================================"

if [ $FAILED -gt 0 ]; then
    echo "[-] Verification finished with failures. Inspect logs in $LOGS_DIR."
    exit 1
else
    echo "[+] All formal properties verified with 0 counter-examples."
    exit 0
fi
