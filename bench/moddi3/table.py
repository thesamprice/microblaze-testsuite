#!/usr/bin/env python3
"""table.py BEFORE/results.txt AFTER/results.txt [be|le]

Every version of libgcc's 64-bit divide and remainder side by side, from
two runs of run.sh: BEFORE with a compiler carrying patches/gcc (the
libgcc series), AFTER with one that also carries the back-end series,
patches/series/gcc-microblaze-carry.  reproduce.sh makes both.

Each cell is the mean estimated clock cycles per call over the 4701
vectors, then in brackets the most any one call took.  The figures are
mbcount.c's estimate from UG984's instruction latencies, not a
measurement; see the comment at the top of mbcount.c.  The assembly
versions do not depend on the compiler, so they come from BEFORE only.

Prints Markdown.  Exits 1 if any variant other than "stock" gave a wrong
result or did not finish.
"""
import re
import sys

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

LINE = re.compile(r'(\S+) (\S+) (\S+) (be|le) ')
RUN = re.compile(r'status=(\d+) .* all n=(\d+) bad=(\d+) ')
CLASSES = re.compile(r'classes .* cyc5=(\d+) cyc3=(\d+) max5=(\d+) max3=(\d+)')


def load(path, endian):
    """{(op, variant, cpu): dict} for one byte order."""
    d = {}
    for line in open(path):
        m = LINE.match(line)
        if not m or m.group(4) != endian:
            continue
        e = d.setdefault(m.group(1, 2, 3), {})
        rest = line[m.end():]
        if rest.endswith('no result\n'):
            e['status'] = int(re.search(r'status=(\d+)', rest).group(1))
        r = RUN.match(rest)
        if r:
            e['status'], e['n'], e['bad'] = map(int, r.groups())
        c = CLASSES.match(rest)
        if c:
            e['cyc5'], e['cyc3'], e['max5'], e['max3'] = map(int, c.groups())
    return d


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    endian = sys.argv[3] if len(sys.argv) > 3 else 'be'
    runs = [load(sys.argv[1], endian), load(sys.argv[2], endian)]
    problems = []

    def cell(op, v, run, cpu, pipe):
        e = runs[run].get((op, v, cpu))
        if e is None:
            return '-'
        if e.get('status') or e.get('bad') or 'cyc5' not in e:
            problems.append('%s %s %s %s in %s: %s' % (
                op, v, cpu, endian, sys.argv[1 + run], e))
            return 'failed'
        n = e['n']
        return '%.1f (%d)' % (e['cyc' + pipe] / n, e['max' + pipe])

    for pipe, name in (('5', '5-stage (C_AREA_OPTIMIZED=0)'),
                       ('3', '3-stage (C_AREA_OPTIMIZED=1)')):
        print('## %s, %s\n' % (name, 'big-endian' if endian == 'be'
                                     else 'little-endian'))
        for op, rows in ROWS.items():
            print('### `__%s`\n' % op)
            print('| version | ' + ' | '.join(c[1] for c in CPUS) + ' |')
            print('|---|' + '---:|' * len(CPUS))
            if op == 'moddi3' and pipe == '5':
                s = runs[0].get(('moddi3', 'stock', 'def'), {})
                if s.get('bad'):
                    what = 'wrong for %d of %d inputs' % (s['bad'], s['n'])
                elif 'n' not in s:
                    what = 'did not finish (exit %s)' % s.get('status', '?')
                else:
                    what = 'correct?'
                print('| Original Xilinx assembly | %s |%s' % (
                    what, ' |' * (len(CPUS) - 1)))
            for v, run, label in rows:
                print('| %s | ' % label + ' | '.join(
                    cell(op, v, run, c[0], pipe) for c in CPUS) + ' |')
            print()

    if problems:
        print('PROBLEMS:', *problems, sep='\n', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
