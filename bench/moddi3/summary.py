#!/usr/bin/env python3
"""summary.py RESULTS.TXT [be|le]

Per-call figures from run.sh's results.txt, one line per routine, variant
and set of CPU options: instructions, the estimated cycles for the
five-stage (cyc5) and three-stage (cyc3) MicroBlaze pipelines, and the
most cycles any one call took.  The cycle figures are mbcount.c's
estimate from UG984's instruction latencies, not a measurement; see the
comment at the top of mbcount.c.

Means are over the 4701 vectors, and cover the routine and the libgcc
helpers it calls, not the harness's call to it.
"""
import re
import sys

ORDER = {'def': 0, 'mlib': 1, 'nodiv': 2, 'full': 3}


def main():
    path = sys.argv[1]
    endian = sys.argv[2] if len(sys.argv) > 2 else 'be'
    rows = {}
    pat = re.compile(r'(\S+) (\S+) (\S+) (be|le) classes .* total=(\d+) '
                     r'cyc5=(\d+) cyc3=(\d+) max5=(\d+) max3=(\d+)')
    calls = {}
    for line in open(path):
        m = re.match(r'(\S+) (\S+) (\S+) (be|le) .* all n=(\d+) ', line)
        if m:
            calls[m.group(1, 2, 3, 4)] = int(m.group(5))
        m = pat.match(line)
        if m and m.group(4) == endian:
            rows[m.group(1, 2, 3)] = tuple(int(x) for x in m.group(5, 6, 7, 8, 9))
    print('%-8s %-13s %-6s %8s %8s %8s %7s %7s'
          % ('routine', 'variant', 'cpu', 'insns', 'cyc5', 'cyc3',
             'max5', 'max3'))
    for key in sorted(rows, key=lambda k: (k[0], k[1], ORDER.get(k[2], 9))):
        n = calls.get(key + (endian,), 4701)
        t, c5, c3, m5, m3 = rows[key]
        print('%-8s %-13s %-6s %8.1f %8.1f %8.1f %7d %7d'
              % (key + (t / n, c5 / n, c3 / n, m5, m3)))


if __name__ == '__main__':
    main()
