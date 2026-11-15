#!/usr/bin/env python3
"""checkcalls.py DIS LO HI: fail if code in the counted range [LO, HI)
branches or calls outside it, since armcount.c would not count the
instructions there.  DIS is objdump -d of the .lg section."""
import re, sys

dis, lo, hi = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
bad = []
for line in open(dis):
    m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f ]+\s+(bl|blx|b|b\.n|b\.w|b[a-z]{2}(?:\.n|\.w)?)\s+([0-9a-f]+)\b', line)
    if m:
        t = int(m.group(3), 16)
        if not lo <= t < hi:
            bad.append(line.strip())
if bad:
    print("checkcalls: branches out of the counted range:\n  " + "\n  ".join(bad))
    sys.exit(1)
