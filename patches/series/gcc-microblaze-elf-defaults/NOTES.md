# gcc-microblaze-elf-defaults

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#120. For:
gcc-patches@gcc.gnu.org. Not yet sent.

## Base and dependencies

Branch `fix/gcc-elf-defaults` (worktree in a session scratchpad), two
commits on `pkg/elfos-scanfix` (`2d6b763ce`), the
`gcc-microblaze-elfos` patch: `fc67547e4`, `0da18fbc0`. Patch 3 is
`5fe8262e9` on branch `fix/gcc-dotl-labels` (worktree
`work/src/gcc-dotl`), on top of those two (#123). Needs the elfos patch
(the overrides it kept are removed here). Not in `patches/gcc/`: the
runner does not carry the elfos series.

Checks: `git_check_commit.py` OK, `check_GNU_style.sh` clean.

## What it does

The elfos NOTES listed adopting more of elfos.h's defaults as a separate
step. These are three of them:

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

- **Local labels** (#123): `LOCAL_LABEL_PREFIX` `"$"` and MicroBlaze's
  own `ASM_GENERATE_INTERNAL_LABEL` (`"*%s%s%ld"`), from the MIPS port,
  go. elfos.h's `ASM_GENERATE_INTERNAL_LABEL` writes `.L5`, `.LC0`,
  `.LCFI0`; `LOCAL_LABEL_PREFIX` becomes `"."` because
  `ASM_OUTPUT_ADDR_VEC_ELT`/`ADDR_DIFF_ELT` print it (`.gpword .L9`,
  `.gpword .L9@GOTOFF` with `-fPIC`). BFD's
  `microblaze_elf_is_local_label_name` accepts `$L`, `L.` and `.L`, and
  gas picks `R_MICROBLAZE_32_SYM_OP_SYM` through `S_IS_LOCAL`, which uses
  the same hook, so relocations do not change. The libgcc `.S` files keep
  their own `$L` labels (local either way). `strings1.c` scanned for
  `$LC` and now scans for `.LC`.

The other kept defaults (`.weakext`, `.space`, `.asciz`,
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

### Patch 3

Base `fix/gcc-elf-defaults` (patches 1-2) against the same plus patch 3,
both built from scratch (binutils from `install-fix-correct`, newlib from
the runner), BE and LE.

Objects: every libgcc, newlib and libgloss object (1256 per endian) was
compared. Code, relocations and section headers are the same apart
from local-symbol names: with `--strip-debug` and `$L` read as `.L`,
`objdump -h -dr -t` matches. On BE without PIC the assembler drops all
local labels; on LE (`$Ltext0`) and with `-fpic`/`-fPIC` on BE
(`$L4`, `$LC0`, jump-table targets) it keeps the same symbols under the
new names. `readelf -wfli` (frame, line, info) matches once the build
paths are normalised. The remaining differences come from the two
source trees' paths (`gcc-dotl-base` against `gcc-dotl`): 22 newlib
objects embed `__FILE__` (assert), which shifts their `.rodata` offsets
and the `DW_OP_addr`s of 6 of them.

`compile.exp execute.exp dg.exp dg-torture.exp microblaze.exp`, BE;
`execute.exp microblaze.exp`, LE; `microblaze.exp` with the four BE
board variants of `../gcc-microblaze-opt/NOTES.md`:

| run | before PASS / FAIL | after PASS / FAIL |
|---|---|---|
| BE full | 104581 / 226 | 104584 / 223 |
| LE | 25212 / 125 | 25212 / 125 |
| variants 1-4 FAIL | 145 / 189 / 139 / 145 | identical |

The 3 are `gcc.dg/pr110729.c`'s `.LPFE` scans. Otherwise the FAIL lists
differ only in the name of `strings1.c`'s `-flto -fno-fat-lto-objects`
scan, which fails both before and after (no assembly to scan), and in
temporary file names inside 8 musttail ERROR lines. (A different stack
from the table above, so the totals differ; most of this stack's
`microblaze.exp` FAILs, 105 in the BE full run, are
`others/picdtr.c`, which does not compile here: "conflicting types for
'myDef'".) `git_check_commit.py` OK.
