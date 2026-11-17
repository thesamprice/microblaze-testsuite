# gcc-testsuite-sync-int-long

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#81 (found while
looking for existing tests of the compare-and-swap fix). For:
gcc-patches@gcc.gnu.org. One patch, so no cover letter. Not yet sent.

## Base and dependencies

Branch `fix/gcc-sync-int-long-master` (worktree in a session
scratchpad), one commit on gcc master `df809a029`: `7465838fb`. Also
applies to master `9571dd0b7` (2026-11-17, `git apply --check`). Tested
as `014dd42ea` on branch `fix/gcc-sync-int-long`, on top of
`fix/gcc-correct` (`gcc-microblaze-audit-fixes`): send it after that
series, since 1/8 fixes the compare-and-swap these tests exercise. None
of the newly enabled tests compares values that differ only in bit 31,
so they would probably pass without it too (not checked).

Testsuite only, so not in `patches/gcc/`.

## What it does

Adds `microblaze*-*-*` to `check_effective_target_sync_int_long`.
MicroBlaze has `lwx`/`swx` and `atomic_compare_and_swapsi`, so 32-bit
`__sync`/`__atomic` operations are inline with no library calls
(checked: `__atomic_fetch_add`, `__atomic_exchange_n` and
`__sync_fetch_and_or` on an `int` are `lwx`/`swx` loops; atomic loads and
stores are plain word accesses). `sync_int_long_stack` follows it.

Not enabled: `sync_char_short` (`char`/`short` atomics become
`__atomic_*_1`/`_2` calls, and bare metal has no libatomic) and
`sync_long_long` (64-bit ones are `__sync_*_8` calls).

## Testing

Builds `build-optaudit/base-be` and `base-le` (`fix/gcc-correct`
compiler, srcdir with this patch), board `microblaze-qemu`. In the
earlier BE full run, 23 tests in the five usual sets were UNSUPPORTED
only for `sync_int_long`.

`dg.exp` (21 files) and `dg-torture.exp` (2 files) for those, plus
`dg.exp=pr86314.c` (`sync_int_long_stack`):

| | BE | LE |
|---|---|---|
| PASS | 149 | 149 |
| FAIL | 0 | 0 |
| UNSUPPORTED | 9 | 9 |

21 tests now run (19 in `gcc.dg`, `gcc.dg/torture/hardbool-ai.c` and
`pr86314.c`), 16 of them with execution tests (22 execution PASS). Still
UNSUPPORTED: `atomic-op-optimize.c` and `pr54087.c` (x86 only) and
`torture/bitint-100.c` (`_BitInt`, 7 levels). `gcc.dg/tls/pr58595.c`
also needs `tls_runtime`, which is false on the board (no
`__tls_get_addr` in libgloss). Tests under other `.exp` files (analyzer,
gomp, simulate-thread, tsan) were not run.
