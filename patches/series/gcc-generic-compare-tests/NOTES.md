# gcc-generic-compare-tests

Five generic tests, one per commit, each written after a MicroBlaze bug
the GCC testsuite did not catch. Base: gcc master `df809a029`. Not sent.

| patch | test | written after | catches it? |
|---|---|---|---|
| 1 | `gcc.c-torture/execute/float-int-compare-1.c` | #54, fint peephole2 | yes, with `-mcpu=v10.0 -mhard-float -mxl-float-convert`: ICE at -O2/-O3, wrong code (abort) with `-fno-checking` |
| 2 | `gcc.c-torture/execute/compare-boundary-1.c`, `-2.c` | the cbranchsi4_reg and unsigned-vs-zero expander bugs | no: neither bug is reachable from C. Covers the boundaries generally |
| 3 | `gcc.dg/gimplefe-62.c` | #76, unsigned compare against 0 | only with the generic gtu/leu-to-ne/eq canonicalization disabled. `cbranch-unsigned-zero.c`, with the same four functions, aborted at -O0 on such a build; this file was not run that way |
| 4 | `gcc.dg/torture/float-compare-1.c` | #60, QEMU fcmp.le/ge | yes, with `-mhard-float` on stock QEMU 10.2.4 (aborts at every level) |
| 5 | `gcc.dg/torture/reg-struct-return-1.c` | #56, -freg-struct-return ICE | yes, every level (14 FAIL, 7 UNRESOLVED) |

Expected results in 1, 2 and 4 come from tables (truncated values,
signed/unsigned ranks, float ranks), not from the operations under test.
None needs target options or a 32-bit int: test 2 uses limits.h, and its
rank tables hold for any width.

## Results

MicroBlaze, QEMU 10.2.4, DejaGnu (execute.exp, dg-torture.exp, dg.exp),
default board:

| build | BE | LE |
|---|---|---|
| gcc with the gcc-microblaze-fixes, zero-fails and cbranch series (build/gcc-xfix, build-le/gcc) | 78 PASS | 78 PASS |
| unpatched master `df809a029` (build/gcc) | 64 PASS, 14 FAIL, 7 UNRESOLVED (all in test 5) | not run |

Hard float (`-mcpu=v10.0 -mhard-float -mxl-float-convert`), tests 1 and
4, compiled directly and run with the board's `microblaze-qemu-run` and
DejaGnu's testglue, -O0 to -Os, big-endian. This ran outside DejaGnu,
because another agent's execute.exp sweep was holding runtest:

| gcc | stock QEMU | QEMU with the local fcmp/fint fixes (`build/qemu-new/all`) |
|---|---|---|
| fixed | both abort at every level | all pass |
| unpatched | both abort at every level (test 1 ICEs at -O2/-O3) | test 1 ICEs at -O2/-O3; with `-fno-checking` aborts there; the rest pass |

The scratch-build check for test 3 is the parent session's run of
`cbranch-unsigned-zero.c`, which has the same four GIMPLE functions. With
`simplify-rtx.cc`'s `(gtu x 0)`/`(leu x 0)` canonicalization disabled,
unpatched MicroBlaze emitted `bgti` and the -O0 run aborted. With the
expander fix it emitted `cmpu`/`blti` and passed. I did not repeat it with
gimplefe-62.c itself.

Portability:

- arm-none-eabi-gcc 16.2.0 (Homebrew, no C library), with a freestanding
  runtime: vectors, semihosting exit, abort. Run on QEMU `mps2-an385`
  (Cortex-M0, Cortex-M3) and `mps2-an386` (Cortex-M4,
  `-mfloat-abi=hard -mfpu=fpv4-sp-d16`), -O0 to -Os and -O2 -flto; test 5
  with `-freg-struct-return`, test 3 at -O0 with `-fgimple`: 84 of 84
  pass. The scripts are in the session scratchpad (`genarm/`).
- aarch64-linux-gnu, Debian GCC 14.2.0 (the `microblaze-testsuite` Docker
  image), -O0 to -Os: all pass. With `-Wall -Wextra` the only warnings
  are intended ones (`-Wtype-limits` on unsigned `< 0`, an unused GIMPLE
  label); the testsuite compiles torture tests with `-w`.
- Not run on x86: no x86 GCC available locally.

Dropped: nothing. `-freg-struct-return` was the doubtful one, since the
only existing tests are SPARC's. The option is accepted on every target
and the test returns only its own structs, so it stays generic. The first
version used plain `char` and failed on aarch64, where `char` is
unsigned; it now uses `signed char`.

Both checkers pass on all five commits: `git_check_commit.py` and
`check_GNU_style.py`.
