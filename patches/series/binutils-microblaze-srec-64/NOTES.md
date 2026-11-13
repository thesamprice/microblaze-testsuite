# binutils-microblaze-srec-64

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#39 (option 2:
fix the generic path).

Upstream base: binutils-gdb master `b6272d0e90717f2b96a748feaba7c5d41fe4ac15`
(2026-11-13).

## Patch

`0001-microblaze-apply-IMM-pair-relocs-for-non-ELF-output.patch`

- `bfd/elf32-microblaze.c`: new `microblaze_elf_imm64_reloc` special
  function, used by the `R_MICROBLAZE_64_PCREL` and `R_MICROBLAZE_64`
  howtos.  For final (non-relocatable) links through
  `bfd_perform_relocation` it computes S + A (minus P + 4 for the PC-relative
  form, matching `microblaze_elf_relocate_section`) and writes it with the
  existing `microblaze_bfd_write_imm_value_64` (high half into the IMM,
  low half into the next instruction).  Relocatable output defers to
  `bfd_elf_generic_reloc`.  Undefined non-weak symbols return
  `bfd_reloc_undefined` so the generic linker still reports them.
  The two "Table entry not really used" comments on those howtos were
  replaced, since the table entry is now used.
- New test `ld/testsuite/ld-microblaze/oformat-srec.{s,ld,d}`: lwi of a
  symbol at 0x12345678 and brlid to a function at 0x23456780, linked
  `--oformat srec`, disassembled with `objdump -D -EB -m microblaze`.

Precedent: the shape (compute from symbol/section/addend, check range,
write) follows `riscv_elf_add_sub_reloc` in bfd/elfxx-riscv.c, which the
relax-cfi series also copies.  No external code used.

`R_MICROBLAZE_64_PCREL` was "not yet verified" in the issue.  Verified:
unpatched, `--oformat srec` wrote `imm 0x5778 / brlid 0` for a call
whose correct encoding is `imm 0x2345 / brlid 0x5774` (generic code puts
the low half in the IMM and measures from the IMM, not the IMM + 4).

## Testing (microblaze-elf, work/build/binutils-new/elf, macOS arm64)

CC_FOR_TARGET: installed microblaze-elf-gcc plus `-B` to debug-stripped
copies of its crt files/libs, so ld's compiler probe can link (see the
no-keep-memory NOTES for why).  This is what makes ld-srec run at all;
with the plain installed gcc it is UNTESTED.

| suite | base | patched |
|---|---|---|
| gas | 331 PASS | 331 PASS |
| ld | 546 PASS, 2 FAIL (merge4, S-records) | 548 PASS, 1 FAIL (merge4) |
| binutils | 268 PASS, 1 FAIL | 268 PASS, 1 FAIL |

Per-test differences: `FAIL: S-records` -> `PASS: S-records`, and
`+PASS: MicroBlaze IMM relocations with --oformat srec`.

Issue reproducer (`t.s`, `-Ttext 0x1000 -Tdata 0x12345678`): the
`objcopy -O srec` and `--oformat srec` outputs now hold the same bytes
(`B0001234 E8605678 ...`); `diff` still differs in the S0 header (it
contains the file name) and in where records are split, which srec.exp
normalises.

The new test, on the unpatched linker, disassembles as
`imm 22136 / lwi r3, r0, 0 / imm 22392 / brlid r15, 0`, so it fails
there (checked by hand with the same input, not as a DejaGnu run).

## Untested / open

- `S-records with constructors` stays UNTESTED (needs a C++ compiler).
- microblazeel-elf not built.  The test assembles with `-EB` and does
  not pass `-EB` to ld (ld warns "could not find any targets that match
  endianness requirement" for `-EB --oformat srec`), so on microblazeel
  it relies on the little-endian linker accepting a big-endian object
  for srec output.  Not verified.
- `--oformat binary` not separately tested; it goes through the same
  generic path.
- Other IMM-pair relocations (GOTPC_64, GOT_64, PLT_64, GOTOFF_64,
  TEXTREL_64, TEXTPCREL_64, TLS forms) still use bfd_elf_generic_reloc.
  TEXTREL_64 could be handled the same way (S + A - text vma); I left it
  out because nothing in the testsuite produces it for a static non-ELF
  link.
