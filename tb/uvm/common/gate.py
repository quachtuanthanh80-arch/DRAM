# Kiểm tra gate báo cáo JSON cho UVM (đảm bảo có commit, coverage, seed và 0 FAIL)
import json
from pathlib import Path


def validate_uvm_report(report_path: Path, min_cov_pct: float = 80.0) -> tuple[bool, list[str]]:
    errors: list[str] = []
    if not report_path.exists():
        return False, [f"Missing UVM report file: {report_path}"]
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if not data.get("commit"):
        errors.append("Missing 'commit' field in UVM JSON report")
    cov = data.get("coverage", {})
    if not isinstance(cov, dict) or "pct" not in cov or "bins" not in cov:
        errors.append("Missing valid 'coverage' object in UVM JSON report")
    elif float(cov["pct"]) < min_cov_pct:
        errors.append(f"Coverage {cov['pct']}% < minimum {min_cov_pct}%")
    seed_results = data.get("seed_results", [])
    if not seed_results:
        errors.append("No seed_results recorded in UVM JSON report")
    for sr in seed_results:
        if not sr.get("passed", False):
            errors.append(f"Seed {sr.get('seed')} failed (env={sr.get('env', data.get('env'))})")
    if data.get("status") != "PASS":
        errors.append(f"Overall report status is {data.get('status')!r}, expected 'PASS'")
    return len(errors) == 0, errors
