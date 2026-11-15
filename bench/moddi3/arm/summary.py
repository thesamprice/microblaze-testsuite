#!/usr/bin/env python3
"""summary.py OUT: the per-call instruction counts run.sh wrote, checked
and tabulated.  For each run it checks that every result was right, that
there is one count per vector, and that the counts add up to the
plugin's total; then prints the mean per call, overall and per class."""
import os, re, sys

out = sys.argv[1]
rows = {}
classes_order = []
fail = 0
for line in open(os.path.join(out, "results.txt")):
    f = line.split()
    fn, v, vs = f[0], f[1], f[2]
    m = re.search(r'bad=(\d+)', line)
    a = re.search(r'calls=(\d+) total=(\d+)', line)
    op = {"__moddi3": 0, "__umoddi3": 1, "__divdi3": 2, "__udivdi3": 3,
          "__aeabi_ldivmod": 4, "__aeabi_uldivmod": 5}[fn]
    d = os.path.join(out, "op%d-%s" % (op, vs))
    counts = [int(x) for x in open(os.path.join(d, v + ".counts"))]
    cls = [x.strip() for x in open(os.path.join(d, "classes.txt"))]
    ok = (m and m.group(1) == "0" and "status=0" in line and a
          and int(a.group(1)) == len(counts) == len(cls)
          and int(a.group(2)) == sum(counts))
    if not ok:
        print("FAILED CHECK:", line.strip())
        fail = 1
        continue
    per = {}
    for c, n in zip(cls, counts):
        per.setdefault(c, []).append(n)
        if c not in classes_order:
            classes_order.append(c)
    rows[(fn, vs, v)] = (sum(counts) / len(counts), min(counts),
                         max(counts), {c: sum(x) / len(x) for c, x in per.items()})

print(open(os.path.join(out, "compiler.txt")).read().strip())
print("%-18s %-8s %-7s %9s %6s %6s" % ("routine", "vectors", "variant",
                                       "mean", "min", "max"))
for (fn, vs, v), (mean, lo, hi, _) in rows.items():
    print("%-18s %-8s %-7s %9.1f %6d %6d"
          % (fn, "signed" if vs == "s" else "unsigned", v, mean, lo, hi))
print()
print("Mean per class:", ", ".join(classes_order))
for (fn, vs, v), (_, _, _, per) in rows.items():
    print("%-18s %-8s %-7s " % (fn, "signed" if vs == "s" else "unsigned", v)
          + " ".join("%8.1f" % per.get(c, 0) for c in classes_order))
sys.exit(fail)
