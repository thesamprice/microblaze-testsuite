# binutils-microblaze-gas-fixes

Issues (thesamprice/rtems-microblaze-linker-relaxation-bug): #87, #91,
#92, #93, #94, #95, #96, #97, #99, in patch order. For:
binutils@sourceware.org. Not yet sent.

## Base and dependencies

The last nine commits of branch `fix/binutils-all` (worktree
`work/src/binutils-fix-all`), on top of `../binutils-microblaze-relax-fixes/`
(9) and `../binutils-microblaze-local-labels/` (1), on `audit/all-patches`
= binutils master `7b7c85d7f65` plus the in-review relax-safe CFI series
(0001-0015), `binutils-microblaze-64-none`,
`binutils-microblaze-no-keep-memory`,
`binutils-microblaze-srec-64/on-relax-cfi`, `binutils-microblaze-eh-relax`
and `binutils-microblaze-opcodes`. See the relax-fixes NOTES.md for the
full list.

Apply order: relax-fixes -> local-labels -> gas-fixes (this). Not checked
against bare master; the ld test expectations changed by 0009 come from
the series underneath (relax-64-none, relax-no-keep-memory, relax-wrap,
relax-addend) and from relax-fixes (relax-align), so 0009 at least needs
them.

| patch | commit | issue |
|---|---|---|
| 0001 line rows at the IMM prefix | `f69c1c9f147` | #87 |
| 0002 symbol in shift/mbar/bit-field immediate | `8ecf75c687f` | #91 |
| 0003 immediates over 32 bits | `ad9fbc9bb2c` | #92 |
| 0004 @TLSTPREL/@TLSDTPMOD | `4c5d2192cf1` | #93 |
| 0005 unknown relocation suffix | `6363018324c` | #94 |
| 0006 register number digits | `03618292d0a` | #95 |
| 0007 `.8byte` | `6b8684571cb` | #96 |
| 0008 @GOTOFF in `.word` | `327283817c0` | #97 |
| 0009 objdump at or above 0x80000000 | `a16eefd1f6e` | #99 |

## Behaviour changes

- Lowercase `@plt` and `@got` (and any unknown suffix) are errors (0005).
  They were silently dropped before, leaving a plain reference.
- `@GOT` and `@PLT` in data (`.word`, `.long`) are errors (0008); they
  were dropped too. `@GOTOFF` in data now gives R_MICROBLAZE_GOTOFF_32.
- `@TLSTPREL`, `@TLSDTPMOD` operands are errors (0004), until ld supports
  the IE/LE TLS models (#111).
- A register number is all of its digits (0006): `r100` and `r32` are
  errors, `r031` is accepted as r31.
- Symbols in shift/mbar/bit-field immediates, and immediates outside
  -0x80000000..0xffffffff, are errors (0002, 0003).
- `.8byte` with a value that needs a relocation is an error (0007).
- objdump names symbols at or above 0x80000000 (0009). Four ld tests
  from the series underneath that link at 0x90000000 (relax-64-none,
  relax-no-keep-memory, relax-wrap, relax-addend) now expect symbolized
  addresses, and so does relax-align from relax-fixes 0009.

## Testing

Tested as part of the 19 commits of `fix/binutils-all`; numbers and
scripts in the relax-fixes NOTES.md (microblaze-elf gas 344 / ld 507 /
binutils 245 PASS, 0 FAIL; microblaze-linux gas 341 / ld 839 / binutils
249 PASS with the base's 12 ld FAIL and 1 XPASS). microblazeel-elf: gas
built and checked in `work/build-fix-all/microblazeel-elf`; every new
test passes.

## Open questions

- Making lowercase `@plt`/`@got` an error could break hand-written
  assembly that relied on the suffix being dropped (it never produced a
  PLT or GOT reference). Upstream may prefer a warning first.
