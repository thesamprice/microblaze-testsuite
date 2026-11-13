import sys
def load(p):
    d={}
    for l in open(p):
        s=l.split()
        if len(s)==2: d[s[1]]=s[0]
    return d
files=sys.argv[1:]
ds=[load(f) for f in files]
names=sorted(set().union(*ds))
for f,d in zip(files,ds):
    c={k:sum(1 for v in d.values() if v==k) for k in ('PASS','FAIL','TIMEOUT')}
    print(f.split('/')[-1], len(d), c)
print('differences / non-pass:')
for n in names:
    v=[d.get(n,'-') for d in ds]
    if any(x!='PASS' for x in v): print(' ', n, *v)
