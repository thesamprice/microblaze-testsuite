# gcc-microblaze-audit-fixes

Issues (thesamprice/rtems-microblaze-linker-relaxation-bug): #81, #82,
#83, #86, #100, #102, #103, #106, in patch order. For:
gcc-patches@gcc.gnu.org. Not yet sent.

| patch | commit | issue |
|---|---|---|
| 0001 compare-and-swap with xor | `03da0a4c5` | #81 |
| 0002 GOT pointer for TLS | `0a4d2c2e7` | #82 |
| 0003 blockage before sp = fp | `6eadaeae8` | #83 |
| 0004 interrupt handler saves and CFI | `e8d0d705d` | #86 |
| 0005 iprefetch out of delay slots | `011fdc375` | #100 |
| 0006 latent patterns, atomic_test_and_set | `371406bd3` | #102 |
| 0007 -mxl-stack-check note | `3656cc953` | #103 |
| 0008 small-divide table under PIC | `1a53dd708` | #106 |

## Base and dependencies

2026-11-16: 0001's test (`atomic-cas-run.c`) was rewritten for review.
The values are named `BIT31` (`(int) (1u << 31)`) and `ALL_BUT_BIT31`
(`(int) ((1u << 31) - 1)`) instead of written in hex. The helpers are
`bool_compare_and_swap`, `val_compare_and_swap` and
`atomic_compare_exchange` (were `bcas`, `vcas`, `acas`), the global is
`memory`, and `check` computes `should_swap` and `value_after` once and
tests one property per `if`, with `__builtin_abort ()` instead of a
declared `abort`. Where the `__sync`/`__atomic` built-ins are
documented (links to the GCC manual), that all three expand to
`atomic_compare_and_swapsi` (checked: each wrapper's code has the
`lwx`/`swx` loop) and why the wrappers are `noipa` is in 0001's commit
message, not the test. The test cases are the same nine. It still aborts with
the old `cmp` loop (`work/install`, -O0 and -O2) and passes at all 7
levels with the fix (14 PASS). The other seven are
unchanged; rebuilding the branch gave them new hashes (table above). The
previous branch is kept as `fix/gcc-correct-v1` (`bfd4bdd40`), which
the compile-fixes, locviews and opt series below were built on; their
patches do not touch this test. `patches/gcc/0013` is the new 0001;
0014-0019 still carry the old hashes in their `From` lines, with the
same content.

2026-11-17: 0003's commit message now traces the blockage through
MIPS history (GCC 3.0-3.3, d9b59f5634a6, 61db64a590e5); see issue #2.
Only the message changed, so 0004-0008 differ only in their From hashes.
Its test, `epilogue-alloca.c`, was then rewritten after MIPS's
`gcc.target/mips/frame-barrier-1.c`: the same alloca function, with
`-fdump-rtl-final` and `scan-rtl-dump-times "unspec_volatile" 2`
(MicroBlaze's blockage is an unnamed `unspec_volatile`).  14 PASS on
big-endian (-O0 to -Os and both LTO variants); the unfixed compiler
has one blockage at every level, and at -O2, -O3 and -Os its code
resets sp before the last load from the alloca area.

Branch `fix/gcc-correct` (worktree `work/src/gcc-fix-correct`), on
`audit/df809a029-all` = gcc master `df809a029` plus 21 of our patches:
`gcc-microblaze-generic-moddi3`, `gcc-microblaze-zero-fails`,
`gcc-microblaze-cbranch`, `gcc-microblaze-libgcc-asm`,
`gcc-microblaze-fixes`, `gcc-microblaze-elfos`, `gcc-microblaze-carry`
and `gcc-microblaze-pcmpbf` (top: "microblaze: expand strlen inline with
pcmpbf"; after the `.file` test-pattern fix it is `bddc90cf2` on branch
`pkg/series-scanfix`, and these eight cherry-pick onto it cleanly).

On the runner's stack (`df809a029` + `patches/gcc/0001`-`0012`, i.e.
without `gcc-microblaze-fixes`, `-elfos`, `-carry`, `-pcmpbf`): 0001-0003
and 0005-0008 apply with `git am` and with the Makefile's
`git apply --index`. **0004 does not**: one hunk's context in
`microblaze_expand_prologue` is `if (!crtl->is_leaf || interrupt_handler
|| break_handler)`, from `gcc-microblaze-fixes` 0002 ("emit only
_break_handler for break_handler"). So 0004 depends on that patch, and
`patches/gcc/` carries the other seven (as 0013-0019). The same seven
also apply, in order, to bare `df809a029` (`git apply --index`, checked).

The RTEMS side of #82 is `../rtems-microblaze-tls-get-addr/`:
`__tls_get_addr` there ignored its argument, so 0002 alone does not fix
extern `_Thread_local` on RTEMS.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK on all eight.

## Testing

Built and run with `work/build-fix-correct` (base: `gcc`, fixed:
`gcc-fixed`, little-endian: `gcc-le`; `check.sh`/`check-fixed.sh` there),
binutils and newlib from the runner (`work/wt-zero/work`), QEMU 10.2.4,
board `microblaze-qemu`, `MB_NO_RELAX=-Wl,--no-relax`.

| | execute.exp | microblaze.exp |
|---|---|---|
| BE, base (21 patches) | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 1077 PASS, 162 FAIL, 9 UNRESOLVED |
| BE, with these 8 | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 1236 PASS, 4 FAIL |
| LE, with these 8 | - | 1213 PASS, 4 FAIL |

The base's failures are this series' new tests run on the unfixed
compiler. The 4 FAILs left, BE and LE, are `isa/nofcmp.c` and
`isa/strlen-pcmpbf-{nopcmp,os,unaligned}.c`: `scan-assembler-not` patterns
that match the `.file "name.c"` directive emitted since the elfos.h
patch. Fixed in `../gcc-microblaze-elfos/` and `../gcc-microblaze-pcmpbf/`
(patterns anchored on the tab); with those, the four tests pass (11 PASS,
0 FAIL in a `runtest` of just those files with the `gcc-fixed` compiler).

Runner stack, BE (`df809a029` + `patches/gcc/0001`-`0019`, i.e. without
0004; built in `work/build-pkg-gcc` with the runner's binutils, newlib,
DejaGnu and QEMU from `work/wt-zero/work`; results in
`work/results-pkg-gcc/be`): execute.exp 24536 PASS, 0 FAIL, 183
UNSUPPORTED (unchanged); microblaze.exp 900 PASS, 0 FAIL (770 with
`0001`-`0012`, plus 130 from the seven patches' tests).

## How to reproduce

```
git -C work/src/gcc worktree add /tmp/g audit/df809a029-all
cd /tmp/g && git am patches/series/gcc-microblaze-audit-fixes/*.patch
# configure as the Makefile does (--target=microblaze-elf --with-newlib
# --disable-multilib ... --enable-languages=c), newlib/libgloss symlinked in
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp microblaze.exp"
```

## Open questions

- 0004 changes which registers interrupt handlers save (no sp, r2, r13);
  that is visible to anyone reading the saved frame in a debugger.
- 0006's movdi/movdf templates are only reached with the post-reload
  splits disabled; they were checked that way, not in a normal build.
