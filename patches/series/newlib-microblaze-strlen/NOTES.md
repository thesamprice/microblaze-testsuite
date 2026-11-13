# newlib-microblaze-strlen

Issue: #70 (thesamprice/rtems-microblaze-linker-relaxation-bug).
Upstream: newlib, patches to newlib@sourceware.org.

Base: newlib-cygwin `ebbbf29a6f771a30625d69e0c964fbacbc027bc3`
("math.h: remove the log2() macro", upstream main fetched 2026-11-12).
Committed on branch `newlib-new-strlen` in the worktree
`work/src/newlib-new` (from the clone `work/src/newlib`, which was only
fetched, not changed).  `git apply --check` of the patch onto a pristine
`ebbbf29` worktree succeeds.

## The patch

`0001-microblaze-rewrite-the-pcmpbf-strlen-in-assembly.patch`

- New `newlib/libc/machine/microblaze/strlen-pcmp.S`, assembled only
  `#ifdef __HAVE_HW_PCMP__`: a byte loop to the first word boundary,
  then `lw`/`lwr` + `pcmpbf` per word (4 instructions per word, was 5),
  and the length taken straight from pcmpbf's 1-4 position instead of a
  second byte scan.  16 instructions, was 23.
- `strlen.c`: the asm branch is deleted; the C body is now inside
  `#ifndef __HAVE_HW_PCMP__`, so exactly one of the two files defines
  `strlen` (checked with nm on both builds below).  The old guard,
  `HAVE_HW_PCMP`, is defined by GCC only when `!flag_iso`
  (gcc/config/microblaze/microblaze-c.cc:79-84); `__HAVE_HW_PCMP__`
  always.
- `Makefile.inc` lists the new file; `newlib/Makefile.in` regenerated
  with automake 1.15.1 and autoconf 2.69 (the versions newlib/README
  names, built locally under `work/build/newlib-new/tools`).  The
  regeneration changed only the strlen-pcmp lines.

Precedent for the layout: aarch64's `strlen.S` + `strlen-stub.c`, where
the .S and the C file have different base names and preprocessor guards
pick which one is empty.  A new name was needed because automake names
objects after the source's base name, so `strlen.c` and `strlen.S`
would both produce `libc_a-strlen.o`.  The little-endian `lwr` trick is
the one the old code used through mb_endian.h's `LOAD4BYTES`.  No
Xilinx code beyond what is already in newlib was read or used.

## Testing

### Exhaustive correctness and instruction counts

`test/` here: `strlen-test.c`, `start.S`, `link.ld` (copied from
bench/moddi3), `run.sh`.  Run as:

```
W=/Volumes/3092583379/src/microblaze-testsuite/work
OLD=$W/src/newlib-new-base NEW=$W/src/newlib-new TOOLBIN=$W/install/bin \
QEMU=$W/install/bin/qemu-system-microblaze \
MBCOUNT=/Volumes/3092583379/src/microblaze-testsuite/bench/moddi3/mbcount.c \
OUT=$W/build/newlib-new/strlen-bench test/run.sh
```

It checks every start alignment 0-7 and length 0-160, twice (zero bytes
after the NUL, and non-zero bytes after it), with zero bytes before the
string: 2576 calls per variant.  QEMU petalogix-s3adsp1800, default CPU
(`use-pcmp-instr` defaults to true), `-icount shift=0`, the test device
from patches/qemu/0001 for the counts.  Both byte orders.

| variant | BE bad | LE bad | static insns |
|---|---|---|---|
| `c`: strlen.c, no pcmp (unchanged) | 0 | 0 | 32 |
| `c-pcmp`: old asm-in-C, -mxl-pattern-compare | 0 | 0 | 23 |
| `s-pcmp`: new strlen-pcmp.S | 0 | 0 | 16 |

The BE objects are identical (objdump) to the ones in the libc.a of the
nl-base, nl-base-pcmp and nl-new-pcmp builds below.

Instructions executed, alignments 0-3, lengths 0-160, summed (same in
BE and LE):

| | instructions | cyc5 est. | cyc3 est. |
|---|---|---|---|
| c | 154901 | 774772 | 946152 |
| c-pcmp (old) | 81855 | 387788 | 450160 |
| s-pcmp (new) | 65316 (-20.2%) | 302520 (-22.0%) | 358532 (-20.4%) |

cyc5/cyc3 are bench/moddi3/mbcount.c's estimates for the 5- and 3-stage
pipelines (UG984 latencies, no hazard stalls modelled); they are
estimates, not measurements.  The plugin's ranges cover alignments 0-7
and both passes, so the cycle sums are over all 2576 calls; the
instruction column is the test's own count for alignments 0-3.

Per call (includes the indirect call and return), BE:

| len | old a0 a1 a2 a3 | new a0 a1 a2 a3 |
|---|---|---|
| 0 | 16 15 15 15 | 17 13 13 13 |
| 1 | 20 20 20 23 | 17 18 18 22 |
| 3 | 28 33 32 31 | 17 32 27 22 |
| 4 | 21 37 36 35 | 21 32 27 22 |
| 8 | 26 42 41 40 | 25 36 31 26 |
| 16 | 36 52 51 50 | 33 44 39 34 |
| 64 | 96 112 111 110 | 81 92 87 82 |
| 160 | 216 232 231 230 | 177 188 183 178 |

The new code is one instruction slower only for an aligned empty
string.

### newlib testsuite, before and after

`check-newlib` from ../testsuite-check-newlib, BE, all with installed
gcc 17.0.0 20261107 (no LE newlib build exists: the gcc is
--disable-multilib):

| build | CFLAGS_FOR_TARGET | PASS | FAIL |
|---|---|---|---|
| nl-base (ebbbf29) | -g -O2 | 32 | 0 |
| nl-base-pcmp (ebbbf29) | -g -O2 -mxl-pattern-compare | 32 | 0 |
| nl-new-pcmp (patched) | -g -O2 -mxl-pattern-compare | 32 | 0 |
| nl-new (patched) | -g -O2 | 32 | 0 |

The four .sum files have identical result lines (NEWLIB_TIMEOUT=300).
An earlier run of nl-new with MB_TIMEOUT=90 timed out in strcmp-1.c;
its binary was identical to nl-base's and passed on rerun; see
../testsuite-check-newlib/NOTES.md.  `libc_a-strlen.o` of nl-base and
nl-new disassemble identically, so the patch does not change the
non-pcmp strlen.

No newlib test calls strlen directly; it is reached through stdio and
the like.  The exhaustive test above is the real check.

## Not tested

- Real hardware.  Only QEMU; QEMU's pcmpbf (target/microblaze/op_helper.c
  helper_pcmpbf) matches UG984's pseudocode.
- Reads past the end: the code never loads a word beyond the one with
  the NUL, by construction, but the test cannot detect such a read (no
  MMU/MPU fault set up).
- `-Os` builds with pattern compare (the .S is used regardless, as the
  old asm was).
- LE newlib testsuite (no LE libc).
- strcmp.c and strcpy.c have the same asm-in-C structure (own rtsd, no
  clobbers, global labels).  strcpy uses pcmpbf's position; strcmp
  discards it and rescans bytes.  Not changed here; a follow-up.

## Open questions

- Licence and copyright line of the new file: I used newlib's short
  permissive notice ("Permission to use, copy, modify, and distribute
  this software is freely granted, provided that this notice is
  preserved.") with "Copyright (C) 2026 Sam Price".  The human should
  confirm the name and whether COPYING.NEWLIB needs an entry.
- LLM involvement: the patch carries `Assisted-by:`.  I know of no
  newlib-specific policy; sourceware projects differ (binutils refuses
  legally significant LLM-generated content).  Check before sending.
- No Signed-off-by: the human adds it.

## Cover note for newlib@sourceware.org

Single patch, so no 0/N; send with `git send-email` to
newlib@sourceware.org.  Text for below the `---`:

> Tested on QEMU (petalogix-s3adsp1800, pattern compare enabled),
> big- and little-endian: every alignment 0-7 and length 0-160 gives the
> right length.  newlib's own testsuite under QEMU gives the same 32
> passes and no failures before and after, built with
> -mxl-pattern-compare.  I have not tested on hardware.  strcmp.c and
> strcpy.c have the same asm-in-C structure; I can send those separately
> if this one is acceptable.
