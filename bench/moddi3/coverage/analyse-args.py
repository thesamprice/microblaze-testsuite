#!/usr/bin/env python3
"""analyse-args.py ARGSDIR VECTORS.H

Which value corners of libgcc's 64-bit divide and remainder a test suite
reaches.  ARGSDIR holds the operand logs qemu-args/argcap.c wrote, one per
run, named TEST-PID.args; VECTORS.H is bench/moddi3/gen.c's output, which
is compared alongside.

Branch coverage (run.sh) says which branches were taken.  This says which
inputs reached them: sign combinations, the extreme operands, exact
division, how many steps the shift-and-subtract loop ran, and the internal
states the loop's correctness argument turns on.  For those it replays the
patched algorithms of patches/gcc (libgcc2.c's __umoddi_no_hw_divide and
the masked __udivmoddi4) on each call's operands.

Logs are from a big-endian guest: r5:r6 is the first argument, high word
first, and r7:r8 the second.
"""
import collections
import glob
import os
import re
import sys

M64 = (1 << 64) - 1
TOP = 1 << 63


def s64(x):
    return x - (1 << 64) if x & TOP else x


def clz(x):
    return 64 - x.bit_length()


def rem_loop(n, d, ev):
    """__umoddi_no_hw_divide, recording internal events.  Each step is
    decided by the sign of R - Y; that it always agrees with R >= Y is
    the claim the code's comment argues, and is checked here too."""
    r = n
    if (d - 1) & M64 < n:
        k = clz(d) - clz(n)
        ev.add('k=0' if k == 0 else 'k=63' if k == 63 else
               'k=1..31' if k < 32 else 'k=32..62')
        y = (d << k) & M64
        while True:
            t = (r - y) & M64
            if r == y:
                ev.add('trial subtraction exactly zero')
            if t == TOP:
                ev.add('R - Y = -2^63')
            if (s64(t) >= 0) != (r >= y):
                ev.add('SIGN TEST DISAGREES WITH R >= Y')
            if s64(t) >= 0:
                r = t
            if r & TOP:
                ev.add('partial remainder >= 2^63')
            y >>= 1
            if k == 0:
                break
            k -= 1
    else:
        ev.add('early exit (|d| > |n| or d = 0)')
    return r


def div_loop(n, d, ev):
    """The masked __udivmoddi4, quotient only."""
    if d <= n:
        k = clz(d) - clz(n)
        ev.add('k=0' if k == 0 else 'k=63' if k == 63 else
               'k=1..31' if k < 32 else 'k=32..62')
        y = (d << k) & M64
        bit = (1 << k) & M64
        q = 0
        r = n
        if r >= y:
            r -= y
            q = bit
            ev.add('first step subtracts')
        else:
            ev.add('first step does not subtract')
        if k > 0:
            y >>= 1
            for _ in range(k):
                if r >= y:
                    r = (((r - y) << 1) + 1) & M64
                else:
                    r = (r << 1) & M64
            q = (q + (r & (bit - 1))) & M64
        else:
            ev.add('no loop (k = 0)')
        if k == 63:
            ev.add('quotient bit 63')
        return q
    ev.add('early exit (d > n)')
    return 0


def classify(fn, a, b):
    ev = set()
    sa, sb = s64(a), s64(b)
    if b == 0:
        ev.add('divisor zero')
        return ev
    if fn in ('__moddi3', '__divdi3'):
        ev.add('signs %s%s' % ('-' if sa < 0 else '+', '-' if sb < 0 else '+'))
        if sa == -TOP:
            ev.add('dividend LLONG_MIN')
        if sb == -TOP:
            ev.add('divisor LLONG_MIN')
        if sb in (1, -1):
            ev.add('divisor +-1')
        if sa == 0:
            ev.add('dividend 0')
        na, nb = abs(sa), abs(sb)
        if na == nb:
            ev.add('|n| == |d|')
        if na >= nb and na % nb == 0 and na:
            ev.add('exact (remainder 0, quotient > 0)')
        if fn == '__moddi3':
            r = rem_loop(na, nb, ev)
            assert r == na % nb
        else:
            q = div_loop(na, nb, ev)
            assert q == na // nb
    else:
        if a & TOP:
            ev.add('dividend top bit set')
        if b & TOP:
            ev.add('divisor top bit set')
        if b == 1:
            ev.add('divisor 1')
        if a == 0:
            ev.add('dividend 0')
        if a == b:
            ev.add('n == d')
        if a >= b and a % b == 0 and a:
            ev.add('exact (remainder 0, quotient > 0)')
        if fn == '__umoddi3':
            r = rem_loop(a, b, ev)
            assert r == a % b
        else:
            q = div_loop(a, b, ev)
            assert q == a // b
    return ev


def main():
    argsdir, vec = sys.argv[1], sys.argv[2]
    tor = {}      # fn -> Counter(event -> calls)
    tests = {}    # fn -> event -> set(test names)
    calls = collections.Counter()
    for path in glob.glob(os.path.join(argsdir, '*.args')):
        test = re.sub(r'-\d+\.args$', '', os.path.basename(path))
        for line in open(path):
            p = line.split()
            if len(p) != 5:
                continue
            fn = p[0]
            a = (int(p[1], 16) << 32) | int(p[2], 16)
            b = (int(p[3], 16) << 32) | int(p[4], 16)
            calls[fn] += 1
            for e in classify(fn, a, b):
                tor.setdefault(fn, collections.Counter())[e] += 1
                tests.setdefault(fn, {}).setdefault(e, set()).add(test)

    # The vectors: every pair goes to all four routines.
    vecs = []
    for m in re.finditer(r'\{ (\(?-?\d+LL(?: - 1\))?), (\(?-?\d+LL(?: - 1\))?),',
                         open(vec).read()):
        v = [eval(x.replace('LL', '')) for x in m.groups()]
        vecs.append((v[0] & M64, v[1] & M64))
    vc = {}
    for fn in ('__moddi3', '__umoddi3', '__divdi3', '__udivdi3'):
        for a, b in vecs:
            for e in classify(fn, a, b):
                vc.setdefault(fn, collections.Counter())[e] += 1

    for fn in ('__moddi3', '__umoddi3', '__divdi3', '__udivdi3'):
        print('\n%s: %d calls from the torture tests, %d vectors'
              % (fn, calls[fn], len(vecs)))
        events = sorted(set(tor.get(fn, {})) | set(vc.get(fn, {})))
        print('  %-42s %9s %6s %9s' % ('case', 'torture', 'tests', 'vectors'))
        for e in events:
            t = tor.get(fn, {}).get(e, 0)
            nt = len(tests.get(fn, {}).get(e, ()))
            v = vc.get(fn, {}).get(e, 0)
            mark = '' if t else '   <- not reached by torture'
            print('  %-42s %9d %6d %9d%s' % (e, t, nt, v, mark))
        if fn in tests:
            for e in sorted(tests[fn]):
                if len(tests[fn][e]) <= 3:
                    print('    %s: only %s' % (e, ', '.join(sorted(tests[fn][e]))))


if __name__ == '__main__':
    main()
