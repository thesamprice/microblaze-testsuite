# binutils-relax-safe-cfi-ef

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#47, steps E
and F of analysis/PLAN-relax-safe-cfi.md.

Base: binutils-gdb master `b6272d0e90717f2b96a748feaba7c5d41fe4ac15`
(2026-11-13) with `patches/binutils/0001`-`0012` applied by `git am`
in order (all applied cleanly; top commit of that stack `20563641aa8`
in work/src/binutils-new, branch `binutils-relax-safe-cfi-ef`).
Patches here are numbered 0013-0015 so they follow 0012.

## Patches

1. `0013-gas-microblaze-don-t-range-check-ADD-and-SUB-fixups.patch`
   (not E or F: a bug found in C/D while testing E).
   `md_apply_fix` (0011) and `microblaze_cfa_fix` (0012) split a
   difference into ADD/SUB fixups, but write.c's fixup_segment then
   range-checks a value computed from the symbols' addresses (MicroBlaze
   has MD_APPLY_SYM_VALUE = 1; RISC-V has 0, which is why RISC-V does not
   hit this).  Measured on 0001-0012:
   - `.space 300; g: brlid r15, ext; nop; h: ...; .byte h - g` ->
     `Error: value of 300 too large for field of 1 byte`
   - relax-cfi.s with `.space 70000` before the function ->
     `Error: value of 00011178 too large for field of 1 byte`
     (so any `.cfi_*` function more than 256 bytes into a section fails
     to assemble)
   - gas's own lns-big-delta with E applied.
   Fix: set `fx_no_overflow` before the fixup is duplicated.  New gas
   test `reloc_diff_far` (fails to assemble without the fix).
   **Recommendation: fold into 0011 and 0012 before sending**; kept
   separate here so the change is reviewable.

2. `0014-gas-microblaze-emit-line-advances-as-relocations.patch` (E).
   `#define DWARF2_USE_FIXED_ADVANCE_PC(FROM, TO) 1` in tc-microblaze.h,
   from tc-riscv.h:138.  New tests: gas `dwarf2-fixed-advance`
   (ADD16/SUB16 pairs in .rela.debug_line), ld `relax-line` (line rows
   after two deleted IMMs; without E, line 2 is at 0x90000008 instead of
   0x90000004 and the sequence ends at 0x90000024 inside `far`).
   Testsuite churn: 11 generic gas DWARF tests (dwarf2-5/11/15/16/17/18/19,
   dwarf-5-loc0, dwarf-5-macro, dwarf-5-macro-include, dwarf-5-irp) fail
   because gas now emits view numbers (it can no longer prove two rows
   differ in address); they already xfail for riscv and for "targets
   that do not evaluate the subtraction of symbols at assembly time".
   I added microblaze to that comment and to the xfail lists, and to
   lns.exp's list that runs lns-common-1-alt/lns-big-delta (as riscv).

3. `0015-microblaze-add-SET_ULEB128-and-SUB_ULEB128-relocatio.patch` (F).
   - include: `R_MICROBLAZE_SET_ULEB128` 44, `R_MICROBLAZE_SUB_ULEB128` 45.
   - bfd: BFD relocs in reloc.c (bfd-in2.h/libbfd.h regenerated; I
     hand-edited them and `make -C bfd headers` produced no further
     change); howtos with a do-nothing special function (from
     `riscv_elf_ignore_reloc`); `microblaze_elf_relocate_section` saves
     the SET value and on the SUB at the same offset rewrites the
     existing ULEB128 field in place, same length, padded with 0x80
     continuation bytes (`microblaze_write_uleb128`); mismatched pairs
     or a value that does not fit give a warning via the existing
     `bfd_reloc_dangerous` path.  Both types added to
     `microblaze_diff_reloc_p` (other-section addend adjustment in
     relax) and to the own-section case list in relax.
   - gas: `microblaze_uleb128_fix`, called from
     `microblaze_pre_output_hook` for each `rs_leb128` frag whose
     symbol is an unresolved O_subtract of two labels in one SEC_CODE
     section (unsigned only); emits SET (minuend + addend) and SUB
     (subtrahend), RISC-V order.  gas keeps writing its own computed
     value, so unrelaxed links and object readers see the right number.
   - readelf: `target_specific_reloc_handling` case for EM_MICROBLAZE
     applying the pair (needed so `readelf --debug-dump` of objects
     does not warn about unknown relocs, as 0010 does for ADD/SUB).
   - Tests: gas `reloc_uleb128`; ld `relax-uleb128` (132 -> 124,
     written as `fc 00` in the field's two bytes; 131 -> 123 `fb 00`)
     and `relax-uleb128-norelax` (stays `84 01 83 01`).

Precedent: RISC-V throughout (tc-riscv.h:138; tc-riscv.c
riscv_insert_uleb128_fixes; elfnn-riscv.c SET/SUB_ULEB128 cases;
elfxx-riscv.c riscv_elf_ignore_reloc).  readelf case modelled on the
LoongArch ULEB128 case next to it.  No Xilinx/AMD code.

## Test results (microblaze-elf, work/build/binutils-new/elf, macOS arm64)

Same CC_FOR_TARGET setup as the other series (installed gcc + -B to
debug-stripped crt/libs).  Baseline = master + 0001-0012.

| suite | master | +0001-0012 | +0013-0014 | +0013-0015 |
|---|---|---|---|---|
| gas | 331 PASS | 334 PASS | 326 PASS, 11 XFAIL | 327 PASS, 11 XFAIL |
| ld | 546 PASS, 2 FAIL | 556 PASS, 1 FAIL | 557 PASS, 1 FAIL | 559 PASS, 1 FAIL |
| binutils | 268 PASS, 1 FAIL | 269 PASS | 269 PASS | 269 PASS |

The remaining ld FAIL is `S-records` (fixed by
binutils-microblaze-srec-64, independent).  Per-test, 0001-0012 ->
0013-0015: gas +PASS reloc_diff_far, dwarf2-fixed-advance,
reloc_uleb128, lns-big-delta (newly run), 11 generic DWARF tests
PASS -> XFAIL; ld +PASS relax-line, relax-uleb128,
relax-uleb128-norelax.  (An intermediate run with E but without the
xfails and without 0013 showed the 11 DWARF FAILs plus lns-common-1
FAIL; after the lns.exp change lns-common-1-alt passes and lns-big-delta
failed until 0013.)

End to end: `microblaze-elf-gcc -O2 -g -S` (installed gcc 17.0.0
20261107) of a two-function file; assembled with this tree, linked
`-relax` with a stub for ext/__mulsi3 (11 IMMs deleted).  47
SET/SUB_ULEB128 pairs in the object.  All 35 decoded line rows sit at
the relaxed address of the instruction they had unrelaxed (script
mapping addresses through the disassembly); `readelf
--debug-dump=line,loc,frames` printed no warnings.  Same input
assembled by work/install's gas (0001-0012 only): 24 of 35 rows wrong.

## Untested / open questions

- **Relocation numbers 44/45** are provisional, like 36-43 (plan step 0:
  agree a block with AMD).  This is the one design decision I could
  not make; I followed the existing provisional numbering.
- Always-on vs. option (plan open question 1) applies to E and F as
  well; both are always on, as RISC-V is when relaxing.  Object-size
  cost not measured on newlib.
- E's cost: about three bytes per line advance instead of one; not
  measured.
- Location lists were not checked value-by-value after relaxation, only
  that readelf decodes them without warnings.
- gas-generated DW_TAG_subprogram DIEs (for asm with `-g`/`.loc`) get
  `DW_AT_high_pc` as `R_MICROBLAZE_32 _start+24` against the global
  symbol; relaxation moves the symbol but not the addend, so it stays
  8 bytes too large after two IMMs are deleted (seen in the relax-line
  link: 0x90000024 instead of 0x9000001c).  Pre-existing, not touched.
- The SUB relocations from dwarf2dbg's temporary labels show as
  `L0^A` symbols in objects (gas's default FAKE_LABEL_NAME "L0\001");
  RISC-V defines a printable FAKE_LABEL_NAME for exactly this reason
  (tc-riscv.h:40-44).  Already true of 0012's CFA relocations; not
  changed here.
- microblazeel-elf not built; the ld tests force -EL.  microblaze-linux
  not tested with this series.
- binutils LLM policy applies; Signed-off-by to be added by the sender.
