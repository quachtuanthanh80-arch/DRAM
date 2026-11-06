"""Compile and run one regression testbench in an isolated build dir: run_one_tb.py <top> [timeout_s]"""
import os, re, subprocess, sys

root = r"D:\RAM"
top = sys.argv[1]
tmo = int(sys.argv[2]) if len(sys.argv) > 2 else 900
src = open(os.path.join(root, "run_iverilog_regression.py"), encoding="utf-8").read()
i = src.index(f'"top": "{top}"')
j = src.index("]", src.index('"sources"', i))
seg = src[src.index('"sources"', i):j]
paths = []
if "top_common_sources" in seg:
    a = src.index("top_common_sources = [")
    paths += [os.path.join(root, *[eval(p) for p in m.split(", ")])
              for m in re.findall(r"os\.path\.join\(root, ([^)]*)\)", src[a:src.index("]", a)])]
paths += [os.path.join(root, *[eval(p) for p in m.split(", ")])
          for m in re.findall(r"os\.path\.join\(root, ([^)]*)\)", seg)]
paths = [os.path.join(root, "rtl", "backend", "secded_72_64_pkg.sv"), os.path.join(root, "tb", "common", "ddr5_jedec_bin_pkg.sv")] + [p for p in paths if not p.endswith(("secded_72_64_pkg.sv", "ddr5_jedec_bin_pkg.sv"))]
bdir = os.path.join(root, "build", "one_" + top)
os.makedirs(bdir, exist_ok=True)
cmd = [r"D:\iverilog\bin\iverilog.exe", "-g2012", "-I", os.path.join(root, "tb", "common"), "-s", top, "-o", "t.vvp"] + paths
r = subprocess.run(cmd, capture_output=True, text=True, cwd=bdir)
if r.returncode:
    sys.exit("compile failed:\n" + r.stdout + r.stderr)
r = subprocess.run([r"D:\iverilog\bin\vvp.exe", os.path.join(bdir, "t.vvp")], capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=root, timeout=tmo)
out = r.stdout.splitlines()
print("rc", r.returncode)
print("\n".join(l for l in out if any(k in l for k in ("TB_RESULT", "FAIL", "XPASS", "XFAIL", "ERROR", "mismatch")))[-2000:] or "\n".join(out[-15:]))
