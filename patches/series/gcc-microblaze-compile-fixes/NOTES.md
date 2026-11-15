# gcc-microblaze-compile-fixes

Issues (thesamprice/rtems-microblaze-linker-relaxation-bug): #116 (0001);
0002-0005 are failures found in the same compile.exp/dg.exp run. For:
gcc-patches@gcc.gnu.org. Not yet sent.

| patch | commit | fixes |
|---|---|---|
| 0001 CONST_INT shift counts | `09fe1fb2d` | #116, LRA ICE (pr65014.c) |
| 0002 return mode from the promotion hook | `5b9931358` | ICEs returning 1- and 2-byte vectors |
| 0003 calls through constant non-function addresses | `99795ca75` | assembler errors, "Unsupported call insn" |
| 0004 TImode argument is four words | `87a330510` | wrong code after a 16-byte vector argument |
| 0005 r20 saved only when the prologue loads it | `d8df05801` | global register variable in r20 restored (20020312-2.c) |

## Base and dependencies

Branch `fix/gcc-compile` (worktree `work/src/gcc-fix-compile`), five
commits on `fix/gcc-correct` (`bfd4bdd40`, i.e. after
`../gcc-microblaze-audit-fixes/`, on `audit/df809a029-all` = gcc master
`df809a029` plus the other gcc series here; see the audit-fixes NOTES.md).

On the runner's stack (`df809a029` + `patches/gcc/0001`-`0019`) two of
the five need context changes, and those versions are `patches/gcc/0020`
to `0024`:

- 0002 conflicts with "microblaze: return small structs in their own
  mode" (`gcc-microblaze-fixes` 0003), which the runner lacks. The runner
  version replaces `LIBCALL_VALUE (TYPE_MODE (valtype))` instead of the
  aggregate special case, and its message says that there it also gives
  a one- or two-byte `-freg-struct-return` struct its own mode.
- 0005's hunk context in `microblaze_must_save_register` comes from the
  interrupt-handler fix (#86, audit-fixes 0004), not in the runner. Same
  change, other context.

0001, 0003 and 0004 are identical on both.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK on all five, and
on the five runner versions.

## Testing

Big-endian, microblaze-elf, binutils/newlib/QEMU from the runner
(`work/wt-zero/work`), board `microblaze-qemu`, `--no-relax`. Results in
`work/results-compile/{base,final,final-r20}` (`final-r20`: 0005's test
alone, 21 PASS, re-run after `-save-temps` was added to it so its
`scan-assembler-not` has a file to scan).

| | compile.exp | dg.exp | dg-torture.exp |
|---|---|---|---|
| base (`fix/gcc-correct`) | 14652 PASS, 22 FAIL | 40031 PASS, 66 FAIL, 3 UNRESOLVED | 24667 PASS, 31 FAIL, 6 UNRESOLVED |
| with these 5 | 14668 PASS, 0 FAIL | 40040 PASS, 55 FAIL, 1 UNRESOLVED | 24697 PASS, 1 FAIL |

With the five: execute.exp 24536 PASS, 0 FAIL; microblaze.exp has the
same 4 FAILs as the base (the `.file`-matching `scan-assembler-not`
tests, see the audit-fixes NOTES.md).

What is left is tracked elsewhere: #118, #120 and #121 (the one
dg-torture FAIL, `strub-run3.c` at -O0), and the `gcc.dg/sibcall-*`
frame-reuse tests, which pass with the sibcall patch of
`../gcc-microblaze-opt/`.

Runner stack, `df809a029` + `patches/gcc/0001`-`0025` (these five as
`0020`-`0024`, `../gcc-microblaze-locviews/` as `0025`), applied with the
Makefile's `git apply --index` loop; builds in `work/build-pkg2/{be,le}`,
results in `work/results-pkg2/{be,le,be-compile}`:

| | execute.exp | microblaze.exp | compile.exp |
|---|---|---|---|
| BE, `0001`-`0019` | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 900 PASS, 0 FAIL | - |
| LE, `0001`-`0019` | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 900 PASS, 0 FAIL | - |
| BE, `0001`-`0025` | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 1005 PASS, 0 FAIL, 2 UNSUPPORTED | 14668 PASS, 0 FAIL, 312 UNSUPPORTED |
| LE, `0001`-`0025` | 24536 PASS, 0 FAIL, 183 UNSUPPORTED | 1005 PASS, 0 FAIL, 2 UNSUPPORTED | - |

The 105 new microblaze.exp passes are the six patches' tests; the two
UNSUPPORTED are 0025's assembly scans in the `-fno-fat-lto-objects` run.
compile.exp is the same as on `fix/gcc-compile`.

## How to reproduce

```
git -C work/src/gcc worktree add /tmp/g fix/gcc-correct
cd /tmp/g && git am patches/series/gcc-microblaze-compile-fixes/*.patch
# build as the Makefile does, then
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu compile.exp dg.exp dg-torture.exp"
```

## Open questions

- 0002 changes which mode a value is returned in only for types whose
  calls ICEd before (one- and two-byte vectors); on the runner's stack
  also for one- and two-byte `-freg-struct-return` structs, which
  `gcc-microblaze-fixes` 0003 fixes the same way.
