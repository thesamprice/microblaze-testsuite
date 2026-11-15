"""table2.py RESULTS: per call, mean over 2000 calls (max in parentheses):
insn = instructions executed (model-free); c5 = five-stage estimate, no
branch target cache; cb = five-stage with a perfect branch target cache
(instructions plus idiv's extra 33); c3 = three-stage estimate; hz =
five-stage data-hazard stalls, upper bound (mbhaz 'hi')."""
import sys
d = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) < 6: continue
    fn, v, cfg, s = p[:4]
    kv = {}
    for x in p[4:]:
        if '=' in x:
            a, b = x.split('=', 1); kv.setdefault(a, b)  # MBCOUNT before MBHAZ (sorted)
    if 'total' not in kv: continue
    hz = None
    if 'MBHAZ' in p:
        i = p.index('MBHAZ'); hk = dict(x.split('=') for x in p[i+1:] if '=' in x); hz = int(hk['hi'])
    d[(fn, v, cfg, s)] = (int(kv['total'])/2000, int(kv['cyc5'])/2000, int(kv['max5']),
                          int(kv['cycb'])/2000, int(kv['maxb']), int(kv['cyc3'])/2000, int(kv['max3']),
                          hz/2000 if hz is not None else 0)
order = ['__divsi3','__modsi3','__udivsi3','__umodsi3','__mulsi3']
names = {'0':'random','1':'short quotient','2':'long quotient','3':'random','4':'short quotient','5':'long quotient'}
cfgs = [c for c in ['def','bs','bsonly','all','allnomul','alldiv'] if any(k[2]==c for k in d)]
for cfg in cfgs:
    print("\n== %s" % cfg)
    print("%-10s %-4s %-15s %8s %15s %15s %15s %6s" % ('routine','', 'operands','insn','c5 (max)','cb (max)','c3 (max)','hz'))
    for fn in order:
        for s in '012345':
            for v in ['asm','gen','inl']:
                r = d.get((fn, v, cfg, s))
                if not r: continue
                print("%-10s %-4s %-15s %8.1f %15s %15s %15s %6.2f" % (fn, v, names[s], r[0],
                      "%.1f (%d)" % (r[1], r[2]), "%.1f (%d)" % (r[3], r[4]), "%.1f (%d)" % (r[5], r[6]), r[7]))
