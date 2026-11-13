# testsuite-check-newlib

Issue: #66 (thesamprice/rtems-microblaze-linker-relaxation-bug).

Not an upstream series: a change to github.com/thesamprice/microblaze-testsuite.

Base: microblaze-testsuite `origin/main` `5bc2764`.  Committed on branch
`newlib-new-check-newlib` in the worktree
`work/src/newlib-new-ts`; the user's checkout (branch
`binutils-relax-cfi`, uncommitted edits) was not touched.

## The patch

`0001-Makefile-run-newlib-s-testsuite-as-check-newlib.patch`

- `check-newlib`: `$(MAKE) -C $(GCC_BUILD) -k check-target-newlib` with
  the same `RUNTEST` and `--target_board=$(BOARD)` as `check-gcc`, then
  copies `newlib.sum`/`newlib.log` to `$(RESULTS)`.
- `NEWLIB_TESTS` (default empty) is appended to RUNTESTFLAGS, like
  `GCC_TESTS`; also passed into Docker.
- `make check` now includes `check-newlib`.
- `NEWLIB_TIMEOUT` (default 300) replaces `MB_TIMEOUT` (90) for this
  target only, because `strcmp-1.c` takes 50-100 s under QEMU (see
  below).
- README: the usage line and the baseline result, beside the check-gcc
  numbers.

Big-endian only, like `check-gcc`: the Makefile's gcc is
`--disable-multilib`, so there is no little-endian newlib to test.  The
issue asked for both endians; that needs a multilib or second build and
is not done.

## How it was run

So as not to touch the shared `work/build/gcc`, `work/src/*` or
`work/install`, the target was run from the worktree with every
component given as an "own tree":

```
W=/Volumes/3092583379/src/microblaze-testsuite/work
make -C $W/src/newlib-new-ts check-newlib WORK=$W/build/newlib-new/work \
  RESULTS=$W/build/newlib-new/work/results-nl-base \
  GCC_BUILD=$W/build/newlib-new/nl-base BINUTILS_BUILD=$W/build/binutils \
  DEJAGNU_SRC=$W/src/dejagnu QEMU=$W/install/bin/qemu-system-microblaze \
  TOOLBIN=$W/install/bin
```

with `work/build/newlib-new/work/site.exp` and the `dejagnu` and
`libxil` stamps made by hand first (so `make` did not reinstall
`libxil.a` into the shared install).  `GCC_BUILD` here is a standalone
newlib build: newlib-cygwin `ebbbf29a6f7` (upstream main, 2026-11-12)
configured at its top level with `--target=microblaze-elf
--disable-multilib CFLAGS_FOR_TARGET="-g -O2"` and built with the
installed `microblaze-elf-gcc` 17.0.0 20261107.  Its top-level
Makefile has the same `check-target-newlib` target as gcc's.

## Results

newlib.sum, DejaGnu `04e420155f7` + board, QEMU 10.2.4 + patches/qemu,
final Makefile (NEWLIB_TIMEOUT=300; the log shows `timeout = 330`, the
board's MB_TIMEOUT+30):

| build | PASS | FAIL | other |
|---|---|---|---|
| newlib ebbbf29, -g -O2 | 32 | 0 | 0 |
| newlib ebbbf29, -g -O2 -mxl-pattern-compare | 32 | 0 | 0 |
| + strlen patch, -g -O2 -mxl-pattern-compare | 32 | 0 | 0 |
| + strlen patch, -g -O2 | 32 | 0 | 0 |

All four .sum files have the same result lines.

32 = compile + execute for 16 programs: iconv (jp, ru, nm), hsearchtest,
stdio (swprintf, nulprintf), stdlib (atexit, size_max), string (memmove1,
tstring, strcmp-1, memcpy-1), time (tzset), wctype (twctype, twctrans,
tiswctype).  Run time about 2.5 minutes, most of it `strcmp-1.c`.

### The one failure seen, and the fix

Before NEWLIB_TIMEOUT, with MB_TIMEOUT=90, one run gave 31 PASS and
`FAIL: newlib.string/strcmp-1.c execution` ("program timed out").  Triage:
the strcmp-1.x binaries of the failing and a passing build were
identical (objdump of .text and .data compared); the same binary passed
and failed on consecutive `NEWLIB_TESTS=string.exp` reruns; run by hand
it took 96 s under microblaze-qemu-run (`-icount 0`), 59 s with
`-icount shift=0,sleep=off` and 50 s without -icount.  So a harness
timeout, not a newlib bug: fixed here with NEWLIB_TIMEOUT.  strcmp-1.c
is the short variant (LONG_TEST not defined).

Otherwise no failures, so nothing to triage.  Two .exp files run nothing, by their
own conditions: `elix.exp` only on `i[3456]86-pc-linux-gnu`;
`UTF-8.exp` returns early unless newlib.h has `_MB_CAPABLE`
(`--enable-newlib-mb`).  No test calls `strlen` directly.

Runs of the same target against newlib builds with
`-mxl-pattern-compare`, used for the strlen series, are in
`../newlib-microblaze-strlen/NOTES.md`.

## Not tested / open

- The target has not been run in the combined gcc tree `make` builds
  (`work/build/gcc`): running it there would write into the shared
  build.  In that tree newlib's flags.exp takes the
  `XGCC_FLAGS_FOR_TARGET` branch and uses xgcc's search paths, rather
  than the `-B$objdir -L$objdir` it used here.
- Docker: not run.
- `libgloss/testsuite` (issue checkbox): not revived.  It has only a
  `configure.in`/`Makefile.in` pair, and `libgloss/configure.ac:237-240`
  comments out `AC_CONFIG_SUBDIRS([testsuite])` ("For now, don't bother
  configuring testsuite").  Undecided; left for the issue.
- Little-endian: not run (see above).
