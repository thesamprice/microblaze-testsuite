"""genb64.py OUT: b64.h with three operand sets of N 64-bit pairs for
__muldi3: 0 random 64-bit, 1 both operands below 2^32 (a 32x32-bit
product), 2 a small negative times a 16-bit value."""
import random, sys
random.seed(64); M = (1 << 64) - 1; N = 2000
s0 = [random.getrandbits(64) for _ in range(2 * N)]
s1 = [random.getrandbits(32) for _ in range(2 * N)]
s2 = []
for _ in range(N):
    s2 += [(-random.getrandbits(20)) & M, random.getrandbits(16)]
with open(sys.argv[1], 'w') as f:
    f.write("#define NS %d\nstatic const unsigned long long bset[3][NS][2] = {\n" % N)
    for s in (s0, s1, s2):
        f.write("{" + ",".join("{0x%xULL,0x%xULL}" % (s[i], s[i + 1])
                               for i in range(0, len(s), 2)) + "},\n")
    f.write("};\n")
