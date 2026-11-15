#!/usr/bin/env python3
"""mkcmd.py LIBGCC_BUILD OBJ: libgcc's own command for one object (from
"make -n"), rewritten for another arm-none-eabi-gcc: prints the flags,
a tab, and the source file.  The build compiler's driver and -B options,
the output, the dependency options and -c SRC are taken out, and paths
relative to the libgcc build directory are made absolute."""
import os, re, shlex, subprocess, sys

lgb, obj = sys.argv[1], sys.argv[2]
srcdir = re.search(r"^srcdir = (.*)$", open(os.path.join(lgb, "Makefile")).read(), re.M).group(1)
srcdir = os.path.normpath(os.path.join(lgb, srcdir))
what_if = []
for f in ("libgcc2.c", "config/arm/lib1funcs.S", "config/arm/bpabi.c"):
    what_if += ["-W", os.path.join(srcdir, f)]
mk = subprocess.run(["make", "-s", "-C", lgb, "-n"] + what_if + [obj],
                    capture_output=True, text=True).stdout
mk = mk.replace("\\\n", " ")
line = next((l for l in mk.splitlines() if re.search(r"(^|\s)-o\s+%s(\s|$)" % re.escape(obj), l)), None)
if line is None:
    sys.exit("mkcmd: no command for %s" % obj)
toks = shlex.split(line)
out, src, i = [], None, 1		# toks[0] is the driver
def absl(p):
    return p if os.path.isabs(p) else os.path.normpath(os.path.join(lgb, p))
while i < len(toks):
    t = toks[i]
    if t.startswith("-B") or t in ("-MD", "-MP"):
        i += 1 if len(t) > 2 or t in ("-MD", "-MP") else 2
        continue
    if t in ("-o", "-MT", "-MF"):
        i += 2
        continue
    if t == "-c":
        src = absl(toks[i + 1])
        i += 2
        continue
    if t in ("-isystem", "-include", "-I"):
        out += [t, absl(toks[i + 1])]
        i += 2
        continue
    if t.startswith("-I"):
        out.append("-I" + absl(t[2:]))
    elif t.endswith(".vis"):		# libgcc passes it as -include
        out += ["-include", absl(t)]
    else:
        out.append(t)
    i += 1
print(" ".join(shlex.quote(x) for x in out) + "\t" + src)
