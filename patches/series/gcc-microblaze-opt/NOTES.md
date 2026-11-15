# gcc-microblaze-opt

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#113, items 1, 3
and 5 (adddi3 immediates, lwr/swr, shift costs). For: gcc-patches@gcc.gnu.org.
Not yet sent.

| patch | commit | #113 item |
|---|---|---|
| 0001 adddi3 constants with addi/addic | `15c9d83fc` | 1 |
| 0002 lwr/swr for byte-reversed accesses | `5d46d2190` | 3 |
| 0003 shift costs without a barrel shifter | `210124658` | 5 |

The measurements (sizes, instruction counts under QEMU) are in each
commit message.

## Base and dependencies

Branch `fix/gcc-opt` (worktree `work/src/gcc-fix-opt`), on
`audit/df809a029-all` = gcc master `df809a029` plus 21 of our patches
(`gcc-microblaze-generic-moddi3`, `-zero-fails`, `-cbranch`,
`-libgcc-asm`, `-fixes`, `-elfos`, `-carry`, `-pcmpbf`). Independent of
`../gcc-microblaze-audit-fixes/`: audit-fixes then opt cherry-pick
cleanly onto the base with the `.file` test-pattern fix
(`pkg/series-scanfix`, checked).

It does **not** apply to the runner's stack (`df809a029` +
`patches/gcc/0001`-`0012`): `microblaze.cc` and `microblaze-protos.h`
conflict with series the runner lacks (`-fixes`, `-elfos`, `-carry`,
`-pcmpbf`). So it is not in `patches/gcc/`.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK on all three.

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

The 4 FAILs are the same in all four runs: the `.file`-matching
`scan-assembler-not` tests fixed since in `../gcc-microblaze-elfos/` and
`../gcc-microblaze-pcmpbf/`. microblaze.exp was also run with four
option sets (`*-var`); after the shift-cost test was made to skip option
sets it does not apply to, no new FAIL.

## Not included

Tail calls (#113 item 4, branch `wip/gcc-sibcall`) are not ready: cc1
ICEs in dwarf2cfi while building newlib. Item 2 (DImode/DFmode only in
even register pairs) is a larger project and not addressed here.

## How to reproduce

```
git -C work/src/gcc worktree add /tmp/g audit/df809a029-all
cd /tmp/g && git am patches/series/gcc-microblaze-opt/*.patch
# build as the Makefile does, then
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp microblaze.exp"
```
