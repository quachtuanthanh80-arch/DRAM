#!/usr/bin/env python3
"""
tools/check_documentation_consistency.py
Automated validation script verifying Markdown link integrity, absence of
local file:/// URLs, and cross-document structural consistency.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DOC_FILES = [
    "README.md",
    "DESIGN.md",
    "METHODOLOGY.md",
    "EVALUATION.md",
    "FORMAL.md",
    "LIMITATIONS.md",
    "REPRODUCIBILITY.md",
    "INSTALL.md",
    "VERSIONING.md",
    "CHANGELOG.md",
    "GOLDEN_OUTPUTS/README.md",
]

LINK_PATTERN = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

def check_file(rel_path):
    fpath = ROOT / rel_path
    if not fpath.exists():
        return [f"File does not exist: {rel_path}"]
    
    errors = []
    content = fpath.read_text(encoding="utf-8")
    lines = content.splitlines()

    # 1. Check for file:/// absolute URLs
    if "file:///" in content:
        for idx, line in enumerate(lines, 1):
            if "file:///" in line:
                errors.append(f"Line {idx}: Forbidden 'file:///' link protocol detected: {line.strip()[:80]}")

    # 2. Check for fragile LaTeX % inside math expressions $...$ or $$...$$
    # Extract display math blocks
    display_math = re.findall(r'\$\$(.+?)\$\$', content, flags=re.DOTALL)
    for block in display_math:
        if '%' in block:
            errors.append(f"Fragile LaTeX syntax (% symbol inside display math block): $${block.strip()}$$")

    # Extract inline math blocks on a per-line basis
    for idx, line in enumerate(lines, 1):
        # strip display math tokens from line if any
        line_clean = re.sub(r'\$\$.*?\$\$', '', line)
        inline_math = re.findall(r'(?<!\$)\$(?!\$)([^\$\n]+?)(?<!\$)\$(?!\$)', line_clean)
        for token in inline_math:
            if '%' in token:
                errors.append(f"Line {idx}: Fragile LaTeX syntax (% symbol inside inline math): ${token}$")

    # 3. Check markdown link targets
    for idx, line in enumerate(lines, 1):
        for match in LINK_PATTERN.finditer(line):
            link_text = match.group(1)
            target = match.group(2).split('#')[0]  # strip anchor
            if not target or target.startswith("http://") or target.startswith("https://") or target.startswith("mailto:"):
                continue
            
            target_path = (fpath.parent / target).resolve()
            if not target_path.exists():
                errors.append(f"Line {idx}: Broken relative link target '{target}' (resolved to: {target_path})")

    return errors

def main():
    print("=" * 70)
    print("Q-Shield Documentation Consistency & Integrity Audit")
    print("=" * 70)

    total_errors = 0
    checked_files = 0

    for doc in DOC_FILES:
        errs = check_file(doc)
        checked_files += 1
        if errs:
            print(f"[FAIL] {doc} ({len(errs)} issues):")
            for e in errs:
                print(f"       - {e}")
            total_errors += len(errs)
        else:
            print(f"[PASS] {doc}")

    print("-" * 70)
    if total_errors == 0:
        print(f"Audit PASSED: {checked_files} documents checked, 0 errors found.")
        return 0
    else:
        print(f"Audit FAILED: {total_errors} errors across {checked_files} documents.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
