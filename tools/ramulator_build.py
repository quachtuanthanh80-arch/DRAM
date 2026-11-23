# File: tools/ramulator_build.py
# Chức năng: Xuất mã nguồn sạch Ramulator2 upstream (72427a1), áp dụng overlay Q-Shield và biên dịch offline trong build/ramulator2/.

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path


UPSTREAM_REPO = Path.home() / "ramulator2"
UPSTREAM_COMMIT = "72427a1"
REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "build" / "ramulator2"
BUILD_DIR = SRC_DIR / "build"
DEPS_STAGE_DIR = SRC_DIR / "_deps_src"
OVERLAY_DIR = REPO_ROOT / "sim" / "ramulator2_qshield"


def run_cmd(cmd, cwd=None, check=True, text=True):
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=text,
        check=check,
    )


def get_tool_version(tool):
    try:
        r = run_cmd([tool, "--version"], check=False)
        out = (r.stdout or r.stderr or "").strip().splitlines()
        return out[0] if out else f"rc={r.returncode}"
    except Exception as exc:
        return f"error: {exc}"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dir_has_files(path: Path) -> bool:
    if not path.is_dir():
        return False
    return any(path.iterdir())


def clear_src_dir_preserving_cache():
    SRC_DIR.mkdir(parents=True, exist_ok=True)
    keep = {"build", "_deps_src"}
    for entry in list(SRC_DIR.iterdir()):
        if entry.name in keep:
            continue
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def extract_upstream_archive(commit_sha: str):
    proc = subprocess.run(
        ["git", "-C", str(UPSTREAM_REPO), "archive", "--format=tar", commit_sha],
        capture_output=True,
        check=True,
    )
    clear_src_dir_preserving_cache()
    with tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r:") as tf:
        try:
            tf.extractall(SRC_DIR, filter="data")
        except TypeError:
            tf.extractall(SRC_DIR)


def stage_offline_deps():
    """Stage cached ext/* and _deps/*-src from ~/ramulator2 (read-only) without network access."""
    cmake_flags = ["-DFETCHCONTENT_FULLY_DISCONNECTED=ON"]
    staged_info = {"ext": [], "fetchcontent": {}}

    src_ext_upstream = UPSTREAM_REPO / "ext"
    if src_ext_upstream.is_dir():
        for sub in sorted(src_ext_upstream.iterdir()):
            if sub.is_dir() and dir_has_files(sub):
                dst = SRC_DIR / "ext" / sub.name
                if not dir_has_files(dst):
                    if dst.exists():
                        shutil.rmtree(dst)
                    shutil.copytree(sub, dst, symlinks=True)
                    staged_info["ext"].append(sub.name)

    fc_targets = []
    cmakelists = SRC_DIR / "CMakeLists.txt"
    if cmakelists.is_file():
        cm_text = cmakelists.read_text(encoding="utf-8", errors="replace")
        fc_targets = re.findall(r"FetchContent_Declare\s*\(\s*([A-Za-z0-9_\-]+)", cm_text)
    for ext_cm in sorted(SRC_DIR.glob("**/CMakeLists.txt")):
        if ext_cm == cmakelists:
            continue
        try:
            txt = ext_cm.read_text(encoding="utf-8", errors="replace")
            fc_targets.extend(re.findall(r"FetchContent_Declare\s*\(\s*([A-Za-z0-9_\-]+)", txt))
        except OSError:
            pass
    # Deduplicate preserving order
    seen_fc = []
    for t in fc_targets:
        if t not in seen_fc:
            seen_fc.append(t)

    deps_upstream = UPSTREAM_REPO / "build" / "_deps"
    if deps_upstream.is_dir():
        DEPS_STAGE_DIR.mkdir(parents=True, exist_ok=True)
        for sub in sorted(deps_upstream.iterdir()):
            if sub.is_dir() and sub.name.endswith("-src") and dir_has_files(sub):
                dst = DEPS_STAGE_DIR / sub.name
                if not dir_has_files(dst):
                    if dst.exists():
                        shutil.rmtree(dst)
                    shutil.copytree(sub, dst, symlinks=True)
                raw_name = sub.name[:-4]  # strip -src
                matched_fc = None
                for t in seen_fc:
                    if t.lower() == raw_name.lower() or re.sub(r"[^a-z0-9]", "", t.lower()) == re.sub(r"[^a-z0-9]", "", raw_name.lower()):
                        matched_fc = t
                        break
                fc_var_suffix = (matched_fc or raw_name).upper()
                cmake_flags.append(f"-DFETCHCONTENT_SOURCE_DIR_{fc_var_suffix}={dst}")
                staged_info["fetchcontent"][fc_var_suffix] = str(dst)

    return cmake_flags, staged_info, seen_fc


def apply_overlay():
    copied = []
    if not OVERLAY_DIR.is_dir():
        return copied
    for p in sorted(OVERLAY_DIR.rglob("*")):
        if not p.is_file():
            continue
        if p.suffix.lower() == ".md":
            continue
        rel = p.relative_to(OVERLAY_DIR)
        dst = SRC_DIR / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dst)
        copied.append(str(rel).replace("\\", "/"))
    return copied


def main():
    t0 = time.monotonic()
    if not UPSTREAM_REPO.is_dir():
        print(f"ERROR: Upstream repo not found at {UPSTREAM_REPO}", file=sys.stderr)
        sys.exit(1)

    res_sha = run_cmd(["git", "-C", str(UPSTREAM_REPO), "rev-parse", "--verify", f"{UPSTREAM_COMMIT}^{{commit}}"], check=False)
    if res_sha.returncode != 0:
        print(f"ERROR: Commit {UPSTREAM_COMMIT} not found in {UPSTREAM_REPO}:\n{res_sha.stderr}", file=sys.stderr)
        sys.exit(1)
    commit_sha = res_sha.stdout.strip()

    build_diag_dir = REPO_ROOT / "build"
    build_diag_dir.mkdir(parents=True, exist_ok=True)

    # Read-only diagnostics into build/
    st_r = run_cmd(["git", "-C", str(UPSTREAM_REPO), "status", "--short"], check=False)
    df_r = run_cmd(["git", "-C", str(UPSTREAM_REPO), "diff"], check=False)
    (build_diag_dir / "ramulator2_local_ref.diff").write_text(
        f"# git -C ~/ramulator2 status --short\n{st_r.stdout}\n# git -C ~/ramulator2 diff\n{df_r.stdout}",
        encoding="utf-8",
    )

    tree_r = run_cmd(["git", "-C", str(UPSTREAM_REPO), "ls-tree", "-r", "--name-only", commit_sha], check=True)
    (build_diag_dir / "ramulator2_tree.txt").write_text(tree_r.stdout, encoding="utf-8")

    gitmodules_path = UPSTREAM_REPO / ".gitmodules"
    gitmodules_text = gitmodules_path.read_text(encoding="utf-8", errors="replace") if gitmodules_path.is_file() else ""
    ext_dir = UPSTREAM_REPO / "ext"
    deps_dir = UPSTREAM_REPO / "build" / "_deps"

    print(f"[ramulator_build] Extracting {UPSTREAM_REPO}@{commit_sha} -> {SRC_DIR}")
    extract_upstream_archive(commit_sha)

    cmake_flags, staged_info, fc_targets = stage_offline_deps()
    copied_overlay = apply_overlay()
    print(f"[ramulator_build] Staged ext={staged_info['ext']}, fetchcontent={list(staged_info['fetchcontent'].keys())}, fc_targets={fc_targets}")
    print(f"[ramulator_build] Applied {len(copied_overlay)} overlay files: {copied_overlay}")

    env_info = {
        "upstream_repo": str(UPSTREAM_REPO),
        "upstream_commit_short": UPSTREAM_COMMIT,
        "upstream_commit_sha": commit_sha,
        "gpp_version": get_tool_version("g++"),
        "cmake_version": get_tool_version("cmake"),
        "cpu_count": os.cpu_count(),
        "gitmodules": gitmodules_text,
        "upstream_ext_entries": sorted([p.name for p in ext_dir.iterdir()]) if ext_dir.is_dir() else [],
        "upstream_deps_entries": sorted([p.name for p in deps_dir.iterdir()]) if deps_dir.is_dir() else [],
        "fc_targets_declared": fc_targets,
        "staged_info": staged_info,
        "overlay_files": copied_overlay,
    }
    (build_diag_dir / "ramulator2_env_info.json").write_text(json.dumps(env_info, indent=2), encoding="utf-8")

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    cfg_cmd = ["cmake", "-S", str(SRC_DIR), "-B", str(BUILD_DIR), "-DCMAKE_BUILD_TYPE=Release", *cmake_flags]
    print("[ramulator_build] Running:", " ".join(cfg_cmd))
    cfg_res = run_cmd(cfg_cmd, check=False)
    if cfg_res.returncode != 0:
        print("=== CMAKE CONFIGURE STDOUT ===\n" + cfg_res.stdout[-4000:], file=sys.stderr)
        print("=== CMAKE CONFIGURE STDERR ===\n" + cfg_res.stderr[-4000:], file=sys.stderr)
        sys.exit(cfg_res.returncode)
    print(cfg_res.stdout[-2000:])

    jobs = str(os.cpu_count() or 4)
    bld_cmd = ["cmake", "--build", str(BUILD_DIR), "-j", jobs]
    print("[ramulator_build] Running:", " ".join(bld_cmd))
    bld_res = run_cmd(bld_cmd, check=False)
    if bld_res.returncode != 0:
        print("=== CMAKE BUILD STDOUT ===\n" + bld_res.stdout[-4000:], file=sys.stderr)
        print("=== CMAKE BUILD STDERR ===\n" + bld_res.stderr[-4000:], file=sys.stderr)
        sys.exit(bld_res.returncode)
    print(bld_res.stdout[-2000:])

    lib_path = SRC_DIR / "libramulator.so"
    py_mods = sorted((SRC_DIR / "python" / "ramulator").glob("_ramulator*.so"))
    if not lib_path.is_file() or not any(p.name.startswith("_ramulator.") for p in py_mods):
        print(f"ERROR: expected libramulator.so ({lib_path.is_file()}) and _ramulator*.so ({py_mods})", file=sys.stderr)
        sys.exit(1)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(SRC_DIR / "python")
    imp_res = subprocess.run(
        [
            sys.executable,
            "-c",
            (
                "import ramulator; "
                "from ramulator.controller import QShield; "
                "from ramulator.controller_plugin import RowHammerObserver; "
                "print(ramulator.__file__, QShield.impl, RowHammerObserver.impl)"
            ),
        ],
        cwd=str(SRC_DIR),
        env=env,
        capture_output=True,
        text=True,
    )
    if imp_res.returncode != 0:
        print("=== IMPORT RAMULATOR STDERR ===\n" + imp_res.stderr, file=sys.stderr)
        sys.exit(imp_res.returncode)

    elapsed = round(time.monotonic() - t0, 3)
    lib_size = lib_path.stat().st_size
    lib_sha = sha256_file(lib_path)
    mod_info = {p.name: {"path": str(p), "size_bytes": p.stat().st_size, "sha256": sha256_file(p)} for p in py_mods}
    build_info = {
        "upstream_commit_sha": commit_sha,
        "libramulator_path": str(lib_path),
        "libramulator_size_bytes": lib_size,
        "libramulator_sha256": lib_sha,
        "python_path": str(SRC_DIR / "python"),
        "python_modules": mod_info,
        "import_check": imp_res.stdout.strip(),
        "elapsed_seconds": elapsed,
        "overlay_files": copied_overlay,
        "cmake_flags": cmake_flags,
    }
    (build_diag_dir / "ramulator2_build_info.json").write_text(json.dumps(build_info, indent=2), encoding="utf-8")
    print(f"[ramulator_build] SUCCESS: lib={lib_path} size={lib_size} sha256={lib_sha} modules={list(mod_info)} elapsed={elapsed}s")


if __name__ == "__main__":
    main()
