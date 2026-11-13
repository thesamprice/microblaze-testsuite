#!/usr/bin/env python3
"""Decode a GCC LSDA call-site table (udata4/uleb128 call sites) from an ELF.
usage: lsda.py file.exe <section-file-offset-hex> <section-addr-hex> <lsda-addr-hex> <func-addr-hex>"""
import sys
f, soff, saddr, lsda, func = sys.argv[1], *[int(x, 16) for x in sys.argv[2:]]
data = open(f, 'rb').read()
p = soff + (lsda - saddr)
def uleb():
    global p
    r = s = 0
    while True:
        b = data[p]; p += 1
        r |= (b & 0x7f) << s; s += 7
        if not b & 0x80: return r
lpstart = data[p]; p += 1
assert lpstart == 0xff
tt = data[p]; p += 1
if tt != 0xff: uleb()
cs = data[p]; p += 1
assert cs == 0x01, "expect uleb128 call sites"
n = uleb(); end = p + n
while p < end:
    s, l, lp, a = uleb(), uleb(), uleb(), uleb()
    print(f"start {func+s:08x} end {func+s+l:08x} lp {func+lp if lp else 0:08x} action {a}")
