#!/usr/bin/env python3
"""
===============================================================================
Script: download_sota_papers.py
Description: Download top-tier research papers (2021-2025) on DRAM Controllers,
             RowHammer Defense, DDR5 Architecture, and Multi-Channel Scaling
             into tailieuthamkhao/ for benchmarking and methodology referencing.
===============================================================================
"""

import os
import sys
import urllib.request
import urllib.error

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tailieuthamkhao")
os.makedirs(OUTPUT_DIR, exist_ok=True)

PAPERS = [
    {
        "filename": "2022_SP_Blacksmith_Jattke.pdf",
        "title": "BLACKSMITH: Scalable Rowhammering in the Frequency Domain (IEEE S&P 2022)",
        "url": "https://arxiv.org/pdf/2111.08544.pdf",
    },
    {
        "filename": "2023_CAL_Ramulator2_Rao_Mutlu.pdf",
        "title": "Ramulator 2.0: A Modern, Modular, and Extensible DRAM Simulator (IEEE CAL 2023)",
        "url": "https://arxiv.org/pdf/2308.06649.pdf",
    },
    {
        "filename": "2022_HPCA_Mithril_Yaglikci.pdf",
        "title": "Mithril: A Low-Cost and Highly-Accurate Rowhammer Mitigation at Low Rowhammer Thresholds (HPCA 2022)",
        "url": "https://arxiv.org/pdf/2205.02324.pdf",
    },
    {
        "filename": "2024_USENIX_ZenHammer_Jattke.pdf",
        "title": "ZenHammer: Rowhammer Attacks on AMD Zen-based Platforms (USENIX Security 2024)",
        "url": "https://arxiv.org/pdf/2403.04610.pdf",
    },
    {
        "filename": "2024_ISCA_PRAC_Rowhammer.pdf",
        "title": "PRAC: Pushing Rowhammer Mitigation into the Memory Controller (ISCA 2024 / IEEE CAL 2024)",
        "url": "https://arxiv.org/pdf/2405.08779.pdf",
    },
]

def download_file(url, target_path, title):
    print(f"[*] Downloading: {title}")
    print(f"    URL: {url}")
    print(f"    Target: {target_path}")
    
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
    req = urllib.request.Request(url, headers=headers)
    
    try:
        with urllib.request.urlopen(req, timeout=60) as response, open(target_path, 'wb') as out_file:
            data = response.read()
            out_file.write(data)
            size_kb = len(data) / 1024.0
            print(f"    [SUCCESS] Saved ({size_kb:.1f} KB)\n")
            return True
    except Exception as e:
        print(f"    [WARNING] Download failed: {e}\n")
        return False

def main():
    print("=" * 80)
    print(" SOTA RESEARCH PAPER DOWNLOADER (2021-2025) FOR Q-SHIELD MEMORY CONTROLLER")
    print("=" * 80)
    print(f"Destination folder: {OUTPUT_DIR}\n")

    success_count = 0
    for p in PAPERS:
        dest = os.path.join(OUTPUT_DIR, p["filename"])
        if os.path.exists(dest) and os.path.getsize(dest) > 10000:
            print(f"[*] Skipping existing paper: {p['filename']} ({os.path.getsize(dest)/1024:.1f} KB)")
            success_count += 1
            continue
        if download_file(p["url"], dest, p["title"]):
            success_count += 1

    print("=" * 80)
    print(f"Download completed: {success_count}/{len(PAPERS)} papers present in {OUTPUT_DIR}")
    print("=" * 80)

if __name__ == "__main__":
    main()
