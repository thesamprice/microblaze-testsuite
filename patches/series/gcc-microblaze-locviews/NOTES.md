# gcc-microblaze-locviews

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#122. For:
gcc-patches@gcc.gnu.org. One patch, so no cover letter. Not yet sent.

## Base and dependencies

Commit `6668ef9b7` on branch `fix/gcc-views` (worktree
`work/src/gcc-fix-views`), one commit on `fix/gcc-correct` (`bfd4bdd40`;
see `../gcc-microblaze-audit-fixes/NOTES.md`). It touches
`microblaze.cc` (option override), two gcc.dg/debug/dwarf2 tests and adds
two gcc.target/microblaze tests, and applies unchanged to the runner's
stack: it is `patches/gcc/0025`.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK.

## What it does

From -O1 with -g, var-tracking turns on location views, and gcc's own
line table (MicroBlaze sets `DWARF2_ASM_LINE_DEBUG_INFO` to 0) then
advances the address with `DW_LNS_advance_pc` and a `.uleb128 $LMn-$LMm`
difference instead of `DW_LNE_set_address`. The assembler resolves the
difference, so when the linker relaxes (the default) and deletes IMMs,
every later row points at the wrong instruction. The patch turns the
views off unless `-g[no-]variable-location-views` is given; inline2.c and
inline6.c, which count `DW_AT_entry_pc`, now ask for views.

## Testing

Big-endian, microblaze-elf, binutils/newlib/QEMU from the runner, board
`microblaze-qemu`:

| | base (`fix/gcc-correct`) | with this |
|---|---|---|
| execute.exp | - | 24536 PASS, 0 FAIL |
| microblaze.exp | - | 1278 PASS, 4 FAIL (the 4 `.file` scans, as the base) |
| gcc.dg/debug + dwarf2 | 1446 PASS, 0 FAIL | 1446 PASS, 0 FAIL |

Line-table check (scripts in a session scratchpad, `views/`, not in this
repo): 9 gcc.c-torture/execute tests and 4 newlib files at -O2 -g, linked
with relaxation and pristine binutils (no relocations for label
differences), each row compared with the unrelaxed link: 9254 of 17575
rows wrong before, 0 of 15101 after.

On the runner's stack as `patches/gcc/0025` (with the compile fixes
as `0020`-`0024`): execute.exp and microblaze.exp have no FAIL, big- and
little-endian; see `../gcc-microblaze-compile-fixes/NOTES.md`.

## Not fixed: location lists, range lists, DW_AT_high_pc

These use label differences too, and DWARF 5 has no option that avoids
them. Over the same files, with pristine binutils, 4924 of 7916 location
list entries, 344 of 1339 range list entries and 206 of 585
`DW_AT_high_pc` values are wrong after relaxation, with or without this
patch. Only the binutils series (relax-safe CFI and
`../binutils-microblaze-relax-fixes/`, which relocate and adjust label
differences) fix them. Workaround without those: `-gdwarf-3
-ffunction-sections`.

## How to reproduce

```
git -C work/src/gcc worktree add /tmp/g fix/gcc-correct
cd /tmp/g && git am patches/series/gcc-microblaze-locviews/*.patch
# build as the Makefile does, then
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp microblaze.exp debug.exp dwarf2.exp"
```

## Open questions

- Turning views off loses the view numbers that tell apart several
  variable locations at one address. It can be lifted once gas emits
  relocations for code label differences and ld updates them when
  relaxing.
