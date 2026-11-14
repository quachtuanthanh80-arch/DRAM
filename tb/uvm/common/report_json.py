# Thu thập coverage chức năng và xuất báo cáo JSON có commit/seed/coverage cho T60 & T62
import datetime
import json
import subprocess
from pathlib import Path


class CoverageTracker:
    """Bộ đếm coverage các góc biên (corner cases) phát hành log [COV] và xuất JSON."""

    def __init__(self, required_bins: list[str] | None = None):
        self.bins: dict[str, int] = {}
        if required_bins:
            for k in required_bins:
                self.bins[k] = 0

    def hit(self, bin_name: str, count: int = 1) -> None:
        self.bins[bin_name] = self.bins.get(bin_name, 0) + count

    def summary(self) -> dict:
        total = len(self.bins)
        hit = sum(1 for v in self.bins.values() if v > 0)
        pct = round((100.0 * hit / total), 2) if total else 0.0
        return {
            "total_bins": total,
            "hit_bins": hit,
            "pct": pct,
            "bins": dict(sorted(self.bins.items())),
        }

    def format_lines(self) -> list[str]:
        s = self.summary()
        lines = [f"[COV] SUMMARY hit={s['hit_bins']}/{s['total_bins']} ({s['pct']}%)"]
        for k, v in s["bins"].items():
            lines.append(f"[COV] bin={k} hits={v}")
        return lines


def git_head_commit(root: Path) -> str:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=5,
        )
        if res.returncode == 0:
            return res.stdout.strip()
    except Exception:
        pass
    return "unknown"


def write_seed_report(
    out_path: Path,
    env: str,
    seed: int,
    passed: bool,
    coverage: CoverageTracker,
    checks: dict,
    root: Path,
    extra: dict | None = None,
) -> dict:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "env": env,
        "seed": seed,
        "passed": passed,
        "commit": git_head_commit(root),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "checks": checks,
        "coverage": coverage.summary(),
    }
    if extra:
        payload["extra"] = extra
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload
