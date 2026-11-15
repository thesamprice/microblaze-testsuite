# gcc-microblaze-opt

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#113, all five
items (adddi3 immediates, odd register pairs, lwr/swr, sibcalls, shift
costs), so #113 is fully implemented. For: gcc-patches@gcc.gnu.org. Not
yet sent.

| patch | commit | #113 item |
|---|---|---|
| 0001 adddi3 constants with addi/addic | `15c9d83fc` | 1 |
| 0002 lwr/swr for byte-reversed accesses | `5d46d2190` | 3 |
| 0003 shift costs without a barrel shifter | `210124658` | 5 |
| 0004 sibcall patterns | `7793f80ab` | 4 |
| 0005 64-bit values in odd register pairs | `5664caf9c` | 2 |

The measurements (sizes, instruction counts under QEMU) are in each
commit message.

## Base and dependencies

Branch `fix/gcc-evenpair` (worktree `work/src/gcc-fix-evenpair`):
0001-0003 are `fix/gcc-opt` (worktree `work/src/gcc-fix-opt`), 0004 is
`fix/gcc-sibcall` (`work/src/gcc-fix-sibcall`) on top, 0005 on top of
that. 0001-0003 are unchanged from the three-patch version of this
folder except for the `[PATCH n/5]` numbering. All five are on
`audit/df809a029-all` = gcc master `df809a029` plus 21 of our patches
(`gcc-microblaze-generic-moddi3`, `-zero-fails`, `-cbranch`,
`-libgcc-asm`, `-fixes`, `-elfos`, `-carry`, `-pcmpbf`).

On top of `../gcc-microblaze-audit-fixes/` (`fix/gcc-correct`), with or
without `../gcc-microblaze-compile-fixes/` and
`../gcc-microblaze-locviews/` (checked by cherry-picking onto
`fix/gcc-compile` + `fix/gcc-views`, and onto `fix/gcc-correct` alone):
0001-0003 apply cleanly; 0004 and 0005 conflict, both times with
audit-fixes, not with the other two series:

- 0004 in `microblaze_expand_epilogue`: audit-fixes 0003 (#83) puts a
  blockage before `sp = fp`, where 0004 makes that move frame-related
  with a `REG_CFA_DEF_CFA` note. Resolution: keep the blockage, then
  0004's move. (0004's message already describes the blockage as shared
  by both epilogues.)
- 0005 in `microblaze.md`, two hunks: audit-fixes 0006 (#102) removes
  `*one_cmpldi2` and its split (MicroBlaze has no `nor`), which 0005
  rewrites for overlapping pairs, and gives the unsplit `*movdi_internal`
  register copy the same overlap-safe order that 0005 gives it.
  Resolution: take audit-fixes' side of both; 0005's message then
  describes `*one_cmpldi2` and the not:DI split, which no longer exist.

The resolved stack (`fix/gcc-compile` + locviews + these five) is branch
`scratch/pkg2-opt-on-compile-views` (`7faac3100`); it was not built.
The series here is not changed for it.

It does **not** apply to the runner's stack (`df809a029` +
`patches/gcc/`): `microblaze.cc` and `microblaze-protos.h`
conflict with series the runner lacks (`-fixes`, `-elfos`, `-carry`,
`-pcmpbf`). So it is not in `patches/gcc/`.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK on all five.

## Testing

Builds and scripts: `work/build-fix-opt/<name>`, results in
`work/results-fix-opt/<tag>` (`base-be`, `base-le`, `i3-be`, `i3-le`,
and `*-var` for the option variants), binutils/newlib/QEMU from the
runner (`work/wt-zero/work`), board `microblaze-qemu`, `--no-relax`.

| | execute.exp + microblaze.exp |
|---|---|
| BE, base | 25474 PASS, 4 FAIL, 186 UNSUPPORTED |
| BE, with 0001-0003 | 25527 PASS, 4 FAIL, 186 UNSUPPORTED |
| LE, base | 25474 PASS, 4 FAIL, 186 UNSUPPORTED |
| LE, with 0001-0003 | 25527 PASS, 4 FAIL, 186 UNSUPPORTED |
| BE and LE, with 0001-0004 | 25580 PASS, 4 FAIL |
| BE and LE, with 0001-0005 | 25615 PASS, 4 FAIL |

The 4 FAILs are the same in all these runs: the `.file`-matching
`scan-assembler-not` tests fixed since in `../gcc-microblaze-elfos/` and
`../gcc-microblaze-pcmpbf/`. microblaze.exp was also run with four
option sets (`*-var`); after the shift-cost test was made to skip option
sets it does not apply to, no new FAIL; with 0001-0004 3978 PASS,
96 FAIL and with 0001-0005 4102 PASS, 96 FAIL, again no new FAIL.

0004 and 0005 were tested in `work/results-sibcall/*` and
`work/results-evenpair/*` (`be`, `le`, `be-var`; `be-sib`/`le-sib` for
`dg.exp=sibcall*`, `be-t64`/`le-t64` for gcc.dg/torture `*64*`):

- 0004: `dg.exp=sibcall*` 18 PASS, 0 FAIL (14 PASS, 4 FAIL before:
  sibcall-3, -4, -9 and -10, which check that the sibling call reuses the
  frame). Under QEMU at -O2, 1000 calls to a one-call wrapper 20012 ->
  15012 instructions, mutual recursion 1000 deep 9011 -> 3010; text at
  -Os over 1646 files 3121940 -> 3120312 bytes (85 files smaller, 18
  larger). Regression: a wrapper that calls and then tail-calls the same
  function, 28010 -> 29010 for 1000 calls (its argument must survive the
  first call in a saved register).
- 0005: gcc.dg/torture `*64*` 892 PASS, 0 FAIL on both endians. A loop
  calling three small 64-bit functions: -21% instructions BE, -23% LE.
  Text over 1653 files -0.11% at -O2, -0.13% at -Os; newlib's libm.a
  -1.0%; largest growth pr58574.c, +456 bytes (one more `__adddf3` call
  per case of a 64-case switch).

## How to reproduce

```
git -C work/src/gcc worktree add /tmp/g audit/df809a029-all
cd /tmp/g && git am patches/series/gcc-microblaze-opt/*.patch
# build as the Makefile does, then
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp microblaze.exp"
```
