# gcc-microblaze-opt

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#113, all five
items (adddi3 immediates, odd register pairs, lwr/swr, sibcalls, shift
costs), so #113 is fully implemented. For: gcc-patches@gcc.gnu.org. Not
yet sent.

| patch | commit on `fix/gcc-opt-on-audit` | #113 item |
|---|---|---|
| 0001 adddi3 constants with addi/addic | `88632195a` | 1 |
| 0002 lwr/swr for byte-reversed accesses | `daaa16af0` | 3 |
| 0003 shift costs without a barrel shifter | `e28f725cf` | 5 |
| 0004 sibcall patterns | `f1edeb12d` | 4 |
| 0005 64-bit values in odd register pairs | `1e6f37808` | 2 |

The measurements (sizes, instruction counts under QEMU) are in each
commit message. They were taken on the earlier base (below) and not
retaken on this one.

## Base and dependencies

Branch `fix/gcc-opt-on-audit` (worktree `work/src/gcc-optaudit`), five
commits on `fix/gcc-correct` (`bfd4bdd40`), i.e. on
`../gcc-microblaze-audit-fixes/`, which sits on gcc master `df809a029`
plus `gcc-microblaze-generic-moddi3`, `-zero-fails`, `-cbranch`,
`-libgcc-asm`, `-fixes`, `-elfos`, `-carry` and `-pcmpbf`. Mail this
series after audit-fixes.

Earlier version: on `audit/df809a029-all` without audit-fixes (`fix/gcc-opt`
`210124658`, `fix/gcc-sibcall` `7793f80ab`, `fix/gcc-evenpair`
`5664caf9c`). Rebasing onto audit-fixes, 0001-0003 applied unchanged and
0004/0005 conflicted with audit-fixes 0003 (#83) and 0006 (#102):

- 0004 in `microblaze_expand_epilogue`: #83 puts a blockage before
  `sp = fp`, which 0004 makes frame-related with a `REG_CFA_DEF_CFA`
  note. Resolved: the blockage, then 0004's move with its note. 0004's
  message already describes the blockage as shared by both epilogues.
- 0005 in `microblaze.md`: #102 removes `*one_cmpldi2` and its `not:DI`
  split and gives the unsplit `*movdi_internal` register copy the
  overlap-safe order, all of which 0005 also changed. Resolved: #102's
  side; 0005 now only changes `adddi3` and `negdi2` in the md file. Its
  message's audit list and ChangeLog are updated to match (the
  complement now goes through the generic word-at-a-time expansion).

The resolutions were first made in `scratch/pkg2-opt-on-compile-views`
(on the compile fixes and locviews too) and reviewed again here; the
cherry-picks onto `fix/gcc-correct` applied without conflict. The
compile-fixes and locviews series also cherry-pick onto this branch
without conflict (checked, not built).

Not in `patches/gcc/`: the runner lacks `-fixes`, `-elfos`, `-carry`
and `-pcmpbf`, which these patches' context needs.

Checks: `git_check_commit.py` OK on all five, `check_GNU_style.sh` clean.

## Testing

### On audit-fixes (this version)

`fix/gcc-correct` (base) and `fix/gcc-opt-on-audit` (with), each built
big- and little-endian with binutils from `install-fix-correct(-le)`,
newlib/DejaGnu/QEMU 10.2.4 from the runner, gcc configured
`--with-headers`, board `microblaze-qemu`, `--no-relax`. Builds in
`work/build-optaudit/`, results in `work/results-optaudit/`.

| run | base | with the series |
|---|---|---|
| BE, compile.exp execute.exp dg.exp dg-torture.exp microblaze.exp | 105124 PASS, 122 FAIL, 8 UNRESOLVED | 105367 PASS, 118 FAIL, 8 UNRESOLVED |
| LE, execute.exp microblaze.exp | 25772 PASS, 4 FAIL | 25913 PASS, 4 FAIL |
| BE microblaze.exp, `-mno-xl-soft-mul` | 1205 PASS, 12 FAIL | 1336 PASS, 12 FAIL |
| BE microblaze.exp, `-mcpu=v10.0 -mxl-barrel-shift -mno-xl-soft-mul -mxl-pattern-compare -mxl-multiply-high` | 1149 PASS, 68 FAIL | 1276 PASS, 68 FAIL |
| BE microblaze.exp, `-mcpu=v8.50.a -mxl-reorder` | 1213 PASS, 4 FAIL | 1337 PASS, 4 FAIL |
| BE microblaze.exp, `-mcpu=v9.6 -mno-xl-soft-mul -mxl-reorder` | 1205 PASS, 12 FAIL | 1329 PASS, 12 FAIL |

No result goes from PASS to anything else and no new FAIL, UNRESOLVED or
XPASS in any run (compared line by line, source paths normalized). The
three `strlen-pcmpbf` `brlid r15,strlen` scans are renamed by 0004 (they
accept `brid` too) and pass. In the full BE run the 4 FAILs that go are
`gcc.dg/sibcall-3`, `-4`, `-9` and `-10`, and 31 tests UNSUPPORTED on
the base (the `musttail*` tests and related PRs, which need sibling
calls) now run and pass, 88 results. The variant runs' FAILs are the
same set on both sides: isa scan tests whose expected instructions
change with the forced options, plus the 4 `.file` scans fixed since
in the elfos/pcmpbf series. The new tests skip themselves in some
variants (1-2 new UNSUPPORTED).

### On the earlier base


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
git -C work/src/gcc worktree add /tmp/g fix/gcc-correct
cd /tmp/g && git am patches/series/gcc-microblaze-opt/*.patch
# build as the Makefile does, then
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp microblaze.exp"
```
