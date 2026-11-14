#!/usr/bin/env python3
"""summary.py RESULTS.TXT [be|le]

Per-call figures from run.sh's results.txt, one line per routine, variant
and set of CPU options: instructions; the estimated cycles for the
five-stage pipeline with no branch target cache (cyc5), with a perfect
one (btc5), and the range the data-hazard stalls add to cyc5 (+haz); the
three-stage pipeline (cyc3); and the most cycles any one call took.  The
cycle figures are mbcount.c's estimates from UG984, not measurements; see
the comment at the top of mbcount.c.

Means are over each run's vectors, and cover the routine and the libgcc
helpers it calls, not the harness's call to it.

Exits 1 if a run other than "stock" has no BENCH line, if the plugin's
instruction total disagrees with the test device's (they must differ by
exactly the two instructions of each call, the call and its delay slot,
which the device counts and the plugin's address range leaves out), or
if a conditional branch's outcome could not be decoded (amb).
"""
import re
import sys

ORDER = {'def': 0, 'mlib': 1, 'nodiv': 2, 'full': 3}
FIELDS = ('total', 'cyc5', 'cyc3', 'max5', 'max3', 'cyc5btc', 'max5btc',
          'haz5lo', 'haz5hi', 'amb')


def load(path, endian):
    """{(op, variant, cpu): dict} for one byte order, checked."""
    runs, problems = {}, []
    for line in open(path):
        m = re.match(r'(\S+) (\S+) (\S+) (be|le) ', line)
        if not m or m.group(4) != endian:
            continue
        e = runs.setdefault(m.group(1, 2, 3), {})
        rest = line[m.end():]
        b = re.search(r' all n=(\d+) bad=(\d+) insns=(\d+) ', rest)
        if b:
            e['n'], e['bad'], e['insns'] = map(int, b.groups())
        if rest.startswith('classes '):
            for f in FIELDS:
                v = re.search(r' %s=(\d+)' % f, rest)
                if v:
                    e[f] = int(v.group(1))
    for key, e in runs.items():
        name = ' '.join(key + (endian,))
        if key[1] == 'stock':
            continue                # wrong and hangs by design; see run.sh
        if 'n' not in e:
            problems.append('%s: no BENCH line' % name)
        elif 'total' not in e:
            problems.append('%s: no MBCOUNT line' % name)
        elif e['insns'] - e['total'] != 2 * e['n']:
            problems.append('%s: device counted %d, plugin %d, for %d calls'
                            % (name, e['insns'], e['total'], e['n']))
        elif e.get('amb'):
            problems.append('%s: %d undecodable branch outcomes'
                            % (name, e['amb']))
    return runs, problems


def main():
    path = sys.argv[1]
    endian = sys.argv[2] if len(sys.argv) > 2 else 'be'
    runs, problems = load(path, endian)
    print('%-8s %-13s %-6s %8s %8s %8s %13s %8s %7s %7s %7s'
          % ('routine', 'variant', 'cpu', 'insns', 'cyc5', 'btc5', '+haz',
             'cyc3', 'max5', 'maxbtc', 'max3'))
    for key in sorted(runs, key=lambda k: (k[0], k[1], ORDER.get(k[2], 9))):
        e = runs[key]
        if 'total' not in e or 'n' not in e:
            continue
        n = e['n']
        haz = '%.1f-%.1f' % (e.get('haz5lo', 0) / n, e.get('haz5hi', 0) / n)
        print('%-8s %-13s %-6s %8.1f %8.1f %8.1f %13s %8.1f %7d %7d %7d'
              % (key + (e['total'] / n, e['cyc5'] / n, e['cyc5btc'] / n,
                        haz, e['cyc3'] / n, e['max5'], e['max5btc'],
                        e['max3'])))
    if problems:
        print('PROBLEMS:', *problems, sep='\n', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
