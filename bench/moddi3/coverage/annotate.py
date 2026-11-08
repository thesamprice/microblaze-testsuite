#!/usr/bin/env python3
"""annotate.py LIBGCC2_C TORTURE.info VECTORS.info

Print libgcc2.c's 64-bit divide and remainder code with the line counts
and branch outcomes from two merged LCOV files side by side, and a summary
per function.

A line is "coverable" when the LCOV file has a DA record for it, which
tcgcov writes for every line with an instruction in the ELF.  Branch
outcomes are the BRDA records: each conditional branch instruction has a
taken and a not-taken outcome, and tcgcov counts them from the control-flow
edges QEMU executed.  Inlined code, such as __udivmoddi4 inside __moddi3,
is attributed to its own source lines.
"""
import re
import sys

FUNCS = ['__udivmoddi4', '__umoddi_no_hw_divide', '__divdi3', '__moddi3',
         '__umoddi3', '__udivdi3']


def load(path):
    da, br = {}, {}
    cur = False
    for line in open(path):
        line = line.rstrip('\n')
        if line.startswith('SF:'):
            cur = line[3:].endswith('libgcc/libgcc2.c')
        elif not cur:
            continue
        elif line.startswith('DA:'):
            ln, cnt = line[3:].split(',')[:2]
            da[int(ln)] = da.get(int(ln), 0) + int(cnt)
        elif line.startswith('BRDA:'):
            ln, blk, b, taken = line[5:].split(',')
            key = (int(ln), blk, b)
            t = 0 if taken == '-' else int(taken)
            br[key] = br.get(key, 0) + t
    return da, br


def spans(src):
    """First definition of each function: from its name at the start of a
    line to the next closing brace in column 0.  The first __udivmoddi4 is
    the TARGET_HAS_NO_HW_DIVIDE one."""
    out = {}
    for f in FUNCS:
        for i, l in enumerate(src):
            if re.match(re.escape(f) + r' \(', l):
                j = i
                while not src[j].startswith('}'):
                    j += 1
                out[f] = (i + 1, j + 1)
                break
    return out


def main():
    src = open(sys.argv[1]).read().split('\n')
    t_da, t_br = load(sys.argv[2])
    v_da, v_br = load(sys.argv[3])
    sp = spans(src)

    print('Summary, libgcc2.c (torture / vectors)')
    print('%-24s %-22s %-22s' % ('function', 'lines hit/coverable',
                                 'branch outcomes hit/all'))
    for f in FUNCS:
        if f not in sp:
            continue
        a, b = sp[f]
        cols = []
        for da, br in ((t_da, t_br), (v_da, v_br)):
            lines = [n for n in range(a, b + 1) if n in da]
            hit = [n for n in lines if da[n] > 0]
            outs = [k for k in br if a <= k[0] <= b]
            bhit = [k for k in outs if br[k] > 0]
            cols.append('%d/%d' % (len(hit), len(lines)))
            cols.append('%d/%d' % (len(bhit), len(outs)))
        print('%-24s %-10s %-11s %-10s %s' % (f, cols[0], cols[2],
                                              cols[1], cols[3]))
    print()
    print('Listing.  Columns: torture count, vectors count, then branch')
    print('outcomes as torture|vectors: + taken at least once, - never,')
    print('. no such branch in that source\'s binaries.')
    print('"." is a line with no instruction of its own.')
    for f in FUNCS:
        if f not in sp:
            continue
        a, b = sp[f]
        print()
        print('==== %s, libgcc2.c:%d-%d' % (f, a, b))
        for n in range(a, b + 1):
            def c(da):
                return '%9d' % da[n] if n in da else '        .'
            outs = sorted(k for k in set(t_br) | set(v_br) if k[0] == n)
            def mark(br, k):
                if k not in br:
                    return '.'
                return '+' if br[k] else '-'
            bs = ' '.join('%s|%s' % (mark(t_br, k), mark(v_br, k))
                          for k in outs)
            print('%s %s %5d  %-60s %s' % (c(t_da), c(v_da), n,
                                           src[n - 1][:60], bs))


if __name__ == '__main__':
    main()
