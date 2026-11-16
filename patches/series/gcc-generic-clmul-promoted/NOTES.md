# gcc-generic-clmul-promoted

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#121. For:
gcc-patches@gcc.gnu.org. One patch, no cover letter. Not yet sent.

## Base and dependencies

Commit `428dff069` on branch `fix/gcc-clmul-promoted` (worktree
`work/src/gcc-clmul`), on gcc master `df809a029`. No dependencies. Also
`patches/gcc/0027`.

Checks: `git_check_commit.py` OK, `check_GNU_style.sh` clean.

## What it does

`expand_CLMUL` (internal-fn.cc) stored its result with `emit_move_insn`.
When the lhs lives in a promoted SUBREG (PROMOTE_MODE widens QImode and
HImode to SImode on MicroBlaze), only the low part is written and the
upper bits the rest of the function relies on are left as they were.
`c-c++-common/builtin-clmulg-1.c` aborted on microblaze-elf at every
level. The patch stores the result the way the other expanders in the
file do (`convert_move` into `SUBREG_REG`). Middle-end, so it may also
fix other PROMOTE_MODE targets; only MicroBlaze was run.

## Testing

MicroBlaze big-endian, QEMU 10.2.4:

- cc1 from `df809a029` (+ `gcc-generic-overaligned-parm`): the test exits
  6 (abort) at -O0 and -O2; with this patch it exits 0 at -O0, -O1, -O2,
  -O3 and -Os.
- In the five-set run of `../gcc-microblaze-elf-defaults/NOTES.md`:
  `builtin-clmulg-1.c` FAIL to PASS, nothing else changed.
- Runner stack `patches/gcc/0001`-`0027`: see the README.
