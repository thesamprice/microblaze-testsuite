#!/usr/bin/env python3
"""table.py BEFORE/results.txt AFTER/results.txt [be|le]

Every version of libgcc's 64-bit divide and remainder side by side, from
two runs of run.sh: BEFORE with a compiler carrying patches/gcc (the
libgcc series), AFTER with one that also carries the back-end series,
patches/series/gcc-microblaze-carry.  reproduce.sh makes both.

Four tables per routine: instructions, which need no model; then
estimated clock cycles for the five-stage pipeline with no branch target
cache, the same with a perfect one, and the three-stage pipeline.  Each
cell is the mean per call over the run's vectors, then in brackets the
most any one call took.  The cycle figures are mbcount.c's estimates
from UG984, not measurements; see the comment at the top of mbcount.c.
The five-stage figures leave out data-hazard stalls; the last section
gives the range they add.  The assembly versions do not depend on the
compiler, so they come from BEFORE only.

Prints Markdown.  Exits 1 if any variant other than "stock" gave a wrong
result or did not finish, or if summary.py's checks fail.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summary  # noqa: E402

CPUS = [('def', 'no options'),
        ('mlib', 'barrel shifter, hw multiply'),
        ('nodiv', 'everything but the divider'),
        ('full', 'everything')]

# (variant in results.txt, run, label).  run 0 is BEFORE, 1 is AFTER.
ROWS = {
    'moddi3': [
        ('asm', 0, 'Assembly fix, upstream `moddi3.S`'),
        ('asm-new', 0, 'Improved assembly, `moddi3-new.S`'),
        ('generic', 0, 'Upstream C, `libgcc2.c`'),
        ('generic', 1, 'Upstream C + back end'),
        ('generic-nohw', 0, 'Upstream C, no-divider code'),
        ('generic-nohw', 1, 'Upstream C, no-divider code + back end'),
        ('patched', 0, 'libgcc series'),
        ('patched', 1, 'libgcc series + back end'),
    ],
}
for op in ('umoddi3', 'divdi3', 'udivdi3'):
    ROWS[op] = [r for r in ROWS['moddi3'] if not r[0].startswith('asm')]

# (mean field, max field, title).  Instructions have no per-call maximum
# in results.txt, so their cells give the mean only.
METRICS = [
    ('total', None, 'Instructions per call'),
    ('cyc5', 'max5', 'Estimated cycles, 5-stage (C_AREA_OPTIMIZED=0), '
     'no branch target cache'),
    ('cyc5btc', 'max5btc', 'Estimated cycles, 5-stage, perfect branch '
     'target cache'),
    ('cyc3', 'max3', 'Estimated cycles, 3-stage (C_AREA_OPTIMIZED=1)'),
]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    endian = sys.argv[3] if len(sys.argv) > 3 else 'be'
    runs, problems = [], []
    for path in sys.argv[1:3]:
        r, p = summary.load(path, endian)
        runs.append(r)
        problems += ['%s: %s' % (path, x) for x in p]

    def cell(op, v, run, cpu, mean, mx):
        e = runs[run].get((op, v, cpu))
        if e is None:
            return '-'
        if e.get('bad') or 'n' not in e or mean not in e:
            problems.append('%s %s %s %s in %s: %s' % (
                op, v, cpu, endian, sys.argv[1 + run], e))
            return 'failed'
        s = '%.1f' % (e[mean] / e['n'])
        return s + (' (%d)' % e[mx] if mx else '')

    order = 'big-endian' if endian == 'be' else 'little-endian'
    for mean, mx, title in METRICS:
        print('## %s, %s\n' % (title, order))
        for op, rows in ROWS.items():
            print('### `__%s`\n' % op)
            print('| version | ' + ' | '.join(c[1] for c in CPUS) + ' |')
            print('|---|' + '---:|' * len(CPUS))
            if op == 'moddi3' and mean == 'total':
                s = runs[0].get(('moddi3', 'stock', 'def'), {})
                if s.get('bad'):
                    what = 'wrong for %d of %d inputs' % (s['bad'], s['n'])
                elif 'n' not in s:
                    what = 'did not finish'
                else:
                    what = 'correct?'
                print('| Original Xilinx assembly | %s |%s' % (
                    what, ' |' * (len(CPUS) - 1)))
            for v, run, label in rows:
                print('| %s | ' % label + ' | '.join(
                    cell(op, v, run, c[0], mean, mx) for c in CPUS) + ' |')
            print()

    print('## Data-hazard stalls, 5-stage, %s\n' % order)
    print('Mean cycles per call that UG984\'s data hazards add to either '
          '5-stage figure, low and high bound.\n')
    for op, rows in ROWS.items():
        print('### `__%s`\n' % op)
        print('| version | ' + ' | '.join(c[1] for c in CPUS) + ' |')
        print('|---|' + '---:|' * len(CPUS))
        for v, run, label in rows:
            cells = []
            for c in CPUS:
                e = runs[run].get((op, v, c[0]))
                if not e or 'haz5lo' not in e:
                    cells.append('-')
                else:
                    cells.append('%.1f-%.1f' % (e['haz5lo'] / e['n'],
                                                e['haz5hi'] / e['n']))
            print('| %s | ' % label + ' | '.join(cells) + ' |')
        print()

    if problems:
        print('PROBLEMS:', *problems, sep='\n', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
