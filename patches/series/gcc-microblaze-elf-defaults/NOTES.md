# gcc-microblaze-elf-defaults

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#120. For:
gcc-patches@gcc.gnu.org. Not yet sent.

## Base and dependencies

Branch `fix/gcc-elf-defaults` (worktree in a session scratchpad), two
commits on `pkg/elfos-scanfix` (`2d6b763ce`), the
`gcc-microblaze-elfos` patch: `fc67547e4`, `0da18fbc0`. Needs that patch
(both overrides it kept are removed here). Not in `patches/gcc/`: the
runner does not carry the elfos series.

Checks: `git_check_commit.py` OK, `check_GNU_style.sh` clean.

## What it does

The elfos NOTES listed adopting more of elfos.h's defaults as a separate
step. These are two of them:

- **MAX_OFILE_ALIGNMENT**: MicroBlaze capped it at 32768 bytes. gas and
  ld handle more: a `.data` with `.balign 1048576` assembles with
  `sh_addralign` 1048576 and links at a 1 MiB boundary. elfos.h's
  (1 << 28) bytes is what `gcc.dg/attr-aligned-3.c` expects of ELF.
- **READONLY_DATA_SECTION_ASM_OP**: `.rodata` (a MicroBlaze-only gas
  directive) becomes elfos.h's `.section .rodata`. The objects are
  byte-identical (checked with a one-word `.rodata`). The testsuite's
  `scan-assembler-symbol-section` follows `.section`, `.csect`, `.const`,
  `.data` and `.text` only, so it put such symbols in `.text`.
  `microblaze_asm_output_ident` pasted the directive after
  `.pushsection`, which the first build of this patch broke
  (`gcc.c-torture/compile/20010510-1.c`, `#ident`, 6 FAIL: ".pushsection
  .section .rodata"); it now uses the names `.sdata2` and `.rodata`, and
  emits the same text as before for both (a short `#ident` checked in
  `.sdata2`).

The other kept defaults (`.weakext`, `$` labels, `.space`, `.asciz`,
mergeable constant sections) are not touched.

## Testing

Big-endian microblaze-elf, binutils/newlib/QEMU 10.2.4 from the runner,
board `microblaze-qemu`, `--no-relax`. Stack: `fix/gcc-compile`
(`d8df05801`, which includes the elfos patch) plus
`gcc-generic-overaligned-parm`, `gcc-generic-clmul-promoted`, these two
and `gcc-testsuite-fixes` (branch `fix/gcc-compile-oaparm`). `compile.exp
execute.exp dg.exp dg-torture.exp microblaze.exp`, against the same stack
without the last three series (`../gcc-generic-overaligned-parm/NOTES.md`):

| | before | after |
|---|---|---|
| PASS | 105255 | 105286 |
| FAIL | 59 | 20 |
| UNRESOLVED | 1 | 1 |
| UNSUPPORTED | 5177 | 5182 |

That run had the first version of 2/2, so 20010510-1.c failed at 6
levels there (counted in the 20). With the `microblaze_asm_output_ident`
fix, `compile.exp=20010510-1.c` passes at all 7 levels and
`cpp.exp=ident*.c` passes (3 PASS); nothing else in the two patches
changed. From these two patches: attr-aligned-3.c 7, array-quals-1.c 20,
20021029-1.c 1 and pr25521.c 1 FAIL to PASS.
