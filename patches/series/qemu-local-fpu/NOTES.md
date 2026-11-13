LOCAL ONLY: not for submission to qemu-devel (QEMU AI policy). Reference for a hand-written fix.

# qemu-local-fpu: fcmp.le/fcmp.ge operands, fint rounding

Issue: #60 (thesamprice/rtems-microblaze-linker-relaxation-bug).

## Preferred upstream route

Get AMD to post Joe Komlodi's 2020 commits (Xilinx QEMU `ac8e7d0b77`,
`82a2b73d73`, both with his Signed-off-by and Edgar's Reviewed-by).
**But see `patches/reference/qemu-komlodi-2020-fcmp-fint/NOTES.md`:
I found no evidence the series ever reached qemu-devel.**  It is absent
from the lists.gnu.org qemu-devel archive for May and June 2020, while
Komlodi's other microblaze postings of the same week, one sent 19
minutes later, are there.  So "Edgar can apply the 2020 posting" may
not be possible; a repost by AMD is the likely route.  Also, Komlodi's
fcmp.ge returns 1 for NaN operands (tested, below), which UG984 Table
104 says should be 0.

## Base

- `work/src/qemu-new` branch `base-local`: QEMU 10.2.4 tarball
  (`ce70e4a95`) + patches/qemu/0001 exit device (`954e754f6`).
- Branch `local-fpu`.
- Upstream master `9d7d057a55` (2026-11-12): **both bugs still
  present**; `helper_fcmp_le`, `helper_fcmp_ge`, `helper_fint` are
  identical to v10.2.4.  Both patches apply to master (`git apply
  --check`).

## Patches

1. `0001-target-microblaze-compare-rB-with-rA-in-fcmp.le-ge.patch`:
   `helper_fcmp_le` computed `float32_le(a, b)` (rA <= rB) and
   `helper_fcmp_ge` `!float32_lt(a, b)` (rA >= rB, and 1 for NaNs).
   UG984 Table 104: le is rB <= rA, ge is rB >= rA, both 0 for
   unordered, both raise FSR[IO] for any NaN.  Now `float32_le(b, a)`
   and `float32_le(a, b)`.  Precedent: `helper_fcmp_lt` in the same
   file already uses `float32_lt(fb.f, fa.f)`, i.e. rB < rA.
2. `0002-target-microblaze-truncate-in-fint.patch`: `float32_to_int32`
   rounds in the current mode (nearest-even, set in `mb_cpu_reset_hold`
   and never changed).  Now `float32_to_int32_round_to_zero`, as UG984
   "32-bit truncating signed conversion" says.

GCC agrees with UG984: for `a <= b` it emits `fcmp.le r3, r6, r5` with
a in r5 and b in r6 (checked with work/install microblaze-elf-gcc -O2
-mhard-float -mxl-float-convert -mcpu=v9.0), so under unpatched QEMU
every hard-float `<=`/`>=` gives the inverse result.

## Tests

`test/run.sh QEMU_BE QEMU_LE` builds and runs, for both byte orders:

- `fpu.S`: 17 checks.  fcmp.lt/gt controls, fcmp.le/ge in both operand
  orders and with equal operands, fcmp.le/ge with a quiet NaN in either
  position, fint of 2.5, 2.75, -2.75, 3.5, -0.75 and 8388609.0.
- `fpu-c.c`: 9 checks from C with GCC's own operand order.

Exit status = first failed check, 0 = pass.

| build | fpu BE | fpu-c BE | fpu LE | fpu-c LE |
|---|---|---|---|---|
| base-local | 3 | 1 | 3 | 1 |
| local-fpu | 0 | 0 | 0 | 0 |
| test-komlodi-ge (local-fpu with fcmp.ge as in Xilinx ac8e7d0b77) | 9 | 5 | 9 | 5 |
| local-all | 0 | 0 | 0 | 0 |

Individual results, BE (one-instruction programs that exit with rD):

| instruction | base-local | local-fpu |
|---|---|---|
| fint 2.5 | 2 | 2 |
| fint 2.75 | 3 | 2 |
| fint -2.75 | -3 | -2 |
| fint 3.5 | 4 | 3 |
| fcmp.le rA=2.0, rB=1.0 (1 <= 2) | 0 | 1 |
| fcmp.le rA=1.0, rB=2.0 (2 <= 1) | 1 | 0 |
| fcmp.ge rA=2.0, rB=1.0 (1 >= 2) | 1 | 0 |
| fcmp.ge rA=1.0, rB=2.0 (2 >= 1) | 0 | 1 |
| fcmp.ge rA=NaN, rB=1.0 | 1 | 0 |
| fcmp.le rA=NaN, rB=1.0 | 0 | 0 |

QEMU's own tests: no tests/tcg/microblaze exists.  tests/functional
microblaze and microblazeel (5 Linux-boot tests) pass on base-local
and on local-all, which contains this series; table in
`../qemu-local-uartlite-irq/NOTES.md`.  This series alone was not run
through them.

## Untested

- FSR flag values (IO/DO) and FPU exceptions with MSR[EE] set; the tests
  run with EE clear and check only rD.
- fint of out-of-range values, NaN and denormals.  UG984 says rD is
  unchanged / 0xFFC00000 with an exception there; QEMU returns
  softfloat's saturated value.  Neither patch changes that, and I did
  not test it.
- Signalling NaN operands.
- No hardware comparison: the expected values are from UG984 only.

## Open questions

- Was the 2020 series ever public?  Ask Edgar or AMD before anyone
  writes "please apply the 2020 posting".
- UG984's NaN behaviour for fcmp.ge vs Komlodi's: worth confirming on
  hardware before choosing.
