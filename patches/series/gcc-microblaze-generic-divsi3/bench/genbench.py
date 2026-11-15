"""genbench.py OUT: bench.h with three operand sets of N pairs each:
signed, for __divsi3, __modsi3 and __mulsi3: 0 random (as libgcc-audit:
32-bit dividend, divisor of random bit length and sign), 1 small quotient
(|a| = |b|*q + r, q in 0..15), 2 large quotient (|b| in 1..15);
unsigned, for __udivsi3 and __umodsi3, no operand negated: 3 random,
4 small quotient, 5 large quotient."""
import random, sys
random.seed(2026); M = 0xffffffff; N = 2000
def sgn(x): return (-x) & M if random.random() < 0.5 else x
sets = [[], [], [], [], [], []]
for _ in range(N):
    a = random.getrandbits(32); b = random.getrandbits(random.choice([4,8,16,24,31,32])) or 1
    sets[0].append((a, sgn(b)))
    b = random.getrandbits(random.choice([8,16,24,28])) | 1; q = random.randrange(16)
    a = min(b*q + random.randrange(b), 0x7fffffff)
    sets[1].append((sgn(a), sgn(b)))
    b = random.randrange(1, 16); a = random.getrandbits(31) | 0x40000000
    sets[2].append((sgn(a), sgn(b)))
    a = random.getrandbits(32); b = random.getrandbits(random.choice([4,8,16,24,31,32])) or 1
    sets[3].append((a, b))
    b = random.getrandbits(random.choice([8,16,24,28])) | 1; q = random.randrange(16)
    sets[4].append((min(b*q + random.randrange(b), M), b))
    sets[5].append((random.getrandbits(32) | 0x40000000, random.randrange(1, 16)))
with open(sys.argv[1], 'w') as f:
    f.write("#define NS %d\nstatic const unsigned int bset[6][NS][2] = {\n" % N)
    for s in sets:
        f.write("{" + ",".join("{0x%x,0x%x}" % p for p in s) + "},\n")
    f.write("};\n")
