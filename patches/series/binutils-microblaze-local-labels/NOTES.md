# binutils-microblaze-local-labels

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#114. For:
binutils@sourceware.org, but not as a patch of its own. One patch, so no
cover letter.

## What to do with it

It is a fixup for two commits of the in-review relax-safe CFI series:

- "gas: microblaze: emit ADD and SUB for code label differences" (the SUB
  half made in `md_apply_fix`), and
- "gas: microblaze: emit CFA advances as relocations" (the SUB and SUB6
  half made in `microblaze_cfa_fix`).

"gas: microblaze: emit line advances as relocations" inherits it through
the first. **Fold it into those two commits for their v2** rather than
sending it separately; it is a separate patch here so the change can be
reviewed.

It also fixes readelf's SUB relocation with an addend: readelf computed
field + A - S instead of field - (S + A). No SUB relocation had an
addend before this change; afterwards the line table of gas's DWARF2 13
test ended at 0x58 instead of 0x18. That hunk belongs with "readelf:
apply MicroBlaze ADD, SUB and SET relocations" of the same series, and
it touches the shared code for RISC-V and LoongArch SUB relocations too
(which gas emits with no addend, so their output does not change).

## Base and dependencies

Commit `0fdf7fd411a` on branch `fix/binutils-all` (worktree
`work/src/binutils-fix-all`), on top of `../binutils-microblaze-relax-fixes/`
(`f738f888bc8`), which sits on `audit/all-patches` = binutils master
`7b7c85d7f65` plus the relax-safe CFI series (0001-0015),
`binutils-microblaze-64-none`, `binutils-microblaze-no-keep-memory`,
`binutils-microblaze-srec-64/on-relax-cfi`, `binutils-microblaze-eh-relax`
and `binutils-microblaze-opcodes`. See the relax-fixes NOTES.md.

Apply order: relax-fixes -> local-labels (this) -> gas-fixes.

## What it does

The SUB half of an ADD/SUB pair is made when fixup_segment applies the
fixup, after adjust_reloc_syms has turned local symbols into section
symbols, so it named the label itself and every such label went into the
symbol table: five `L0^A` for a three-instruction function with CFI;
73 `$L*` and 11 `L0^A` in a `gcc -g -O2` program linked with `--relax`,
which objdump then used to name code. The SUB half is now made against
the section symbol plus offset, under the same conditions as
adjust_reloc_syms. The same program then has the same `.debug_info`,
`.debug_line` and `.eh_frame` contents as before and none of its own
local labels. For objects from older assemblers, MicroBlaze local labels
are target-special symbols (as RISC-V, PR27584/PR27916), so nm omits them
and objdump does not use them as function names.

## Testing

Tested only as part of the 19 commits of `fix/binutils-all`: see the
relax-fixes NOTES.md (microblaze-elf gas 344 / ld 507 / binutils 245 PASS,
0 FAIL; microblaze-linux gas 341 / ld 839 / binutils 249 PASS with the
base's 12 ld FAIL and 1 XPASS).

## Open questions

- Whether upstream wants the readelf sign fix as its own patch, since it
  changes common code used by RISC-V and LoongArch.
