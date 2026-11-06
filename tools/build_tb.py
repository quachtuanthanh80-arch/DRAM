import os, re, subprocess, sys

# Biên dịch một testbench của regression vào thư mục build/, kèm file/top phụ (+top=<module>) để trace.
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
top, out = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
src = open(os.path.join(root, "run_iverilog_regression.py"), encoding="utf-8").read()
i = src.index(f'"top": "{top}"')
j = src.index('"sources": [', i)
k = src.index("]", j)
files = [os.path.join(root, *[p.strip().strip('"') for p in m.split(",")])
         for m in re.findall(r'os\.path\.join\(root, ([^)]*)\)', src[j:k])]
srcs = [a for a in extra if not a.startswith("+top=")]
tops = [a[5:] for a in extra if a.startswith("+top=")]
cmd = ["iverilog", "-g2012", "-I", os.path.join(root, "tb", "common"), "-s", top]
for t in tops:
    cmd += ["-s", t]
cmd += ["-o", out] + files + srcs
r = subprocess.run(cmd, capture_output=True, text=True)
print("\n".join(l for l in (r.stdout + r.stderr).splitlines() if "sorry" not in l and "Padding" not in l)[:3000])
sys.exit(r.returncode)
