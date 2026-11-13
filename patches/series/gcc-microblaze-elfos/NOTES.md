# gcc-microblaze-elfos

Issue: #34 (thesamprice/rtems-microblaze-linker-relaxation-bug),
"MicroBlaze never migrated to elfos.h -- __has_attribute(symver) lies".
Upstream: PR target/101766, gcc-patches@gcc.gnu.org.  One patch, so no
cover letter.

## Base

Committed on branch `scratch/gcc-new-elfos` in the worktree
`work/src/gcc-new-elfos` (from the clone `work/src/gcc`, not changed), on
`xilinx-rework` (`d01983184` = upstream `df809a029` plus four microblaze
commits); commit `423f5843b`.  It does **not** apply to bare
`df809a029`: one microblaze.h hunk's context includes the
`microblaze_has_bitfield` / TARGET_HAS_BITFIELD lines added by the
xilinx-rework commit "microblaze: use bsefi and bsifi for bit-fields".
The conflict is context only; rebasing onto upstream master needs that
hunk refreshed (not done).

Checks: `contrib/gcc-changelog/git_check_commit.py` OK;
`contrib/check_GNU_style.py` no output; `git diff --check` clean;
`tools/review-commit-msg.py --project gcc`: no Signed-off-by, the
LLM-policy flag (95 non-test lines), 240 words vs a p90 of 235.
`tools/check-patch-style.py` "ChangeLog block has no directory header"
(it uses `gcc/ChangeLog:`, the GCC form).

## The patch

`0001-microblaze-include-elfos.h-PR-target-101766.patch`

- `config.gcc`: `elfos.h` first in `tm_file` for `microblaze*-*-elf`,
  `microblaze*-*-rtems*` and `microblaze*-linux*`, so `microblaze.h` and
  the OS headers after it override elfos.h.  Precedent: lm32
  (`config.gcc` lm32-*-elf/rtems/uclinux: `tm_file="elfos.h ${tm_file} ..."`).
  The RTEMS stanza's no-op `tm_file="${tm_file}"` line is folded into the
  next one.
- `microblaze.h`: removed what elfos.h now provides with the same meaning
  (OBJECT_FORMAT_ELF, DWARF2_DEBUGGING_INFO, PREFERRED_DEBUGGING_TYPE,
  ASCII_DATA_ASM_OP, TYPE_ASM_OP, SIZE_ASM_OP, COMMON_ASM_OP,
  TYPE_OPERAND_FMT, MAKE_DECL_ONE_ONLY, TARGET_ASM_NAMED_SECTION,
  TARGET_LIBC_HAS_FUNCTION) and the MicroBlaze ASM_DECLARE_OBJECT_NAME /
  ASM_FINISH_DECLARE_OBJECT (elfos.h's versions take the size from
  DECL_SIZE_UNIT, which is the fix below, and use gnu_unique_object for
  one-only C++ objects; otherwise the same).  Kept, with an
  `#undef` first: ASM_DECLARE_FUNCTION_NAME (empty; the prologue emits
  .ent/.type/label), ASM_GENERATE_INTERNAL_LABEL (`$L`), ASM_OUTPUT_SKIP
  (`.space`), STRING_ASM_OP (`.asciz`), MAX_OFILE_ALIGNMENT (32768*8),
  ASM_WEAKEN_LABEL (`.weakext`), READONLY_DATA_SECTION_ASM_OP
  (`.rodata`), INIT/FINI_SECTION_ASM_OP (with `"ax"`).  Added
  `#undef TARGET_ASM_SELECT_RTX_SECTION`, so constant-pool entries stay in
  `.rodata` instead of elfos.h's mergeable `.rodata.cstN` (a first build
  without it moved double constants in 20190901-1.c, pr39228.c and
  pr42691.c into .rodata.cst4/.cst8 with relocations against `$LC0+4`;
  I kept the old placement to keep this patch free of code changes and
  because MicroBlaze's linker relaxation and SEC_MERGE have not been
  tested together here).
- `microblaze.cc`, `microblaze-protos.h`: `microblaze_declare_object`
  removed (its only user was the old ASM_DECLARE_OBJECT_NAME), with its
  stale comment.
- Tests: `gcc.target/microblaze/others/elf-symver.c` (__ELF__ defined,
  __has_attribute (symver), `.symver` emitted) and `elf-size-flex.c`
  (`.size x, 12` for `struct { int n; int a[]; } x = { 2, { 3, 4 } }`).
  Both skip `-fno-fat-lto-objects`, which produces no assembly.

I wrote this from the bug and elfos.h, not from Vincent Fazio's
attachment 54646 (read only after mine was written, to compare).  His
puts elfos.h after microblaze.h plus a new microblaze/elf.h of
overrides; mine puts elfos.h first, so no new file is needed.  His keeps
the MicroBlaze ASM_DECLARE_OBJECT_NAME, so it keeps the .size bug.  No
Xilinx code involved.

### What changes in the output

Object code, symbols and section contents: only
- `__ELF__` is predefined (sources that test it, such as newlib's
  `sys/cdefs.h` and `ssp/stack_protector.c`, change accordingly);
- `__attribute__ ((symver))` works and emits `.symver`;
- `.size` of an object with an initialized flexible array member is the
  real size (12, was 4 for the example);
- new capabilities from elfos.h: -gctf/-gbtf, -frecord-gcc-switches,
  ASM_OUTPUT_EXTERNAL (visibility on extern decls).  Not exercised.

Assembly text only (no change to the object): a `.file "x.c"` line,
`.type x, @object` / `.size x, N` spacing, strings written by
default_elf_asm_output_ascii (`.asciz "..."` instead of
`.ascii "...\0"`), and `.globl __divdi3`-style lines for libcalls.

Side effect seen in gcc.target/microblaze: data_var2.c, sdata_var2.c and
sdata_var5.c under `-O2 -flto -fuse-linker-plugin -fno-fat-lto-objects`
went FAIL -> PASS.  That is spurious: their patterns (`.data*`,
`.sdata[^2]+`) now match the new `.file "data_var2.c"` line in an
otherwise empty LTO-only output.  The patterns are too loose; not fixed
here.

## Testing (all numbers from runs in this session)

Builds: `work/build/gcc-new` = baseline (`d01983184`; the same tree
later carries the pcmpbf patch, which does not change default-flag
output), `work/build/gcc-new-elfos` = this patch, both full microblaze-elf
c,lto + newlib, configure flags from `gcc-xfix-full`.  For the assembly
comparisons the baseline compiler was `work/build/gcc-xfix-full/gcc`
(also built from `d01983184`).  RTEMS: `gcc-new-base-microblaze-rtems7`
(from `work/src/gcc-xfix`, read-only) and
`gcc-new-elfos-microblaze-rtems7`, all-gcc only.

### Generated code, gcc.c-torture/execute

Script: compile every `execute/*.c` (1701) with both compilers at -O2
(`-w -fpermissive`, newlib headers), big- and little-endian, assemble
each with microblaze-elf-as, and compare `objdump -dr`, `objdump -s`
(every section) and `readelf -s` without the STT_FILE entry and the
symbol count.  1678 tests compile in each configuration; 16 more need
-std=gnu89 (compared for elf -O2 only); 7 compile in neither compiler.

| configuration | objects compared | differing |
|---|---|---|
| elf -O2, BE+LE | 2 x 1678 (+2 x 16 at -std=gnu89) | 20010924-1, pr33382 (BE and LE): .size only |
| elf -O2 -fPIC, BE+LE | 2 x 1678 | the same 2, .size only |
| rtems -O2, BE+LE | 2 x 1678 | the same 2, .size only |
| elf -O2 -g, BE+LE | 2 x 1678 | 156: the 2 above, plus .debug_line_str/.debug_line/.debug_info differing only by include-path strings (the two compilers live in different build dirs), plus 20050215-1 (BE, LE), whose source has `#ifdef __ELF__` (debug info only; code identical) |

### Libraries built by each compiler

`objdump -dr` of .text/.data/.rodata/.sdata*/.bss: libgcc.a (24564
insns), libm.a (58062) and libgloss.a (2162) identical.  libc.a: 22
members differ.  21 of them contain the build-tree source path through
`__FILE__`, which differs between the two trees (I checked that the path
is present in each of the 21, and read the full diff for rand.o,
strsignal.o and tmpnam.o: only the path and offsets after it).  The
other is ssp/stack_protector.o, which gains `__stack_chk_fail_local`
under `#ifdef __ELF__`.

### Testsuites (microblaze-elf BE, QEMU, board microblaze-qemu, MB_NO_RELAX=-Wl,--no-relax)

| run | before | after |
|---|---|---|
| gcc.target/microblaze | 620 PASS / 142 FAIL / 31 UNRESOLVED / 1 UNSUPPORTED | 647 / 139 / 31 / 3 |
| gcc.c-torture/execute | 24536 PASS / 14 FAIL / 176 UNSUPPORTED | identical result lines |
| gcc.dg/ipa/symver1.c | FAIL (excess errors: "symver is only supported on ELF platforms") + 2 UNRESOLVED | 3 PASS |

microblaze.exp delta: +24 PASS and +2 UNSUPPORTED from the two new
tests (the -fno-fat-lto-objects skip), and the 3 spurious FAIL -> PASS
described above.  Nothing else changed (sorted .sum diff).

symver and __ELF__ also checked by hand on the microblaze-rtems7
compiler: before, `#ifndef __ELF__` fires; after, `__ELF__` and
`__rtems__` are both defined and `.symver foo_v1, foo@VERS_1` is
emitted.

## Not done / open questions

- microblaze-linux: only the after-state compiler was built
  (`gcc-new-elfos-microblazeel-linux-gnu`, all-gcc, no macro
  redefinition warnings).  It defines `__ELF__`, `__linux__`,
  `__gnu_linux__` and emits `.symver` at -fPIC.  No before/after
  comparison and no run: no linux baseline build, no glibc sysroot.  Its
  `__thread` variable came out as `__emutls_v.tl` where microblaze-elf
  uses `.tbss`; I did not check whether the unpatched linux compiler does
  the same (likely a configure-time TLS detection difference with
  --without-headers, but unverified).
- No little-endian DejaGnu run (the build is --disable-multilib).  LE
  was covered only by the object comparisons.
- No full gcc.dg / gcc.c-torture/compile run; no bootstrap (cross).
- Whether to also adopt elfos.h's defaults that are kept here
  (`.weak` for `.weakext`, `.section .rodata`, `.L` labels, `.zero`,
  mergeable constant sections, the default MAX_OFILE_ALIGNMENT) is a
  separate, behaviour-changing step; each needs its own testing,
  `.rodata.cstN` especially against linker relaxation.
- TARGET_HAVE_SWITCHABLE_BSS_SECTIONS becomes true from elfos.h; the
  object comparison shows no change from it (MicroBlaze's own
  ASM_OUTPUT_ALIGNED_BSS/LOCAL and microblaze_select_section still decide
  placement), but I did not trace why in detail.
- Approach A (only adding ASM_OUTPUT_SYMVER_DIRECTIVE) is not needed if
  this goes in; it would fix the __has_attribute mismatch without __ELF__.
- Overlap with our gcc #24 (ASM_PREFERRED_EH_DATA_FORMAT): this patch
  does not change that macro, but it deletes the DWARF2_DEBUGGING_INFO /
  PREFERRED_DEBUGGING_TYPE block directly below it, so whichever lands
  second may need a trivial context rebase.  Not checked against the #24
  patch itself.
- GCC AI policy: the header changes are LLM-written; the user decides.
